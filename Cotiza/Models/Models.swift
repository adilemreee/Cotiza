import Foundation
import SwiftData

// MARK: - Enums

/// The language a document is written in for the client. Independent of the app's UI language.
nonisolated enum DocumentLanguage: String, CaseIterable, Identifiable, Sendable, Codable {
    case english = "en"
    case spanish = "es"
    case turkish = "tr"

    var id: String { rawValue }
    var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .spanish: Locale(identifier: "es_US")
        case .turkish: Locale(identifier: "tr_TR")
        }
    }
    var language: Locale.Language { Locale.Language(identifier: rawValue) }

    /// The words for this language. Every client-facing text (PDF, messages, reports, signing) goes through it.
    func text(_ english: String, _ spanish: String, _ turkish: String) -> String {
        switch self {
        case .english: english
        case .spanish: spanish
        case .turkish: turkish
        }
    }

    /// The language the phone is set to, when Cotiza speaks it; otherwise English.
    static var device: DocumentLanguage {
        switch Locale.current.language.languageCode {
        case .spanish: .spanish
        case .turkish: .turkish
        default: .english
        }
    }

    /// Short code shown on the language button: EN, ES, TR.
    var code: String { rawValue.uppercased() }
}

nonisolated enum DocumentKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case estimate
    case invoice
    var id: String { rawValue }
}

nonisolated enum DocumentStatus: String, CaseIterable, Identifiable, Sendable, Codable {
    case draft
    case sent
    case approved
    case paid
    var id: String { rawValue }
}

/// How often a recurring invoice is copied.
nonisolated enum RepeatInterval: String, CaseIterable, Identifiable, Sendable, Codable {
    case never, weekly, biweekly, monthly
    var id: String { rawValue }

    /// The next date after `date`, keeping the day of the month for monthly repeats.
    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .never: nil
        case .weekly: calendar.date(byAdding: .day, value: 7, to: date)
        case .biweekly: calendar.date(byAdding: .day, value: 14, to: date)
        case .monthly: calendar.date(byAdding: .month, value: 1, to: date)
        }
    }
}

/// How the client paid. Printed on the PDF in the document's language.
nonisolated enum PaymentMethod: String, CaseIterable, Identifiable, Sendable, Codable {
    case cash, check, zelle, cashApp, venmo, card, other
    var id: String { rawValue }
}

nonisolated enum Trade: String, CaseIterable, Identifiable, Sendable, Codable {
    case general, painting, landscaping, cleaning, flooring, roofing, plumbing, electrical, drywall, concrete, hvac, handyman
    /// Anything not listed; the contractor types what they do (BusinessProfile.customTrade).
    case other
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "hammer.fill"
        case .painting: "paintbrush.fill"
        case .landscaping: "leaf.fill"
        case .cleaning: "sparkles"
        case .flooring: "square.grid.3x3.fill"
        case .roofing: "house.fill"
        case .plumbing: "drop.fill"
        case .electrical: "bolt.fill"
        case .drywall: "rectangle.split.2x2.fill"
        case .concrete: "square.stack.3d.down.right.fill"
        case .hvac: "fan.fill"
        case .handyman: "wrench.and.screwdriver.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    /// English name, used when prompting the on-device model.
    var englishName: String {
        switch self {
        case .general: "general contracting"
        case .painting: "painting"
        case .landscaping: "landscaping and lawn care"
        case .cleaning: "cleaning"
        case .flooring: "flooring"
        case .roofing: "roofing"
        case .plumbing: "plumbing"
        case .electrical: "electrical"
        case .drywall: "drywall"
        case .concrete: "concrete and masonry"
        case .hvac: "HVAC"
        case .handyman: "handyman services"
        case .other: "home services"
        }
    }
}

// MARK: - Models

