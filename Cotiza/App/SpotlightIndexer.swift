import AppIntents
import CoreSpotlight
import os

/// Keeps Spotlight and Siri's list of documents in step with the database.
enum SpotlightIndexer {
    private static let logger = Logger(subsystem: "com.cotiza.app", category: "spotlight")

    /// Replaces everything Cotiza has in Spotlight with what is saved now.
    /// Cheap for the few hundred documents a contractor has; also drops deleted ones.
    static func reindexAll() async {
        do {
            let entities = try AppDatabase.allDocuments().map(DocumentEntity.init)
            let index = CSSearchableIndex.default()
            try await index.deleteAppEntities(ofType: DocumentEntity.self)
            try await index.indexAppEntities(entities)
        } catch {
            logger.error("Reindex failed: \(error.localizedDescription, privacy: .public)")
        }
        // Lets phrases like "Mark <job> as paid" match the current job titles.
        CotizaShortcuts.updateAppShortcutParameters()
    }

    static func index(_ documents: [JobDocument]) async {
        do {
            try await CSSearchableIndex.default().indexAppEntities(documents.map(DocumentEntity.init))
        } catch {
            logger.error("Index failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
