import Foundation
import PDFKit
import Testing
@testable import Cotiza

@Suite("Turkish")
struct TurkishTests {
    // MARK: Parser

    @Test func `turkish job with each prices, hours and a client`() throws {
        let draft = RuleBasedParser.parse("2 yatak odası boyama tanesi 350, 3 kapı takma tanesi 120 dolar ve 8 saat işçilik saati 45. Müşteri Ayşe Yılmaz.")
        #expect(draft.textLanguage == .turkish)
        #expect(draft.clientName == "Ayşe Yılmaz")
        try #require(draft.items.count == 3)

        #expect(draft.items[0].text == "Yatak odası boyama")
        #expect(draft.items[0].quantity == 2)
        #expect(draft.items[0].unitPrice == 350)

        #expect(draft.items[1].text == "Kapı takma")
        #expect(draft.items[1].quantity == 3)
        #expect(draft.items[1].unitPrice == 120)

        #expect(draft.items[2].text == "İşçilik")
        #expect(draft.items[2].quantity == 8)
        #expect(draft.items[2].unit == "saat")
        #expect(draft.items[2].unitPrice == 45)
        #expect(draft.items[2].isLabor)
    }

    @Test func `turkish number words, case endings and totals`() throws {
        let draft = RuleBasedParser.parse("Üç pencere değişimi toplam 1.200 dolar, 40 metrekare parke döşeme metrekaresi 25'ten, iki buçuk saat temizlik saati 30")
        try #require(draft.items.count == 3)
        // A total for three divides into a unit price.
        #expect(draft.items[0].quantity == 3)
        #expect(draft.items[0].unitPrice == 400)
        #expect(draft.items[1].quantity == 40)
        #expect(draft.items[1].unit == "m²")
        #expect(draft.items[1].unitPrice == 25)
        #expect(draft.items[2].quantity == 2.5)
        #expect(draft.items[2].unitPrice == 30)
    }

    @Test func `turkish "each" suffix and client before için`() throws {
        let draft = RuleBasedParser.parse("Mehmet Kaya için 4 priz değişimi 15'er dolar")
        #expect(draft.clientName == "Mehmet Kaya")
        try #require(draft.items.count == 1)
        #expect(draft.items[0].quantity == 4)
        #expect(draft.items[0].unitPrice == 15)
    }

    @Test func `altı is six only at the start of a phrase`() {
        #expect(RuleBasedParser.replaceNumberWords(in: "altı kapı takılacak").hasPrefix("6 kapı"))
        #expect(RuleBasedParser.replaceNumberWords(in: "lavabo altı dolap değişimi").contains("lavabo altı"))
    }

    @Test func `english and spanish are never read with turkish rules`() {
        #expect(RuleBasedParser.detectLanguage(of: "Paint 2 rooms 350") == .english)
        #expect(RuleBasedParser.detectLanguage(of: "Destapar el desagüe 120") == .spanish)
        #expect(RuleBasedParser.replaceNumberWords(in: "Install trim on ten doors") == "Install trim on 10 doors")
    }

    @Test func `turkish receipts skip totals, tax and payment`() {
        let lines = ReceiptParser.parse([
            "SİLİKON MASTİK  *89,90",
            "ARA TOPLAM  *89,90",
            "TOPKDV  *14,98",
            "TOPLAM  *89,90",
            "NAKİT  *100,00",
        ])
        #expect(lines.count == 1)
        #expect(lines.first?.unitPrice == 89.9)
    }

    @Test func `lira written every way`() throws {
        let cases: [(String, Double, Double)] = [
            ("Kombi bakımı 1.800 ₺", 1, 1800),
            ("₺950 lavabo değişimi", 1, 950),
            ("Batarya değişimi 750 TL'den", 1, 750),
            ("Kapı kolu değişimi 52,50 TL", 1, 52.5),
            ("Silikon 52 lira 5 kuruş", 1, 52.05),
            ("Mutfak tadilatı on bin liralık", 1, 10000),
            ("Elektrik tesisatı iki bin beş yüz lira", 1, 2500),
            ("Çatı tamiri bin iki yüz lira", 1, 1200),
        ]
        for (text, quantity, price) in cases {
            let draft = RuleBasedParser.parse(text)
            try #require(draft.items.count == 1, "\(text)")
            #expect(draft.items[0].quantity == quantity, "\(text)")
            #expect(draft.items[0].unitPrice == price, "\(text)")
            #expect(!draft.items[0].text.contains("₺") && !draft.items[0].text.lowercased().contains("bin"), "\(text)")
        }
    }

