import Foundation
import os
import UIKit
import UserNotifications

/// A follow-up the app should show on a given day.
nonisolated struct Reminder: Equatable, Sendable {
    enum Kind: String, Sendable { case followUp, overdue, repeatReady }

    let kind: Kind
    let documentID: UUID
    let fireDate: Date
    let title: String
    let body: String

    var identifier: String { "reminder.\(kind.rawValue).\(documentID.uuidString)" }
}

/// Local notifications for estimates waiting on an answer and invoices past their due date.
/// Nothing leaves the phone: these are scheduled on the device.
enum ReminderScheduler {
    /// Days after sending an estimate before Cotiza suggests following up.
    static let followUpDays = 3
    /// Reminders arrive in the morning, not at the minute the document was sent.
    static let hour = 9
    private static let prefix = "reminder."
    private static let logger = Logger(subsystem: "com.cotiza.app", category: "reminders")

    /// What should be scheduled right now. Dates already past are skipped; the app shows those itself.
    static func plan(for documents: [JobDocument], now: Date = .now, calendar: Calendar = .current) -> [Reminder] {
        followUps(documents, now: now, calendar: calendar) + repeats(documents, now: now, calendar: calendar)
    }

    /// The morning a recurring invoice is copied: "Maria Lopez · $120.00: a new copy of INV-1004 is ready to send."
    private static func repeats(_ documents: [JobDocument], now: Date, calendar: Calendar) -> [Reminder] {
        documents.compactMap { document in
            guard document.kind == .invoice, document.repeatInterval != .never, let next = document.nextRepeatDate,
                  let fire = morning(days: 0, after: next, calendar: calendar), fire > now else { return nil }
            let client = document.client?.name ?? ""
            let total = Money.string(document.totals.total, locale: .current)
            let who = client.isEmpty ? total : "\(client) · \(total)"
            return Reminder(
                kind: .repeatReady, documentID: document.uuid, fireDate: fire,
                title: String(localized: "Invoice ready to send"),
                body: String(localized: "\(who): a new copy of \(document.displayNumber) is ready to send.")
            )
        }
    }

    private static func followUps(_ documents: [JobDocument], now: Date, calendar: Calendar) -> [Reminder] {
        documents.compactMap { document in
            let client = document.client?.name ?? ""
            let total = Money.string(document.totals.total, locale: .current)
            switch document.kind {
            case .estimate:
                guard document.status == .sent, let sentAt = document.sentAt,
                      let fire = morning(days: followUpDays, after: sentAt, calendar: calendar), fire > now else { return nil }
                let who = client.isEmpty ? document.displayNumber : "\(document.displayNumber) · \(client)"
                return Reminder(
                    kind: .followUp, documentID: document.uuid, fireDate: fire,
                    title: String(localized: "Follow up on your estimate"),
                    body: String(localized: "\(who) has been waiting \(followUpDays) days for an answer (\(total)).")
                )
            case .invoice:
                guard document.status != .paid, document.status != .draft, let due = document.dueDate,
                      let fire = morning(days: 1, after: due, calendar: calendar), fire > now else { return nil }
                // After a partial payment, the reminder is about what is still owed.
                let owed = Money.string(document.balanceDue, locale: .current)
                let who = client.isEmpty ? owed : "\(client) · \(owed)"
                return Reminder(
                    kind: .overdue, documentID: document.uuid, fireDate: fire,
                    title: String(localized: "\(document.displayNumber) is overdue"),
                    body: String(localized: "\(who) was due \(due.formatted(.dateTime.day().month())).")
                )
            }
        }
    }

    private static func morning(days: Int, after date: Date, calendar: Calendar) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) else { return nil }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    /// Asks once, at the moment a reminder first becomes useful (the first document sent).
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Replaces every pending Cotiza reminder with what the documents call for now.
    static func sync() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let enabled = ((try? AppDatabase.context.fetch(.init()) as [BusinessProfile]) ?? []).first?.remindersEnabled ?? true
        guard enabled, await center.notificationSettings().authorizationStatus == .authorized,
              let documents = try? AppDatabase.allDocuments() else { return }

        for reminder in plan(for: documents) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["document": reminder.documentID.uuidString, "kind": reminder.kind.rawValue]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            do {
                try await center.add(request)
            } catch {
                logger.error("Couldn't schedule reminder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Opens the document behind a tapped reminder.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["document"] as? String, let id = UUID(uuidString: raw) else { return }
        let latestRepeat = info["kind"] as? String == Reminder.Kind.repeatReady.rawValue
        await MainActor.run {
            AppRouter.shared.opensLatestRepeat = latestRepeat
            AppRouter.shared.documentToOpen = id
        }
    }
}
