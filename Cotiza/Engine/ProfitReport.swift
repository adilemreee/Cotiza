import Foundation
import UIKit

/// Money in and materials out for a month or a year, for the contractor and their accountant.
///
/// Income is counted on the day it comes in (cash basis, as most sole proprietors file): each deposit or
/// partial payment on its own date, and the rest when the document is marked paid.
/// Materials cost comes from the cost recorded on each line: receipts fill it in, and it can be typed.
nonisolated struct ProfitReport: Equatable, Sendable {
    enum Period: String, CaseIterable, Identifiable, Sendable {
        case month, year
        var id: String { rawValue }
    }

    struct Row: Equatable, Sendable, Identifiable {
        var id: UUID
        var paidAt: Date
        var number: String
        var client: String
        var job: String
        /// Before sales tax: what the IRS calls gross receipts when you remit the tax yourself.
        var revenue: Double
        var tax: Double
        var materialsCost: Double

        var total: Double { Money.round(revenue + tax) }
        var profit: Double { Money.round(revenue - materialsCost) }
    }

    let interval: DateInterval
    let rows: [Row]

    var revenue: Double { Money.round(rows.reduce(0) { $0 + $1.revenue }) }
    var tax: Double { Money.round(rows.reduce(0) { $0 + $1.tax }) }
    var total: Double { Money.round(rows.reduce(0) { $0 + $1.total }) }
    var materialsCost: Double { Money.round(rows.reduce(0) { $0 + $1.materialsCost }) }
    var profit: Double { Money.round(revenue - materialsCost) }
    /// Jobs with money in this period; a job paid in parts is one job.
    var jobCount: Int { Set(rows.map(\.number)).count }

    init(rows all: [Row], period: Period, containing date: Date, calendar: Calendar = .current) {
        let component: Calendar.Component = period == .month ? .month : .year
        let interval = calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 0)
        self.interval = interval
        rows = all
            .filter { interval.start <= $0.paidAt && $0.paidAt < interval.end }
            .sorted { $0.paidAt < $1.paidAt }
    }

    // MARK: Export

    /// One line per paid job, plain numbers so any spreadsheet reads them.
    func csv(language: DocumentLanguage) -> String {
        let s = ReportStrings(language: language)
        let date = Date.ISO8601FormatStyle().year().month().day()
        func field(_ text: String) -> String {
            text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                : text
        }
        func number(_ value: Double) -> String { String(format: "%.2f", value) }
        var lines = [[s.datePaid, s.number, s.client, s.job, s.revenue, s.tax, s.total, s.materials, s.profit].joined(separator: ",")]
        for row in rows {
            lines.append([
                row.paidAt.formatted(date), field(row.number), field(row.client), field(row.job),
                number(row.revenue), number(row.tax), number(row.total), number(row.materialsCost), number(row.profit),
            ].joined(separator: ","))
        }
        lines.append([s.totals, "", "", "", number(revenue), number(tax), number(total), number(materialsCost), number(profit)]
            .joined(separator: ","))
        return lines.joined(separator: "\n") + "\n"
    }

    func periodTitle(_ period: Period, locale: Locale) -> String {
        switch period {
        case .month: interval.start.formatted(.dateTime.month(.wide).year().locale(locale))
        case .year: interval.start.formatted(.dateTime.year().locale(locale))
        }
    }

    @MainActor
    func writeFiles(period: Period, business: String, language: DocumentLanguage) throws -> (csv: URL, pdf: URL) {
        let s = ReportStrings(language: language)
        let title = periodTitle(period, locale: language.locale)
        let name = "\(s.fileName) \(title)".replacingOccurrences(of: "/", with: "-")
        let directory = FileManager.default.temporaryDirectory.appending(path: "Report-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let csvURL = directory.appending(path: name + ".csv")
        // A byte-order mark so Excel opens accents (López, Pérez) correctly.
        try Data(("\u{FEFF}" + csv(language: language)).utf8).write(to: csvURL, options: .atomic)
        let pdfURL = directory.appending(path: name + ".pdf")
        try ReportPDF(report: self, title: title, business: business, strings: s).render().write(to: pdfURL, options: .atomic)
        return (csvURL, pdfURL)
    }
}

extension ProfitReport.Row {
    /// One row for each time money came in on a document: each deposit or partial payment, and what was
    /// left when it was marked paid. Revenue, tax and materials are split in proportion to each amount,
    /// so a job paid in two halves adds up to the same totals as one paid at once.
    @MainActor
    static func rows(for document: JobDocument) -> [Self] {
        let totals = document.totals
        guard totals.total > 0 else { return [] }
        let costed = document.allItems.filter { $0.unitCost > 0 }
        let materials = Money.round(costed.reduce(0) { $0 + $1.cost })
        // Each row is the difference between running shares, so the cents always add up to the whole.
        var paidSoFar = 0.0
        return document.income.map { event in
            let before = min(paidSoFar / totals.total, 1)
            paidSoFar += event.amount
            let after = min(paidSoFar / totals.total, 1)
            func part(_ whole: Double) -> Double { Money.round(Money.round(whole * after) - Money.round(whole * before)) }
            return Self(
                id: event.id,
                paidAt: event.date,
                number: document.displayNumber,
                client: document.client?.name ?? "",
                job: document.title,
                revenue: part(totals.subtotal),
                tax: part(totals.tax),
                materialsCost: part(materials)
            )
        }
    }
}

