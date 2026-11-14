import UIKit

/// Plain-value copy of everything a PDF needs, so rendering never touches the database.
nonisolated struct DocumentSnapshot: Sendable, Equatable {
    struct Item: Sendable, Equatable {
        var text: String
        var quantity: Double
        var unit: String
        var unitPrice: Double
        var amount: Double
    }

    var kind: DocumentKind
    var language: DocumentLanguage
    var displayNumber: String
    var title: String
    var date: Date
    var isPaid: Bool

    var businessName: String
    var ownerName: String
    var businessPhone: String
    var businessEmail: String
    var businessAddress: String
    var licenseNumber: String
    var logo: Data?

    var clientName: String
    var clientPhone: String
    var clientEmail: String
    var clientAddress: String

    var items: [Item]
    var totals: Totals
    var taxRate: Double
    var notes: String
    var terms: String
    var paymentInstructions: String
    var showsBranding: Bool
    var validUntil: Date? = nil
    var dueDate: Date? = nil
    var signature: Data? = nil
    var signerName: String = ""
    var signedAt: Date? = nil

    var fileName: String {
        let safeNumber = displayNumber.replacingOccurrences(of: "/", with: "-")
        let word = PDFStrings(language: language).documentWord(kind)
        return "\(word)-\(safeNumber).pdf"
    }
}

extension DocumentSnapshot {
    nonisolated func formatted(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(language.locale))
    }

    init(document: JobDocument, profile: BusinessProfile?, showsBranding: Bool) {
        self.init(
            kind: document.kind,
            language: document.language,
            displayNumber: document.displayNumber,
            title: document.title,
            date: document.createdAt,
            isPaid: document.status == .paid,
            businessName: profile?.businessName ?? "",
            ownerName: profile?.ownerName ?? "",
            businessPhone: profile?.phone ?? "",
            businessEmail: profile?.email ?? "",
            businessAddress: profile?.address ?? "",
            licenseNumber: profile?.licenseNumber ?? "",
            logo: profile?.logoData,
            clientName: document.client?.name ?? "",
            clientPhone: document.client?.phone ?? "",
            clientEmail: document.client?.email ?? "",
            clientAddress: document.client?.address ?? "",
            items: document.sortedItems.map {
                Item(text: $0.text, quantity: $0.quantity, unit: $0.unit, unitPrice: $0.unitPrice, amount: $0.amount)
            },
            totals: document.totals,
            taxRate: document.taxRate,
            notes: document.notes,
            terms: profile?.terms ?? "",
            paymentInstructions: profile?.paymentInstructions ?? "",
            showsBranding: showsBranding,
            validUntil: document.validUntil,
            dueDate: document.dueDate,
            signature: document.signatureData,
            signerName: document.signerName,
            signedAt: document.signedAt
        )
    }
}

/// The words printed on the PDF. They follow the document's language, not the phone's.
nonisolated struct PDFStrings: Sendable {
    let language: DocumentLanguage
    private var es: Bool { language == .spanish }

    func documentWord(_ kind: DocumentKind) -> String {
        switch kind {
        case .estimate: es ? "Cotización" : "Estimate"
        case .invoice: es ? "Factura" : "Invoice"
        }
    }
    var date: String { es ? "Fecha" : "Date" }
    var preparedFor: String { es ? "Preparado para" : "Prepared for" }
    var billTo: String { es ? "Facturar a" : "Bill to" }
    var project: String { es ? "Trabajo" : "Project" }
    var description: String { es ? "Descripción" : "Description" }
    var quantity: String { es ? "Cant." : "Qty" }
    var unitPrice: String { es ? "Precio" : "Rate" }
    var amount: String { es ? "Importe" : "Amount" }
    var subtotal: String { "Subtotal" }
    var tax: String { es ? "Impuesto" : "Tax" }
    var total: String { "Total" }
    var amountDue: String { es ? "Total a pagar" : "Amount due" }
    var paid: String { es ? "PAGADO" : "PAID" }
    var notes: String { es ? "Notas" : "Notes" }
    var terms: String { es ? "Términos" : "Terms" }
    var payment: String { es ? "Formas de pago" : "Payment" }
    var license: String { es ? "Licencia" : "License" }
    var validity: String { es ? "Esta cotización es válida por 30 días." : "This estimate is valid for 30 days." }
    func validity(until date: String) -> String { es ? "Esta cotización es válida hasta el \(date)." : "This estimate is valid until \(date)." }
    var validUntil: String { es ? "Válida hasta" : "Valid until" }
    var due: String { es ? "Vence" : "Due" }
    var signedOn: String { es ? "Firmada el" : "Signed on" }
    var clientSignature: String { es ? "Firma del cliente" : "Client signature" }
    var thanks: String { es ? "Gracias por su preferencia." : "Thank you for your business." }
    var branding: String { es ? "Creado con Cotiza" : "Made with Cotiza" }
    func page(_ number: Int) -> String { es ? "Página \(number)" : "Page \(number)" }
}

