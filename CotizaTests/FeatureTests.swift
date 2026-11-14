import Contacts
import Foundation
import PDFKit
import SwiftData
import Testing
import UIKit
@testable import Cotiza

@Suite("Receipt parser")
struct ReceiptParserTests {
    @Test func `item lines are kept and totals, tax and payment are left out`() throws {
        let lines = ReceiptParser.parse([
            "THE HOME STORE #0582",
            "123 MAIN ST HOUSTON TX",
            "012345678901 2X4X8 STUD  3.98",
            "098765432109 DRYWALL SCREWS 1LB  7.96",
            "2 @ 3.98",
            "PAINTERS TAPE 1.88IN  5.47 N",
            "SUBTOTAL  17.41",
            "SALES TAX 8.25%  1.44",
            "TOTAL  18.85",
            "VISA  18.85",
            "CHANGE DUE  0.00",
        ])
        try #require(lines.count == 3)
        #expect(lines[0] == ReceiptLine(text: "2X4X8 Stud", unitPrice: 3.98))
        #expect(lines[1] == ReceiptLine(text: "Drywall Screws 1LB", quantity: 2, unitPrice: 3.98))
        #expect(lines[2] == ReceiptLine(text: "Painters Tape 1.88IN", unitPrice: 5.47))
    }

    @Test func `spanish receipts with decimal commas and dollar signs`() throws {
        let lines = ReceiptParser.parse([
            "Pintura blanca 1 galón  $32,50",
            "Rodillo  $8,99",
            "Descuento  -2,00",
            "Impuesto  3,40",
            "Total  $42,89",
            "Efectivo  $50,00",
        ])
        try #require(lines.count == 2)
        #expect(lines[0].text == "Pintura blanca 1 galón")
        #expect(lines[0].unitPrice == 32.5)
        #expect(lines[1].unitPrice == 8.99)
    }

    @Test func `thousands separators are one price`() throws {
        let lines = ReceiptParser.parse(["WATER HEATER 50 GAL  1,249.00"])
        #expect(lines.first?.unitPrice == 1249)
    }

    @Test func `separate pieces on one printed line are joined in reading order`() {
        let pieces: [(text: String, box: CGRect)] = [
            ("4.99", CGRect(x: 0.8, y: 0.70, width: 0.1, height: 0.02)),
            ("CAULK", CGRect(x: 0.1, y: 0.705, width: 0.2, height: 0.02)),
            ("TOTAL", CGRect(x: 0.1, y: 0.50, width: 0.2, height: 0.02)),
            ("4.99", CGRect(x: 0.8, y: 0.50, width: 0.1, height: 0.02)),
        ]
        #expect(ReceiptReader.groupIntoLines(pieces) == ["CAULK  4.99", "TOTAL  4.99"])
    }

    @Test func `the text recognizer reads a rendered receipt`() async throws {
        let size = CGSize(width: 600, height: 300)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let font = UIFont.monospacedSystemFont(ofSize: 28, weight: .regular)
            for (index, (name, price)) in [("ROLLER COVER", "6.97"), ("TOTAL", "6.97")].enumerated() {
                let y = CGFloat(40 + index * 70)
                (name as NSString).draw(at: CGPoint(x: 30, y: y), withAttributes: [.font: font])
                (price as NSString).draw(at: CGPoint(x: 460, y: y), withAttributes: [.font: font])
            }
        }
        let lines = try await ReceiptReader.lines(in: try #require(image.cgImage))
        let items = ReceiptParser.parse(lines)
        #expect(items == [ReceiptLine(text: "Roller Cover", unitPrice: 6.97)])
    }
}

