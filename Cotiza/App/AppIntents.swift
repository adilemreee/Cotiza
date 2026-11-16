import AppIntents
import CoreSpotlight
import Observation
import SwiftData

/// Lets Siri, Shortcuts, Spotlight and the Action button steer the app.
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var wantsNewEstimate = false
    /// A document Siri, Shortcuts or Spotlight asked to open.
    var documentToOpen: UUID?
    /// Set with `documentToOpen` when it is a recurring invoice and its newest copy should open instead.
    var opensLatestRepeat = false
    /// Bumped after a good moment (sent, approved, paid); the home screen then decides whether to ask for a rating.
    var reviewCheck = 0
    private init() {}
}

// MARK: - Document entity

/// An estimate or invoice as Siri, Shortcuts and Spotlight see it.
nonisolated struct DocumentEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Estimate or invoice" }
    static let defaultQuery = DocumentQuery()

    let id: UUID
    let kind: DocumentKind
    let number: String
    let title: String
    let clientName: String
    let total: Double
    let statusLabel: String
    let kindLabel: String

    @MainActor
    init(_ document: JobDocument) {
        id = document.uuid
        kind = document.kind
        number = document.displayNumber
        title = document.title.isEmpty ? String(localized: "Untitled job") : document.title
        clientName = document.client?.name ?? ""
        total = document.totals.total
        statusLabel = String(localized: document.status.label)
        kindLabel = String(localized: document.kind.label)
    }

    /// "E-1001 · Maria Lopez · $1,250.00 · Sent"
    var summaryLine: String {
        [number, clientName, Money.string(total, locale: .current), statusLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(summaryLine)",
            image: .init(systemName: kind == .estimate ? "doc.text" : "doc.text.fill")
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = title
        attributes.contentDescription = summaryLine
        // Searching a client's name, the number or the word "invoice" finds the document.
        attributes.keywords = [number, clientName, kindLabel].filter { !$0.isEmpty }
        return attributes
    }
}

nonisolated struct DocumentQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [DocumentEntity] {
        try AppDatabase.documents(ids: identifiers).map(DocumentEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [DocumentEntity] {
        try AppDatabase.allDocuments().prefix(20).map(DocumentEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [DocumentEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try await suggestedEntities() }
        return try AppDatabase.allDocuments()
            .filter { document in
                [document.title, document.client?.name ?? "", document.displayNumber, String(document.number)]
                    .contains { $0.localizedStandardContains(query) }
            }
            .map(DocumentEntity.init)
    }
}

enum CotizaIntentError: Error, CustomLocalizedStringResourceConvertible {
    case documentNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .documentNotFound: "That document is no longer in Precia."
        }
    }
}

// MARK: - Intents

struct StartEstimateIntent: AppIntent {
    static let title: LocalizedStringResource = "New estimate"
    static let description = IntentDescription("Open Precia ready to describe a job by voice.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.wantsNewEstimate = true
        return .result()
    }
}

/// Also what runs when someone taps a Cotiza document in Spotlight.
struct OpenDocumentIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open document"
    static let description = IntentDescription("Opens an estimate or invoice in Precia.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Document", requestValueDialog: "Which estimate or invoice?")
    var target: DocumentEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.documentToOpen = target.id
        return .result()
    }
}

struct MoneyOwedIntent: AppIntent {
    static let title: LocalizedStringResource = "Money owed to me"
    static let description = IntentDescription("Says how much your clients still owe you and how much you were paid this month.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let summary = DocumentSummary(documents: try AppDatabase.allDocuments())
        let pending = Money.string(summary.pending, locale: .current)
        let paid = Money.string(summary.paidThisMonth, locale: .current)
        return .result(value: summary.pending, dialog: "Awaiting payment: \(pending). Paid this month: \(paid).")
    }
}

struct MarkPaidIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark as paid"
    static let description = IntentDescription("Marks an estimate or invoice as paid.")

    @Parameter(title: "Document", requestValueDialog: "Which one was paid?")
    var document: DocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$document) as paid")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = try AppDatabase.document(id: document.id) else { throw CotizaIntentError.documentNotFound }
        model.apply(status: .paid)
        try AppDatabase.context.save()
        await SpotlightIndexer.index([model])
        WidgetData.publish()
        await ReminderScheduler.sync()
        let number = model.displayNumber
        let total = Money.string(model.totals.total, locale: .current)
        return .result(dialog: "\(number) is paid: \(total).")
    }
}

// MARK: - Shortcuts

struct CotizaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartEstimateIntent(),
            phrases: [
                "New estimate in \(.applicationName)",
                "Start an estimate with \(.applicationName)",
            ],
            shortTitle: "New estimate",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: MoneyOwedIntent(),
            phrases: [
                "How much am I owed in \(.applicationName)",
                "What do my clients owe me in \(.applicationName)",
                "Check my payments in \(.applicationName)",
            ],
            shortTitle: "Money owed to me",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: MarkPaidIntent(),
            phrases: [
                "Mark \(\.$document) as paid in \(.applicationName)",
                "Mark a job as paid in \(.applicationName)",
            ],
            shortTitle: "Mark as paid",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: OpenDocumentIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Find a job in \(.applicationName)",
            ],
            shortTitle: "Open document",
            systemImageName: "doc.text.magnifyingglass"
        )
    }
}