/// Helvetica Neue embeds cleanly in PDFs, so client-side search and copy work, and its digits are tabular.
enum PDFFont {
    static func make(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        let name = switch weight {
        case .heavy, .black, .bold: "HelveticaNeue-Bold"
        case .semibold, .medium: "HelveticaNeue-Medium"
        default: "HelveticaNeue"
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

struct PDFRenderer {
    private let page = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
    private let margin: CGFloat = 48
    private let accent = UIColor(red: 0.84, green: 0.33, blue: 0.08, alpha: 1)
    private let ink = UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1)
    private let secondary = UIColor(red: 0.42, green: 0.44, blue: 0.48, alpha: 1)
    private let hairline = UIColor(red: 0.86, green: 0.87, blue: 0.89, alpha: 1)
    private let band = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)

    func render(_ snapshot: DocumentSnapshot) -> Data {
        let strings = PDFStrings(language: snapshot.language)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(strings.documentWord(snapshot.kind)) \(snapshot.displayNumber)",
            kCGPDFContextAuthor as String: snapshot.businessName,
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        return renderer.pdfData { context in
            var layout = Layout(context: context, renderer: self, strings: strings, showsBranding: snapshot.showsBranding)
            layout.beginPage()
            drawHeader(snapshot, strings: strings, layout: &layout)
            drawParties(snapshot, strings: strings, layout: &layout)
            drawTable(snapshot, strings: strings, layout: &layout)
            drawTotals(snapshot, strings: strings, layout: &layout)
            drawClosing(snapshot, strings: strings, layout: &layout)
        }
    }

    /// Writes the PDF to a temporary file so it can be previewed and shared with a real file name.
    func writeFile(_ snapshot: DocumentSnapshot) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Documents-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: snapshot.fileName)
        try render(snapshot).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Layout cursor

    private struct Layout {
        let context: UIGraphicsPDFRendererContext
        let renderer: PDFRenderer
        let strings: PDFStrings
        let showsBranding: Bool
        var y: CGFloat = 0
        var pageNumber = 0

        var left: CGFloat { renderer.margin }
        var right: CGFloat { renderer.page.width - renderer.margin }
        var width: CGFloat { right - left }
        var bottom: CGFloat { renderer.page.height - 64 }

        mutating func beginPage() {
            context.beginPage()
            pageNumber += 1
            y = renderer.margin
            drawFooter()
        }

        mutating func ensure(_ height: CGFloat) {
            if y + height > bottom { beginPage() }
        }

        private func drawFooter() {
            let footerY = renderer.page.height - 40
            let font = PDFFont.make(8)
            renderer.draw(strings.page(pageNumber), font: font, color: renderer.secondary,
                          in: CGRect(x: left, y: footerY, width: width, height: 12), alignment: .right)
            if showsBranding {
                renderer.draw(strings.branding, font: font, color: renderer.secondary,
                              in: CGRect(x: left, y: footerY, width: width, height: 12), alignment: .left)
            }
        }
    }