@Suite("Client message")
struct ClientMessageTests {
    private func snapshot(kind: DocumentKind, language: DocumentLanguage, signed: Bool = false, paid: Bool = false) -> DocumentSnapshot {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 12, day: 12))!
        return DocumentSnapshot(
            kind: kind, language: language, displayNumber: kind == .estimate ? "E-1003" : "INV-1004", title: "Sala",
            date: .now, isPaid: paid, businessName: "López Painting LLC", ownerName: "Carlos López", businessPhone: "",
            businessEmail: "", businessAddress: "", licenseNumber: "", logo: nil, clientName: "Maria Lopez",
            clientPhone: "", clientEmail: "", clientAddress: "", items: [],
            totals: Totals(lines: [.init(amount: 920, isTaxable: false)], taxRate: 0), taxRate: 0, notes: "",
            terms: "", paymentInstructions: "Zelle (713) 555-0142", showsBranding: false,
            validUntil: kind == .estimate ? date : nil, dueDate: kind == .invoice ? date : nil,
            signature: signed ? Data([1]) : nil
        )
    }

    @Test func `spanish estimate greets by first name with total and validity`() {
        let text = ClientMessage.text(for: snapshot(kind: .estimate, language: .spanish))
        #expect(text.hasPrefix("Hola Maria, le envío la cotización E-1003 de López Painting LLC por "))
        #expect(text.contains("válida hasta el 12 de diciembre de 2026"))
        #expect(text.hasSuffix("Carlos López"))
    }

    @Test func `english invoice has due date and how to pay`() {
        let text = ClientMessage.text(for: snapshot(kind: .invoice, language: .english))
        #expect(text.contains("here is invoice INV-1004 from López Painting LLC for $920.00, due December 12, 2026."))
        #expect(text.contains("Payment: Zelle (713) 555-0142"))
    }

    @Test func `signed estimates and paid invoices say so`() {
        #expect(ClientMessage.text(for: snapshot(kind: .estimate, language: .english, signed: true)).contains("signed copy"))
        #expect(ClientMessage.text(for: snapshot(kind: .invoice, language: .spanish, paid: true)).contains("ya pagada"))
    }
}

