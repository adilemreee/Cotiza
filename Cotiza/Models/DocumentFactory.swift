import Foundation
import SwiftData

/// Creates and derives documents. Kept out of the views so the rules live in one place.
struct DocumentFactory {
    let context: ModelContext

    @discardableResult
    func makeEstimate(from draft: EstimateDraft, transcript: String, profile: BusinessProfile) -> JobDocument {
        let document = JobDocument(
            kind: .estimate,
            number: profile.nextEstimateNumber,
            title: draft.title,
            language: profile.documentLanguage,
            taxRate: profile.defaultTaxRate
        )
        profile.nextEstimateNumber += 1
        document.validUntil = Self.date(days: profile.estimateValidDays, after: document.createdAt)
        document.transcript = transcript
        document.notes = draft.notes
        context.insert(document)

        for (index, item) in draft.items.enumerated() {
            let line = LineItem(
                text: item.text,
                quantity: item.quantity,
                unit: item.unit,
                unitPrice: item.unitPrice,
                isLabor: item.isLabor,
                // Sales tax normally applies to materials, not labor. Editable per line.
                isTaxable: !item.isLabor,
                sortIndex: index
            )
            context.insert(line)
            line.document = document
        }

        if let name = draft.clientName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            document.client = existingClient(named: name) ?? {
                let client = Client(name: name)
                context.insert(client)
                return client
            }()
        }
        return document
    }

    /// Copies an estimate into a new invoice and marks the estimate approved.
    @discardableResult
    func makeInvoice(from estimate: JobDocument, profile: BusinessProfile) -> JobDocument {
        let invoice = JobDocument(
            kind: .invoice,
            number: profile.nextInvoiceNumber,
            title: estimate.title,
            language: estimate.language,
            taxRate: estimate.taxRate
        )
        profile.nextInvoiceNumber += 1
        invoice.dueDate = Self.date(days: profile.paymentDueDays, after: invoice.createdAt)
        invoice.notes = estimate.notes
        invoice.transcript = estimate.transcript
        context.insert(invoice)
        invoice.client = estimate.client
        copyItems(from: estimate, to: invoice)
        if estimate.status != .paid { estimate.status = .approved }
        return invoice
    }

    @discardableResult
    func duplicate(_ source: JobDocument, profile: BusinessProfile) -> JobDocument {
        let number = source.kind == .estimate ? profile.nextEstimateNumber : profile.nextInvoiceNumber
        if source.kind == .estimate { profile.nextEstimateNumber += 1 } else { profile.nextInvoiceNumber += 1 }
        let copy = JobDocument(kind: source.kind, number: number, title: source.title, language: source.language, taxRate: source.taxRate)
        copy.notes = source.notes
        copy.transcript = source.transcript
        switch source.kind {
        case .estimate: copy.validUntil = Self.date(days: profile.estimateValidDays, after: copy.createdAt)
        case .invoice: copy.dueDate = Self.date(days: profile.paymentDueDays, after: copy.createdAt)
        }
        context.insert(copy)
        copy.client = source.client
        copyItems(from: source, to: copy)
        return copy
    }

    /// Remembers the prices used on a document so the next estimate can reuse them.
    func learnPrices(from document: JobDocument) {
        let existing = (try? context.fetch(FetchDescriptor<PriceBookItem>())) ?? []
        var byName = Dictionary(existing.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for item in document.allItems where item.unitPrice > 0 {
            let name = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80 else { continue }
            if let entry = byName[name.lowercased()] {
                entry.unitPrice = item.unitPrice
                entry.unit = item.unit
                entry.useCount += 1
                entry.updatedAt = .now
            } else {
                let entry = PriceBookItem(name: name, unit: item.unit, unitPrice: item.unitPrice, isLabor: item.isLabor)
                entry.useCount = 1
                context.insert(entry)
                byName[name.lowercased()] = entry
            }
        }
    }

    func priceHints(limit: Int = 15) -> [PriceHint] {
        var descriptor = FetchDescriptor<PriceBookItem>(sortBy: [SortDescriptor(\.useCount, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        let items = (try? context.fetch(descriptor)) ?? []
        return items.map { PriceHint(name: $0.name, unit: $0.unit, unitPrice: $0.unitPrice) }
    }

    // MARK: Recurring invoices

    /// Copies every recurring invoice whose day has come. Missed periods are caught up, at most 12 at a time.
    @discardableResult
    func makeDueRepeats(profile: BusinessProfile, now: Date = .now, calendar: Calendar = .current) -> [JobDocument] {
        let all = (try? context.fetch(FetchDescriptor<JobDocument>())) ?? []
        let today = calendar.startOfDay(for: now)
        var made: [JobDocument] = []
        for template in all where template.kind == .invoice && template.repeatInterval != .never {
            var count = 0
            while let due = template.nextRepeatDate, calendar.startOfDay(for: due) <= today, count < 12 {
                // Another device may already have made this copy and synced it.
                let exists = all.contains {
                    $0.repeatSourceID == template.uuid && calendar.isDate($0.createdAt, inSameDayAs: due)
                }
                if !exists { made.append(makeRepeat(of: template, on: due, profile: profile)) }
                template.nextRepeatDate = template.repeatInterval.next(after: due, calendar: calendar)
                count += 1
            }
        }
        return made
    }

    private func makeRepeat(of template: JobDocument, on date: Date, profile: BusinessProfile) -> JobDocument {
        let invoice = JobDocument(kind: .invoice, number: profile.nextInvoiceNumber, title: template.title,
                                  language: template.language, taxRate: template.taxRate)
        profile.nextInvoiceNumber += 1
        invoice.createdAt = date
        invoice.dueDate = Self.date(days: profile.paymentDueDays, after: date)
        invoice.notes = template.notes
        invoice.repeatSourceID = template.uuid
        context.insert(invoice)
        invoice.client = template.client
        copyItems(from: template, to: invoice)
        return invoice
    }

    static func date(days: Int, after start: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: max(days, 0), to: calendar.startOfDay(for: start)) ?? start
    }

    private func copyItems(from source: JobDocument, to target: JobDocument) {
        for item in source.sortedItems {
            let line = LineItem(text: item.text, quantity: item.quantity, unit: item.unit, unitPrice: item.unitPrice,
                                isLabor: item.isLabor, isTaxable: item.isTaxable, sortIndex: item.sortIndex)
            line.unitCost = item.unitCost
            context.insert(line)
            line.document = target
        }
    }

    private func existingClient(named name: String) -> Client? {
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        return clients.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }
}

/// Runs the recurring-invoice copies against the app's database.
enum RecurringInvoices {
    @discardableResult
    static func run(now: Date = .now) -> [JobDocument] {
        let context = AppDatabase.context
        guard let profile = try? context.fetch(FetchDescriptor<BusinessProfile>()).first else { return [] }
        let made = DocumentFactory(context: context).makeDueRepeats(profile: profile, now: now)
        if !made.isEmpty { try? context.save() }
        return made
    }
}
