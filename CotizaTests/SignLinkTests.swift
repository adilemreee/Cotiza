import UIKit
import Foundation
import Testing
@testable import Cotiza

@Suite("Signing links")
struct SignLinkTests {
    private func snapshot(language: DocumentLanguage = .spanish, tax: Double = 8.25) -> DocumentSnapshot {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 12, day: 12))!
        let items = [
            DocumentSnapshot.Item(text: "Pintar recámaras", quantity: 3, unit: "", unitPrice: 450, amount: 1350),
            DocumentSnapshot.Item(text: "Pintura premium", quantity: 6, unit: "gal", unitPrice: 52.89, amount: 317.34),
        ]
        return DocumentSnapshot(
            kind: .estimate, language: language, displayNumber: "E-1003", title: "Pintura interior", date: date, isPaid: false,
            businessName: "López Painting LLC", ownerName: "Carlos López", businessPhone: "(713) 555-0142", businessEmail: "",
            businessAddress: "", licenseNumber: "", logo: nil, clientName: "Maria Lopez", clientPhone: "", clientEmail: "",
            clientAddress: "", items: items,
            totals: Totals(lines: items.map { .init(amount: $0.amount, isTaxable: true) }, taxRate: tax), taxRate: tax,
            notes: "", terms: "50% de anticipo.", paymentInstructions: "", showsBranding: false, validUntil: date
        )
    }

    @Test func `the page content is formatted in the document's language`() {
        let page = SignLinkDocument(snapshot())
        #expect(page.kindLabel == "Cotización")
        #expect(page.number == "E-1003")
        #expect(page.businessContact == "(713) 555-0142")
        #expect(page.items[1].detail.hasPrefix("6 gal × "))
        #expect(page.totals.count == 2)
        #expect(page.totals[1].label.hasPrefix("Impuesto"))
        #expect(page.validUntilText == "12 de diciembre de 2026")
        #expect(page.terms.hasPrefix("50% de anticipo.\nEsta cotización es válida hasta"))
        #expect(SignLinkDocument(snapshot(tax: 0)).totals.isEmpty)
    }

    @Test func `the upload carries the language, the page and the PDF`() throws {
        let body = try SignLink.body(for: snapshot(language: .english), pdf: Data("%PDF-1.7".utf8))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["language"] as? String == "en")
        #expect(json["pdf"] as? String == Data("%PDF-1.7".utf8).base64EncodedString())
        #expect((json["document"] as? [String: Any])?["kindLabel"] as? String == "Estimate")
    }

    @Test func `the server's answers are read, with or without fractional seconds`() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let signed = try SignLink.decode(Data("""
        {"status":"signed","signerName":"Maria Lopez","signedAt":"2026-11-12T17:04:39.780Z","signature":"\(png.base64EncodedString())"}
        """.utf8))
        #expect(signed.status == "signed")
        #expect(signed.signerName == "Maria Lopez")
        #expect(signed.signature == png)
        #expect(signed.signedAt != nil)
        let plain = try SignLink.decode(Data(#"{"status":"pending","signerName":null,"signedAt":"2026-11-12T17:04:39Z","signature":null}"#.utf8))
        #expect(plain.status == "pending")
        #expect(plain.signedAt != nil)
    }

    @Test func `secrets are long, URL-safe and different each time`() {
        let a = SignLink.newSecret(), b = SignLink.newSecret()
        #expect(a.count == 43)
        #expect(a != b)
        #expect(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func `the message to the client includes the link`() throws {
        let url = try #require(URL(string: "https://cotiza.adilemree.xyz/s/abc"))
        let es = ClientMessage.signLink(for: snapshot(), url: url)
        #expect(es.hasPrefix("Hola Maria, le envío la cotización E-1003 de López Painting LLC por "))
        #expect(es.contains("\nhttps://cotiza.adilemree.xyz/s/abc\n"))
        #expect(ClientMessage.signLink(for: snapshot(language: .english), url: url).contains("approve it with your signature here:"))
    }
}

/// Talks to the live signing service, so it only runs when asked:
/// TEST_RUNNER_COTIZA_LIVE_TESTS=1 xcodebuild test -only-testing:CotizaTests/SignLinkLiveTests
@MainActor
@Suite("Signing links, live server", .enabled(if: ProcessInfo.processInfo.environment["COTIZA_LIVE_TESTS"] == "1"))
struct SignLinkLiveTests {
    @Test func `a link is created, signed in the browser, collected and deleted`() async throws {
        let date = Date.now
        let items = [DocumentSnapshot.Item(text: "Live test — paint", quantity: 1, unit: "", unitPrice: 100, amount: 100)]
        let snapshot = DocumentSnapshot(
            kind: .estimate, language: .spanish, displayNumber: "E-TEST", title: "Prueba automática", date: date, isPaid: false,
            businessName: "Cotiza Test", ownerName: "", businessPhone: "", businessEmail: "", businessAddress: "",
            licenseNumber: "", logo: nil, clientName: "Test Client", clientPhone: "", clientEmail: "", clientAddress: "",
            items: items, totals: Totals(lines: [.init(amount: 100, isTaxable: false)], taxRate: 0), taxRate: 0,
            notes: "", terms: "", paymentInstructions: "", showsBranding: false
        )
        let secret = SignLink.newSecret()
        let created = try await SignLink.create(snapshot: snapshot, secret: secret)
        defer { Task { await SignLink.delete(id: created.id, secret: secret) } }
        #expect(created.url.absoluteString.hasPrefix("https://cotiza.adilemree.xyz/s/"))
        guard case .pending = try await SignLink.check(id: created.id, secret: secret) else { Issue.record("not pending"); return }

        // What the page's script sends.
        let ink = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 40)).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 10, y: 18, width: 100, height: 4))
        }
        let png = try #require(ink.pngData())
        var sign = URLRequest(url: created.url.appending(path: "sign"))
        sign.httpMethod = "POST"
        sign.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sign.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": "Test Client", "agree": true, "signature": "data:image/png;base64," + png.base64EncodedString(),
        ])
        let (_, response) = try await URLSession.shared.data(for: sign)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        guard case .signed(let returned, let name, _) = try await SignLink.check(id: created.id, secret: secret) else {
            Issue.record("not signed"); return
        }
        #expect(name == "Test Client")
        #expect(returned == png)
        await SignLink.delete(id: created.id, secret: secret)
        guard case .gone = try await SignLink.check(id: created.id, secret: secret) else { Issue.record("not deleted"); return }
    }
}
