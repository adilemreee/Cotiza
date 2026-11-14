import Foundation
import PDFKit
import StoreKitTest
import Testing
@testable import Cotiza

@Suite("PDF")
struct PDFTests {
    private func snapshot(itemCount: Int, language: DocumentLanguage = .english, kind: DocumentKind = .estimate) -> DocumentSnapshot {
        let items = (1...itemCount).map { index in
            DocumentSnapshot.Item(text: "Install interior door number \(index) including hardware and trim", quantity: 2, unit: "", unitPrice: 120, amount: 240)
        }
        return DocumentSnapshot(
            kind: kind, language: language, displayNumber: "E-1001", title: "Kitchen remodel", date: .now, isPaid: false,
            businessName: "López Painting LLC", ownerName: "Carlos López", businessPhone: "(555) 123-4567",
            businessEmail: "carlos@example.com", businessAddress: "12 Main St, Houston, TX", licenseNumber: "TX-99812", logo: nil,
            clientName: "Maria Lopez", clientPhone: "", clientEmail: "", clientAddress: "44 Oak Ave",
            items: items,
            totals: Totals(lines: items.map { .init(amount: $0.amount, isTaxable: true) }, taxRate: 8.25),
            taxRate: 8.25, notes: "Work starts Monday.", terms: "50% deposit.", paymentInstructions: "Zelle", showsBranding: true
        )
    }

    @Test func `a short estimate fits on one page with the expected text`() throws {
        let data = PDFRenderer().render(snapshot(itemCount: 3))
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1)
        let text = try #require(pdf.string)
        #expect(text.contains("ESTIMATE"))
        #expect(text.contains("López Painting LLC"))
        #expect(text.contains("Maria Lopez"))
        #expect(text.contains("$779.40"))
        #expect(text.contains("Made with Cotiza"))
    }

    @Test func `a long estimate flows onto more pages without losing lines`() throws {
        let data = PDFRenderer().render(snapshot(itemCount: 60))
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount >= 2)
        let text = try #require(pdf.string)
        #expect(text.contains("door number 1 "))
        #expect(text.contains("door number 60"))
    }

    @Test func `spanish documents use spanish labels`() throws {
        let data = PDFRenderer().render(snapshot(itemCount: 2, language: .spanish, kind: .invoice))
        let text = try #require(PDFDocument(data: data)?.string)
        #expect(text.contains("FACTURA"))
        #expect(text.contains("Total a pagar".uppercased()))
        #expect(text.contains("Formas de pago".uppercased()))
    }
}

@Suite("Subscription", .serialized)
struct SubscriptionTests {
    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "cotiza-tests-\(UUID().uuidString)"))
    }

    @Test func `free accounts get three estimates`() throws {
        let store = SubscriptionStore(defaults: try makeDefaults())
        #expect(store.canCreateEstimate)
        store.recordEstimateCreated()
        store.recordEstimateCreated()
        #expect(store.freeEstimatesLeft == 1)
        store.recordEstimateCreated()
        #expect(!store.canCreateEstimate)
    }

    @Test func `buying the yearly plan unlocks pro`() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let store = SubscriptionStore(defaults: try makeDefaults())
        // The local StoreKit test server can take a moment to start serving a new session.
        for _ in 0..<60 where store.products.isEmpty {
            await store.loadProducts()
            if store.products.isEmpty { try await Task.sleep(for: .milliseconds(500)) }
        }
        #expect(store.products.map(\.id) == SubscriptionStore.productIDs)

        let yearly = try #require(store.yearly)
        #expect(yearly.subscription?.introductoryOffer?.paymentMode == .freeTrial)
        let trial = try #require(yearly.subscription?.introductoryOffer?.period)
        #expect(trial.unit == .day && trial.value == 3)
        let week = try #require(store.weekly?.subscription?.subscriptionPeriod)
        #expect(week.unit == .week && week.value == 1)
        #expect(store.monthly?.subscription?.introductoryOffer == nil)
        #expect(!store.isPro)

        let purchased = try await store.purchase(yearly)
        #expect(purchased)
        #expect(store.isPro)
        #expect(store.canCreateEstimate)
    }
}