@Model
final class BusinessProfile {
    var businessName: String = ""
    var ownerName: String = ""
    var phone: String = ""
    var email: String = ""
    var address: String = ""
    var licenseNumber: String = ""
    @Attribute(.externalStorage) var logoData: Data?
    var tradeRaw: String = Trade.general.rawValue
    /// What the contractor does when the trade is "Other", in their own words ("pool cleaning").
    var customTrade: String = ""
    var defaultTaxRate: Double = 0
    var documentLanguageRaw: String = DocumentLanguage.english.rawValue
    var terms: String = ""
    var paymentInstructions: String = ""
    var nextEstimateNumber: Int = 1001
    var nextInvoiceNumber: Int = 1001
    /// How long a new estimate stays valid, printed on the PDF.
    var estimateValidDays: Int = 30
    /// Days after the invoice date that payment is due.
    var paymentDueDays: Int = 14
    /// Local notifications for estimates with no answer and unpaid invoices past their due date.
    var remindersEnabled: Bool = true
    /// Added on top of what the contractor paid for materials from a scanned receipt.
    var materialMarkupPercent: Double = 15
    /// Asked for on new estimates, as a share of the total. 0 means no deposit.
    var defaultDepositPercent: Double = 0
    /// ISO 4217 code for every amount ("USD", "TRY"). Empty means the phone's region decides.
    var currencyCode: String = ""
    var createdAt: Date = Date.now

    init() {}

    var trade: Trade {
        get { Trade(rawValue: tradeRaw) ?? .general }
        set { tradeRaw = newValue.rawValue }
    }

    /// How the on-device model is told what this business does.
    var tradeDescription: String {
        let custom = customTrade.trimmingCharacters(in: .whitespacesAndNewlines)
        return trade == .other && !custom.isEmpty ? String(custom.prefix(80)) : trade.englishName
    }

    var documentLanguage: DocumentLanguage {
        get { DocumentLanguage(rawValue: documentLanguageRaw) ?? .english }
        set { documentLanguageRaw = newValue.rawValue }
    }

    /// The currency amounts are written in: the one chosen in Settings, else the phone's.
    var currency: String {
        get { currencyCode.isEmpty ? Money.regionCurrency : currencyCode }
        set { currencyCode = newValue }
    }
}

@Model
final class Client {
    var name: String = ""
    var phone: String = ""
    var email: String = ""
    var address: String = ""
    var createdAt: Date = Date.now
    // Optional because iCloud (CloudKit) sync requires every relationship to be.
    @Relationship(deleteRule: .nullify, inverse: \JobDocument.client) var documents: [JobDocument]? = []

    init(name: String, phone: String = "", email: String = "", address: String = "") {
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
    }
}

@Model
final class JobDocument {
    /// Stable ID that Siri, Shortcuts and Spotlight use to point at this document.
    var uuid: UUID = UUID()
    var kindRaw: String = DocumentKind.estimate.rawValue
    var statusRaw: String = DocumentStatus.draft.rawValue
    var languageRaw: String = DocumentLanguage.english.rawValue
    var number: Int = 0
    var title: String = ""
    var notes: String = ""
    /// What the contractor originally said or typed. Kept so the job can be re-generated.
    var transcript: String = ""
    var taxRate: Double = 0
    var createdAt: Date = Date.now
    var sentAt: Date?
    var paidAt: Date?
    /// Estimates: the last day the price holds. Nil on documents made before this existed.
    var validUntil: Date?
    /// Invoices: the day payment is due.
    var dueDate: Date?
    /// The client's signature, drawn on the phone, as a transparent PNG.
    @Attribute(.externalStorage) var signatureData: Data?
    var signerName: String = ""
    var signedAt: Date?
    /// A signing link sent to the client (see SignLink). Empty when there is none.
    var signRequestID: String = ""
    var signRequestURL: String = ""
    /// Proves to the server that this user made the link. Synced with the document through the user's
    /// private iCloud, so any of their devices can collect the signature.
    var signRequestSecret: String = ""
    var signRequestSentAt: Date?
    /// Invoices only: copied into a new invoice on `nextRepeatDate`, then again every interval.
    var repeatRaw: String = RepeatInterval.never.rawValue
    var nextRepeatDate: Date?
    /// On an invoice made by a repeat: the `uuid` of the invoice it was copied from.
    var repeatSourceID: UUID?
    /// The share of the total asked for before work starts. 0 means no deposit.
    var depositPercent: Double = 0
    var client: Client?
    // Optional because iCloud (CloudKit) sync requires every relationship to be. Read through `allItems`.
    @Relationship(deleteRule: .cascade, inverse: \LineItem.document) var items: [LineItem]? = []
    /// Money received so far: a deposit, partial payments. Read through `sortedPayments`.
    @Relationship(deleteRule: .cascade, inverse: \Payment.document) var payments: [Payment]? = []

