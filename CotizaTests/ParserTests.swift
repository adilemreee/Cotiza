import Foundation
import Testing
@testable import Cotiza

@Suite("Rule-based parser")
struct ParserTests {
    @Test func `spanish job with unit prices`() throws {
        let draft = RuleBasedParser.parse("Pintar dos recámaras a 350 cada una, instalar 3 puertas a 120 dólares cada una y 8 horas de mano de obra a 45 la hora. Cliente María López.")
        #expect(draft.clientName == "María López")
        #expect(draft.textLanguage == .spanish)
        try #require(draft.items.count == 3)

        #expect(draft.items[0].text == "Pintar recámaras")
        #expect(draft.items[0].quantity == 2)
        #expect(draft.items[0].unitPrice == 350)

        #expect(draft.items[1].text == "Instalar puertas")
        #expect(draft.items[1].quantity == 3)
        #expect(draft.items[1].unitPrice == 120)

        #expect(draft.items[2].text == "Mano de obra")
        #expect(draft.items[2].quantity == 8)
        #expect(draft.items[2].unit == "hr")
        #expect(draft.items[2].unitPrice == 45)
        #expect(draft.items[2].isLabor)
    }

    @Test func `english job with units and dollar signs`() throws {
        let draft = RuleBasedParser.parse("Install 200 square feet of laminate flooring at $4.50 a square foot. Remove old carpet for $300. Client is John Smith.")
        #expect(draft.clientName == "John Smith")
        #expect(draft.textLanguage == .english)
        try #require(draft.items.count == 2)

        #expect(draft.items[0].text == "Install laminate flooring")
        #expect(draft.items[0].quantity == 200)
        #expect(draft.items[0].unit == "sq ft")
        #expect(draft.items[0].unitPrice == 4.5)

        #expect(draft.items[1].text == "Remove old carpet")
        #expect(draft.items[1].quantity == 1)
        #expect(draft.items[1].unitPrice == 300)
    }

    @Test func `a total price is divided across the quantity`() throws {
        let draft = RuleBasedParser.parse("Instalar 3 ventanas por 600 dólares")
        let item = try #require(draft.items.first)
        #expect(item.quantity == 3)
        #expect(item.unitPrice == 200)
    }

    @Test func `an uneven total stays a lump sum`() throws {
        let draft = RuleBasedParser.parse("Install 3 windows for $500")
        let item = try #require(draft.items.first)
        #expect(item.quantity == 1)
        #expect(item.unitPrice == 500)
        #expect(item.text.contains("3"))
    }

    @Test func `thousands separators are read as one number`() throws {
        let draft = RuleBasedParser.parse("Cambiar el techo por $12,500")
        let item = try #require(draft.items.first)
        #expect(item.unitPrice == 12_500)
        #expect(item.text == "Cambiar el techo")
    }

    @Test func `joined nouns are not split into two items`() throws {
        let draft = RuleBasedParser.parse("Instalar lavamanos y espejo por 250")
        try #require(draft.items.count == 1)
        #expect(draft.items[0].text == "Instalar lavamanos y espejo")
        #expect(draft.items[0].unitPrice == 250)
    }

    @Test func `work without a price is kept with a zero price`() throws {
        let draft = RuleBasedParser.parse("Reparar la cerca del patio")
        let item = try #require(draft.items.first)
        #expect(item.unitPrice == 0)
        #expect(item.text == "Reparar la cerca del patio")
    }

    @Test(arguments: ["", "   ", "ok", "gracias."])
    func `filler produces no items`(input: String) {
        #expect(RuleBasedParser.parse(input).items.isEmpty)
    }

    @Test func `a bare number at the end of a phrase is its price`() throws {
        let draft = RuleBasedParser.parse("Demo the old tile, new vanity 600")
        try #require(draft.items.count == 2)
        #expect(draft.items[0].text == "Demo the old tile")
        #expect(draft.items[0].unitPrice == 0)
        #expect(draft.items[1].text == "New vanity")
        #expect(draft.items[1].quantity == 1)
        #expect(draft.items[1].unitPrice == 600)
    }

    @Test func `timing and deposit remarks become notes, not line items`() throws {
        let draft = RuleBasedParser.parse("Cortar el pasto por 180. Empezamos el lunes, se pide la mitad de anticipo.")
        try #require(draft.items.count == 1)
        #expect(draft.items[0].unitPrice == 180)
        #expect(draft.notes == "Empezamos el lunes. Se pide la mitad de anticipo.")
    }

    /// Every regex in the parser is compiled at run time, so each code path gets exercised here:
    /// an unsupported pattern would otherwise only surface as a crash in the field.
    @Test(arguments: [
        "Pintar la sala $400",
        "Pintar la sala 400 dólares",
        "Pintar la sala a 400",
        "Pintar la sala 400",
        "Pintar la sala",
        "3 puertas",
        "200 pies cuadrados de piso a 4,50 el pie cuadrado",
        "12 linear feet of baseboard at $3.25 per foot, plus 2 gallons of primer at 30 each",
        "Para la señora Ana Pérez: limpieza por 6 horas a 40 por hora, en total 240",
        "y también más de con por a",
        "$", "100", "a 5 manos", "50%", "1,200.50", "¿¡...!?", "😀 pintar 🏠 por 300",
        "Instalar 3 ventanas por 600 dólares en total y cambiar 2 chapas a 45 c/u; luego limpiar todo",
    ])
    func `no input crashes the parser`(input: String) {
        let draft = RuleBasedParser.parse(input)
        #expect(draft.items.allSatisfy { $0.quantity > 0 && $0.unitPrice >= 0 && !$0.text.isEmpty })
        _ = RuleBasedParser.numbers(in: input)
    }

