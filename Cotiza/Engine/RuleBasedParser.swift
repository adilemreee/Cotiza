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

/// Deterministic Spanish/English/Turkish job-description parser.
///
/// Used on devices without Apple Intelligence, and as the safety net whenever the
/// on-device model refuses or fails. It never invents numbers: every quantity and
/// price in the result is literally present in the input.
nonisolated enum RuleBasedParser {

    /// `spoken` is the language the contractor said they speak ("I speak" on the capture screen).
    /// Turkish there is trusted outright; otherwise the text decides between Spanish and English.
    static func parse(_ transcript: String, spoken: DocumentLanguage? = nil) -> EstimateDraft {
        var text = transcript
            .replacingOccurrences(of: "\n", with: ". ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let language = detectLanguage(of: transcript, spoken: spoken)

        let clientName = language == .turkish ? turkishClient(from: &text) : extractClient(from: &text)
        text = replaceNumberWords(in: text, language: language)

        var items: [DraftItem] = []
        var notes: [String] = []
        // The last line was work with no price or quantity yet ("Pintar la sala").
        var lastIsOpenJob = false
        for segment in segments(of: text) {
            switch parseSegment(segment, language: language) {
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

        let title = items.first.map { String($0.text.prefix(48)) } ?? ""
        let noteText = notes.isEmpty ? "" : notes.joined(separator: ". ") + "."
        return EstimateDraft(title: title, clientName: clientName, items: items, notes: noteText, source: .basic, textLanguage: language)
    }

    static func detectLanguage(of text: String, spoken: DocumentLanguage? = nil) -> DocumentLanguage {
        // Short phrases ("kapı 120 lira") don't carry enough to guess from.
        if spoken == .turkish { return .turkish }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.spanish, .english, .turkish]
        recognizer.processString(text)
        // Letters only Turkish uses settle it; otherwise Turkish needs a confident guess, so a short
        // English or Spanish phrase is never read with Turkish rules.
        // (Not ü: Spanish has it too, as in "desagüe".)
        let hasTurkishLetters = text.contains(where: { "çğışöÇĞİŞÖ".contains($0) })
        let turkishConfidence = recognizer.languageHypotheses(withMaximum: 3)[.turkish] ?? 0
        if hasTurkishLetters || turkishConfidence >= 0.9 { return .turkish }
        return recognizer.dominantLanguage == .spanish ? .spanish : .english
    }

    /// Every number that literally appears in the text (after number words are converted).
    static func numbers(in transcript: String, spoken: DocumentLanguage? = nil) -> [Double] {
        let text = replaceNumberWords(in: transcript, language: detectLanguage(of: transcript, spoken: spoken))
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

    /// "Müşteri Ayşe Yılmaz", "Ayşe Yılmaz için", "Ayşe Hanım". The name is taken out of the job text.
    private static func turkishClient(from text: inout String) -> String? {
        let name = #"(\p{Lu}[\p{L}\-]+(?:\s+\p{Lu}[\p{L}\-]+){0,2})"#
        let patterns = [
            #"(?i:\b(?:müşteri(?:nin adı)?|musteri(?:nin adi)?|müşterimiz)(?:\s+(?:de|da))?)[:\s]+"# + name + #"(?:['’]\p{L}+)?[.,;]?"#,
            name + #"\s+(?i:hanım|hanim|bey)(?:['’]?\p{L}*)?\b"#,
            #"(\p{Lu}[\p{L}\-]+(?:\s+\p{Lu}[\p{L}\-]+){1,2})(?:['’]\p{L}+)?\s+(?i:için|icin)\b"#,
        ]
        for pattern in patterns {
            guard let match = text.firstMatch(of: rx(pattern)), let found = match.output[1].substring else { continue }
            let result = String(found)
            text.replaceSubrange(match.range, with: ". ")
            return result
        }
        return nil
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

    private static let turkishOnes: [(String, Int)] = [
        ("iki", 2), ("üç", 3), ("uc", 3), ("dört", 4), ("dort", 4), ("beş", 5), ("bes", 5), ("altı", 6),
        ("yedi", 7), ("sekiz", 8), ("dokuz", 9),
    ]
    private static let turkishTens: [(String, Int)] = [
        ("on", 10), ("yirmi", 20), ("otuz", 30), ("kırk", 40), ("kirk", 40), ("elli", 50), ("altmış", 60),
        ("yetmiş", 70), ("seksen", 80), ("doksan", 90),
    ]

    static func replaceNumberWords(in text: String, language: DocumentLanguage? = nil) -> String {
        if (language ?? detectLanguage(of: text)) == .turkish { return turkishNumbers(in: text) }
        var result = text
        for (word, digits) in numberWords {
            result = result.replacing(rx("(?i)\\b\(word)\\b"), with: digits)
        }
        return result
    }

    /// Turkish digits and number words: "1.200" is 1200, "120'den" is 120, "350'şer" is 350 each,
    /// "yirmi beş" is 25, "iki yüz" is 200, "iki buçuk" is 2.5. "Bir" is left alone: it is also "a".
    private static func turkishNumbers(in text: String) -> String {
        var s = text
        // Thousands dots: "1.200", "12.500.000". A dot before exactly three digits.
        while let match = s.firstMatch(of: rx(#"(\d)\.(\d{3})(?!\d)"#)) {
            s.replaceSubrange(match.range, with: "\(match.output[1].substring!)\(match.output[2].substring!)")
        }
        // "₺950", "1.800 ₺", "750 TL'den": the lira written as a sign or with a case ending becomes "lira".
        s = s.replacing(rx(#"₺\s?(\d[\d,]*(?:\.\d+)?)"#)) { "\($0.output[1].substring!) lira" }
        s = s.replacing(rx(#"(\d)\s?₺"#)) { "\($0.output[1].substring!) lira" }
        s = s.replacing(rx(#"(?i)\b(?:tl|ytl)['’]?\p{L}*(?!\p{L})"#), with: "lira")
        // "metre kare", said as two words.
        s = s.replacing(rx(#"(?i)\bmetre\s+kare(\p{L}*)"#)) { "metrekare\($0.output[1].substring!)" }
        // "350'şer", "120'şer": so much each.
        s = s.replacing(rx(#"(\d[\d,]*(?:\.\d+)?)['’](?:şer|şar|ser|sar|er|ar)(?!\p{L})"#)) { "tanesi \($0.output[1].substring!)" }
        // Case endings: "120'den", "45'ten", "600'e".
        s = s.replacing(rx(#"(\d)['’]\p{L}+"#)) { "\($0.output[1].substring!)" }
        // "Bir de": "also".
        s = s.replacing(rx(#"(?i)\bbir de\b"#), with: ",")
        let ones = turkishOnes.map(\.0).joined(separator: "|")
        let tens = turkishTens.map(\.0).joined(separator: "|")
        func value(_ word: Substring?, _ table: [(String, Int)]) -> Int {
            guard let word else { return 0 }
            return table.first { $0.0 == word.lowercased() }?.1 ?? 0
        }
        // "iki yüz", "yüz elli": hundreds.
        s = s.replacing(rx("(?i)\\b(?:(\(ones))\\s+)?yüz(?:\\s+(\(tens)))?(?:\\s+(\(ones)))?\\b")) { m in
            let hundreds = max(value(m.output[1].substring, turkishOnes), 1) * 100
            return String(hundreds + value(m.output[2].substring, turkishTens) + value(m.output[3].substring, turkishOnes))
        }
        // "yirmi beş": tens and ones.
        s = s.replacing(rx("(?i)\\b(\(tens))\\s+(\(ones))\\b")) { m in
            String(value(m.output[1].substring, turkishTens) + value(m.output[2].substring, turkishOnes))
        }
        for (word, number) in turkishTens {
            s = s.replacing(rx("(?i)\\b\(word)\\b"), with: String(number))
        }
        for (word, number) in turkishOnes where word != "altı" {
            s = s.replacing(rx("(?i)\\b\(word)\\b"), with: String(number))
        }
        // "altı" is six, but also "under" ("lavabo altı"): only when it opens a phrase.
        s = s.replacing(rx(#"(?i)(^|[,.;]\s*|\bve\s+)altı\b"#)) { "\($0.output[1].substring ?? "")6" }
        // "iki bin beş yüz" (by now "2 bin 500") is 2500; "bin iki yüz" is 1200; "on bin" is 10000.
        for (word, size) in [("milyon", 1_000_000), ("bin", 1000)] {
            s = s.replacing(rx("(?i)(?:\\b(\\d+)\\s+)?\\b\(word)\\b(?:\\s+(\\d+)(?![\\d.,]))?")) { m in
                let times = m.output[1].substring.flatMap { Int($0) } ?? 1
                let rest = m.output[2].substring.flatMap { Int($0) } ?? 0
                return String(times * size + (rest < size ? rest : 0)) + (rest >= size ? " \(rest)" : "")
            }
        }
        // "2 buçuk saat": and a half. "yarım saat": half.
        s = s.replacing(rx(#"(?i)(\d+)\s+buçuk\b"#)) { "\($0.output[1].substring!).5" }
        s = s.replacing(rx(#"(?i)\byarım\b"#), with: "0.5")
        // "52 lira 50 kuruş" is 52.50.
        s = s.replacing(rx(#"(?i)(\d+)\s*(?:lira|dolar)\s+(\d{1,2})\s*kuruş\b"#)) { m in
            let cents = String(m.output[2].substring!)
            return "\(m.output[1].substring!).\(cents.count == 1 ? "0" + cents : cents) lira"
        }
        // "52,50": a decimal comma.
        s = s.replacing(rx(#"(\d),(\d{1,2})(?![\d])"#)) { "\($0.output[1].substring!).\($0.output[2].substring!)" }
        return s
    }

    // MARK: Segmentation

    private static func segments(of text: String) -> [String] {
        let primary = text.split(separator: rx(#"(?i)[.;]\s+|[.;]\s*$|,\s+|\s+(?:también|tambien|además|ademas|luego|después|despues|plus|also|then|ayrıca|ayrica|sonra|artı)\s+"#))
        var result: [String] = []
        for piece in primary {
            let segment = String(piece)
            let parts = segment.split(separator: rx(#"(?i)\s+(?:y|and|más|mas|ve|artı)\s+"#)).map(String.init)
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
        /// Turkish puts "each" before the price ("tanesi 120"), inside the matched range.
        var isEach = false
    }

    private static let unitTable: [(pattern: String, unit: String)] = [
        (#"metrekare|m2|m²"#, "m²"),
        (#"pies cuadrados|pie cuadrado|square feet|square foot|sq\.? ?ft\.?|sqft"#, "sq ft"),
        (#"pies lineales|pie lineal|linear feet|linear foot|lin\.? ?ft\.?"#, "lin ft"),
        (#"metros cuadrados|metro cuadrado|square meters|square meter"#, "m²"),
        (#"yardas cuadradas|yarda cuadrada|square yards|square yard"#, "sq yd"),
        (#"yardas|yarda|yards|yard|yd"#, "yd"),
        (#"pies|pie|feet|foot|ft"#, "ft"),
        (#"horas|hora|hours|hour|hrs|hr|saat"#, "hr"),
        (#"días|dias|día|dia|days|day|gün|gun"#, "day"),
        (#"galones|galón|galon|gallons|gallon|gal"#, "gal"),
        (#"cajas|caja|boxes|box|kutu"#, "box"),
        (#"bolsas|bolsa|bags|bag|torba|çuval|cuval"#, "bag"),
        (#"metros|metro|meters|meter|metre"#, "m"),
        (#"libras|libra|pounds|pound|lbs|lb"#, "lb"),
        (#"kilo|kg"#, "kg"),
        (#"litre|lt"#, "L"),
        (#"ton"#, "ton"),
        (#"rulo"#, "rulo"),
        (#"paket"#, "paket"),
        (#"kova"#, "kova"),
        (#"oda"#, "oda"),
        (#"adet|tane"#, ""),
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
        let totalPrefixes: Set<String> = ["por", "for", "en", "de", "son", "toplam", "toplamda", "hepsi"]
        let eachPrefixes: Set<String> = ["tanesi", "adedi", "saati", "saatliği", "saatligi", "saatlik", "metrekaresi", "metresi",
                                         "günlüğü", "gunlugu", "günü", "günlük", "galonu", "rulosu", "paketi", "kovası", "kutusu",
                                         "torbası", "litresi", "tonu", "başına", "basina", "başı", "basi", "her biri", "beheri"]
        let turkishPrefixes = "(?:(?:metrekare|metre|saat|gün|adet|tane|kişi|oda)\\s+)?(?:başına|basina|başı|basi)|tanesi|adedi|saati|saatliği|saatligi|saatlik|metrekaresi|metresi|günlüğü|gunlugu|günü|günlük|galonu|rulosu|paketi|kovası|kutusu|torbası|litresi|tonu|her biri|beheri|fiyatı|fiyati|ücreti|ucreti|tutarı|tutari|toplam|toplamda|hepsi"
        let prefix = "(\\b(?:a|at|por|for|en|de|cuestan|cuesta|cobro|son|valen|vale|\(turkishPrefixes))\\s+)?"
        let amount = #"(\d[\d,]*(?:\.\d+)?)"#
        let notAUnit = "(?!\\s*(?:\(unitAlternation)|manos|capas|coats|kat|%|por ciento|percent)\\b)"
        let patterns = [
            "(?i)\(prefix)[\\$€₺]\\s?\(amount)",
            "(?i)\(prefix)\(amount)\\s*(?:€|₺)",
            // Turkish adds case endings to the currency: "liradan", "liraya", "liralık", "dolarlık".
            "(?i)\(prefix)\(amount)\\s*(?:dólares|dolares|dollars|dollar|bucks|usd|pesos|euros|euro|eur|avro|dolar\\p{L}*|lira\\p{L}*|tl)(?!\\p{L})",
            "(?i)(\\b(?:a|at|por|for|cuestan|cuesta|cobro|son|\(turkishPrefixes))\\s+)\(amount)(?![\\d.,]*\\d)\(notAUnit)",
        ]
        for pattern in patterns {
            guard let match = s.matches(of: rx(pattern)).last,
                  let digits = match.output[2].substring,
                  let value = number(String(digits)) else { continue }
            let prefixWord = match.output[1].substring.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            // "metrekare başına": the last word says it.
            let lastWord = prefixWord.split(separator: " ").last.map(String.init) ?? prefixWord
            return PriceMatch(value: value, range: match.range, isTotalPrefix: totalPrefixes.contains(prefixWord),
                              isEach: eachPrefixes.contains(prefixWord) || eachPrefixes.contains(lastWord))
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

    /// Turkish verbs come last ("kapı takılacak", "duvarı boyamak"), so a stem anywhere marks real work.
    private static let turkishWork = #"\b(?:boya|tak|montaj|monte|tamir|onar|değiş|degis|sök|sok|temizle|kes|döşe|dose|sıva|siva|zımpara|zimpara|kur|yık|yik|cila|vernik|izolasyon|yalıtım|yalitim|fayans|seramik|parke|alçı|alci|tadilat|tesisat|kablo|boru|çatı|cati|bahçe|bahce|budama|biç|bic)\p{L}*"#

    private static func parseSegment(_ segment: String, language: DocumentLanguage = .english) -> Parsed? {
        var s = segment

        // 1. Price
        let price = findPrice(in: s)
        if let price { s.replaceSubrange(price.range, with: " ") }

        // 2. "each" / "total" markers
        let eachPattern = #"(?i)\b(?:c/u|cada(?:\s+un[oa]?)?|each|apiece|tanesi|adedi|her biri|her birine|birim fiyatı|beheri|saati|saatliği|saatlik|metrekaresi|metresi|günlüğü|günü|günlük|galonu|rulosu|paketi|kovası|kutusu|torbası|litresi|başına|basina|başı|por\s+(?:hora|pie|pieza|unidad|galón|galon|yarda|metro|día|dia)(?:\s+cuadrad[oa])?|(?:la|el)\s+(?:hora|pie|pieza|unidad|galón|galon|yarda|metro|día|dia)(?:\s+cuadrad[oa])?|(?:an?|per)\s+(?:hour|foot|square foot|sq ft|piece|unit|gallon|yard|day))(?![\p{L}])"#
        var isEach = price?.isEach ?? false
        if price != nil, !isEach, let match = s.firstMatch(of: rx(eachPattern)) {
            isEach = true
            s.replaceSubrange(match.range, with: " ")
        }
        var saysTotal = false
        if let match = s.firstMatch(of: rx(#"(?i)\b(?:en total|in total|total|toplamda|toplam|hepsi)\b"#)) {
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
        var description = clean(s, language: language)
        var placeholder: String?
        let laborWords = rx(#"(?i)\b(?:mano de obra|labor|labour|işçilik|iscilik|işçi|isci|usta|emek)\b"#)
        let isLabor = unit == "hr" || unit == "day" || description.firstMatch(of: laborWords) != nil
        let letterCount = description.count(where: \.isLetter)

        if price == nil {
            // Without a price, only keep segments that look like real work, not filler.
            let wordCount = description.split(separator: " ").count
            guard letterCount >= 4, wordCount >= 2 || quantityMatches.count > 0 else { return nil }
            let startsWithWork = language == .turkish
                ? description.firstMatch(of: rx("(?i)\(turkishWork)")) != nil
                : description.firstMatch(of: rx("(?i)^(?:\(workVerbs))\\b")) != nil
            if !startsWithWork, chosen == nil {
                return .note(clean(segment, language: language))
            }
        } else if letterCount < 3 {
            description = isLabor ? language.text("Labor", "Labor", "İşçilik") : language.text("Item", "Item", "Kalem")
            placeholder = description
        }

        // 5. Unit price
        var unitPrice = price?.value ?? 0
        // Turkish says "each" out loud ("tanesi 350"); "3 oda 4.500 lira" is the price for all three.
        let isTotal = price.map { $0.isTotalPrefix || saysTotal || language == .turkish } ?? false
        // Turkish "yarım gün … 1.500 lira": half a day for 1,500.
        if let price, !isEach, isTotal, quantity > 1 || (language == .turkish && quantity < 1) {
            let each = price.value / quantity
            if abs(Money.round(each) * quantity - price.value) < 0.005 {
                unitPrice = Money.round(each)
            } else {
                // The total doesn't divide evenly: keep it as one lump-sum line.
                let label = unit.isEmpty ? "" : " \(written(unit, in: language))"
                description = "\(description) (\(Money.quantity(quantity, locale: Locale(identifier: "en_US")))\(label))"
                quantity = 1
                unit = ""
            }
        }

        return .item(DraftItem(text: description, quantity: quantity, unit: written(unit, in: language),
                                unitPrice: unitPrice, isLabor: isLabor),
                     placeholder: placeholder)
    }

    /// Units are matched in one short form ("hr"); a Turkish document prints them in Turkish.
    static func written(_ unit: String, in language: DocumentLanguage) -> String {
        guard language == .turkish else { return unit }
        let turkish = ["hr": "saat", "day": "gün", "box": "kutu", "bag": "torba", "gal": "galon",
                       "sq ft": "ft²", "lin ft": "ft", "sq yd": "yd²", "lb": "libre"]
        return turkish[unit] ?? unit
    }

    private static func clean(_ raw: String, language: DocumentLanguage = .english) -> String {
        var s = raw.replacing(rx(#"\s+"#), with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let leading = rx(#"(?i)^(?:y|and|de|del|of|con|with|también|tambien|luego|más|mas|plus|x|necesito|necesita|hay que|vamos a|voy a|i need to|we need to|need to|ve|ayrıca|ayrica|sonra|artı)\s+"#)
        let trailing = rx(#"(?i)\s+(?:a|at|por|for|de|of|en|y|and|con|with|son|ve|ile|lazım|gerek)$"#)
        var changed = true
        while changed {
            changed = false
            let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-–—"))
            if trimmed != s { s = trimmed; changed = true }
            if let match = s.firstMatch(of: leading) { s.removeSubrange(match.range); changed = true }
            if let match = s.firstMatch(of: trailing) { s.removeSubrange(match.range); changed = true }
        }
        guard let first = s.first else { return "" }
        // Turkish "işçilik" capitalizes to "İşçilik", not "Işçilik".
        return String(first).uppercased(with: language.locale) + s.dropFirst()
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