    init(kind: DocumentKind, number: Int, title: String, language: DocumentLanguage, taxRate: Double) {
        self.kindRaw = kind.rawValue
        self.number = number
        self.title = title
        self.languageRaw = language.rawValue
        self.taxRate = taxRate
    }

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRaw) ?? .estimate }
        set { kindRaw = newValue.rawValue }
    }

    var status: DocumentStatus {
        get { DocumentStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var language: DocumentLanguage {
        get { DocumentLanguage(rawValue: languageRaw) ?? .english }
        set { languageRaw = newValue.rawValue }
    }

    var allItems: [LineItem] { items ?? [] }

    var repeatInterval: RepeatInterval {
        get { RepeatInterval(rawValue: repeatRaw) ?? .never }
        set { repeatRaw = newValue.rawValue }
    }

    var sortedItems: [LineItem] {
        allItems.sorted { $0.sortIndex < $1.sortIndex }
    }

    var totals: Totals {
        Totals(lines: allItems.map { .init(amount: $0.amount, isTaxable: $0.isTaxable) }, taxRate: taxRate)
    }

    var displayNumber: String {
        (kind == .estimate ? "E-" : "INV-") + String(number)
    }

    var sortedPayments: [Payment] {
        (payments ?? []).sorted { $0.date < $1.date }
    }

    /// Everything recorded as received, whatever the status says.
    var amountPaid: Double {
        Money.round((payments ?? []).reduce(0) { $0 + $1.amount })
    }

    /// The deposit asked for to start; 0 when there is none.
    var depositAmount: Double {
        depositPercent > 0 ? Money.round(totals.total * min(depositPercent, 100) / 100) : 0
    }

    /// What the client still owes. Nothing once the document is marked paid.
    var balanceDue: Double {
        status == .paid ? 0 : max(Money.round(totals.total - amountPaid), 0)
    }

    var isPartlyPaid: Bool { status != .paid && amountPaid > 0 }

    /// Money in, on the day it came in: every recorded payment, plus whatever was left when the
    /// document was marked paid (all of it for documents with no payments).
    var income: [(id: UUID, date: Date, amount: Double)] {
        var events = sortedPayments.filter { $0.amount > 0 }.map { (id: $0.uuid, date: $0.date, amount: $0.amount) }
        if status == .paid {
            let rest = Money.round(totals.total - amountPaid)
            if rest > 0 { events.append((id: uuid, date: paidAt ?? createdAt, amount: rest)) }
        }
        return events
    }

    /// Changes the status and keeps the sent/paid dates in step.
    func apply(status newStatus: DocumentStatus) {
        status = newStatus
        switch newStatus {
        case .paid: paidAt = paidAt ?? .now
        case .sent:
            sentAt = sentAt ?? .now
            paidAt = nil
        case .draft, .approved: paidAt = nil
        }
    }

    /// Turns repeating on or off. The first copy is one interval after the invoice date, moved forward to today or later.
    func setRepeat(_ interval: RepeatInterval, now: Date = .now, calendar: Calendar = .current) {
        repeatInterval = interval
        guard interval != .never else {
            nextRepeatDate = nil
            return
        }
        let today = calendar.startOfDay(for: now)
        var next = interval.next(after: calendar.startOfDay(for: createdAt), calendar: calendar) ?? today
        while next < today, let later = interval.next(after: next, calendar: calendar) { next = later }
        nextRepeatDate = next
    }

    /// An unpaid invoice whose due date has passed.
    func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard kind == .invoice, status != .paid, status != .draft, let dueDate else { return false }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }

    /// Saves the client's signature. Signing an estimate approves it.
    func sign(png: Data, name: String, at date: Date = .now) {
        signatureData = png
        signerName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        signedAt = date
        if kind == .estimate, status != .paid { apply(status: .approved) }
    }

    var hasOpenSignLink: Bool { !signRequestID.isEmpty && signatureData == nil }

    func clearSignLink() {
        signRequestID = ""
        signRequestURL = ""
        signRequestSecret = ""
        signRequestSentAt = nil
    }

    func removeSignature() {
        signatureData = nil
        signerName = ""
        signedAt = nil
    }

    /// An estimate sent and waiting for a yes, or an invoice sent and not paid yet.
    var isAwaitingPayment: Bool {
        switch kind {
        case .estimate: status == .sent
        case .invoice: status != .paid && status != .draft
        }
    }
}

/// The two numbers on the home screen, also spoken by Siri.
struct DocumentSummary: Equatable {
    let pending: Double
    let paidThisMonth: Double