    @Test func `a measurement after the job description prices that job`() throws {
        let draft = RuleBasedParser.parse("Pintar la sala de Maria Lopez, 400 pies cuadrados a 2 dolares el pie, mas pintura 120 dolares")
        #expect(draft.clientName == "Maria Lopez")
        #expect(draft.title == "Pintar la sala")
        try #require(draft.items.count == 2)

        #expect(draft.items[0].text == "Pintar la sala")
        #expect(draft.items[0].quantity == 400)
        #expect(draft.items[0].unit == "sq ft")
        #expect(draft.items[0].unitPrice == 2)

        #expect(draft.items[1].text == "Pintura")
        #expect(draft.items[1].unitPrice == 120)
    }

    @Test func `english job for a named client with the measurement after it`() throws {
        let draft = RuleBasedParser.parse("Paint the kitchen for John Smith, 300 square feet at $3 a square foot")
        #expect(draft.clientName == "John Smith")
        try #require(draft.items.count == 1)
        #expect(draft.items[0].text == "Paint the kitchen")
        #expect(draft.items[0].quantity == 300)
        #expect(draft.items[0].unitPrice == 3)
    }

    @Test func `hours after a priced job stay their own labor line`() throws {
        let draft = RuleBasedParser.parse("Pintar la sala por 300, 8 horas a 40 la hora")
        try #require(draft.items.count == 2)
        #expect(draft.items[0].unitPrice == 300)
        #expect(draft.items[1].text == "Labor")
        #expect(draft.items[1].quantity == 8)
        #expect(draft.items[1].isLabor)
    }

    @Test func `an uneven lump sum keeps the job name and the measurement`() throws {
        let draft = RuleBasedParser.parse("Limpiar el patio, 3 horas por 100")
        try #require(draft.items.count == 1)
        #expect(draft.items[0].text == "Limpiar el patio (3 hr)")
        #expect(draft.items[0].unitPrice == 100)
    }

    @Test(arguments: ["Pintura de Sherwin Williams por 90", "Pintar con Benjamin Moore por 400", "Material de Home Depot por 85",
                      "Pintar la casa de San Antonio por 500", "Mover muebles de la Sala por 50"])
    func `brands and places are not clients`(input: String) {
        #expect(RuleBasedParser.parse(input).clientName == nil)
    }

    @Test func `duration is not mistaken for a price`() throws {
        let draft = RuleBasedParser.parse("Limpieza profunda por 6 horas a 40 la hora")
        let item = try #require(draft.items.first)
        #expect(item.quantity == 6)
        #expect(item.unit == "hr")
        #expect(item.unitPrice == 40)
    }
}

@Suite("Engine validation")
struct EngineValidationTests {
    @Test func `prices the contractor never said are cleared`() {
        let generated = GeneratedEstimate(
            title: "Bathroom repaint",
            clientName: "Ana Ruiz",
            items: [
                GeneratedItem(description: "Paint bathroom", quantity: 1, unit: "", unitPrice: 400, isLabor: true),
                GeneratedItem(description: "Replace faucet", quantity: 1, unit: "each", unitPrice: 185, isLabor: true),
            ],
            notes: ""
        )
        let transcript = "Pintar el baño por 400 y cambiar la llave"
        let draft = EstimateEngine.validated(generated, transcript: transcript, priceBook: [], language: .english, fallback: RuleBasedParser.parse(transcript))

        #expect(draft.items[0].unitPrice == 400)
        #expect(draft.items[1].unitPrice == 0, "185 was never spoken")
        #expect(draft.items[1].unit == "")
        #expect(draft.clientName == nil, "Ana Ruiz was never spoken")
    }

    @Test func `a spoken total divided by quantity counts as grounded`() {
        let generated = GeneratedEstimate(
            title: "Windows", clientName: "",
            items: [GeneratedItem(description: "Install windows", quantity: 3, unit: "", unitPrice: 200, isLabor: true)],
            notes: ""
        )
        let transcript = "Instalar 3 ventanas por 600"
        let draft = EstimateEngine.validated(generated, transcript: transcript, priceBook: [], language: .english, fallback: RuleBasedParser.parse(transcript))
        #expect(draft.items[0].unitPrice == 200)
    }

    @Test func `price book prices are allowed`() {
        let generated = GeneratedEstimate(
            title: "Doors", clientName: "",
            items: [GeneratedItem(description: "Install interior door", quantity: 2, unit: "", unitPrice: 120, isLabor: true)],
            notes: ""
        )
        let hints = [PriceHint(name: "Install interior door", unit: "", unitPrice: 120)]
        let draft = EstimateEngine.validated(generated, transcript: "instalar dos puertas", priceBook: hints, language: .english, fallback: RuleBasedParser.parse("instalar dos puertas"))
        #expect(draft.items[0].unitPrice == 120)
    }
}

@Suite("Totals")
struct TotalsTests {
    @Test func `tax applies only to taxable lines`() {
        let totals = Totals(lines: [.init(amount: 700, isTaxable: false), .init(amount: 200, isTaxable: true)], taxRate: 8.25)
        #expect(totals.subtotal == 900)
        #expect(totals.tax == 16.5)
        #expect(totals.total == 916.5)
    }

    @Test func `amounts round to cents`() {
        let totals = Totals(lines: [.init(amount: Money.round(3 * 33.335), isTaxable: true)], taxRate: 7)
        #expect(totals.subtotal == 100.01)
        #expect(totals.tax == 7)
        #expect(totals.total == 107.01)
    }
}
