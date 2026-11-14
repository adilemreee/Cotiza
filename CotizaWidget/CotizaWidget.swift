import SwiftUI
import WidgetKit

private let accent = Color(red: 0.85, green: 0.33, blue: 0.08)
private let newEstimateURL = URL(string: "cotiza://new-estimate")!

struct SummaryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, snapshot: WidgetSnapshot(pending: 1250, paidThisMonth: 3400, awaitingCount: 2, overdueCount: 0, updatedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        // The app reloads the widget whenever the numbers change; the midnight refresh
        // only catches the start of a new month.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [current()], policy: .after(midnight)))
    }

    private func current() -> SummaryEntry {
        SummaryEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .empty)
    }
}

// MARK: - Money owed

struct SummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    private var pending: String { WidgetSnapshot.money(entry.snapshot.pending) }
    private var paid: String { WidgetSnapshot.money(entry.snapshot.paid(asOf: entry.date)) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Awaiting \(pending)", systemImage: "hourglass")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Awaiting payment", systemImage: "hourglass")
                    .font(.caption)
                    .widgetAccentable()
                Text(pending)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                if entry.snapshot.overdueCount > 0 {
                    Text("Overdue: \(entry.snapshot.overdueCount)").font(.caption)
                } else {
                    Text("Paid this month: \(paid)").font(.caption).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(spacing: 16) {
                amounts
                Link(destination: newEstimateURL) {
                    VStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(accent, in: Circle())
                        Text("New estimate")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
            }
        default:
            amounts
        }
    }

    private var amounts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Awaiting payment", systemImage: "hourglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(pending)
                .font(.title.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if entry.snapshot.overdueCount > 0 {
                Label("Overdue: \(entry.snapshot.overdueCount)", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            Text("Paid this month")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(paid)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CotizaSummary", provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Money owed")
        .description("What your clients still owe you and what came in this month.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Record button

struct RecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CotizaRecord", provider: SummaryProvider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .widgetAccentable()
            }
            .widgetURL(newEstimateURL)
            .containerBackground(.background, for: .widget)
            .accessibilityLabel("New estimate")
        }
        .configurationDisplayName("New estimate")
        .description("Start describing a job from the Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct CotizaWidgets: WidgetBundle {
    var body: some Widget {
        SummaryWidget()
        RecordWidget()
    }
}