    init(documents: [JobDocument], now: Date = .now, calendar: Calendar = .current) {
        pending = Money.round(documents.filter(\.isAwaitingPayment).reduce(0) { $0 + $1.balanceDue })
        paidThisMonth = Money.round(documents
            .flatMap(\.income)
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount })
    }
}

@Model
final class LineItem {
    var text: String = ""
    var quantity: Double = 1
    var unit: String = ""
    var unitPrice: Double = 0
    var isLabor: Bool = false
    var isTaxable: Bool = true
    /// What the contractor paid per unit (from a receipt or typed in). 0 means unknown. Never shown to the client.
    var unitCost: Double = 0
    var sortIndex: Int = 0
    var document: JobDocument?

    init(text: String, quantity: Double = 1, unit: String = "", unitPrice: Double = 0, isLabor: Bool = false, isTaxable: Bool = true, sortIndex: Int = 0) {
        self.text = text
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.isLabor = isLabor
        self.isTaxable = isTaxable
        self.sortIndex = sortIndex
    }

    var amount: Double { Money.round(quantity * unitPrice) }
    var cost: Double { Money.round(quantity * unitCost) }
}

@Model
final class Payment {
    /// Stable ID for report rows.
    var uuid: UUID = UUID()
    var amount: Double = 0
    var date: Date = Date.now
    var methodRaw: String = PaymentMethod.cash.rawValue
    var document: JobDocument?

    init(amount: Double, date: Date = .now, method: PaymentMethod = .cash) {
        self.amount = Money.round(amount)
        self.date = date
        self.methodRaw = method.rawValue
    }

    var method: PaymentMethod {
        get { PaymentMethod(rawValue: methodRaw) ?? .other }
        set { methodRaw = newValue.rawValue }
    }
}

@Model
final class PriceBookItem {
    var name: String = ""
    var unit: String = ""
    var unitPrice: Double = 0
    var isLabor: Bool = false
    var useCount: Int = 0
    var updatedAt: Date = Date.now

    init(name: String, unit: String = "", unitPrice: Double, isLabor: Bool = false) {
        self.name = name
        self.unit = unit
        self.unitPrice = unitPrice
        self.isLabor = isLabor
    }
}

// MARK: - Money

nonisolated enum Money {
    static func round(_ value: Double) -> Double {
        (value * 100).rounded(.toNearestOrAwayFromZero) / 100
    }

    /// The price to charge for something that cost `cost`, with `percent` markup.
    static func withMarkup(_ cost: Double, percent: Double) -> Double {
        round(cost * (1 + max(percent, 0) / 100))
    }

    /// The business's currency. Set from the profile when the app starts and whenever it changes
    /// (`RootView`); every amount in the app, the PDF and the messages is written in it.
    nonisolated(unsafe) static var currencyCode = "USD"

    /// Currencies offered in Settings, most likely first. The phone's own is added when it's missing.
    static let commonCurrencies = ["USD", "TRY", "EUR", "MXN", "GBP", "CAD"]

    /// The phone region's currency: TRY in Türkiye, USD in the United States.
    static var regionCurrency: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    static func string(_ value: Double, locale: Locale = Locale(identifier: "en_US"), currency: String? = nil) -> String {
        value.formatted(.currency(code: currency ?? currencyCode).locale(locale))
    }

    /// "₺", "$", "€": the symbol a document in `locale` uses for `currency`.
    static func symbol(_ currency: String? = nil, locale: Locale = .current) -> String {
        let format = FloatingPointFormatStyle<Double>.Currency(code: currency ?? currencyCode).locale(locale)
        return 0.0.formatted(format).filter { !$0.isNumber && !",. \u{00A0}\u{202F}".contains($0) }
    }

    /// Quantity without trailing zeros: 3, 2.5, 120.
    static func quantity(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}

nonisolated struct Totals: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        var amount: Double
        var isTaxable: Bool
    }

    let subtotal: Double
    let taxableSubtotal: Double
    let tax: Double
    let total: Double

    init(lines: [Line], taxRate: Double) {
        subtotal = Money.round(lines.reduce(0) { $0 + $1.amount })
        taxableSubtotal = Money.round(lines.filter(\.isTaxable).reduce(0) { $0 + $1.amount })
        tax = Money.round(taxableSubtotal * max(taxRate, 0) / 100)
        total = Money.round(subtotal + tax)
    }
}
