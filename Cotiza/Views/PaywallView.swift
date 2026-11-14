import StoreKit
import SwiftUI

/// Legal and support links, served from https://cotiza.adilemree.xyz (source: AppStore/site).
/// Spanish-speaking users get the Spanish pages.
enum AppLinks {
    static let site = "https://cotiza.adilemree.xyz"
    static let supportEmail = "destek@adilemree.xyz"

    private static var languagePrefix: String {
        Locale.current.language.languageCode == .spanish ? "/es" : ""
    }

    /// Subscription terms; the page links Apple's Standard EULA.
    static var terms: URL { page("/terms") }
    static var privacy: URL { page("/privacy") }
    static var supportPage: URL { page("/support") }
    static var support: URL { URL(string: "mailto:\(supportEmail)") ?? supportPage }

    /// The numeric Apple ID from App Store Connect (App Information). Until it's set, the
    /// "Rate Cotiza" row stays hidden; the in-app rating prompt works without it.
    static let appStoreID: String? = nil
    static var writeReview: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }

    private static func page(_ path: String) -> URL {
        // Built from constants, so this never fails; the fallback keeps it from ever trapping.
        URL(string: site + languagePrefix + path) ?? URL(filePath: "/")
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionStore.self) private var store

    @State private var selectedID = SubscriptionStore.yearlyID
    @State private var trialEligible = false
    @State private var errorMessage: String?
    @State private var isRestoring = false

    /// What the plan cards show. Built from StoreKit products so prices always match the App Store.
    private struct Plan: Identifiable {
        let id: String
        let product: Product?
        let title: LocalizedStringResource
        let price: String
        let detail: String?
        let badge: String?
        let trialDays: Int?
    }

    private var plans: [Plan] {
        var result: [Plan] = []
        if let yearly = store.yearly {
            let perMonth = (yearly.price / 12).formatted(yearly.priceFormatStyle)
            var badge: String?
            if let monthly = store.monthly, monthly.price > 0 {
                let saving = 1 - (yearly.price / (monthly.price * 12))
                let percent = Int((NSDecimalNumber(decimal: saving).doubleValue * 100).rounded())
                if percent >= 5 { badge = String(localized: "Save \(percent)%") }
            }
            result.append(Plan(
                id: yearly.id, product: yearly, title: "Yearly",
                price: String(localized: "\(yearly.displayPrice) per year"),
                detail: String(localized: "Only \(perMonth) per month"),
                badge: badge,
                trialDays: trialEligible ? Self.trialDays(of: yearly) : nil
            ))
        }
        if let monthly = store.monthly {
            result.append(Plan(
                id: monthly.id, product: monthly, title: "Monthly",
                price: String(localized: "\(monthly.displayPrice) per month"),
                detail: nil, badge: nil,
                trialDays: trialEligible ? Self.trialDays(of: monthly) : nil
            ))
        }
        if let weekly = store.weekly {
            result.append(Plan(
                id: weekly.id, product: weekly, title: "Weekly",
                price: String(localized: "\(weekly.displayPrice) per week"),
                detail: nil, badge: nil,
                trialDays: trialEligible ? Self.trialDays(of: weekly) : nil
            ))
        }
        #if DEBUG
        if result.isEmpty, UserDefaults.standard.bool(forKey: "CotizaMockPlans") {
            result = [
                Plan(id: SubscriptionStore.yearlyID, product: nil, title: "Yearly", price: String(localized: "\("$99.99") per year"),
                     detail: String(localized: "Only \("$8.33") per month"), badge: String(localized: "Save \(44)%"), trialDays: 3),
                Plan(id: SubscriptionStore.monthlyID, product: nil, title: "Monthly", price: String(localized: "\("$14.99") per month"),
                     detail: nil, badge: nil, trialDays: nil),
                Plan(id: SubscriptionStore.weeklyID, product: nil, title: "Weekly", price: String(localized: "\("$4.99") per week"),
                     detail: nil, badge: nil, trialDays: nil),
            ]
        }
        #endif
        return result
    }

    private var selectedPlan: Plan? {
        plans.first { $0.id == selectedID } ?? plans.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    features
                    planSection
                }
                .readableWidth(560)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { footer }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task(id: store.products.map(\.id)) {
                if let subscription = store.yearly?.subscription {
                    trialEligible = await subscription.isEligibleForIntroOffer
                }
            }
            .task {
                // A failed load (no connection at launch) shouldn't leave the paywall empty.
                if store.loadState == .failed { await store.loadProducts() }
            }
            .sensoryFeedback(.success, trigger: store.isPro) { _, new in new }
            .onChange(of: store.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Cotiza Pro")
                .font(.largeTitle.bold())
            Text("Look professional. Win more jobs. Get paid faster.")
                .font(.body)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            feature("infinity", "Unlimited estimates", "Quote every job, every day.")
            feature("doc.text.fill", "Invoices in one tap", "Turn an approved estimate into an invoice and track who paid.")
            feature("signature", "Client signs on your phone", "Approved on the spot, with the signature on the PDF.")
            feature("chart.bar.xaxis", "Profit reports", "Income, materials and profit by month, ready for your accountant.")
            feature("photo.badge.checkmark.fill", "Your logo, your brand", "No Cotiza footer on what your client sees.")
            feature("book.closed.fill", "Remembers your prices", "Your usual prices fill in by themselves.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(Color.secondary)
            }
        }
    }

    @ViewBuilder
    private var planSection: some View {
        if !plans.isEmpty {
            VStack(spacing: 10) {
                ForEach(plans) { plan in
                    planCard(plan)
                }
            }
        } else if store.loadState == .loading {
            ProgressView()
                .padding(.vertical, 30)
        } else {
            VStack(spacing: 10) {
                Text("Plans couldn't be loaded. Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await store.loadProducts() }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 16)
        }
    }

    private func planCard(_ plan: Plan) -> some View {
        let selected = plan.id == selectedPlan?.id
        return Button {
            selectedID = plan.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.headline)
                            .fixedSize()
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .foregroundStyle(.white)
                                .background(Color.green, in: Capsule())
                        }
                    }
                    Text(plan.price)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    if let detail = plan.detail {
                        Text(detail)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectedID)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                purchase()
            } label: {
                if store.isPurchasing {
                    ProgressView().tint(.white)
                } else if let days = selectedPlan?.trialDays {
                    Text("Try \(days) days free")
                } else {
                    Text("Subscribe")
                }
            }
            .buttonStyle(.primary)
            .disabled(selectedPlan == nil || store.isPurchasing)

            if let plan = selectedPlan {
                Group {
                    if plan.trialDays != nil {
                        Text("Free trial, then \(plan.price). Renews automatically. Cancel anytime in the App Store.")
                    } else {
                        Text("\(plan.price). Renews automatically. Cancel anytime in the App Store.")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 18) {
                Button("Restore purchases") { restore() }
                    .disabled(isRestoring)
                Link("Terms", destination: AppLinks.terms)
                Link("Privacy", destination: AppLinks.privacy)
            }
            .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: Actions

    private func purchase() {
        guard let product = selectedPlan?.product else { return }
        Task {
            do {
                if try await store.purchase(product) { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                try await store.restore()
                if !store.isPro {
                    errorMessage = String(localized: "No active subscription was found for this Apple Account.")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func trialDays(of product: Product) -> Int? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let multiplier = switch offer.period.unit {
        case .day: 1
        case .week: 7
        case .month: 30
        case .year: 365
        @unknown default: 1
        }
        return offer.period.value * multiplier
    }
}
