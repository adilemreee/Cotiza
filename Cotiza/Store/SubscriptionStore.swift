import Foundation
import Observation
import StoreKit
import os

/// Owns the Pro subscription: products, purchase, restore and the current entitlement.
@Observable
final class SubscriptionStore {
    static let monthlyID = "com.cotiza.app.pro.monthly"
    static let yearlyID = "com.cotiza.app.pro.yearly"
    static let weeklyID = "com.cotiza.app.pro.weekly"
    /// Order shown on the paywall: the yearly plan (with the free trial) first.
    static let productIDs = [yearlyID, monthlyID, weeklyID]
    /// Estimates a free account can create before the paywall.
    static let freeEstimateLimit = 3

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var products: [Product] = []
    private(set) var loadState: LoadState = .loading
    private(set) var isPro = false
    private(set) var isPurchasing = false
    private(set) var estimatesCreated: Int

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    private static let createdKey = "estimatesCreated"
    private static let logger = Logger(subsystem: "com.cotiza.app", category: "store")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        estimatesCreated = defaults.integer(forKey: Self.createdKey)
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await refreshEntitlement()
            await loadProducts()
        }
    }

    var canCreateEstimate: Bool {
        isPro || estimatesCreated < Self.freeEstimateLimit
    }

    var freeEstimatesLeft: Int {
        max(Self.freeEstimateLimit - estimatesCreated, 0)
    }

    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var weekly: Product? { products.first { $0.id == Self.weeklyID } }

    func recordEstimateCreated() {
        estimatesCreated += 1
        defaults.set(estimatesCreated, forKey: Self.createdKey)
    }

    func loadProducts() async {
        loadState = .loading
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Self.productIDs.compactMap { id in loaded.first { $0.id == id } }
            loadState = products.isEmpty ? .failed : .loaded
        } catch {
            Self.logger.error("Product load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed
        }
    }

    /// Returns true when the purchase completed and Pro is now active.
    func purchase(_ product: Product) async throws -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return false }
            await transaction.finish()
            await refreshEntitlement()
            return isPro
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        #if DEBUG
        // Lets screenshots and manual QA exercise Pro screens without a StoreKit session.
        if UserDefaults.standard.bool(forKey: "CotizaForcePro") { active = true }
        #endif
        isPro = active
    }
}