@MainActor
@Suite("Dates, signature, reminders and widget")
struct DocumentLifecycleTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: BusinessProfile.self, Client.self, JobDocument.self, LineItem.self, PriceBookItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func day(_ value: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: value, hour: 15))!
    }

    private func document(_ kind: DocumentKind, total: Double, in context: ModelContext) -> JobDocument {
        let document = JobDocument(kind: kind, number: 1001, title: "Paint", language: .english, taxRate: 0)
        context.insert(document)
        let line = LineItem(text: "Work", quantity: 1, unitPrice: total)
        context.insert(line)
        line.document = document
        return document
    }

    @Test func `new estimates and invoices get dates from the business settings`() throws {
        let context = try makeContext()
        let profile = BusinessProfile()
        profile.estimateValidDays = 15
        profile.paymentDueDays = 7
        context.insert(profile)
        let factory = DocumentFactory(context: context)
        let estimate = factory.makeEstimate(from: EstimateDraft(title: "Sala", items: []), transcript: "", profile: profile)
        let invoice = factory.makeInvoice(from: estimate, profile: profile)
        let today = Calendar.current.startOfDay(for: .now)
        #expect(estimate.validUntil == Calendar.current.date(byAdding: .day, value: 15, to: today))
        #expect(invoice.dueDate == Calendar.current.date(byAdding: .day, value: 7, to: today))
        #expect(invoice.validUntil == nil)
    }

    @Test func `signing approves the estimate and removing keeps the status`() throws {
        let context = try makeContext()
        let estimate = document(.estimate, total: 500, in: context)
        estimate.apply(status: .sent)
        estimate.sign(png: Data([1, 2, 3]), name: "  Maria Lopez ", at: day(12))
        #expect(estimate.status == .approved)
        #expect(estimate.signerName == "Maria Lopez")
        #expect(estimate.signedAt == day(12))
        estimate.removeSignature()
        #expect(estimate.signatureData == nil)
        #expect(estimate.status == .approved)
    }

    @Test func `an invoice is overdue from the day after it was due until it is paid`() throws {
        let context = try makeContext()
        let invoice = document(.invoice, total: 100, in: context)
        invoice.apply(status: .sent)
        invoice.dueDate = day(10)
        #expect(!invoice.isOverdue(now: day(10), calendar: calendar))
        #expect(invoice.isOverdue(now: day(11), calendar: calendar))
        invoice.apply(status: .paid)
        #expect(!invoice.isOverdue(now: day(11), calendar: calendar))
    }

    @Test func `reminders follow up on sent estimates and chase unpaid invoices`() throws {
        let context = try makeContext()
        let estimate = document(.estimate, total: 500, in: context)
        estimate.apply(status: .sent)
        estimate.sentAt = day(10)
        let invoice = document(.invoice, total: 900, in: context)
        invoice.apply(status: .sent)
        invoice.dueDate = day(20)
        let draft = document(.invoice, total: 50, in: context)
        draft.dueDate = day(20)

        let plan = ReminderScheduler.plan(for: [estimate, invoice, draft], now: day(11), calendar: calendar)
        try #require(plan.count == 2)
        #expect(plan[0].kind == .followUp)
        #expect(plan[0].fireDate == calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 9)))
        #expect(plan[0].body.contains("E-1001"))
        #expect(plan[1].kind == .overdue)
        #expect(plan[1].fireDate == calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9)))

        // Once answered or paid, or once the day has passed, nothing is scheduled.
        estimate.apply(status: .approved)
        invoice.apply(status: .paid)
        #expect(ReminderScheduler.plan(for: [estimate, invoice], now: day(11), calendar: calendar).isEmpty)
    }

    @Test func `the widget snapshot matches the home screen and resets each month`() throws {
        let context = try makeContext()
        let sent = document(.invoice, total: 400, in: context)
        sent.apply(status: .sent)
        sent.dueDate = .distantPast
        let paid = document(.invoice, total: 250, in: context)
        paid.apply(status: .paid)
        let snapshot = WidgetData.snapshot(of: [sent, paid])
        #expect(snapshot.pending == 400)
        #expect(snapshot.paidThisMonth == 250)
        #expect(snapshot.awaitingCount == 1)
        #expect(snapshot.overdueCount == 1)
        #expect(snapshot.paid(asOf: Calendar.current.date(byAdding: .month, value: 1, to: .now)!) == 0)

        let defaults = try #require(UserDefaults(suiteName: "widget-test-\(UUID())"))
        snapshot.save(to: defaults)
        #expect(WidgetSnapshot.load(from: defaults) == snapshot)
        #expect(WidgetSnapshot.money(1250, locale: Locale(identifier: "en_US")) == "$1,250")
        #expect(WidgetSnapshot.money(12.5, locale: Locale(identifier: "en_US")) == "$12.50")
    }

    @Test func `a picked contact fills only the empty fields`() {
        let contact = CNMutableContact()
        contact.givenName = "Maria"
        contact.familyName = "Lopez"
        contact.phoneNumbers = [
            CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "(713) 555-0100")),
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "(713) 555-0199")),
        ]
        contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "maria@example.com")]
        let picked = PickedContact(contact)
        #expect(picked.name == "Maria Lopez")
        #expect(picked.phone == "(713) 555-0199")

        let client = Client(name: "Señora Lopez", phone: "", email: "old@example.com")
        picked.fill(client)
        #expect(client.name == "Señora Lopez")
        #expect(client.phone == "(713) 555-0199")
        #expect(client.email == "old@example.com")
    }

    @Test func `a signed estimate prints the signer, the signing date and the valid-until date`() throws {
        let context = try makeContext()
        let estimate = document(.estimate, total: 500, in: context)
        estimate.validUntil = day(30)
        let ink = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 40)).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 10, y: 18, width: 100, height: 4))
        }
        estimate.sign(png: try #require(ink.pngData()), name: "Maria Lopez", at: day(12))
        let data = PDFRenderer().render(DocumentSnapshot(document: estimate, profile: nil, showsBranding: false))
        let text = try #require(PDFDocument(data: data)?.string)
        #expect(text.contains("Client signature: Maria Lopez"))
        #expect(text.contains("Valid until: November 30, 2026"))
        #expect(text.contains("valid until November 30, 2026"))
        #expect(text.contains("November 12, 2026"))
    }
}
