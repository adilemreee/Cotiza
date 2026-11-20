import Foundation
import WidgetKit

/// Writes the home-screen numbers for the widget and asks WidgetKit to redraw.
enum WidgetData {
    static func snapshot(of documents: [JobDocument], now: Date = .now) -> WidgetSnapshot {
        let summary = DocumentSummary(documents: documents, now: now)
        return WidgetSnapshot(
            pending: summary.pending,
            paidThisMonth: summary.paidThisMonth,
            awaitingCount: documents.count(where: \.isAwaitingPayment),
            overdueCount: documents.count { $0.isOverdue(now: now) },
            updatedAt: now,
            currencyCode: Money.currencyCode
        )
    }

    static func publish() {
        guard let documents = try? AppDatabase.allDocuments() else { return }
        let new = snapshot(of: documents)
        guard new != WidgetSnapshot.load() else { return }
        new.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
