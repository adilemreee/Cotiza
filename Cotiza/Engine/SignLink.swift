import BackgroundTasks
import Foundation
import os
import UserNotifications

/// What the client's signing page shows. Text is formatted here, in the document's language,
/// so the server only stores and prints it.
nonisolated struct SignLinkDocument: Codable, Equatable, Sendable {
    struct Line: Codable, Equatable, Sendable {
        var text: String
        var detail: String
        var amount: String
    }

    struct Total: Codable, Equatable, Sendable {
        var label: String
        var value: String
    }

    var businessName: String
    var businessContact: String
    var kindLabel: String
    var number: String
    var title: String
    var clientName: String
    var dateText: String
    var validUntilText: String
    var items: [Line]
    var totals: [Total]
    var total: String
    var notes: String
    var terms: String

    init(_ s: DocumentSnapshot) {
        let strings = PDFStrings(language: s.language)
        let locale = s.language.locale
        businessName = s.businessName.isEmpty ? s.ownerName : s.businessName
        businessContact = [s.businessPhone, s.businessEmail].filter { !$0.isEmpty }.joined(separator: " · ")
        kindLabel = strings.documentWord(s.kind)
        number = s.displayNumber
        title = s.title
        clientName = s.clientName
        dateText = s.formatted(s.date)
        validUntilText = s.validUntil.map(s.formatted) ?? ""
        items = s.items.map { item in
            let quantity = Money.quantity(item.quantity, locale: locale) + (item.unit.isEmpty ? "" : " \(item.unit)")
            return Line(text: item.text, detail: "\(quantity) × \(Money.string(item.unitPrice, locale: locale))",
                        amount: Money.string(item.amount, locale: locale))
        }
        totals = s.totals.tax > 0
            ? [Total(label: strings.subtotal, value: Money.string(s.totals.subtotal, locale: locale)),
               Total(label: strings.tax(rate: Money.quantity(s.taxRate, locale: locale)), value: Money.string(s.totals.tax, locale: locale))]
            : []
        total = Money.string(s.totals.total, locale: locale)
        notes = s.notes
        let validity = s.validUntil.map { strings.validity(until: s.formatted($0)) } ?? ""
        // The page shows totals before the grand total, so the deposit goes with the terms instead.
        let deposit = s.depositIsDue
            ? "\(strings.depositToStart(percent: Money.quantity(s.depositPercent, locale: locale))): \(Money.string(s.depositAmount, locale: locale))"
            : ""
        terms = [deposit, s.terms, validity].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// The signing-link service on the Cotiza site (Server/sign). The client signs in the browser; the app
/// collects the signature and deletes the request from the server.
nonisolated enum SignLink {
    static let api = URL(string: "https://precia.adilemree.xyz/api/v1/sign-requests")!

    enum Failure: LocalizedError {
        case server
        var errorDescription: String? {
            String(localized: "The signing link couldn't be created. Check your connection and try again.")
        }
    }

    struct Created: Decodable, Sendable {
        let id: String
        let url: URL
    }

    struct Status: Decodable, Sendable {
        let status: String
        let signerName: String?
        let signedAt: Date?
        let signature: Data?
    }

    enum Result: Sendable {
        case pending
        case signed(png: Data, name: String, at: Date)
        /// Expired, withdrawn, or already collected by another of the user's devices.
        case gone
    }

    static func newSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func body(for snapshot: DocumentSnapshot, pdf: Data) throws -> Data {
        struct Body: Encodable {
            let language: String
            let document: SignLinkDocument
            let pdf: String
        }
        return try JSONEncoder().encode(Body(language: snapshot.language.rawValue, document: SignLinkDocument(snapshot),
                                             pdf: pdf.base64EncodedString()))
    }

    @MainActor
    static func create(snapshot: DocumentSnapshot, secret: String, session: URLSession = .shared) async throws -> Created {
        let pdf = PDFRenderer().render(snapshot)
        var request = URLRequest(url: api)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Cotiza-Secret")
        request.httpBody = try body(for: snapshot, pdf: pdf)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else { throw Failure.server }
        return try JSONDecoder().decode(Created.self, from: data)
    }

    static func decode(_ data: Data) throws -> Status {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            return date
        }
        return try decoder.decode(Status.self, from: data)
    }

    static func check(id: String, secret: String, session: URLSession = .shared) async throws -> Result {
        var request = URLRequest(url: api.appending(path: id))
        request.setValue(secret, forHTTPHeaderField: "X-Cotiza-Secret")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            let status = try decode(data)
            if status.status == "signed", let png = status.signature, let name = status.signerName {
                return .signed(png: png, name: name, at: status.signedAt ?? .now)
            }
            return status.status == "pending" ? .pending : .gone
        case 404:
            return .gone
        default:
            throw Failure.server
        }
    }

    static func delete(id: String, secret: String, session: URLSession = .shared) async {
        var request = URLRequest(url: api.appending(path: id))
        request.httpMethod = "DELETE"
        request.setValue(secret, forHTTPHeaderField: "X-Cotiza-Secret")
        _ = try? await session.data(for: request)
    }
}

/// Collects signatures from open signing links: when the app becomes active, and in the background.
enum SignLinkSync {
    static let taskID = "com.cotiza.app.signcheck"
    private static let logger = Logger(subsystem: "com.cotiza.app", category: "signlink")

    /// Applies every signature the server has. Returns how many documents were signed.
    @discardableResult
    static func run(notify: Bool = true) async -> Int {
        guard let documents = try? AppDatabase.allDocuments() else { return 0 }
        var signed: [JobDocument] = []
        for document in documents where document.hasOpenSignLink && !document.signRequestSecret.isEmpty {
            let id = document.signRequestID, secret = document.signRequestSecret
            do {
                switch try await SignLink.check(id: id, secret: secret) {
                case .pending:
                    continue
                case .signed(let png, let name, let date):
                    document.sign(png: png, name: name, at: date)
                    document.clearSignLink()
                    ReviewPrompt.goodMoment()
                    signed.append(document)
                    await SignLink.delete(id: id, secret: secret)
                    if notify { await announce(document) }
                case .gone:
                    // Signed on another device (the signature arrives through iCloud), withdrawn, or expired.
                    if document.signatureData == nil { document.clearSignLink() }
                }
            } catch {
                logger.error("Sign link check failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try? AppDatabase.context.save()
        if !signed.isEmpty { WidgetData.publish() }
        scheduleIfNeeded()
        return signed.count
    }

    private static func announce(_ document: JobDocument) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(document.signerName) approved \(document.displayNumber)")
        content.body = String(localized: "The estimate was signed online. The signature is on the PDF.")
        content.sound = .default
        content.userInfo = ["document": document.uuid.uuidString]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "signed.\(document.uuid.uuidString)", content: content, trigger: nil))
    }

    /// Asks iOS for a background check while a link is open. iOS decides when it runs (often within an hour).
    static func scheduleIfNeeded() {
        let open = ((try? AppDatabase.allDocuments()) ?? []).contains(where: \.hasOpenSignLink)
        guard open else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
