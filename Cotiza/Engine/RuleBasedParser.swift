import Foundation
import NaturalLanguage
import os

// MARK: - Draft types

nonisolated struct DraftItem: Equatable, Sendable, Identifiable {
    var id = UUID()
    var text: String
    var quantity: Double = 1
    var unit: String = ""
    var unitPrice: Double = 0
    var isLabor: Bool = false

    static func == (lhs: DraftItem, rhs: DraftItem) -> Bool {
        lhs.text == rhs.text && lhs.quantity == rhs.quantity && lhs.unit == rhs.unit
            && lhs.unitPrice == rhs.unitPrice && lhs.isLabor == rhs.isLabor
    }
}

nonisolated struct EstimateDraft: Equatable, Sendable {
    enum Source: Sendable { case appleIntelligence, basic }

    var title: String
    var clientName: String?
    var items: [DraftItem]
    var notes: String = ""
    var source: Source = .basic
    /// The language the item text is currently written in.
    var textLanguage: DocumentLanguage = .english
}

// MARK: - Rule-based parser

/// Deterministic Spanish/English job-description parser.
///
/// Used on devices without Apple Intelligence, and as the safety net whenever the
/// on-device model refuses or fails. It never invents numbers: every quantity and
/// price in the result is literally present in the input.
nonisolated enum RuleBasedParser {

    static func parse(_ transcript: String) -> EstimateDraft {
        var text = transcript
            .replacingOccurrences(of: "\n", with: ". ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        let clientName = extractClient(from: &text)
        text = replaceNumberWords(in: text)

        var items: [DraftItem] = []
        var notes: [String] = []
        // The last line was work with no price or quantity yet ("Pintar la sala").
        var lastIsOpenJob = false
        for segment in segments(of: text) {
            switch parseSegment(segment) {
            case .item(var item, let placeholder):
                if let placeholder, lastIsOpenJob, let job = items.popLast() {
                    // "Pintar la sala, 400 pies a 2 el pie": the measurement prices the job just named.
                    item.text = job.text + item.text.dropFirst(placeholder.count)
                    item.isLabor = item.isLabor || job.isLabor
                }
                lastIsOpenJob = placeholder == nil && item.unitPrice == 0 && item.quantity == 1 && item.unit.isEmpty
                items.append(item)
            case .note(let note):
                notes.append(note)
                lastIsOpenJob = false
            case nil:
                break
            }
        }

        let language = detectLanguage(of: transcript)
        let title = items.first.map { String($0.text.prefix(48)) } ?? ""
        let noteText = notes.isEmpty ? "" : notes.joined(separator: ". ") + "."
        return EstimateDraft(title: title, clientName: clientName, items: items, notes: noteText, source: .basic, textLanguage: language)
    }

    static func detectLanguage(of text: String) -> DocumentLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.spanish, .english]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .spanish ? .spanish : .english
    }

    /// Every number that literally appears in the text (after number words are converted).
    static func numbers(in transcript: String) -> [Double] {
        let text = replaceNumberWords(in: transcript)
        return text.matches(of: rx(#"\d[\d,]*(?:\.\d+)?"#)).compactMap { number(String($0.0)) }
    }

    // MARK: Client

    private static func extractClient(from text: inout String) -> String? {
        explicitClient(from: &text) ?? possessiveClient(from: &text)
    }

    /// "Cliente María López", "for Mrs. Smith".
    private static func explicitClient(from text: inout String) -> String? {
        let pattern = #"(?i:\b(?:(?:el |la |para el |para la |for the |for )?(?:cliente|client|customer)(?: es| se llama| is| name is)?|para (?:el señor|la señora|don|doña|el sr\.?|la sra\.?)|for (?:mr\.?|mrs\.?|ms\.?)))[:\s]+(\p{Lu}[\p{L}'’\-]+(?:\s+\p{Lu}[\p{L}'’\-]+){0,2})[.,;]?"#
        guard let match = text.firstMatch(of: rx(pattern)), let name = match.output[1].substring else { return nil }
        let result = String(name)
        text.replaceSubrange(match.range, with: ". ")
        return result
    }

    /// Brands named after people, which the name tagger reads as a person.
    private static let brandNames: Set<String> = [
        "sherwin williams", "benjamin moore", "home depot", "kelly moore", "dunn edwards", "dunn-edwards",
        "pittsburgh", "glidden", "valspar", "behr", "lowes", "lowe's", "lowe’s", "ace", "menards", "rust oleum",
        "james hardie", "owens corning", "simpson", "kohler", "moen", "delta", "pella", "andersen", "milgard",
    ]

    /// First words of place names, which follow "de"/"para" just like a client does.
    private static let placeWords: Set<String> = ["san", "santa", "los", "las", "el", "la", "new", "fort", "port", "lake", "mount"]

    /// "Pintar la sala de María López", "paint the kitchen for John Smith": a capitalized name after
    /// de/para/for. Where the device has the name model, it must also read as a person; without it,
    /// only full names (two or three words) count. The name is taken out of the job text.
    private static func possessiveClient(from text: inout String) -> String? {
        let candidate = rx(#"(?i:\b(?:de|del|para|for)\s+)(\p{Lu}[\p{L}'’\-]+(?:\s+\p{Lu}[\p{L}'’\-]+){0,2})"#)
        let people = personalNameRanges(in: text)
        for match in text.matches(of: candidate) {
            guard let name = match.output[1].substring, !brandNames.contains(name.lowercased()) else { continue }
            let words = name.split(separator: " ")
            let isPerson: Bool
            if let people {
                isPerson = people.contains { $0.overlaps(name.startIndex..<name.endIndex) }
            } else {
                isPerson = words.count >= 2 && !placeWords.contains(words[0].lowercased())
            }
            guard isPerson else { continue }
            let result = String(name)
            text.replaceSubrange(match.range, with: "")
            return result
        }
        return nil
    }

    /// Names the language tagger reads as people, or nil when this device has no name model for the language.
    private static func personalNameRanges(in text: String) -> [Range<String.Index>]? {
        let language: NLLanguage = detectLanguage(of: text) == .spanish ? .spanish : .english
        guard NLTagger.availableTagSchemes(for: .word, language: language).contains(.nameType) else { return nil }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var ranges: [Range<String.Index>] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if tag == .personalName { ranges.append(range) }
            return true
        }
        return ranges
    }

    // MARK: Number words

    private static let numberWords: [(String, String)] = [
        ("dos", "2"), ("tres", "3"), ("cuatro", "4"), ("cinco", "5"), ("seis", "6"), ("siete", "7"),
        ("ocho", "8"), ("nueve", "9"), ("diez", "10"), ("once", "11"), ("doce", "12"), ("trece", "13"),
        ("catorce", "14"), ("quince", "15"), ("dieciséis", "16"), ("dieciseis", "16"), ("diecisiete", "17"),
        ("dieciocho", "18"), ("diecinueve", "19"), ("veinte", "20"), ("treinta", "30"), ("cuarenta", "40"),
        ("cincuenta", "50"), ("cien", "100"),
        ("two", "2"), ("three", "3"), ("four", "4"), ("five", "5"), ("six", "6"), ("seven", "7"),
        ("eight", "8"), ("nine", "9"), ("ten", "10"), ("eleven", "11"), ("twelve", "12"), ("fifteen", "15"),
        ("twenty", "20"), ("thirty", "30"), ("forty", "40"), ("fifty", "50"),
    ]

    static func replaceNumberWords(in text: String) -> String {
        var result = text
        for (word, digits) in numberWords {
            result = result.replacing(rx("(?i)\\b\(word)\\b"), with: digits)
        }
        return result
    }

    // MARK: Segmentation

    private static func segments(of text: String) -> [String] {
        let primary = text.split(separator: rx(#"(?i)[.;]\s+|[.;]\s*$|,\s+|\s+(?:también|tambien|además|ademas|luego|después|despues|plus|also|then)\s+"#))
        var result: [String] = []
        for piece in primary {
            let segment = String(piece)
            let parts = segment.split(separator: rx(#"(?i)\s+(?:y|and|más|mas)\s+"#)).map(String.init)
            // Only split on "y"/"and" when each side carries its own price —
            // otherwise "sink and mirror" would be torn apart.
            if parts.count > 1, parts.allSatisfy({ findPrice(in: $0) != nil }) {
                result.append(contentsOf: parts)
            } else {
                result.append(segment)
            }
        }
        return result
    }

    // MARK: Segment parsing

    private struct PriceMatch {
        var value: Double
        var range: Range<String.Index>
        var isTotalPrefix: Bool
    }

    private static let unitTable: [(pattern: String, unit: String)] = [
        (#"pies cuadrados|pie cuadrado|square feet|square foot|sq\.? ?ft\.?|sqft"#, "sq ft"),
        (#"pies lineales|pie lineal|linear feet|linear foot|lin\.? ?ft\.?"#, "lin ft"),
        (#"metros cuadrados|metro cuadrado|square meters|square meter"#, "m²"),
        (#"yardas cuadradas|yarda cuadrada|square yards|square yard"#, "sq yd"),
        (#"yardas|yarda|yards|yard|yd"#, "yd"),
        (#"pies|pie|feet|foot|ft"#, "ft"),
        (#"horas|hora|hours|hour|hrs|hr"#, "hr"),
        (#"días|dias|día|dia|days|day"#, "day"),
        (#"galones|galón|galon|gallons|gallon|gal"#, "gal"),
        (#"cajas|caja|boxes|box"#, "box"),
        (#"bolsas|bolsa|bags|bag"#, "bag"),
        (#"metros|metro|meters|meter"#, "m"),
        (#"libras|libra|pounds|pound|lbs|lb"#, "lb"),
    ]

    private static var unitAlternation: String {
        unitTable.map(\.pattern).joined(separator: "|")
    }

    private static func canonicalUnit(_ raw: String) -> String {
        let lowered = raw.lowercased()
        for entry in unitTable where lowered.wholeMatch(of: rx("(?:\(entry.pattern))")) != nil {
            return entry.unit
        }
        return ""
    }

    private static func findPrice(in s: String) -> PriceMatch? {
        let totalPrefixes: Set<String> = ["por", "for", "en", "de", "son"]
        let prefix = #"(\b(?:a|at|por|for|en|de|cuestan|cuesta|cobro|son|valen|vale)\s+)?"#
        let amount = #"(\d[\d,]*(?:\.\d+)?)"#
        let notAUnit = "(?!\\s*(?:\(unitAlternation)|manos|capas|coats|%|por ciento|percent)\\b)"
        let patterns = [
            "(?i)\(prefix)\\$\\s?\(amount)",
            "(?i)\(prefix)\(amount)\\s*(?:dólares|dolares|dollars|dollar|bucks|usd|pesos)\\b",
            "(?i)(\\b(?:a|at|por|for|cuestan|cuesta|cobro|son)\\s+)\(amount)(?![\\d.,]*\\d)\(notAUnit)",
        ]
        for pattern in patterns {
            guard let match = s.matches(of: rx(pattern)).last,
                  let digits = match.output[2].substring,
                  let value = number(String(digits)) else { continue }
            let prefixWord = match.output[1].substring.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            return PriceMatch(value: value, range: match.range, isTotalPrefix: totalPrefixes.contains(prefixWord))
        }
        // "New vanity 600": a bare number that ends the phrase is the price for the whole line.
        // (Swift Regex has no lookbehind, so the preceding letter is matched and then excluded from the range.)
        if let match = s.firstMatch(of: rx(#"\p{L}\s+(\d[\d,]*(?:\.\d+)?)\s*$"#)),
           let digits = match.output[1].substring,
           let value = number(String(digits)), value >= 10 {
            return PriceMatch(value: value, range: digits.startIndex..<s.endIndex, isTotalPrefix: true)
        }
        return nil
    }

    private enum Parsed {
        /// `placeholder` is the stand-in name ("Item", "Labor") when the phrase was only numbers.
        case item(DraftItem, placeholder: String?)
        /// Something the contractor said that isn't billable work: timing, deposit, a reminder.
        case note(String)
    }

    /// Verbs that open a description of real work. An unpriced phrase starting with one is kept
    /// as a line to price; anything else unpriced is treated as a note for the client.
    private static let workVerbs = #"pintar|instalar|cambiar|reparar|quitar|poner|cortar|limpiar|colocar|remover|reemplazar|arreglar|podar|lavar|sellar|construir|demoler|resanar|lijar|barnizar|destapar|soldar|nivelar|emparejar|texturizar|impermeabilizar|montar|desmontar|retirar|tirar|paint|install|replace|repair|remove|fix|cut|clean|demo|demolish|build|patch|sand|seal|trim|mow|haul|lay|hang|pressure wash|power wash|stain|caulk|prime|frame|pour|grout|tile|rewire|unclog|mount|tear out|dispose"#

    private static func parseSegment(_ segment: String) -> Parsed? {
        var s = segment

        // 1. Price
        let price = findPrice(in: s)
        if let price { s.replaceSubrange(price.range, with: " ") }

        // 2. "each" / "total" markers
        let eachPattern = #"(?i)\b(?:c/u|cada(?:\s+un[oa]?)?|each|apiece|por\s+(?:hora|pie|pieza|unidad|galón|galon|yarda|metro|día|dia)(?:\s+cuadrad[oa])?|(?:la|el)\s+(?:hora|pie|pieza|unidad|galón|galon|yarda|metro|día|dia)(?:\s+cuadrad[oa])?|(?:an?|per)\s+(?:hour|foot|square foot|sq ft|piece|unit|gallon|yard|day))(?![\p{L}])"#
        var isEach = false
        if price != nil, let match = s.firstMatch(of: rx(eachPattern)) {
            isEach = true
            s.replaceSubrange(match.range, with: " ")
        }
        var saysTotal = false
        if let match = s.firstMatch(of: rx(#"(?i)\b(?:en total|in total|total)\b"#)) {
            saysTotal = true
            s.replaceSubrange(match.range, with: " ")
        }

        // 3. Quantity and unit
        var quantity = 1.0
        var unit = ""
        let quantityRegex = rx("(?i)(\\d[\\d,]*(?:\\.\\d+)?)\\s*(\(unitAlternation))?(?![\\p{L}\\d])(\\s+(?:de|of)\\b)?")
        let quantityMatches = s.matches(of: quantityRegex)
        let withUnit = quantityMatches.filter { $0.output[2].substring != nil }
        let chosen = quantityMatches.count == 1 ? quantityMatches.first : (withUnit.count == 1 ? withUnit.first : nil)
        if let chosen, let digits = chosen.output[1].substring, let value = number(String(digits)), value > 0 {
            quantity = value
            unit = chosen.output[2].substring.map { canonicalUnit(String($0)) } ?? ""
            s.replaceSubrange(chosen.range, with: " ")
        }

        // 4. Description
        var description = clean(s)
        var placeholder: String?
        let laborWords = rx(#"(?i)\b(?:mano de obra|labor|labour)\b"#)
        let isLabor = unit == "hr" || unit == "day" || description.firstMatch(of: laborWords) != nil
        let letterCount = description.count(where: \.isLetter)

        if price == nil {
            // Without a price, only keep segments that look like real work, not filler.
            let wordCount = description.split(separator: " ").count
            guard letterCount >= 4, wordCount >= 2 || quantityMatches.count > 0 else { return nil }
            let startsWithWork = description.firstMatch(of: rx("(?i)^(?:\(workVerbs))\\b")) != nil
            if !startsWithWork, chosen == nil {
                return .note(clean(segment))
            }
        } else if letterCount < 3 {
            description = isLabor ? "Labor" : "Item"
            placeholder = description
        }

        // 5. Unit price
        var unitPrice = price?.value ?? 0
        if let price, !isEach, price.isTotalPrefix || saysTotal, quantity > 1 {
            let each = price.value / quantity
            if abs(Money.round(each) * quantity - price.value) < 0.005 {
                unitPrice = Money.round(each)
            } else {
                // The total doesn't divide evenly: keep it as one lump-sum line.
                let label = unit.isEmpty ? "" : " \(unit)"
                description = "\(description) (\(Money.quantity(quantity, locale: Locale(identifier: "en_US")))\(label))"
                quantity = 1
                unit = ""
            }
        }

        return .item(DraftItem(text: description, quantity: quantity, unit: unit, unitPrice: unitPrice, isLabor: isLabor),
                     placeholder: placeholder)
    }

    private static func clean(_ raw: String) -> String {
        var s = raw.replacing(rx(#"\s+"#), with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let leading = rx(#"(?i)^(?:y|and|de|del|of|con|with|también|tambien|luego|más|mas|plus|x|necesito|necesita|hay que|vamos a|voy a|i need to|we need to|need to)\s+"#)
        let trailing = rx(#"(?i)\s+(?:a|at|por|for|de|of|en|y|and|con|with|son)$"#)
        var changed = true
        while changed {
            changed = false
            let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-–—"))
            if trimmed != s { s = trimmed; changed = true }
            if let match = s.firstMatch(of: leading) { s.removeSubrange(match.range); changed = true }
            if let match = s.firstMatch(of: trailing) { s.removeSubrange(match.range); changed = true }
        }
        guard let first = s.first else { return "" }
        return first.uppercased() + s.dropFirst()
    }

    // MARK: Helpers

    private static func number(_ raw: String) -> Double? {
        var s = raw
        // "1,200" → thousands separator; "4,50" → decimal comma.
        s = s.replacing(rx(#",(?=\d{3}(?:\D|$))"#), with: "")
        s = s.replacingOccurrences(of: ",", with: ".")
        return Double(s)
    }

    private static let logger = Logger(subsystem: "com.cotiza.app", category: "parser")

    /// Swift compiles regex strings at run time, so a pattern the engine rejects (lookbehind, for one)
    /// is caught by tests in debug builds and, in a shipped build, degrades to "no match" instead of
    /// taking the app down. Parsing runs off the main actor (see `EstimateEngine.parse`).
    private static func rx(_ pattern: String) -> Regex<AnyRegexOutput> {
        do {
            return try Regex(pattern)
        } catch {
            logger.fault("Invalid regex \(pattern, privacy: .public): \(error.localizedDescription, privacy: .public)")
            assertionFailure("Invalid regex \(pattern): \(error)")
            return Regex(/(?!)/)
        }
    }
}
