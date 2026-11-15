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
