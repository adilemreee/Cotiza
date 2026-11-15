import Foundation
import PDFKit
import SwiftData
import Testing
@testable import Cotiza

@MainActor
@Suite("Deposits and partial payments")
struct PaymentTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: BusinessProfile.self, Client.self, JobDocument.self, LineItem.self, PriceBookItem.self, Payment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 15))!
    }

    /// An estimate for $1,000 of labor and $75 of taxable paint at 10% tax: total $1,082.50.
    private func estimate(deposit: Double, in context: ModelContext) -> (JobDocument, BusinessProfile) {
        let profile = BusinessProfile()
        profile.defaultTaxRate = 10
        profile.defaultDepositPercent = deposit
        context.insert(profile)
        let draft = EstimateDraft(title: "Paint the house", clientName: "Maria Lopez", items: [
            DraftItem(text: "Labor", quantity: 1, unitPrice: 1000, isLabor: true),
            DraftItem(text: "Paint", quantity: 1, unitPrice: 75),
        ])
        let document = DocumentFactory(context: context).makeEstimate(from: draft, transcript: "", profile: profile)
        document.createdAt = day(10, 1)
        return (document, profile)
    }

    @Test func `new estimates ask for the business deposit, worked out on the total with tax`() throws {
        let context = try makeContext()
        let (document, _) = estimate(deposit: 50, in: context)
        #expect(document.totals.total == 1082.5)
        #expect(document.depositPercent == 50)
        #expect(document.depositAmount == 541.25)
        #expect(document.balanceDue == 1082.5)
        document.depositPercent = 0
        #expect(document.depositAmount == 0)
    }

    @Test func `a deposit approves the estimate and leaves the rest owed`() throws {
        let context = try makeContext()
        let (document, _) = estimate(deposit: 50, in: context)
        document.apply(status: .sent)
        let factory = DocumentFactory(context: context)
        #expect(factory.record(payment: 0, method: .cash, to: document) == nil)
        factory.record(payment: 541.25, on: day(10, 3), method: .zelle, to: document)
        #expect(document.status == .approved)
        #expect(document.amountPaid == 541.25)
        #expect(document.balanceDue == 541.25)
        #expect(document.isPartlyPaid)
    }

    @Test func `the deposit moves to the invoice and is counted once`() throws {
        let context = try makeContext()
        let (document, profile) = estimate(deposit: 50, in: context)
        let factory = DocumentFactory(context: context)
        factory.record(payment: 541.25, on: day(11, 3), method: .zelle, to: document)
        let invoice = factory.makeInvoice(from: document, profile: profile)
        invoice.apply(status: .sent)

        #expect(document.sortedPayments.isEmpty)
        #expect(document.depositAmount == 0)
        #expect(document.status == .approved)
        #expect(invoice.depositPercent == 50)
        #expect(invoice.sortedPayments.map(\.amount) == [541.25])
        #expect(invoice.balanceDue == 541.25)

        let summary = DocumentSummary(documents: [document, invoice], now: day(11, 20), calendar: calendar)
        #expect(summary.paidThisMonth == 541.25)
        #expect(summary.pending == 541.25)
    }

    @Test func `paying the rest marks it paid on that day, and removing a payment undoes it`() throws {
        let context = try makeContext()
        let (document, profile) = estimate(deposit: 50, in: context)
        let factory = DocumentFactory(context: context)
        let invoice = factory.makeInvoice(from: document, profile: profile)
        invoice.apply(status: .sent)
        factory.record(payment: 500, on: day(11, 3), method: .cash, to: invoice)
        let last = try #require(factory.record(payment: 582.5, on: day(11, 9), method: .check, to: invoice))
        #expect(invoice.status == .paid)
        #expect(invoice.paidAt == day(11, 9))
        #expect(invoice.balanceDue == 0)

        factory.remove(last, from: invoice)
        #expect(invoice.status == .sent)
        #expect(invoice.paidAt == nil)
        #expect(invoice.balanceDue == 582.5)
    }

    @Test func `marking paid by hand counts only what was not already received`() throws {
        let context = try makeContext()
        let (document, profile) = estimate(deposit: 50, in: context)
        let factory = DocumentFactory(context: context)
        let invoice = factory.makeInvoice(from: document, profile: profile)
        factory.record(payment: 300, on: day(10, 20), method: .cash, to: invoice)
        invoice.apply(status: .paid)
        invoice.paidAt = day(11, 5)
        #expect(invoice.income.map(\.amount) == [300, 782.5])

        let october = DocumentSummary(documents: [invoice], now: day(10, 25), calendar: calendar)
        let november = DocumentSummary(documents: [invoice], now: day(11, 25), calendar: calendar)
        #expect(october.paidThisMonth == 300)
        #expect(november.paidThisMonth == 782.5)
        #expect(november.pending == 0)
    }

    @Test func `the report splits a job paid in parts by month and the cents add up`() throws {
        let context = try makeContext()
        let (document, profile) = estimate(deposit: 0, in: context)
        document.allItems.first { $0.text == "Paint" }?.unitCost = 50
        let factory = DocumentFactory(context: context)
        let invoice = factory.makeInvoice(from: document, profile: profile)
        factory.record(payment: 333.33, on: day(10, 20), method: .zelle, to: invoice)
        factory.record(payment: 749.17, on: day(11, 4), method: .zelle, to: invoice)
        #expect(invoice.status == .paid)

        let rows = ProfitReport.Row.rows(for: invoice)
        try #require(rows.count == 2)
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(Money.round(rows[0].revenue + rows[1].revenue) == 1075)
        #expect(Money.round(rows[0].tax + rows[1].tax) == 7.5)
        #expect(Money.round(rows[0].materialsCost + rows[1].materialsCost) == 50)
        #expect(Money.round(rows[0].total + rows[1].total) == 1082.5)

        let october = ProfitReport(rows: rows, period: .month, containing: day(10, 1), calendar: calendar)
        let year = ProfitReport(rows: rows, period: .year, containing: day(10, 1), calendar: calendar)
        #expect(october.total == 333.33)
        #expect(year.total == 1082.5)
        #expect(year.jobCount == 1)
    }

    // MARK: What the client sees

    private func pdfText(_ document: JobDocument, profile: BusinessProfile) throws -> String {
        let snapshot = DocumentSnapshot(document: document, profile: profile, showsBranding: false)
        let pdf = try #require(PDFDocument(data: PDFRenderer().render(snapshot)))
        return pdf.string ?? ""
    }

    @Test func `the estimate PDF asks for the deposit and the invoice shows what was paid`() throws {
        let context = try makeContext()
        let (document, profile) = estimate(deposit: 50, in: context)
        profile.paymentInstructions = "Zelle 555-0142"
        let estimateText = try pdfText(document, profile: profile)
        #expect(estimateText.contains("Deposit to start (50%)"))
        #expect(estimateText.contains("$541.25"))
        #expect(estimateText.contains("Zelle 555-0142"))

        let factory = DocumentFactory(context: context)
        factory.record(payment: 300, on: day(11, 3), method: .zelle, to: document)
        let invoice = factory.makeInvoice(from: document, profile: profile)
        invoice.language = .spanish
        let invoiceText = try pdfText(invoice, profile: profile)
        #expect(invoiceText.contains("SALDO PENDIENTE"))
        #expect(invoiceText.contains("Pagado"))
        #expect(!invoiceText.contains("Anticipo para empezar"))
    }

    @Test func `client messages mention the deposit and the balance`() throws {
        let context = try makeContext()
        let (document, profile) = estimate(deposit: 50, in: context)
        profile.businessName = "López Painting"
        func message(_ document: JobDocument) -> String {
            ClientMessage.text(for: DocumentSnapshot(document: document, profile: profile, showsBranding: false))
        }
        #expect(message(document).contains("A deposit of $541.25 (50%) is due to start."))
        document.language = .spanish
        #expect(message(document).contains("Para empezar se pide un anticipo de"))
        document.language = .english

        let factory = DocumentFactory(context: context)
        factory.record(payment: 541.25, on: day(11, 3), method: .zelle, to: document)
        #expect(message(document).contains("I received your payment of $541.25."))
        #expect(message(document).contains("Balance due: $541.25."))

        let invoice = factory.makeInvoice(from: document, profile: profile)
        #expect(message(invoice).contains("I've received $541.25; the balance due is $541.25"))
    }

    @Test func `the signing page lists the deposit with the terms`() throws {
        let context = try makeContext()
        let (document, profile) = estimate(deposit: 50, in: context)
        profile.terms = "Balance on completion."
        let page = SignLinkDocument(DocumentSnapshot(document: document, profile: profile, showsBranding: false))
        #expect(page.terms.hasPrefix("Deposit to start (50%): $541.25\nBalance on completion."))
    }
}