    // MARK: - Sections

    private func drawHeader(_ s: DocumentSnapshot, strings: PDFStrings, layout: inout Layout) {
        let top = layout.y
        let rightColumn: CGFloat = 200
        let leftWidth = layout.width - rightColumn - 16
        var leftY = top

        if let data = s.logo, let logo = UIImage(data: data), logo.size.width > 0, logo.size.height > 0 {
            let maxSize = CGSize(width: 150, height: 60)
            let scale = min(maxSize.width / logo.size.width, maxSize.height / logo.size.height, 1)
            let size = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
            logo.draw(in: CGRect(origin: CGPoint(x: layout.left, y: leftY), size: size))
            leftY += size.height + 10
        }

        let name = s.businessName.isEmpty ? s.ownerName : s.businessName
        if !name.isEmpty {
            leftY += draw(name, font: PDFFont.make(20, .bold), color: ink,
                          in: CGRect(x: layout.left, y: leftY, width: leftWidth, height: 80)) + 4
        }
        var details: [String] = []
        if !s.businessName.isEmpty, !s.ownerName.isEmpty { details.append(s.ownerName) }
        if !s.businessAddress.isEmpty { details.append(s.businessAddress) }
        let contact = [s.businessPhone, s.businessEmail].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        if !contact.isEmpty { details.append(contact) }
        if !s.licenseNumber.isEmpty { details.append("\(strings.license) \(s.licenseNumber)") }
        if !details.isEmpty {
            leftY += draw(details.joined(separator: "\n"), font: PDFFont.make(9.5), color: secondary,
                          in: CGRect(x: layout.left, y: leftY, width: leftWidth, height: 120), lineSpacing: 2.5)
        }

        let rightX = layout.right - rightColumn
        var rightY = top
        rightY += draw(strings.documentWord(s.kind).uppercased(), font: PDFFont.make(24, .heavy), color: accent,
                       in: CGRect(x: rightX, y: rightY, width: rightColumn, height: 40), alignment: .right, kern: 1.2) + 6
        rightY += draw(s.displayNumber, font: PDFFont.make(11, .semibold), color: ink,
                       in: CGRect(x: rightX, y: rightY, width: rightColumn, height: 16), alignment: .right) + 3
        let dateText = s.formatted(s.date)
        rightY += draw("\(strings.date): \(dateText)", font: PDFFont.make(9.5), color: secondary,
                       in: CGRect(x: rightX, y: rightY, width: rightColumn, height: 16), alignment: .right)
        let deadline: String? = switch s.kind {
        case .estimate: s.validUntil.map { "\(strings.validUntil): \(s.formatted($0))" }
        case .invoice: s.isPaid ? nil : s.dueDate.map { "\(strings.due): \(s.formatted($0))" }
        }
        if let deadline {
            rightY += 2
            rightY += draw(deadline, font: PDFFont.make(9.5, .semibold), color: ink,
                           in: CGRect(x: rightX, y: rightY, width: rightColumn, height: 16), alignment: .right)
        }
        if s.isPaid {
            rightY += 8
            let stamp = CGRect(x: layout.right - 76, y: rightY, width: 76, height: 22)
            let path = UIBezierPath(roundedRect: stamp, cornerRadius: 4)
            UIColor(red: 0.10, green: 0.55, blue: 0.30, alpha: 1).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            draw(strings.paid, font: PDFFont.make(11, .heavy), color: UIColor(red: 0.10, green: 0.55, blue: 0.30, alpha: 1),
                 in: stamp.insetBy(dx: 0, dy: 4), alignment: .center, kern: 1.5)
            rightY += 22
        }

        layout.y = max(leftY, rightY) + 18
        rule(at: layout.y, layout: layout, color: ink, width: 1.2)
        layout.y += 18
    }

