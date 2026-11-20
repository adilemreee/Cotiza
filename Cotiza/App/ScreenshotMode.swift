#if DEBUG
import CoreGraphics
import Foundation
import SwiftData

/// App Store screenshots: `-CotizaScreen <scene>` opens one screen with realistic sample data,
/// in the language the simulator runs in. Used by `Tools/screenshots.sh`. Debug builds only.
enum ScreenshotScene: String {
    case capture, editor, pdf, signature, home, report, paywall

    static var current: ScreenshotScene? {
        UserDefaults.standard.string(forKey: "CotizaScreen").flatMap(ScreenshotScene.init(rawValue:))
    }

    /// The estimate the editor, PDF and signature scenes open.
    static let heroID = UUID(uuidString: "C0717A00-0000-4000-8000-000000000001")!

    /// The store language the simulator runs in: English, Spanish or Turkish.
    private static var language: DocumentLanguage { .device }

    // MARK: Sample data

    /// A painting business with a month of work: estimates out, invoices paid, one overdue, one repeating.
    static func seed(in context: ModelContext) {
        guard current != nil, (try? context.fetchCount(FetchDescriptor<JobDocument>())) == 0,
              let profile = try? context.fetch(FetchDescriptor<BusinessProfile>()).first else { return }
        let language = language
        func t(_ english: String, _ spanish: String, _ turkish: String) -> String { language.text(english, spanish, turkish) }
        profile.documentLanguage = language
        profile.terms = t("50% deposit to start, balance on completion.", "50% de anticipo para empezar y el resto al terminar.",
                          "İşe başlarken %50 kapora, kalanı iş bitince.")
        profile.paymentInstructions = t("Zelle (713) 555-0142, check or cash.", "Zelle (713) 555-0142, cheque o efectivo.",
                                        "IBAN TR12 0006 4000 0011 2345 6789 01, nakit ya da kart.")
        let turkish = language == .turkish
        if turkish {
            // A painter in Istanbul, so the Turkish screens read naturally.
            profile.businessName = "Yılmaz Boya Dekorasyon"
            profile.ownerName = "Mehmet Yılmaz"
            profile.phone = "0532 555 01 42"
            profile.email = "mehmet@yilmazboya.example"
            profile.address = "Bağdat Cad. No: 210, Kadıköy, İstanbul"
            profile.licenseNumber = ""
            profile.defaultTaxRate = 20
        }

        let calendar = Calendar.current
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!.addingTimeInterval(10 * 3600) }
        func client(_ name: String, _ phone: String, _ address: String) -> Client {
            let client = Client(name: name, phone: phone, address: address)
            context.insert(client)
            return client
        }
        typealias Line = (text: String, quantity: Double, unit: String, price: Double, cost: Double, labor: Bool)
        /// Dollar prices, or lira prices a Turkish client would expect.
        func price(_ dollars: Double, _ lira: Double) -> Double { turkish ? lira : dollars }
        @discardableResult
        func document(_ kind: DocumentKind, _ title: String, _ who: Client, _ lines: [Line], status: DocumentStatus,
                      created: Int, paid: Int? = nil, due: Int? = nil, repeats: RepeatInterval = .never, id: UUID? = nil) -> JobDocument {
            let number = kind == .estimate ? profile.nextEstimateNumber : profile.nextInvoiceNumber
            if kind == .estimate { profile.nextEstimateNumber += 1 } else { profile.nextInvoiceNumber += 1 }
            let document = JobDocument(kind: kind, number: number, title: title, language: profile.documentLanguage, taxRate: profile.defaultTaxRate)
            if let id { document.uuid = id }
            document.createdAt = day(created)
            context.insert(document)
            document.client = who
            for (index, line) in lines.enumerated() {
                let item = LineItem(text: line.text, quantity: line.quantity, unit: line.unit, unitPrice: line.price,
                                    isLabor: line.labor, isTaxable: !line.labor, sortIndex: index)
                item.unitCost = line.cost
                context.insert(item)
                item.document = document
            }
            document.apply(status: status)
            if status == .sent || status == .approved || status == .paid { document.sentAt = day(created) }
            if let paid { document.paidAt = day(paid) }
            switch kind {
            case .estimate: document.validUntil = day(created + profile.estimateValidDays)
            case .invoice: document.dueDate = day(due ?? created + profile.paymentDueDays)
            }
            if repeats != .never { document.setRepeat(repeats) }
            return document
        }

