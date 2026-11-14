import StoreKit
import SwiftData
import SwiftUI

struct HomeView: View {
    @Bindable var profile: BusinessProfile

    @Environment(\.modelContext) private var context
    @Environment(SubscriptionStore.self) private var store
    @Environment(\.requestReview) private var requestReview
    @Query(sort: \JobDocument.createdAt, order: .reverse) private var documents: [JobDocument]

    @State private var path = NavigationPath()
    @State private var filter: Filter = .all
    @State private var showsCapture = false
    @State private var showsPaywall = false
    @State private var showsSettings = false
    @State private var showsReports = false
    @State private var router = AppRouter.shared
    @AppStorage("didOfferTrial") private var didOfferTrial = false

    enum Filter: Hashable, CaseIterable {
        case all, estimates, invoices

        var label: LocalizedStringResource {
            switch self {
            case .all: "All"
            case .estimates: "Estimates"
            case .invoices: "Invoices"
            }
        }
    }

    private var filtered: [JobDocument] {
        switch filter {
        case .all: documents
        case .estimates: documents.filter { $0.kind == .estimate }
        case .invoices: documents.filter { $0.kind == .invoice }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if documents.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        SummaryCard(documents: documents)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(filtered) { document in
                            NavigationLink(value: document) {
                                DocumentRow(document: document)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    context.delete(document)
                                }
                            }
                        }
                        if filtered.isEmpty {
                            Text("Nothing here yet.")
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .listSectionSpacing(14)
            .readableListWidth()
            .navigationTitle("Cotiza")
            .navigationDestination(for: JobDocument.self) { document in
                DocumentEditorView(document: document, profile: profile) { created in
                    path.append(created)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reports", systemImage: "chart.bar.xaxis") {
                        if store.isPro { showsReports = true } else { showsPaywall = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                }
                if !store.isPro {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showsPaywall = true
                        } label: {
                            Label("Go Pro", systemImage: "crown.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                newEstimateBar
            }
        }
        .fullScreenCover(isPresented: $showsCapture) {
            CaptureView(profile: profile) { document in
                showsCapture = false
                path.append(document)
            }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(profile: profile)
        }
        .sheet(isPresented: $showsReports) {
            ReportView(profile: profile)
        }
        .onChange(of: router.documentToOpen, initial: true) { _, id in
            // Set by Siri, Shortcuts or a Spotlight result.
            guard let id else { return }
            router.documentToOpen = nil
            let latestRepeat = router.opensLatestRepeat
            router.opensLatestRepeat = false
            if latestRepeat { RecurringInvoices.run() }
            // A "ready to send" reminder points at the recurring invoice; open the copy it just made.
            let copy = latestRepeat
                ? documents.filter { $0.repeatSourceID == id }.max { $0.createdAt < $1.createdAt }
                : nil
            guard let document = copy ?? documents.first(where: { $0.uuid == id }) else { return }
            showsCapture = false
            showsSettings = false
            showsReports = false
            showsPaywall = false
            path = NavigationPath([document])
        }
        .onChange(of: router.wantsNewEstimate, initial: true) { _, wants in
            // Set by the "New estimate" Siri shortcut.
            guard wants else { return }
            router.wantsNewEstimate = false
            didOfferTrial = true
            startNewEstimate()
        }
        #if DEBUG
        .task { await openScreenshotScene() }
        #endif
        .task(id: router.reviewCheck) {
            guard router.reviewCheck > 0, ReviewPrompt().shouldAsk() else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            ReviewPrompt().markAsked()
            requestReview()
        }
        // Haptics: a new document lands, one is deleted, the filter changes.
        .sensoryFeedback(.success, trigger: documents.count) { old, new in new > old }
        .sensoryFeedback(.impact(weight: .light), trigger: documents.count) { old, new in new < old }
        .sensoryFeedback(.selection, trigger: filter)
        .task {
            // Offer the free trial once, right after setup, while intent is highest.
            guard !didOfferTrial, !store.isPro else { return }
            try? await Task.sleep(for: .seconds(0.6))
            didOfferTrial = true
            showsPaywall = true
        }
    }

    #if DEBUG
    private func openScreenshotScene() async {
        guard let scene = ScreenshotScene.current else { return }
        didOfferTrial = true
        try? await Task.sleep(for: .seconds(0.3))
        switch scene {
        case .capture: showsCapture = true
        case .editor, .pdf, .signature: router.documentToOpen = ScreenshotScene.heroID
        case .report: showsReports = true
        case .paywall: showsPaywall = true
        case .home: break
        }
    }
    #endif

    private func startNewEstimate() {
        if store.canCreateEstimate {
            showsCapture = true
        } else {
            showsPaywall = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text("Your first estimate takes one minute")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Tap the button below and describe the job out loud, with your prices.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
        .padding(.horizontal, 12)
    }

    private var newEstimateBar: some View {
        VStack(spacing: 8) {
            Button {
                startNewEstimate()
            } label: {
                Label("New estimate", systemImage: "mic.fill")
            }
            .buttonStyle(.primary)

            if !store.isPro {
                Text("Free plan: \(store.freeEstimatesLeft) of \(SubscriptionStore.freeEstimateLimit) estimates left")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

// MARK: - Summary

private struct SummaryCard: View {
    let documents: [JobDocument]

    private var summary: DocumentSummary { DocumentSummary(documents: documents) }

    var body: some View {
        HStack(spacing: 12) {
            metric("Awaiting reply", value: summary.pending, symbol: "hourglass", tint: .blue)
            metric("Paid this month", value: summary.paidThisMonth, symbol: "checkmark.seal.fill", tint: .green)
        }
    }

    private func metric(_ title: LocalizedStringKey, value: Double, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(Money.string(value, locale: .current))
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Row

private struct DocumentRow: View {
    let document: JobDocument

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title.isEmpty ? String(localized: "Untitled job") : document.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(document.displayNumber)
                        .monospacedDigit()
                        .fixedSize()
                    if document.repeatInterval != .never {
                        Image(systemName: "repeat")
                            .accessibilityLabel(Text(document.repeatInterval.label))
                    }
                    if let name = document.client?.name, !name.isEmpty {
                        Text("·")
                        Text(name).lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(Money.string(document.totals.total, locale: .current))
                    .font(.headline)
                    .monospacedDigit()
                if document.isOverdue() {
                    Text("Overdue")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.14), in: Capsule())
                } else {
                    StatusBadge(status: document.status)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 4)
    }
}