    private func drawParties(_ s: DocumentSnapshot, strings: PDFStrings, layout: inout Layout) {
        let columnWidth = (layout.width - 24) / 2
        let top = layout.y
        var leftY = top
        var rightY = top
        let labelFont = PDFFont.make(8, .semibold)

        let hasClient = !s.clientName.isEmpty
        if hasClient {
            let label = s.kind == .invoice ? strings.billTo : strings.preparedFor
            leftY += draw(label.uppercased(), font: labelFont, color: secondary,
                          in: CGRect(x: layout.left, y: leftY, width: columnWidth, height: 12), kern: 0.8) + 5
            leftY += draw(s.clientName, font: PDFFont.make(12, .semibold), color: ink,
                          in: CGRect(x: layout.left, y: leftY, width: columnWidth, height: 40)) + 3
            let details = [s.clientAddress, s.clientPhone, s.clientEmail].filter { !$0.isEmpty }.joined(separator: "\n")
            if !details.isEmpty {
                leftY += draw(details, font: PDFFont.make(9.5), color: secondary,
                              in: CGRect(x: layout.left, y: leftY, width: columnWidth, height: 80), lineSpacing: 2.5)
            }
        }
        if !s.title.isEmpty {
            let x = hasClient ? layout.left + columnWidth + 24 : layout.left
            let width = hasClient ? columnWidth : layout.width
            rightY += draw(strings.project.uppercased(), font: labelFont, color: secondary,
                           in: CGRect(x: x, y: rightY, width: width, height: 12), kern: 0.8) + 5
            rightY += draw(s.title, font: PDFFont.make(12, .semibold), color: ink,
                           in: CGRect(x: x, y: rightY, width: width, height: 60))
        }
        if hasClient || !s.title.isEmpty {
            layout.y = max(leftY, rightY) + 22
        }
    }

    private struct Columns {
        let description: CGRect
        let quantity: CGRect
        let rate: CGRect
        let amount: CGRect

        init(left: CGFloat, width: CGFloat) {
            let amountWidth: CGFloat = 84
            let rateWidth: CGFloat = 78
            let quantityWidth: CGFloat = 72
            let descriptionWidth = width - amountWidth - rateWidth - quantityWidth - 20
            description = CGRect(x: left + 10, y: 0, width: descriptionWidth - 10, height: 0)
            quantity = CGRect(x: left + 10 + descriptionWidth, y: 0, width: quantityWidth, height: 0)
            rate = CGRect(x: quantity.maxX, y: 0, width: rateWidth, height: 0)
            amount = CGRect(x: rate.maxX, y: 0, width: amountWidth, height: 0)
        }
    }

    private func drawTableHeader(strings: PDFStrings, columns: Columns, layout: inout Layout) {
        let height: CGFloat = 24
        band.setFill()
        UIBezierPath(roundedRect: CGRect(x: layout.left, y: layout.y, width: layout.width, height: height), cornerRadius: 4).fill()
        let font = PDFFont.make(8, .semibold)
        let textY = layout.y + 8
        draw(strings.description.uppercased(), font: font, color: secondary, in: columns.description.at(y: textY, height: 12), kern: 0.8)
        draw(strings.quantity.uppercased(), font: font, color: secondary, in: columns.quantity.at(y: textY, height: 12), alignment: .right, kern: 0.8)
        draw(strings.unitPrice.uppercased(), font: font, color: secondary, in: columns.rate.at(y: textY, height: 12), alignment: .right, kern: 0.8)
        draw(strings.amount.uppercased(), font: font, color: secondary, in: columns.amount.at(y: textY, height: 12), alignment: .right, kern: 0.8)
        layout.y += height + 4
    }

