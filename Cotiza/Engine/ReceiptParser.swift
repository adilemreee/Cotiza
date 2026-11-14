import CoreGraphics
import Foundation
import ImageIO
import Vision

/// One purchase read off a store receipt.
nonisolated struct ReceiptLine: Equatable, Sendable, Identifiable {
    var id = UUID()
    var text: String
    var quantity: Double = 1
    var unitPrice: Double

    var total: Double { Money.round(quantity * unitPrice) }

    static func == (lhs: ReceiptLine, rhs: ReceiptLine) -> Bool {
        lhs.text == rhs.text && lhs.quantity == rhs.quantity && lhs.unitPrice == rhs.unitPrice
    }
}

/// Turns the text lines of a receipt into purchases. It keeps lines that end in a price and
/// skips totals, tax, payment and discount lines. Every price comes straight from the receipt.
nonisolated enum ReceiptParser {
    private static let skipWords = [
        "subtotal", "sub total", "sub-total", "total", "tax", "impuesto", "iva", "balance", "saldo", "change", "cambio",
        "cash", "efectivo", "visa", "mastercard", "master card", "amex", "american express", "discover", "debit", "debito",
        "débito", "credit", "credito", "crédito", "tarjeta", "card", "tender", "payment", "pago", "paid", "pagado", "savings",
        "you saved", "ahorro", "discount", "descuento", "coupon", "cupon", "cupón", "rewards", "points", "puntos", "auth",
        "approval", "ref #", "account", "acct", "items sold", "tip", "propina", "amount due", "importe", "rounding",
    ]

    private static let price = #"(-)?\$?\s?(\d{1,3}(?:[,\s]\d{3})*[.,]\d{2}|\d{1,6}[.,]\d{2})(?:\s*-)?(?:\s+[A-Z]{1,2})?\s*$"#
    private static let multiple = #"^(\d+(?:[.,]\d+)?)\s*(?:@|x|X|×)\s*\$?(\d+[.,]\d{2})"#

    static func parse(_ lines: [String]) -> [ReceiptLine] {
        var result: [ReceiptLine] = []
        for raw in lines {
            let line = raw.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // "2 @ 3.98" under an item: the item's total was for two.
            if let match = line.firstMatch(of: rx(multiple)),
               let quantity = number(match.output[1].substring), let each = number(match.output[2].substring), quantity > 0 {
                let rest = clean(String(line[match.range.upperBound...]).replacing(rx(price), with: ""))
                if rest.count(where: \.isLetter) >= 3 {
                    result.append(ReceiptLine(text: rest, quantity: quantity, unitPrice: each))
                } else if var last = result.popLast() {
                    if abs(last.unitPrice - quantity * each) < 0.015 || last.quantity == 1 {
                        last.quantity = quantity
                        last.unitPrice = each
                    }
                    result.append(last)
                }
                continue
            }

            guard let match = line.firstMatch(of: rx(price)),
                  match.output[1].substring == nil,
                  let value = number(match.output[2].substring), value > 0 else { continue }
            let name = clean(String(line[..<match.range.lowerBound]))
            guard name.count(where: \.isLetter) >= 3, !isSummary(name) else { continue }
            result.append(ReceiptLine(text: name, unitPrice: value))
        }
        return result
    }

    private static func isSummary(_ name: String) -> Bool {
        let lowered = " " + name.lowercased() + " "
        return skipWords.contains { word in
            lowered.firstMatch(of: rx("[^\\p{L}]" + NSRegularExpression.escapedPattern(for: word) + "[^\\p{L}]")) != nil
        }
    }

    /// Drops SKUs and barcodes, stray symbols and extra spaces: "012345678901 2X4 STUD 8FT" → "2X4 Stud 8FT".
    private static func clean(_ raw: String) -> String {
        var s = raw.replacing(rx(#"\b\d{5,}\b"#), with: " ")
        s = s.replacing(rx(#"[<>*#|_=]+"#), with: " ")
        s = s.replacing(rx(#"\s+"#), with: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,-:$"))
        // Receipts shout; the client's PDF shouldn't.
        if s == s.uppercased() {
            s = s.lowercased().split(separator: " ").map { word in
                word.contains(where: \.isNumber) ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst()
            }.joined(separator: " ")
        }
        return s
    }

    private static func number(_ raw: Substring?) -> Double? {
        guard var s = raw.map(String.init) else { return nil }
        s = s.replacingOccurrences(of: " ", with: "")
        if s.contains("."), s.contains(",") {
            s = s.replacingOccurrences(of: ",", with: "")
        } else if let comma = s.lastIndex(of: ","), s.distance(from: comma, to: s.endIndex) == 3 {
            s.replaceSubrange(comma...comma, with: ".")
        } else {
            s = s.replacingOccurrences(of: ",", with: "")
        }
        return Double(s)
    }

    private static func rx(_ pattern: String) -> Regex<AnyRegexOutput> {
        (try? Regex(pattern)) ?? Regex(/(?!)/)
    }
}

/// Reads the text of a receipt photo on the device, line by line, top to bottom.
nonisolated enum ReceiptReader {
    static func lines(in image: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "es-US")]
        // Correction "fixes" SKUs and prices into words.
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: image, orientation: orientation)
        let pieces = observations.compactMap { observation -> (text: String, box: CGRect)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return (text, CGRect(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height))
        }
        return groupIntoLines(pieces)
    }

    /// Receipts print the item on the left and the price on the right; Vision reads them as separate
    /// pieces. Pieces whose vertical centers line up are joined into one line, left to right.
    static func groupIntoLines(_ pieces: [(text: String, box: CGRect)]) -> [String] {
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY } // Vision's origin is bottom-left.
        var rows: [[(text: String, box: CGRect)]] = []
        for piece in sorted {
            if let index = rows.indices.last, let anchor = rows[index].first,
               abs(anchor.box.midY - piece.box.midY) < max(anchor.box.height, piece.box.height) * 0.5 {
                rows[index].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ") }
    }
}