/// Words in the exported report, in the business's document language.
nonisolated struct ReportStrings: Sendable {
    let language: DocumentLanguage
    private var es: Bool { language == .spanish }

    var fileName: String { es ? "Reporte Cotiza" : "Cotiza report" }
    var heading: String { es ? "Reporte de ingresos y gastos" : "Income and expense report" }
    var datePaid: String { es ? "Fecha de pago" : "Date paid" }
    var number: String { es ? "Número" : "Number" }
    var client: String { es ? "Cliente" : "Client" }
    var job: String { es ? "Trabajo" : "Job" }
    var revenue: String { es ? "Ingresos (sin impuesto)" : "Revenue (before tax)" }
    var tax: String { es ? "Impuesto cobrado" : "Sales tax collected" }
    var total: String { es ? "Total cobrado" : "Total collected" }
    var materials: String { es ? "Costo de materiales" : "Materials cost" }
    var profit: String { es ? "Ganancia" : "Profit" }
    var totals: String { es ? "Totales" : "Totals" }
    var jobsPaid: String { es ? "Trabajos pagados" : "Jobs paid" }
    var noJobs: String { es ? "No hay trabajos pagados en este periodo." : "No jobs were paid in this period." }
    var note: String {
        es ? "Ingresos contados en la fecha de pago, incluidos anticipos y pagos parciales. El costo de materiales incluye solo los conceptos con costo registrado (de recibos escaneados o escrito a mano). No es asesoría fiscal; revísalo con tu contador."
           : "Income is counted on the date it was paid, including deposits and partial payments. Materials cost includes only items with a recorded cost (from scanned receipts or typed in). Not tax advice; review it with your accountant."
    }
}

/// A one-or-more page summary for the accountant.
private struct ReportPDF {
    let report: ProfitReport
    let title: String
    let business: String
    let strings: ReportStrings

    private let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private let margin: CGFloat = 48
    private let ink = UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1)
    private let secondary = UIColor(red: 0.42, green: 0.44, blue: 0.48, alpha: 1)
    private let accent = UIColor(red: 0.84, green: 0.33, blue: 0.08, alpha: 1)

    func render() -> Data {
        let locale = strings.language.locale
        func money(_ value: Double) -> String { Money.string(value, locale: locale) }
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            var y = margin
            y += draw(strings.heading, PDFFont.make(20, .bold), ink, x: margin, y: y, width: 516) + 4
            y += draw([business, title].filter { !$0.isEmpty }.joined(separator: " · "), PDFFont.make(11), secondary,
                      x: margin, y: y, width: 516) + 20

            let summary: [(String, Double)] = [
                (strings.revenue, report.revenue), (strings.tax, report.tax), (strings.total, report.total),
                (strings.materials, report.materialsCost), (strings.profit, report.profit),
            ]
            for (label, value) in summary {
                let bold = label == strings.profit
                draw(label, PDFFont.make(11, bold ? .bold : .regular), bold ? accent : ink, x: margin, y: y, width: 300)
                draw(money(value), PDFFont.make(11, bold ? .bold : .regular), bold ? accent : ink, x: margin + 300, y: y, width: 216, align: .right)
                y += 20
            }
            y += draw("\(strings.jobsPaid): \(report.jobCount)", PDFFont.make(10), secondary, x: margin, y: y, width: 516) + 18

            // Table
            let columns: [(String, CGFloat, NSTextAlignment)] = [
                (strings.datePaid, 70, .left), (strings.number, 62, .left), (strings.client, 140, .left),
                (strings.revenue, 82, .right), (strings.materials, 80, .right), (strings.profit, 82, .right),
            ]
            @MainActor func header() {
                var x = margin
                for (label, width, align) in columns {
                    draw(label.uppercased(), PDFFont.make(7.5, .semibold), secondary, x: x, y: y, width: width - 4, align: align)
                    x += width
                }
                y += 22
            }
            header()
            if report.rows.isEmpty {
                y += draw(strings.noJobs, PDFFont.make(10), secondary, x: margin, y: y, width: 516) + 10
            }
            for row in report.rows {
                if y > page.height - 90 {
                    context.beginPage()
                    y = margin
                    header()
                }
                let values = [
                    row.paidAt.formatted(.dateTime.month(.abbreviated).day().locale(locale)), row.number,
                    row.client.isEmpty ? row.job : row.client,
                    money(row.revenue), money(row.materialsCost), money(row.profit),
                ]
                var x = margin
                for (value, column) in zip(values, columns) {
                    draw(value, PDFFont.make(9.5), ink, x: x, y: y, width: column.1 - 4, align: column.2)
                    x += column.1
                }
                y += 18
            }
            y += 16
            if y > page.height - 90 {
                context.beginPage()
                y = margin
            }
            draw(strings.note, PDFFont.make(8.5), secondary, x: margin, y: y, width: 516)
        }
    }

    @discardableResult
    private func draw(_ text: String, _ font: UIFont, _ color: UIColor, x: CGFloat, y: CGFloat, width: CGFloat, align: NSTextAlignment = .left) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        let height = ceil(attributed.boundingRect(with: CGSize(width: width, height: 400), options: [.usesLineFragmentOrigin], context: nil).height)
        attributed.draw(with: CGRect(x: x, y: y, width: width, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return height
    }
}