    private func drawTable(_ s: DocumentSnapshot, strings: PDFStrings, layout: inout Layout) {
        let columns = Columns(left: layout.left, width: layout.width)
        layout.ensure(80)
        drawTableHeader(strings: strings, columns: columns, layout: &layout)

        let textFont = PDFFont.make(10.5)
        let numberFont = PDFFont.make(10.5, .regular)
        let locale = s.language.locale

        for item in s.items {
            // Capped at one page so a pasted wall of text is truncated instead of running off the sheet.
            let maxTextHeight = page.height - 64 - margin - 60
            let textHeight = min(measure(item.text, font: textFont, width: columns.description.width, lineSpacing: 2), maxTextHeight)
            let rowHeight = max(textHeight, 14) + 16
            if layout.y + rowHeight > layout.bottom {
                layout.beginPage()
                drawTableHeader(strings: strings, columns: columns, layout: &layout)
            }
            let textY = layout.y + 8
            draw(item.text, font: textFont, color: ink, in: columns.description.at(y: textY, height: textHeight + 2), lineSpacing: 2)
            let quantity = Money.quantity(item.quantity, locale: locale) + (item.unit.isEmpty ? "" : " \(item.unit)")
            draw(quantity, font: numberFont, color: ink, in: columns.quantity.at(y: textY, height: 14), alignment: .right)
            draw(Money.string(item.unitPrice, locale: locale), font: numberFont, color: ink, in: columns.rate.at(y: textY, height: 14), alignment: .right)
            draw(Money.string(item.amount, locale: locale), font: numberFont, color: ink, in: columns.amount.at(y: textY, height: 14), alignment: .right)
            layout.y += rowHeight
            rule(at: layout.y, layout: layout, color: hairline, width: 0.5)
        }
        layout.y += 14
    }

    private func drawTotals(_ s: DocumentSnapshot, strings: PDFStrings, layout: inout Layout) {
        let boxWidth: CGFloat = 230
        let x = layout.right - boxWidth
        let locale = s.language.locale
        let showsTax = s.totals.tax > 0
        layout.ensure(showsTax ? 96 : 60)

        let labelFont = PDFFont.make(10.5)
        let numberFont = PDFFont.make(10.5, .regular)
        func row(_ label: String, _ value: String) {
            draw(label, font: labelFont, color: secondary, in: CGRect(x: x + 10, y: layout.y, width: 110, height: 14))
            draw(value, font: numberFont, color: ink, in: CGRect(x: x + 110, y: layout.y, width: boxWidth - 120, height: 14), alignment: .right)
            layout.y += 20
        }

        if showsTax {
            row(strings.subtotal, Money.string(s.totals.subtotal, locale: locale))
            let rate = Money.quantity(s.taxRate, locale: locale)
            row("\(strings.tax) (\(rate)%)", Money.string(s.totals.tax, locale: locale))
            layout.y += 2
        }

        let totalRect = CGRect(x: x, y: layout.y, width: boxWidth, height: 36)
        accent.setFill()
        UIBezierPath(roundedRect: totalRect, cornerRadius: 6).fill()
        let totalLabel = s.kind == .invoice && !s.isPaid ? strings.amountDue : strings.total
        draw(totalLabel.uppercased(), font: PDFFont.make(9.5, .bold), color: .white,
             in: CGRect(x: x + 12, y: layout.y + 12, width: 110, height: 14), kern: 0.8)
        draw(Money.string(s.totals.total, locale: locale), font: PDFFont.make(15, .bold), color: .white,
             in: CGRect(x: x + 100, y: layout.y + 9, width: boxWidth - 112, height: 20), alignment: .right)
        layout.y += 36 + 26
    }

