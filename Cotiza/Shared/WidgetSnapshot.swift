import Foundation

/// The numbers the widget shows. Compiled into both the app and the widget extension;
/// the app writes it to the shared App Group after every change it mirrors to the system.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroup = "group.com.cotiza.app"
    private static let key = "widgetSnapshot"

    var pending: Double
    var paidThisMonth: Double
    var awaitingCount: Int
    var overdueCount: Int
    var updatedAt: Date
    /// The business's currency; snapshots saved before it existed decode as dollars.
    var currencyCode: String? = nil

    static let empty = WidgetSnapshot(pending: 0, paidThisMonth: 0, awaitingCount: 0, overdueCount: 0, updatedAt: .distantPast)

    static func load(from defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    /// "Paid this month" resets when a new month starts, even if the app hasn't been opened since.
    func paid(asOf now: Date, calendar: Calendar = .current) -> Double {
        calendar.isDate(updatedAt, equalTo: now, toGranularity: .month) ? paidThisMonth : 0
    }

    /// "$1,250" — cents only when there are any, so the number fits a small widget.
    static func money(_ value: Double, currency: String? = nil, locale: Locale = .current) -> String {
        let hasCents = (value * 100).rounded().truncatingRemainder(dividingBy: 100) != 0
        return value.formatted(.currency(code: currency ?? "USD").precision(.fractionLength(hasCents ? 2 : 0)).locale(locale))
    }
}
