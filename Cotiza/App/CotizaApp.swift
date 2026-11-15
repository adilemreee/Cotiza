import SwiftData
import SwiftUI

@main
struct CotizaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: SubscriptionStore
    @State private var showsSplash = true
    private let container: ModelContainer

    init() {
        #if DEBUG
        // `CotizaCloudKitDebug=1` in the environment: Core Data's iCloud sync log on stderr, before the
        // database opens. Registered, not saved, so it is gone on the next launch.
        if ProcessInfo.processInfo.environment["CotizaCloudKitDebug"] != nil {
            UserDefaults.standard.register(defaults: ["com.apple.CoreData.CloudKitDebug": 3,
                                                      "com.apple.CoreData.Logging.stderr": 1])
        }
        CloudKitReport.watchIfRequested()
        // `-CotizaResetState YES` (UI tests) starts like a fresh install: no settings, nothing saved to disk.
        if UserDefaults.standard.bool(forKey: "CotizaResetState") {
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        }
        #endif
        // Created after any reset so it reads the fresh free-estimate count.
        _store = State(initialValue: SubscriptionStore())
        container = AppDatabase.container
        #if DEBUG
        Self.seedDemoDataIfRequested(in: container)
        CloudKitReport.runIfRequested()
        // Screenshots show the screen itself, not the launch animation.
        if ScreenshotScene.current != nil { _showsSplash = State(initialValue: false) }
        #endif
    }

    #if DEBUG
    /// `-CotizaDemoData YES` starts with a filled-in business so screens can be checked without typing.
    private static func seedDemoDataIfRequested(in container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "CotizaDemoData") else { return }
        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<BusinessProfile>())) ?? []
        if existing.isEmpty {
            let profile = BusinessProfile()
            profile.businessName = "López Painting LLC"
            profile.ownerName = "Carlos López"
            profile.phone = "(713) 555-0142"
            profile.email = "carlos@lopezpainting.example"
            profile.address = "2210 Harrisburg Blvd, Houston, TX 77003"
            profile.licenseNumber = "TX-48213"
            profile.trade = .painting
            profile.defaultTaxRate = 8.25
            profile.terms = "50% deposit to start, balance on completion."
            profile.paymentInstructions = "Zelle (713) 555-0142, check or cash."
            context.insert(profile)
            try? context.save()
        }
        defaults.set(true, forKey: "hasOnboarded")
        defaults.set(true, forKey: "didOfferTrial")
        if defaults.bool(forKey: "CotizaDemoPaid") { seedPaidJobs(in: context) }
        ScreenshotScene.seed(in: context)
    }

    /// `-CotizaDemoPaid YES`: three paid jobs this month, one with receipt costs and a monthly repeat,
    /// so the report and recurring invoices can be checked.
    private static func seedPaidJobs(in context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<JobDocument>())) == 0,
              let profile = try? context.fetch(FetchDescriptor<BusinessProfile>()).first else { return }
        let jobs: [(String, String, [(String, Double, Double, Double)], Int, RepeatInterval)] = [
            ("Pintar la sala", "Maria Lopez", [("Pintar la sala", 400, 2, 0), ("Interior Paint Gal", 2, 20.12, 17.49)], 3, .never),
            ("Lawn care", "Ana Pérez", [("Mow and edge", 1, 60, 0), ("Fertilizer", 1, 28.74, 24.99)], 1, .monthly),
            ("Fix kitchen sink", "John Smith", [("Labor", 3, 65, 0)], 8, .never),
        ]
        let factory = DocumentFactory(context: context)
        for (title, clientName, lines, day, interval) in jobs {
            let draft = EstimateDraft(title: title, clientName: clientName, items: lines.map {
                DraftItem(text: $0.0, quantity: $0.1, unitPrice: $0.2)
            })
            let estimate = factory.makeEstimate(from: draft, transcript: "", profile: profile)
            let invoice = factory.makeInvoice(from: estimate, profile: profile)
            for (line, item) in zip(invoice.sortedItems, lines) { line.unitCost = item.3 }
            // This month's `day` (date(bySetting:) would jump to next month for days already past).
            var parts = Calendar.current.dateComponents([.year, .month], from: .now)
            parts.day = day
            parts.hour = 12
            let date = Calendar.current.date(from: parts) ?? .now
            invoice.createdAt = date
            invoice.apply(status: .paid)
            invoice.paidAt = date
            invoice.setRepeat(interval)
        }
        // A job with half paid up front: the deposit moves to the invoice, which still owes the rest.
        let draft = EstimateDraft(title: "Pintar exterior", clientName: "Luis Ramos", items: [
            DraftItem(text: "Pintar exterior de la casa", quantity: 1, unitPrice: 1800),
        ])
        let estimate = factory.makeEstimate(from: draft, transcript: "", profile: profile)
        estimate.depositPercent = 50
        factory.record(payment: estimate.depositAmount, on: .now.addingTimeInterval(-86_400 * 2), method: .zelle, to: estimate)
        let invoice = factory.makeInvoice(from: estimate, profile: profile)
        invoice.apply(status: .sent)
        try? context.save()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(store)
                if showsSplash {
                    SplashView { showsSplash = false }
                        .zIndex(1)
                }
            }
        }
        .modelContainer(container)
        // Collects signatures from signing links while the app isn't open (see SignLinkSync).
        .backgroundTask(.appRefresh(SignLinkSync.taskID)) {
            await SignLinkSync.run()
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [BusinessProfile]
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        Group {
            // A profile that arrived from iCloud counts as set up, so a new iPhone skips onboarding.
            if let profile = profiles.first {
                HomeView(profile: profile)
            } else {
                OnboardingView { hasOnboarded = true }
            }
        }
        .animation(.smooth, value: hasOnboarded)
        .task {
            // After the splash: indexing and scheduling on launch would otherwise slow its animation.
            try? await Task.sleep(for: .seconds(2))
            await Self.refreshSystemViews()
        }
        .onChange(of: profiles.count) { _, count in
            if count > 1 { AppDatabase.mergeDuplicateProfiles(in: context) }
            if count > 0 { hasOnboarded = true }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Recurring invoices whose day came while the app was closed.
                if !RecurringInvoices.run().isEmpty { Task { await Self.refreshSystemViews() } }
                Task { await SignLinkSync.run() }
            case .background:
                // Catches every edit, new document and deletion made while the app was open.
                try? context.save()
                Task { await Self.refreshSystemViews() }
            default:
                break
            }
        }
        .onOpenURL { url in
            // From the widget: cotiza://new-estimate
            if url.host() == "new-estimate" { AppRouter.shared.wantsNewEstimate = true }
        }
    }
}

extension RootView {
    /// Spotlight, Siri's document list, the widget and reminders all mirror the database.
    static func refreshSystemViews() async {
        RecurringInvoices.run()
        await SignLinkSync.run()
        await SpotlightIndexer.reindexAll()
        WidgetData.publish()
        await ReminderScheduler.sync()
    }
}
