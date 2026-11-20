import Foundation
import Testing
@testable import Cotiza

/// How dictation writes real jobs, in each language, and what the estimate must say.
@Suite("Spoken phrases")
struct SpokenPhraseTests {
    nonisolated struct Case: CustomTestStringConvertible, Sendable {
        let text: String
        let lines: [(String, Double, String, Double)]
        var testDescription: String { text }
    }

    nonisolated static let cases: [Case] = [
        // English
        .init(text: "Replace the kitchen faucet $189.99 and labor $145",
              lines: [("Replace the kitchen faucet", 1, "", 189.99), ("Labor", 1, "", 145)]),
        .init(text: "Install 1,200 square feet of laminate flooring at $2.50 a square foot",
              lines: [("Install laminate flooring", 1200, "sq ft", 2.5)]),
        .init(text: "Mow and edge the lawn 4 times at 55 each", lines: [("Mow and edge the lawn", 4, "", 55)]),
        .init(text: "Twelve hundred dollars for the deck stain", lines: [("Deck stain", 1, "", 1200)]),
        .init(text: "Two thousand five hundred for the roof repair", lines: [("Roof repair", 1, "", 2500)]),
        .init(text: "Half an hour of labor at 80 an hour", lines: [("Labor", 0.5, "hr", 80)]),
        .init(text: "Haul away debris $300 total for 3 loads", lines: [("Haul away debris", 3, "", 100)]),
        .init(text: "Deposit 50% to start. Paint the living room 800.", lines: [("Paint the living room", 1, "", 800)]),
        .init(text: "Paint the trim once for 300", lines: [("Paint the trim once", 1, "", 300)]),
        // Spanish
        .init(text: "Mil doscientos dólares por barnizar la terraza", lines: [("Barnizar la terraza", 1, "", 1200)]),
        .init(text: "Dos mil quinientos por reparar el techo", lines: [("Reparar el techo", 1, "", 2500)]),
        .init(text: "Media hora de trabajo a 80 la hora", lines: [("Trabajo", 0.5, "hr", 80)]),
        .init(text: "Quitar escombro 300 en total por 3 viajes", lines: [("Quitar escombro", 3, "", 100)]),
        .init(text: "Cortar el pasto 4 veces a 55 cada vez", lines: [("Cortar el pasto", 4, "", 55)]),
        .init(text: "Instalar 2 ventanas a quinientos cada una", lines: [("Instalar ventanas", 2, "", 500)]),
        .init(text: "Tres galones de primer a 32 cada uno y dos galones de pintura a 48 c/u",
              lines: [("Primer", 3, "gal", 32), ("Pintura", 2, "gal", 48)]),
        .init(text: "Instalar una hora y media a 60 la hora", lines: [("Instalar", 1.5, "hr", 60)]),
        // Turkish
        .init(text: "Müşteri Mehmet Kaya. Salon boyama 2.500 TL, 3 kapı takma tanesi 1.200 lira, 40 metre kare parke döşeme metrekare başına 300 TL, işçilik 8 saat saatlik 250 lira ve kombi bakımı 1.800 ₺.",
              lines: [("Salon boyama", 1, "", 2500), ("Kapı takma", 3, "", 1200), ("Parke döşeme", 40, "m²", 300),
                      ("İşçilik", 8, "saat", 250), ("Kombi bakımı", 1, "", 1800)]),
        .init(text: "Boya 6 kutu tanesi 1.250 TL", lines: [("Boya", 6, "kutu", 1250)]),
        .init(text: "Yarım gün işçilik 1500 lira", lines: [("İşçilik", 0.5, "gün", 3000)]),
        .init(text: "Priz değişimi 4 adet 150'şer lira", lines: [("Priz değişimi", 4, "", 150)]),
    ]

    @Test(arguments: cases)
    func `each phrase becomes the right lines`(_ c: Case) throws {
        let draft = RuleBasedParser.parse(c.text)
        try #require(draft.items.count == c.lines.count, "\(draft.items.map(\.text))")
        for (item, expected) in zip(draft.items, c.lines) {
            #expect(item.text == expected.0)
            #expect(item.quantity == expected.1)
            #expect(item.unit == expected.2)
            #expect(item.unitPrice == expected.3)
        }
    }

    @Test func `and joins one number, not two`() {
        #expect(RuleBasedParser.replaceNumberWords(in: "a hundred and fifty", language: .english) == "150")
        #expect(RuleBasedParser.replaceNumberWords(in: "two and three doors", language: .english) == "2 and 3 doors")
        #expect(RuleBasedParser.replaceNumberWords(in: "treinta y cinco", language: .spanish) == "35")
        #expect(RuleBasedParser.replaceNumberWords(in: "dos y tres puertas", language: .spanish) == "2 y 3 puertas")
        #expect(RuleBasedParser.replaceNumberWords(in: "paint it once", language: .english) == "paint it once")
        #expect(RuleBasedParser.replaceNumberWords(in: "once puertas", language: .spanish) == "11 puertas")
    }

    @Test func `deposits become a note, not a line`() {
        let draft = RuleBasedParser.parse("Deposit 50% to start. Paint the living room 800.")
        #expect(draft.notes.contains("50%"))
        let spanish = RuleBasedParser.parse("Pintar la sala 800. Anticipo de 400 para empezar.")
        #expect(spanish.items.count == 1)
        #expect(spanish.notes.contains("400"))
    }

    @Test func `turkish receipts in lira`() {
        let lines = ReceiptParser.parse(["SİLİKON MASTİK 89,90 TL", "SATEN BOYA 2,5 LT ₺1.250,00", "TOPLAM ₺1.339,90"])
        #expect(lines.map(\.unitPrice) == [89.9, 1250])
    }
}