        // Paid work earlier this month (for "Paid this month" and the report); dates stay inside the month.
        let monthDay = calendar.component(.day, from: .now)
        let early = { (offset: Int) in -min(monthDay - 1, offset) }

        let maria = turkish ? client("Ayşe Demir", "0533 555 01 98", "Moda Cad. No: 45, Kadıköy, İstanbul")
            : client("Maria Lopez", "(713) 555-0198", t("4512 Rose St, Houston, TX", "4512 Calle Rosa, Houston, TX", ""))
        let ana = turkish ? client("Elif Şahin", "0535 555 01 10", "Fenerbahçe Mah. Dalga Sok. 8, Kadıköy, İstanbul")
            : client("Ana Pérez", "(713) 555-0110", "88 Oak Bend Dr, Houston, TX")
        let john = turkish ? client("Ali Çelik", "0532 555 01 75", "Ataşehir Bulvarı 12, Ataşehir, İstanbul")
            : client("John Smith", "(832) 555-0175", "1200 Westheimer Rd, Houston, TX")
        let robert = turkish ? client("Can Öztürk", "0542 555 01 33", "Göztepe Mah. Tütüncü Mehmet Efendi Cad. 73, İstanbul")
            : client("Robert Chen", "(281) 555-0133", "73 Lakeview Ct, Sugar Land, TX")
        let linda = turkish ? client("Zeynep Kaya", "0536 555 01 61", "Caddebostan Mah. Plaj Yolu 9, İstanbul")
            : client("Linda García", "(713) 555-0161", "905 Elm St, Bellaire, TX")

        document(.invoice, t("Deep house cleaning", "Limpieza profunda de casa", "Detaylı ev temizliği"), linda, [
            (t("Deep cleaning, 3 bedrooms", "Limpieza profunda, 3 recámaras", "Detaylı temizlik, 3 oda"), 1, "", price(320, 4500), 0, true),
            (t("Cleaning supplies", "Productos de limpieza", "Temizlik malzemeleri"), 1, "", price(45.98, 850), price(39.98, 700), false),
        ], status: .paid, created: early(9), paid: early(8))
        document(.invoice, t("Exterior house painting", "Pintura exterior de la casa", "Dış cephe boyama"), robert, [
            (t("Paint house exterior", "Pintar exterior de la casa", "Dış cephe boyama"), turkish ? 170 : 1800, turkish ? "m²" : "sq ft", price(1.75, 280), 0, true),
            (t("Premium exterior paint", "Pintura exterior premium", "Premium dış cephe boyası"), 12, turkish ? "kutu" : "gal", price(57.49, 1450), price(49.99, 1250), false),
            (t("Sand and patch", "Lijar y resanar", "Zımpara ve alçı"), 6, turkish ? "saat" : "hr", price(45, 450), 0, true),
        ], status: .paid, created: early(7), paid: early(4))
        document(.invoice, t("Lawn care", "Mantenimiento de jardín", "Bahçe bakımı"), ana, [
            (t("Mow and edge", "Cortar y orillar el pasto", "Çim biçme ve kenar düzeltme"), 4, "", price(55, 600), 0, true),
            (t("Fertilizer", "Fertilizante", "Gübre"), 1, "", price(28.74, 380), price(24.99, 320), false),
        ], status: .paid, created: early(5), paid: early(3), repeats: .monthly)
        document(.invoice, t("Kitchen faucet replacement", "Cambio de llave de cocina", "Mutfak bataryası değişimi"), john, [
            (t("Install new faucet", "Instalar llave nueva", "Yeni batarya montajı"), 1, "", price(145, 900), 0, true),
            (t("Kitchen faucet", "Llave de cocina", "Mutfak bataryası"), 1, "", price(189.99, 2450), price(164.99, 2100), false),
        ], status: .sent, created: -4, due: -1)
        document(.estimate, t("Roof repair", "Reparación de techo", "Çatı tamiri"), robert, [
            (t("Replace damaged shingles", "Cambiar tejas dañadas", "Hasarlı kiremit değişimi"), turkish ? 11 : 120, turkish ? "m²" : "sq ft", price(6.5, 950), 0, true),
            (t("Seal chimney flashing", "Sellar chimenea", "Baca izolasyonu"), 1, "", price(275, 3500), 0, true),
        ], status: .approved, created: -3)
        document(.estimate, t("Fence staining", "Barnizar la cerca", "Bahçe çiti verniği"), linda, [
            (t("Stain wood fence", "Barnizar cerca de madera", "Ahşap çit vernikleme"), turkish ? 50 : 160, turkish ? "m" : "lin ft", price(4.25, 180), 0, true),
        ], status: .sent, created: -2)

