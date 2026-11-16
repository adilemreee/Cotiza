#if DEBUG
import CloudKit
import CoreData
import Foundation

/// `-CotizaCloudKitReport YES`: asks iCloud what is really stored for this user, counted by record type,
/// and writes it to Documents/cloudkit-report.txt (and the console). For checking sync on a device
/// without relying on CloudKit Console.
enum CloudKitReport {
    /// `CotizaCloudKitDebug=1`: prints every sync step (setup, import, export) with its full error.
    static func watchIfRequested() {
        guard ProcessInfo.processInfo.environment["CotizaCloudKitDebug"] != nil else { return }
        NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                               object: nil, queue: nil) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
            let kind = switch event.type {
            case .setup: "setup"
            case .import: "import"
            case .export: "export"
            @unknown default: "other"
            }
            print("CK EVENT \(kind) succeeded=\(event.succeeded) \(event.error.map { "\($0)" } ?? "")")
            if let error = event.error as? CKError, let parts = error.partialErrorsByItemID {
                for (item, part) in parts { print("CK PART \(item): \(part)") }
            }
        }
    }

    static func runIfRequested() {
        // The environment variable works with `devicectl device process launch --environment-variables`.
        guard UserDefaults.standard.bool(forKey: "CotizaCloudKitReport")
            || ProcessInfo.processInfo.environment["CotizaCloudKitReport"] != nil else { return }
        Task { await run() }
    }

    static func run() async {
        var lines = ["Precia CloudKit report \(Date.now.formatted(.iso8601))"]
        let container = CKContainer(identifier: AppDatabase.iCloudContainer)
        do {
            let status = try await container.accountStatus()
            lines.append("account: \(status == .available ? "available" : "status \(status.rawValue)")")
            let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
            var token: CKServerChangeToken?
            var byType: [String: [String]] = [:]
            var deleted = 0
            var more = true
            while more {
                let changes = try await container.privateCloudDatabase.recordZoneChanges(inZoneWith: zone, since: token)
                for (id, result) in changes.modificationResultsByID {
                    switch result {
                    case .success(let modification):
                        byType[modification.record.recordType, default: []].append(id.recordName)
                    case .failure(let error):
                        lines.append("record \(id.recordName) failed: \(error.localizedDescription)")
                    }
                }
                deleted += changes.deletions.count
                token = changes.changeToken
                more = changes.moreComing
            }
            for type in byType.keys.sorted() {
                lines.append("\(type): \(byType[type]!.count)  \(byType[type]!.sorted().joined(separator: ", "))")
            }
            lines.append("deletions reported: \(deleted)")
            // `CotizaCloudKitLookup=<record name>,<record name>`: what the server says about each one.
            let lookup = ProcessInfo.processInfo.environment["CotizaCloudKitLookup"]?.split(separator: ",") ?? []
            if !lookup.isEmpty {
                let ids = lookup.map { CKRecord.ID(recordName: String($0), zoneID: zone) }
                for (id, result) in try await container.privateCloudDatabase.records(for: ids) {
                    switch result {
                    case .success(let record):
                        lines.append("lookup \(id.recordName): \(record.recordType) modified \(record.modificationDate.map { "\($0)" } ?? "?")")
                    case .failure(let error):
                        lines.append("lookup \(id.recordName): \(error)")
                    }
                }
            }
        } catch {
            lines.append("error: \(error)")
        }
        let text = lines.joined(separator: "\n")
        print(text)
        let url = URL.documentsDirectory.appending(path: "cloudkit-report.txt")
        try? Data(text.utf8).write(to: url, options: .atomic)
    }
}
#endif