    private func drawClosing(_ s: DocumentSnapshot, strings: PDFStrings, layout: inout Layout) {
        let bodyFont = PDFFont.make(9.5)
        let labelFont = PDFFont.make(8, .semibold)

        func block(_ label: String, _ body: String) {
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let height = measure(body, font: bodyFont, width: layout.width, lineSpacing: 2.5)
            layout.ensure(min(height, 200) + 30)
            layout.y += draw(label.uppercased(), font: labelFont, color: secondary,
                             in: CGRect(x: layout.left, y: layout.y, width: layout.width, height: 12), kern: 0.8) + 5
            layout.y += draw(body, font: bodyFont, color: ink,
                             in: CGRect(x: layout.left, y: layout.y, width: layout.width, height: max(layout.bottom - layout.y, 20)), lineSpacing: 2.5) + 16
        }

        block(strings.notes, s.notes)
        if s.kind == .invoice { block(strings.payment, s.paymentInstructions) }
        let validity = s.validUntil.map { strings.validity(until: s.formatted($0)) } ?? strings.validity
        let terms = s.kind == .estimate
            ? [s.terms, validity].filter { !$0.isEmpty }.joined(separator: "\n")
            : s.terms
        block(strings.terms, terms)

        let signature = s.signature.flatMap(UIImage.init(data:))
        if s.kind == .estimate || signature != nil {
            let signatureHeight: CGFloat = signature == nil ? 0 : 54
            layout.ensure(70 + signatureHeight)
            layout.y += 30 + signatureHeight
            let lineWidth: CGFloat = 220
            if let signature, signature.size.width > 0, signature.size.height > 0 {
                let scale = min(lineWidth / signature.size.width, 50 / signature.size.height)
                let size = CGSize(width: signature.size.width * scale, height: signature.size.height * scale)
                signature.draw(in: CGRect(x: layout.left + 4, y: layout.y - size.height - 3, width: size.width, height: size.height))
                if let signedAt = s.signedAt {
                    draw(s.formatted(signedAt), font: PDFFont.make(10.5), color: ink,
                         in: CGRect(x: layout.left + lineWidth + 34, y: layout.y - 17, width: 116, height: 14))
                }
            }
            let signatureLabel = s.signerName.isEmpty ? strings.clientSignature : "\(strings.clientSignature): \(s.signerName)"
            for (x, label, width) in [(layout.left, signatureLabel, lineWidth), (layout.left + lineWidth + 30, strings.date, CGFloat(120))] {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x, y: layout.y))
                path.addLine(to: CGPoint(x: x + width, y: layout.y))
                path.lineWidth = 0.8
                ink.setStroke()
                path.stroke()
                draw(label, font: PDFFont.make(8.5), color: secondary, in: CGRect(x: x, y: layout.y + 5, width: width, height: 12))
            }
            layout.y += 30
        }

        layout.ensure(24)
        draw(strings.thanks, font: PDFFont.make(10, .medium), color: secondary,
             in: CGRect(x: layout.left, y: layout.y, width: layout.width, height: 14))
        layout.y += 20
    }

    // MARK: - Drawing primitives

    private func attributes(font: UIFont, color: UIColor, alignment: NSTextAlignment, lineSpacing: CGFloat, kern: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern]
    }

    private func measure(_ text: String, font: UIFont, width: CGFloat, lineSpacing: CGFloat = 0) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: attributes(font: font, color: ink, alignment: .left, lineSpacing: lineSpacing, kern: 0))
        let bounds = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(bounds.height)
    }

    /// Draws text and returns the height it actually used.
    @discardableResult
    fileprivate func draw(_ text: String, font: UIFont, color: UIColor, in rect: CGRect, alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 0, kern: CGFloat = 0) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: attributes(font: font, color: color, alignment: alignment, lineSpacing: lineSpacing, kern: kern))
        let bounds = attributed.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let height = min(ceil(bounds.height), max(rect.height, ceil(font.lineHeight)))
        attributed.draw(with: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], context: nil)
        return height
    }

    private func rule(at y: CGFloat, layout: Layout, color: UIColor, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: layout.left, y: y))
        path.addLine(to: CGPoint(x: layout.right, y: y))
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}

private extension CGRect {
    func at(y: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: minX, y: y, width: width, height: height)
    }
}
