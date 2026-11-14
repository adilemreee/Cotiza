import Foundation
import SwiftData
import Testing
@testable import Cotiza

@MainActor
@Suite("Markup, recurring invoices, reports and iCloud merge")
struct BusinessTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: BusinessProfile.self, Client.self, JobDocument.self, LineItem.self, PriceBookItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 15))!
    }

    // MARK: Markup

    @Test func `markup is added on top of the cost and rounded to cents`() {
        #expect(Money.withMarkup(8.97, percent: 15) == 10.32)
        #expect(Money.withMarkup(100, percent: 20) == 120)
        #expect(Money.withMarkup(5, percent: 0) == 5)
        #expect(Money.withMarkup(5, percent: -10) == 5)
    }

    @Test func `a line knows its cost apart from its price`() {
        let line = LineItem(text: "Paint", quantity: 2, unitPrice: 20.12)
        line.unitCost = 17.49
        #expect(line.amount == 40.24)
        #expect(line.cost == 34.98)
    }

    // MARK: Recurring invoices

    @Test func `monthly repeats keep the day and clamp short months`() {
        #expect(RepeatInterval.monthly.next(after: day(1, 31), calendar: calendar).map { calendar.component(.day, from: $0) } == 28)
        #expect(RepeatInterval.weekly.next(after: day(11, 1), calendar: calendar).map { calendar.component(.day, from: $0) } == 8)
        #expect(RepeatInterval.never.next(after: day(11, 1), calendar: calendar) == nil)
    }

    @Test func `turning on a repeat picks the first date that isn't in the past`() throws {
        let context = try makeContext()
        let invoice = JobDocument(kind: .invoice, number: 1001, title: "Lawn", language: .english, taxRate: 0)
        context.insert(invoice)
        invoice.createdAt = day(8, 10)
        invoice.setRepeat(.monthly, now: day(11, 12), calendar: calendar)
        #expect(invoice.nextRepeatDate.map { calendar.dateComponents([.month, .day], from: $0) } == DateComponents(month: 12, day: 10))
        invoice.setRepeat(.never, now: day(11, 12), calendar: calendar)
        #expect(invoice.nextRepeatDate == nil)
    }

    @Test func `due repeats are copied once each, with new numbers, dates and the same items`() throws {
        let context = try makeContext()
        let profile = BusinessProfile()
        profile.nextInvoiceNumber = 1010
        profile.paymentDueDays = 7
        context.insert(profile)
        let client = Client(name: "Maria Lopez")
        context.insert(client)
        let template = JobDocument(kind: .invoice, number: 1009, title: "Lawn care", language: .spanish, taxRate: 8.25)
        context.insert(template)
        template.client = client
        template.apply(status: .paid)
        let line = LineItem(text: "Mow and edge", quantity: 1, unitPrice: 60)
        line.unitCost = 5
        context.insert(line)
        line.document = template
        template.repeatInterval = .weekly
        template.nextRepeatDate = day(11, 1)

        let made = DocumentFactory(context: context).makeDueRepeats(profile: profile, now: day(11, 12), calendar: calendar)
        try #require(made.count == 2)
        #expect(made.map(\.number) == [1010, 1011])
        #expect(made.map { calendar.component(.day, from: $0.createdAt) } == [1, 8])
        #expect(made.allSatisfy { $0.status == .draft && $0.repeatSourceID == template.uuid && $0.client === client })
        #expect(made.allSatisfy { $0.repeatInterval == .never })
        #expect(made[0].dueDate.map { calendar.component(.day, from: $0) } == 8)
        #expect(made[0].allItems.first?.unitCost == 5)
        #expect(made[0].totals.total == template.totals.total)
        #expect(template.nextRepeatDate.map { calendar.component(.day, from: $0) } == 15)
        #expect(profile.nextInvoiceNumber == 1012)

        // Running again the same day makes nothing new.
        #expect(DocumentFactory(context: context).makeDueRepeats(profile: profile, now: day(11, 12), calendar: calendar).isEmpty)
    }

    @Test func `a copy another device already made is not made again`() throws {
        let context = try makeContext()
        let profile = BusinessProfile()
        context.insert(profile)
        let template = JobDocument(kind: .invoice, number: 1001, title: "Cleaning", language: .english, taxRate: 0)
        context.insert(template)
        template.repeatInterval = .monthly
        template.nextRepeatDate = day(11, 1)
        let synced = JobDocument(kind: .invoice, number: 1002, title: "Cleaning", language: .english, taxRate: 0)
        context.insert(synced)
        synced.createdAt = day(11, 1)
        synced.repeatSourceID = template.uuid

        let made = DocumentFactory(context: context).makeDueRepeats(profile: profile, now: day(11, 12), calendar: calendar)
        #expect(made.isEmpty)
        #expect(template.nextRepeatDate.map { calendar.component(.month, from: $0) } == 12)
    }

    @Test func `the morning a repeat is due, a reminder says it is ready`() throws {
        let context = try makeContext()
        let template = JobDocument(kind: .invoice, number: 1004, title: "Lawn", language: .english, taxRate: 0)
        context.insert(template)
        template.repeatInterval = .monthly
        template.nextRepeatDate = day(12, 1)
        let plan = ReminderScheduler.plan(for: [template], now: day(11, 12), calendar: calendar)
        try #require(plan.count == 1)
        #expect(plan[0].kind == .repeatReady)
        #expect(plan[0].fireDate == calendar.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 9)))
        #expect(plan[0].body.contains("INV-1004"))
    }

    // MARK: Report

    private func row(_ number: String, paid: Date, revenue: Double, tax: Double = 0, cost: Double = 0, client: String = "Ana") -> ProfitReport.Row {
        ProfitReport.Row(id: UUID(), paidAt: paid, number: number, client: client, job: "Job", revenue: revenue, tax: tax, materialsCost: cost)
    }

    @Test func `a month report counts only jobs paid that month`() {
        let rows = [
            row("INV-1", paid: day(11, 3), revenue: 1000, tax: 82.5, cost: 300),
            row("INV-2", paid: day(11, 28), revenue: 500, cost: 0),
            row("INV-3", paid: day(10, 31), revenue: 999),
            row("INV-4", paid: day(12, 1), revenue: 999),
        ]
        let report = ProfitReport(rows: rows, period: .month, containing: day(11, 12), calendar: calendar)
        #expect(report.rows.map(\.number) == ["INV-1", "INV-2"])
        #expect(report.revenue == 1500)
        #expect(report.tax == 82.5)
        #expect(report.total == 1582.5)
        #expect(report.materialsCost == 300)
        #expect(report.profit == 1200)

        let year = ProfitReport(rows: rows, period: .year, containing: day(11, 12), calendar: calendar)
        #expect(year.rows.count == 4)
    }

    @Test func `the csv quotes commas and ends with totals`() {
        let report = ProfitReport(rows: [row("INV-1", paid: day(11, 3), revenue: 1000, tax: 82.5, cost: 300, client: "López, María")],
                                  period: .month, containing: day(11, 12), calendar: calendar)
        let lines = report.csv(language: .english).split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Date paid,Number,Client,Job,Revenue (before tax)"))
        #expect(lines[1].contains(",INV-1,\"López, María\",Job,1000.00,82.50,1082.50,300.00,700.00"))
        #expect(lines[2] == "Totals,,,,1000.00,82.50,1082.50,300.00,700.00")
        #expect(report.csv(language: .spanish).hasPrefix("Fecha de pago,Número,Cliente"))
    }

    @Test func `report rows come only from paid documents and use recorded costs`() throws {
        let context = try makeContext()
        let invoice = JobDocument(kind: .invoice, number: 1001, title: "Paint", language: .english, taxRate: 10)
        context.insert(invoice)
        let labor = LineItem(text: "Labor", quantity: 8, unitPrice: 50, isLabor: true, isTaxable: false)
        let paint = LineItem(text: "Paint", quantity: 2, unitPrice: 40)
        paint.unitCost = 30
        for line in [labor, paint] {
            context.insert(line)
            line.document = invoice
        }
        #expect(ProfitReport.Row(invoice) == nil)
        invoice.apply(status: .paid)
        let row = try #require(ProfitReport.Row(invoice))
        #expect(row.revenue == 480)
        #expect(row.tax == 8)
        #expect(row.materialsCost == 60)
        #expect(row.profit == 420)
    }

    @Test func `exported files are written`() throws {
        let report = ProfitReport(rows: [row("INV-1", paid: day(11, 3), revenue: 1000)], period: .month, containing: day(11, 12), calendar: calendar)
        let files = try report.writeFiles(period: .month, business: "López Painting", language: .spanish)
        #expect(files.csv.pathExtension == "csv")
        #expect(try Data(contentsOf: files.pdf).starts(with: Data("%PDF".utf8)))
    }

    // MARK: iCloud

    @Test func `two profiles from two devices merge into the oldest`() throws {
        let context = try makeContext()
        let original = BusinessProfile()
        original.createdAt = day(1, 1)
        original.businessName = "López Painting"
        original.nextEstimateNumber = 1020
        let newPhone = BusinessProfile()
        newPhone.createdAt = day(11, 12)
        newPhone.phone = "(713) 555-0142"
        newPhone.nextEstimateNumber = 1001
        newPhone.nextInvoiceNumber = 1005
        context.insert(original)
        context.insert(newPhone)
        try context.save()

        AppDatabase.mergeDuplicateProfiles(in: context)
        let profiles = try context.fetch(FetchDescriptor<BusinessProfile>())
        try #require(profiles.count == 1)
        #expect(profiles[0].businessName == "López Painting")
        #expect(profiles[0].phone == "(713) 555-0142")
        #expect(profiles[0].nextEstimateNumber == 1020)
        #expect(profiles[0].nextInvoiceNumber == 1005)
    }
}

@Suite("Trade")
struct TradeTests {
    @Test @MainActor func `an unlisted trade uses what the contractor typed`() {
        let profile = BusinessProfile()
        profile.trade = .painting
        profile.customTrade = "pool cleaning"
        #expect(profile.tradeDescription == "painting")
        profile.trade = .other
        #expect(profile.tradeDescription == "pool cleaning")
        profile.customTrade = "   "
        #expect(profile.tradeDescription == "home services")
    }
}
