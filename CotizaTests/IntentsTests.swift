import Foundation
import SwiftData
import Testing
@testable import Cotiza

@MainActor
@Suite("Siri and Spotlight")
struct IntentsTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: BusinessProfile.self, Client.self, JobDocument.self, LineItem.self, PriceBookItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func document(_ kind: DocumentKind, _ status: DocumentStatus, total: Double, in context: ModelContext) -> JobDocument {
        let document = JobDocument(kind: kind, number: 1001, title: "Paint", language: .english, taxRate: 0)
        context.insert(document)
        let line = LineItem(text: "Work", quantity: 1, unitPrice: total)
        context.insert(line)
        line.document = document
        document.apply(status: status)
        return document
    }

    @Test func `money owed counts sent estimates and unpaid invoices`() throws {
        let context = try makeContext()
        let documents = [
            document(.estimate, .sent, total: 100, in: context),
            document(.estimate, .draft, total: 1000, in: context),
            document(.invoice, .sent, total: 250, in: context),
            document(.invoice, .approved, total: 50, in: context),
            document(.invoice, .draft, total: 7000, in: context),
            document(.invoice, .paid, total: 300, in: context),
        ]
        let summary = DocumentSummary(documents: documents)
        #expect(summary.pending == 400)
        #expect(summary.paidThisMonth == 300)
    }

    @Test func `payments from an earlier month are not this month's`() throws {
        let context = try makeContext()
        let old = document(.invoice, .paid, total: 300, in: context)
        old.paidAt = Calendar.current.date(byAdding: .month, value: -2, to: .now)
        #expect(DocumentSummary(documents: [old]).paidThisMonth == 0)
    }

    @Test func `marking paid keeps the first paid date and reopening clears it`() throws {
        let context = try makeContext()
        let invoice = document(.invoice, .paid, total: 10, in: context)
        let firstPaid = try #require(invoice.paidAt)
        invoice.apply(status: .paid)
        #expect(invoice.paidAt == firstPaid)
        invoice.apply(status: .approved)
        #expect(invoice.paidAt == nil)
    }

    @Test func `documents that share an id get their own`() throws {
        let context = try makeContext()
        let shared = UUID()
        let first = document(.estimate, .draft, total: 1, in: context)
        let second = document(.invoice, .draft, total: 2, in: context)
        first.uuid = shared
        second.uuid = shared
        try context.save()

        AppDatabase.repairDocumentIDs(in: context)
        #expect(first.uuid != second.uuid)
        #expect([first.uuid, second.uuid].contains(shared))
    }

    @Test func `the spotlight line shows number, client, total and status`() throws {
        let context = try makeContext()
        let estimate = document(.estimate, .sent, total: 1250, in: context)
        let client = Client(name: "Maria Lopez")
        context.insert(client)
        estimate.client = client
        let entity = DocumentEntity(estimate)
        #expect(entity.summaryLine.hasPrefix("E-1001 · Maria Lopez · "))
        #expect(entity.summaryLine.contains(Money.string(1250, locale: .current)))
        #expect(entity.id == estimate.uuid)
    }
}
