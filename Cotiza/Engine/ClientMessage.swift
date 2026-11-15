import Foundation

/// The short note sent with the PDF by text or WhatsApp, in the document's language.
///
/// Turkish names the business in parentheses ("… ektedir (López Boya): $920.00") because the
/// "from" suffix (-dan/-den/-tan/-ten) depends on how the name ends.
nonisolated enum ClientMessage {
    private struct Parts {
        let t: (String, String, String) -> String
        let greeting: String
        let from: String
        let total: String

        init(_ s: DocumentSnapshot) {
            let language = s.language
            t = { language.text($0, $1, $2) }
            let firstName = s.clientName.split(separator: " ").first.map(String.init) ?? ""
            greeting = firstName.isEmpty
                ? language.text("Hi,", "Hola,", "Merhaba,")
                : language.text("Hi \(firstName),", "Hola \(firstName),", "Merhaba \(firstName),")
            let business = s.businessName.isEmpty ? s.ownerName : s.businessName
            from = business.isEmpty ? "" : language.text(" from \(business)", " de \(business)", " (\(business))")
            total = Money.string(s.totals.total, locale: language.locale)
        }
    }

    /// Sent with a signing link: the client reviews and signs the estimate in the browser.
    static func signLink(for s: DocumentSnapshot, url: URL) -> String {
        let p = Parts(s)
        let (greeting, from, total, number) = (p.greeting, p.from, p.total, s.displayNumber)
        var lines = [p.t(
            "\(greeting) here is estimate \(number)\(from) for \(total). You can review it and approve it with your signature here:",
            "\(greeting) le envío la cotización \(number)\(from) por \(total). Puede revisarla y aprobarla con su firma aquí:",
            "\(greeting) \(number) numaralı teklif hazır\(from): \(total). Buradan inceleyip imzanızla onaylayabilirsiniz:"),
            url.absoluteString]
        if !s.ownerName.isEmpty { lines.append(s.ownerName) }
        return lines.joined(separator: "\n")
    }

    static func text(for s: DocumentSnapshot) -> String {
        let p = Parts(s)
        let t = p.t
        let (greeting, from, total, number) = (p.greeting, p.from, p.total, s.displayNumber)
        let locale = s.language.locale
        let deposit = Money.string(s.depositAmount, locale: locale)
        let percent = Money.quantity(s.depositPercent, locale: locale)
        let paidSoFar = Money.string(s.amountPaid, locale: locale)
        let balance = Money.string(s.balanceDue, locale: locale)
        let payment = s.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        func paymentLine() {
            if !payment.isEmpty { lines.append(t("Payment: \(payment)", "Formas de pago: \(payment)", "Ödeme: \(payment)")) }
        }
        switch s.kind {
        case .estimate:
            if s.amountPaid > 0 {
                // A receipt for the deposit.
                lines.append(t(
                    "\(greeting) here is estimate \(number)\(from) for \(total). I received your payment of \(paidSoFar).",
                    "\(greeting) le envío la cotización \(number)\(from) por \(total). Recibí su pago de \(paidSoFar).",
                    "\(greeting) \(number) numaralı teklif ektedir\(from): \(total). \(paidSoFar) tutarındaki ödemenizi aldım."))
                if s.balanceDue > 0 {
                    lines.append(t("Balance due: \(balance). Thank you!", "Saldo pendiente: \(balance). ¡Gracias!",
                                   "Kalan tutar: \(balance). Teşekkürler!"))
                } else {
                    lines.append(t("It's paid in full. Thank you!", "Queda pagada por completo. ¡Gracias!",
                                   "Tamamı ödendi. Teşekkürler!"))
                }
            } else if s.signature != nil {
                lines.append(t(
                    "\(greeting) here is the signed copy of estimate \(number)\(from) for \(total). Thank you for your trust!",
                    "\(greeting) le envío la copia firmada de la cotización \(number)\(from) por \(total). ¡Gracias por su confianza!",
                    "\(greeting) \(number) numaralı teklifin imzalı kopyası ektedir\(from): \(total). Güveniniz için teşekkürler!"))
                if s.depositIsDue {
                    lines.append(t("To get started, the deposit is \(deposit).", "Para empezar, el anticipo es de \(deposit).",
                                   "İşe başlamak için kapora \(deposit)."))
                    paymentLine()
                }
            } else {
                var first = t(
                    "\(greeting) here is estimate \(number)\(from) for \(total).",
                    "\(greeting) le envío la cotización \(number)\(from) por \(total).",
                    "\(greeting) \(number) numaralı teklif ektedir\(from): \(total).")
                if let date = s.validUntil {
                    let day = s.formatted(date)
                    first += t(" It's valid until \(day).", " Es válida hasta el \(day).", " \(day) tarihine kadar geçerlidir.")
                }
                lines.append(first)
                if s.depositIsDue {
                    lines.append(t(
                        "A deposit of \(deposit) (\(percent)%) is due to start.",
                        "Para empezar se pide un anticipo de \(deposit) (\(percent)%).",
                        "İşe başlamak için \(deposit) (%\(percent)) kapora alınır."))
                }
                lines.append(t("Let me know if you have any questions.", "Si tiene alguna pregunta, con gusto le ayudo.",
                               "Sorunuz olursa memnuniyetle yardımcı olurum."))
            }
        case .invoice:
            if s.isPaid {
                lines.append(t(
                    "\(greeting) here is invoice \(number)\(from) for \(total), paid in full. Thank you!",
                    "\(greeting) le envío la factura \(number)\(from) por \(total), ya pagada. ¡Gracias!",
                    "\(greeting) \(number) numaralı fatura ektedir\(from): \(total), tamamı ödendi. Teşekkürler!"))
            } else {
                var first = s.amountPaid > 0
                    ? t("\(greeting) here is invoice \(number)\(from) for \(total). I've received \(paidSoFar); the balance due is \(balance)",
                        "\(greeting) le envío la factura \(number)\(from) por \(total). Ya recibí \(paidSoFar); el saldo pendiente es de \(balance)",
                        "\(greeting) \(number) numaralı fatura ektedir\(from): \(total). \(paidSoFar) aldım; kalan tutar \(balance)")
                    : t("\(greeting) here is invoice \(number)\(from) for \(total)",
                        "\(greeting) le envío la factura \(number)\(from) por \(total)",
                        "\(greeting) \(number) numaralı fatura ektedir\(from): \(total)")
                if let date = s.dueDate {
                    let day = s.formatted(date)
                    first += t(", due \(day).", ", con vencimiento el \(day).", ", son ödeme tarihi \(day).")
                } else {
                    first += "."
                }
                lines.append(first)
                paymentLine()
                lines.append(t("Thank you.", "Gracias.", "Teşekkürler."))
            }
        }
        if !s.ownerName.isEmpty { lines.append(s.ownerName) }
        return lines.joined(separator: "\n")
    }
}
