import Foundation
import os
import SwiftData

/// The one database, shared by the app's scenes and by Siri, Shortcuts and Spotlight,
/// which all run in the app's process.
enum AppDatabase {
    static let iCloudContainer = "iCloud.com.cotiza.app"
    private static let logger = Logger(subsystem: "com.cotiza.app", category: "database")
    private static let schema = Schema([BusinessProfile.self, Client.self, JobDocument.self, LineItem.self, PriceBookItem.self, Payment.self])

    private static let setup: (container: ModelContainer, syncsWithICloud: Bool) = {
        var inMemory = false
        #if DEBUG
        // `-CotizaResetState YES` (UI tests) starts like a fresh install, with nothing saved to disk.
        inMemory = UserDefaults.standard.bool(forKey: "CotizaResetState")
        #endif
        // Stays in the app's own container even though the app has an App Group for the widget:
        // the widget only reads a small summary, never the database.
        if !inMemory {
            do {
                // Mirrors the store to the user's private iCloud database. Without an iCloud account it
                // works locally and starts syncing once the user signs in.
                let synced = ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .private(iCloudContainer))
                return (try prepared(ModelContainer(for: schema, configurations: synced)), true)
            } catch {
                logger.error("iCloud store unavailable, using the local store: \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, groupContainer: .none, cloudKitDatabase: .none)
            return (try prepared(ModelContainer(for: schema, configurations: local)), false)
        } catch {
            // The schema is defined in this binary; failing to open it is unrecoverable.
            fatalError("Could not open the database: \(error)")
        }
    }()

    static var container: ModelContainer { setup.container }
    /// False when the store couldn't be opened with iCloud and the app fell back to this device only.
    static var syncsWithICloud: Bool { setup.syncsWithICloud }

    private static func prepared(_ container: ModelContainer) -> ModelContainer {
        repairDocumentIDs(in: container.mainContext)
        mergeDuplicateProfiles(in: container.mainContext)
        return container
    }

    static var context: ModelContext { container.mainContext }

    static func allDocuments() throws -> [JobDocument] {
        try context.fetch(FetchDescriptor<JobDocument>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    static func documents(ids: [UUID]) throws -> [JobDocument] {
        try context.fetch(FetchDescriptor<JobDocument>(predicate: #Predicate { ids.contains($0.uuid) }))
    }

    static func document(id: UUID) throws -> JobDocument? {
        var descriptor = FetchDescriptor<JobDocument>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// A second iPhone set up before iCloud delivered the first one's data ends up with two business profiles.
    /// Keeps the oldest, fills its empty fields from the others and keeps numbering past every number used.
    static func mergeDuplicateProfiles(in context: ModelContext) {
        let descriptor = FetchDescriptor<BusinessProfile>(sortBy: [SortDescriptor(\.createdAt)])
        guard let profiles = try? context.fetch(descriptor), profiles.count > 1, let keep = profiles.first else { return }
        for extra in profiles.dropFirst() {
            keep.nextEstimateNumber = max(keep.nextEstimateNumber, extra.nextEstimateNumber)
            keep.nextInvoiceNumber = max(keep.nextInvoiceNumber, extra.nextInvoiceNumber)
            if keep.businessName.isEmpty { keep.businessName = extra.businessName }
            if keep.ownerName.isEmpty { keep.ownerName = extra.ownerName }
            if keep.phone.isEmpty { keep.phone = extra.phone }
            if keep.email.isEmpty { keep.email = extra.email }
            if keep.address.isEmpty { keep.address = extra.address }
            if keep.licenseNumber.isEmpty { keep.licenseNumber = extra.licenseNumber }
            if keep.logoData == nil { keep.logoData = extra.logoData }
            if keep.terms.isEmpty { keep.terms = extra.terms }
            if keep.paymentInstructions.isEmpty { keep.paymentInstructions = extra.paymentInstructions }
            context.delete(extra)
        }
        try? context.save()
    }

    /// Documents saved before `uuid` existed may share the one default value the migration filled in.
    /// Gives each of them its own ID so Siri and Spotlight open the right one.
    static func repairDocumentIDs(in context: ModelContext) {
        guard let documents = try? context.fetch(FetchDescriptor<JobDocument>()) else { return }
        var seen = Set<UUID>()
        var changed = false
        for document in documents where !seen.insert(document.uuid).inserted {
            document.uuid = UUID()
            seen.insert(document.uuid)
            changed = true
        }
        if changed { try? context.save() }
    }
}
