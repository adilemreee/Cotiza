import Foundation

/// The short note sent with the PDF by text or WhatsApp, in the document's language.
nonisolated enum ClientMessage {
    /// Sent with a signing link: the client reviews and signs the estimate in the browser.
    static func signLink(for s: DocumentSnapshot, url: URL) -> String {
        let es = s.language == .spanish
        let firstName = s.clientName.split(separator: " ").first.map(String.init) ?? ""
        let greeting = es ? (firstName.isEmpty ? "Hola," : "Hola \(firstName),") : (firstName.isEmpty ? "Hi," : "Hi \(firstName),")
        let total = Money.string(s.totals.total, locale: s.language.locale)
        let business = s.businessName.isEmpty ? s.ownerName : s.businessName
        let from = business.isEmpty ? "" : (es ? " de \(business)" : " from \(business)")
        var lines = [es
            ? "\(greeting) le envío la cotización \(s.displayNumber)\(from) por \(total). Puede revisarla y aprobarla con su firma aquí:"
            : "\(greeting) here is estimate \(s.displayNumber)\(from) for \(total). You can review it and approve it with your signature here:",
            url.absoluteString]
        if !s.ownerName.isEmpty { lines.append(s.ownerName) }
        return lines.joined(separator: "\n")
    }

    static func text(for s: DocumentSnapshot) -> String {
        let es = s.language == .spanish
        let firstName = s.clientName.split(separator: " ").first.map(String.init) ?? ""
        let greeting = es
            ? (firstName.isEmpty ? "Hola," : "Hola \(firstName),")
            : (firstName.isEmpty ? "Hi," : "Hi \(firstName),")
        let total = Money.string(s.totals.total, locale: s.language.locale)
        let business = s.businessName.isEmpty ? s.ownerName : s.businessName
        let from = business.isEmpty ? "" : (es ? " de \(business)" : " from \(business)")
        let number = s.displayNumber

        var lines: [String] = []
        switch s.kind {
        case .estimate:
            if s.signature != nil {
                lines.append(es
                    ? "\(greeting) le envío la copia firmada de la cotización \(number)\(from) por \(total). ¡Gracias por su confianza!"
                    : "\(greeting) here is the signed copy of estimate \(number)\(from) for \(total). Thank you for your trust!")
            } else {
                var first = es
                    ? "\(greeting) le envío la cotización \(number)\(from) por \(total)."
                    : "\(greeting) here is estimate \(number)\(from) for \(total)."
                if let date = s.validUntil {
                    first += es ? " Es válida hasta el \(s.formatted(date))." : " It's valid until \(s.formatted(date))."
                }
                lines.append(first)
                lines.append(es ? "Si tiene alguna pregunta, con gusto le ayudo." : "Let me know if you have any questions.")
            }
        case .invoice:
            if s.isPaid {
                lines.append(es
                    ? "\(greeting) le envío la factura \(number)\(from) por \(total), ya pagada. ¡Gracias!"
                    : "\(greeting) here is invoice \(number)\(from) for \(total), paid in full. Thank you!")
            } else {
                var first = es
                    ? "\(greeting) le envío la factura \(number)\(from) por \(total)"
                    : "\(greeting) here is invoice \(number)\(from) for \(total)"
                if let date = s.dueDate {
                    first += es ? ", con vencimiento el \(s.formatted(date))." : ", due \(s.formatted(date))."
                } else {
                    first += "."
                }
                lines.append(first)
                let payment = s.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
                if !payment.isEmpty {
                    lines.append(es ? "Formas de pago: \(payment)" : "Payment: \(payment)")
                }
                lines.append(es ? "Gracias." : "Thank you.")
            }
        }
        if !s.ownerName.isEmpty { lines.append(s.ownerName) }
        return lines.joined(separator: "\n")
    }
}