        // The hero estimate: what the editor, PDF and signature scenes show.
        document(.estimate, t("Interior painting, 3 bedrooms", "Pintura interior, 3 recámaras", "İç boya, 3 oda"), maria, [
            (t("Paint bedrooms (walls and ceiling)", "Pintar recámaras (paredes y techo)", "Oda boyama (duvar ve tavan)"), 3, "", price(450, 4500), 0, true),
            (t("Patch and sand walls", "Resanar y lijar paredes", "Duvar alçı ve zımpara"), 4, turkish ? "saat" : "hr", price(45, 450), 0, true),
            (t("Premium interior paint", "Pintura interior premium", "Premium iç cephe boyası"), 6, turkish ? "kutu" : "gal", price(52.89, 1450), price(45.99, 1250), false),
            (t("Tape, plastic and rollers", "Cinta, plástico y rodillos", "Bant, naylon ve rulo"), 1, "", price(38.50, 650), price(33.48, 520), false),
        ], status: .sent, created: 0, id: heroID)
        try? context.save()
    }

    // MARK: Signature

    /// A cursive-looking signature that fills the pad, so the signature screenshot isn't empty.
    static func signature(in size: CGSize) -> [[CGPoint]] {
        guard size.width > 120, size.height > 80 else { return [] }
        let left = size.width * 0.14, right = size.width * 0.80
        let baseline = size.height * 0.60
        let tall = min(size.height * 0.34, 90)
        // Joined letters: a prolate cycloid makes a loop per letter; tall loops read as l, h, d, short ones as e, a.
        let heights: [Double] = [0.95, 0.42, 0.5, 0.92, 0.4, 0.48, 1.0, 0.45, 0.38, 0.85, 0.42]
        let loops = Double(heights.count)
        let a = (right - left) / (loops * 2 * .pi)
        var word: [CGPoint] = []
        let samples = 600
        for step in 0...samples {
            let t = Double(step) / Double(samples) * loops * 2 * .pi
            let index = min(Int(t / (2 * .pi)), heights.count - 1)
            // `+ sin` puts the loop at the top of each letter, as in joined handwriting; the shear slants it.
            let y = baseline - tall * heights[index] * (0.5 - 0.5 * cos(t)) + 3 * sin(t * 0.21)
            let x = left + a * t + a * 1.35 * sin(t) + (baseline - y) * 0.32
            word.append(CGPoint(x: x, y: y))
        }
        // The capital, written first, and a quick underline flourish.
        let capital = (0...50).map { step -> CGPoint in
            let t = Double(step) / 50
            return CGPoint(x: left - tall * 0.28 + tall * 0.34 * t + tall * 0.12 * sin(t * 2 * .pi),
                           y: baseline - tall * 1.15 * sin(t * .pi))
        }
        let flourish = (0...60).map { step -> CGPoint in
            let t = Double(step) / 60
            return CGPoint(x: left - tall * 0.1 + (right - left + tall * 0.5) * t,
                           y: baseline + tall * 0.28 - tall * 0.14 * sin(t * .pi) + tall * 0.06 * t)
        }
        return [capital, word, flourish]
    }
}
#endif
