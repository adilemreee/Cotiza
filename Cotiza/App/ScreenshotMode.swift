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

    private static var spanish: Bool { Locale.current.language.languageCode == .spanish }

    // MARK: Sample data

    /// A painting business with a month of work: estimates out, invoices paid, one overdue, one repeating.
    static func seed(in context: ModelContext) {
        guard current != nil, (try? context.fetchCount(FetchDescriptor<JobDocument>())) == 0,
              let profile = try? context.fetch(FetchDescriptor<BusinessProfile>()).first else { return }
        let es = spanish
        profile.documentLanguage = es ? .spanish : .english
        profile.terms = es ? "50% de anticipo para empezar y el resto al terminar." : "50% deposit to start, balance on completion."
        profile.paymentInstructions = es ? "Zelle (713) 555-0142, cheque o efectivo." : "Zelle (713) 555-0142, check or cash."

        let calendar = Calendar.current
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!.addingTimeInterval(10 * 3600) }
        func client(_ name: String, _ phone: String, _ address: String) -> Client {
            let client = Client(name: name, phone: phone, address: address)
            context.insert(client)
            return client
        }
        typealias Line = (text: String, quantity: Double, unit: String, price: Double, cost: Double, labor: Bool)
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

        let maria = client("Maria Lopez", "(713) 555-0198", es ? "4512 Calle Rosa, Houston, TX" : "4512 Rose St, Houston, TX")
        let ana = client("Ana Pérez", "(713) 555-0110", "88 Oak Bend Dr, Houston, TX")
        let john = client("John Smith", "(832) 555-0175", "1200 Westheimer Rd, Houston, TX")
        let robert = client("Robert Chen", "(281) 555-0133", "73 Lakeview Ct, Sugar Land, TX")
        let linda = client("Linda García", "(713) 555-0161", "905 Elm St, Bellaire, TX")

        document(.invoice, es ? "Limpieza profunda de casa" : "Deep house cleaning", linda, [
            (es ? "Limpieza profunda, 3 recámaras" : "Deep cleaning, 3 bedrooms", 1, "", 320, 0, true),
            (es ? "Productos de limpieza" : "Cleaning supplies", 1, "", 45.98, 39.98, false),
        ], status: .paid, created: early(9), paid: early(8))
        document(.invoice, es ? "Pintura exterior de la casa" : "Exterior house painting", robert, [
            (es ? "Pintar exterior de la casa" : "Paint house exterior", 1800, "sq ft", 1.75, 0, true),
            (es ? "Pintura exterior premium" : "Premium exterior paint", 12, "gal", 57.49, 49.99, false),
            (es ? "Lijar y resanar" : "Sand and patch", 6, "hr", 45, 0, true),
        ], status: .paid, created: early(7), paid: early(4))
        document(.invoice, es ? "Mantenimiento de jardín" : "Lawn care", ana, [
            (es ? "Cortar y orillar el pasto" : "Mow and edge", 4, "", 55, 0, true),
            (es ? "Fertilizante" : "Fertilizer", 1, "", 28.74, 24.99, false),
        ], status: .paid, created: early(5), paid: early(3), repeats: .monthly)
        document(.invoice, es ? "Cambio de llave de cocina" : "Kitchen faucet replacement", john, [
            (es ? "Instalar llave nueva" : "Install new faucet", 1, "", 145, 0, true),
            (es ? "Llave de cocina" : "Kitchen faucet", 1, "", 189.99, 164.99, false),
        ], status: .sent, created: -4, due: -1)
        document(.estimate, es ? "Reparación de techo" : "Roof repair", robert, [
            (es ? "Cambiar tejas dañadas" : "Replace damaged shingles", 120, "sq ft", 6.5, 0, true),
            (es ? "Sellar chimenea" : "Seal chimney flashing", 1, "", 275, 0, true),
        ], status: .approved, created: -3)
        document(.estimate, es ? "Barnizar la cerca" : "Fence staining", linda, [
            (es ? "Barnizar cerca de madera" : "Stain wood fence", 160, "lin ft", 4.25, 0, true),
        ], status: .sent, created: -2)

        // The hero estimate: what the editor, PDF and signature scenes show.
        document(.estimate, es ? "Pintura interior, 3 recámaras" : "Interior painting, 3 bedrooms", maria, [
            (es ? "Pintar recámaras (paredes y techo)" : "Paint bedrooms (walls and ceiling)", 3, "", 450, 0, true),
            (es ? "Resanar y lijar paredes" : "Patch and sand walls", 4, "hr", 45, 0, true),
            (es ? "Pintura interior premium" : "Premium interior paint", 6, "gal", 52.89, 45.99, false),
            (es ? "Cinta, plástico y rodillos" : "Tape, plastic and rollers", 1, "", 38.50, 33.48, false),
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
