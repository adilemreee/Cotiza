import Foundation
import FoundationModels
import os

/// A price the contractor has used before, offered to the model as a hint.
nonisolated struct PriceHint: Sendable, Equatable {
    var name: String
    var unit: String
    var unitPrice: Double
}

@Generable(description: "A contractor's job estimate")
nonisolated struct GeneratedEstimate {
    @Guide(description: "Short job title, 3 to 6 words")
    var title: String
    @Guide(description: "The client's name if the contractor said it, otherwise an empty string")
    var clientName: String
    @Guide(description: "One entry per distinct task or material")
    var items: [GeneratedItem]
    @Guide(description: "Extra conditions the contractor mentioned such as timeline or deposit, otherwise an empty string")
    var notes: String
}

@Generable(description: "One line of an estimate")
nonisolated struct GeneratedItem {
    @Guide(description: "Clear professional description of the task or material, without the price")
    var description: String
    @Guide(description: "How many units. Use 1 when not stated")
    var quantity: Double
    @Guide(description: "Unit of measure such as m², sq ft, hr, gal, ft, day. Empty string when counting whole things")
    var unit: String
    @Guide(description: "Price for ONE unit as a plain number, in the currency the contractor works in. Use 0 when the contractor did not say a price")
    var unitPrice: Double
    @Guide(description: "True for labor or services, false for materials or products")
    var isLabor: Bool
}

/// Turns what a contractor said into a structured estimate, entirely on device.
nonisolated struct EstimateEngine: Sendable {
    private static let logger = Logger(subsystem: "com.cotiza.app", category: "engine")

    static var isAppleIntelligenceAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// `spoken` is the language picked under "I speak"; `currency` the business's (ISO code).
    func makeDraft(transcript: String, trade: String, language: DocumentLanguage, spoken: DocumentLanguage? = nil,
                   currency: String = "USD", priceBook: [PriceHint]) async -> EstimateDraft {
        let trimmed = String(transcript.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2500))
        let fallback = await Self.parse(trimmed, spoken: spoken)
        guard !trimmed.isEmpty, Self.isAppleIntelligenceAvailable else { return fallback }

        do {
            let generated = try await generate(transcript: trimmed, trade: trade, language: language, currency: currency, priceBook: priceBook)
            let draft = Self.validated(generated, transcript: trimmed, spoken: spoken, priceBook: priceBook, language: language, fallback: fallback)
            // If the model returned nothing usable, the deterministic parse is the better answer.
            return draft.items.isEmpty ? fallback : draft
        } catch {
            Self.logger.error("On-device generation failed: \(error.localizedDescription, privacy: .public)")
            return fallback
        }
    }

    @concurrent
    private static func parse(_ text: String, spoken: DocumentLanguage?) async -> EstimateDraft {
        RuleBasedParser.parse(text, spoken: spoken)
    }

    private func generate(transcript: String, trade: String, language: DocumentLanguage, currency: String, priceBook: [PriceHint]) async throws -> GeneratedEstimate {
        let outputLanguage = language.text("English", "Spanish", "Turkish")
        let currencyName = Locale(identifier: "en_US").localizedString(forCurrencyCode: currency) ?? currency
        var instructions = """
        You turn a contractor's spoken job description into the line items of a written estimate. \
        The contractor works in \(trade) and may speak Spanish, English, Turkish, or a mix.

        Rules:
        - Write the title, every description and the notes in \(outputLanguage), using the professional wording a client expects.
        - Make one item per distinct task or material.
        - Copy quantities and prices exactly as spoken. Never guess or invent a price: if no price was said for an item, its unitPrice is 0.
        - unitPrice is the price for one unit. If the contractor gave a total for several units, divide it by the quantity.
        - Do not add tasks the contractor did not mention.
        - Prices are in \(currencyName). Words like dollars, lira, TL, ₺ or euros only name the currency; never convert between currencies.
        - In Turkish, a dot separates thousands and a comma marks decimals: 2.500 is 2500 and 52,50 is 52.5. \
        "bin" is a thousand ("iki bin beş yüz" is 2500) and "tanesi", "adedi", "metrekaresi", "saati" or "başına" mark the price of one unit.
        - Write units in \(outputLanguage)\(language == .turkish ? " (m², m, saat, gün, kutu, litre, kg)" : "").
        """
        if !priceBook.isEmpty {
            let lines = priceBook.prefix(15).map { hint in
                "- \(hint.name): \(Money.quantity(hint.unitPrice, locale: Locale(identifier: "en_US"))) \(currency)\(hint.unit.isEmpty ? "" : " per \(hint.unit)")"
            }
            instructions += "\n\nThe contractor's usual prices. Use one only when an item clearly matches and no price was spoken:\n" + lines.joined(separator: "\n")
        }

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "Job description:\n\(transcript)",
            generating: GeneratedEstimate.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return response.content
    }

    /// Keeps the model honest: any price that was neither spoken nor in the price book is cleared,
    /// so the contractor fills it in instead of sending a number nobody chose.
    static func validated(_ generated: GeneratedEstimate, transcript: String, spoken: DocumentLanguage? = nil, priceBook: [PriceHint],
                          language: DocumentLanguage, fallback: EstimateDraft) -> EstimateDraft {
        let said = RuleBasedParser.numbers(in: transcript, spoken: spoken)
        let known = priceBook.map(\.unitPrice)

        func isGrounded(_ price: Double, quantity: Double) -> Bool {
            let candidates = said + known
            return candidates.contains { abs($0 - price) < 0.006 || abs($0 - price * quantity) < 0.006 }
        }

        let items: [DraftItem] = generated.items.compactMap { item in
            let text = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let quantity = item.quantity.isFinite && item.quantity > 0 ? Money.round(item.quantity) : 1
            var price = item.unitPrice.isFinite && item.unitPrice > 0 ? Money.round(item.unitPrice) : 0
            if price > 0, !isGrounded(price, quantity: quantity) { price = 0 }
            // The model sometimes answers "hr" on a Turkish estimate: write the unit the client reads.
            let unit = RuleBasedParser.written(item.unit.trimmingCharacters(in: .whitespacesAndNewlines), in: language)
            return DraftItem(
                text: text,
                quantity: quantity,
                unit: ["each", "ea", "unit", "units", "item", "none", "n/a"].contains(unit.lowercased()) ? "" : unit,
                unitPrice: price,
                isLabor: item.isLabor
            )
        }

        let clientName = generated.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        // A name the model produced must actually occur in what was said.
        let groundedClient = !clientName.isEmpty && transcript.localizedCaseInsensitiveContains(clientName) ? clientName : fallback.clientName

        return EstimateDraft(
            title: generated.title.trimmingCharacters(in: .whitespacesAndNewlines),
            clientName: groundedClient,
            items: items,
            notes: generated.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .appleIntelligence,
            textLanguage: language
        )
    }
}