    @Test func `turkish units, per-unit words and totals`() throws {
        let squareMeters = RuleBasedParser.parse("40 metre kare parke döşeme metrekare başına 300 TL")
        try #require(squareMeters.items.count == 1)
        #expect(squareMeters.items[0].text == "Parke döşeme")
        #expect(squareMeters.items[0].quantity == 40)
        #expect(squareMeters.items[0].unit == "m²")
        #expect(squareMeters.items[0].unitPrice == 300)

        let rolls = RuleBasedParser.parse("Duvar kağıdı 3 rulo rulosu 400 lira")
        #expect(rolls.items.first?.text == "Duvar kağıdı")
        #expect(rolls.items.first?.unit == "rulo")
        #expect(rolls.items.first?.unitPrice == 400)

        // Without "tanesi", the amount is for all of them.
        let rooms = RuleBasedParser.parse("Boya badana 3 oda 4.500 lira")
        #expect(rooms.items.first?.quantity == 3)
        #expect(rooms.items.first?.unitPrice == 1500)
    }

    @Test func `the spoken language settles short phrases`() {
        let draft = RuleBasedParser.parse("kapi 120 lira", spoken: .turkish)
        #expect(draft.textLanguage == .turkish)
        #expect(draft.items.first?.unitPrice == 120)
        #expect(RuleBasedParser.numbers(in: "2.500 ve 52,50", spoken: .turkish).contains(2500))
        #expect(RuleBasedParser.numbers(in: "2.500 ve 52,50", spoken: .turkish).contains(52.5))
    }

    @Test func `amounts in lira`() {
        #expect(Money.string(2500, locale: Locale(identifier: "tr_TR"), currency: "TRY") == "₺2.500,00")
        #expect(Money.symbol("TRY", locale: Locale(identifier: "tr_TR")) == "₺")
        #expect(WidgetSnapshot.money(1250, currency: "TRY", locale: Locale(identifier: "tr_TR")) == "₺1.250")
    }

    @Test func `model units are written in turkish`() {
        let generated = GeneratedEstimate(title: "İşçilik", clientName: "", items: [
            GeneratedItem(description: "İşçilik", quantity: 8, unit: "hr", unitPrice: 450, isLabor: true),
        ], notes: "")
        let draft = EstimateEngine.validated(generated, transcript: "8 saat işçilik saati 450", spoken: .turkish, priceBook: [],
                                             language: .turkish, fallback: RuleBasedParser.parse(""))
        #expect(draft.items.first?.unit == "saat")
        #expect(draft.items.first?.unitPrice == 450)
    }

    // MARK: What the client sees

    private func snapshot(kind: DocumentKind) -> DocumentSnapshot {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 12, day: 12))!
        return DocumentSnapshot(
            kind: kind, language: .turkish, displayNumber: kind == .estimate ? "E-1003" : "INV-1004", title: "Salon boyama",
            date: date, isPaid: false, businessName: "Yılmaz Boya", ownerName: "Ali Yılmaz", businessPhone: "",
            businessEmail: "", businessAddress: "", licenseNumber: "", logo: nil, clientName: "Ayşe Demir",
            clientPhone: "", clientEmail: "", clientAddress: "",
            items: [.init(text: "Salon boyama", quantity: 1, unit: "", unitPrice: 920, amount: 920)],
            totals: Totals(lines: [.init(amount: 920, isTaxable: false)], taxRate: 0), taxRate: 0, notes: "",
            terms: "", paymentInstructions: "IBAN TR00 0000", showsBranding: false,
            validUntil: kind == .estimate ? date : nil, dueDate: kind == .invoice ? date : nil,
            depositPercent: kind == .estimate ? 50 : 0, depositAmount: kind == .estimate ? 460 : 0
        )
    }

    @Test func `turkish client messages`() {
        let estimate = ClientMessage.text(for: snapshot(kind: .estimate))
        #expect(estimate.hasPrefix("Merhaba Ayşe, E-1003 numaralı teklif ektedir (Yılmaz Boya): "))
        #expect(estimate.contains("12 Aralık 2026 tarihine kadar geçerlidir."))
        #expect(estimate.contains("kapora alınır"))
        let invoice = ClientMessage.text(for: snapshot(kind: .invoice))
        #expect(invoice.contains("numaralı fatura ektedir"))
        #expect(invoice.contains("son ödeme tarihi 12 Aralık 2026."))
        #expect(invoice.contains("Ödeme: IBAN TR00 0000"))
    }

    @Test func `turkish PDF uses turkish words and capitals`() throws {
        let data = PDFRenderer().render(snapshot(kind: .estimate))
        let text = try #require(PDFDocument(data: data)?.string)
        #expect(text.contains("TEKLİF"))
        #expect(!text.contains("TEKLIF"))
        #expect(text.contains("AÇIKLAMA"))
        #expect(text.contains("Başlangıç kaporası"))
        #expect(text.contains("Bizi tercih ettiğiniz için teşekkür ederiz."))
    }

    @Test func `turkish report export`() {
        let row = ProfitReport.Row(id: UUID(), paidAt: .now, number: "INV-1", client: "Ayşe", job: "İş",
                                   revenue: 100, tax: 0, materialsCost: 20)
        let csv = ProfitReport(rows: [row], period: .month, containing: .now).csv(language: .turkish)
        #expect(csv.hasPrefix("Ödeme tarihi,Numara,Müşteri"))
    }
}
