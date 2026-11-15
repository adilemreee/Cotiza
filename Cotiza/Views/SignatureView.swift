import SwiftUI
import UIKit

/// Words the client reads while signing. Like the PDF, they follow the document's language,
/// because the client, not the contractor, is holding the phone.
nonisolated struct SignatureStrings: Sendable {
    let language: DocumentLanguage
    private func t(_ en: String, _ es: String, _ tr: String) -> String { language.text(en, es, tr) }

    func title(_ number: String) -> String { t("Approve estimate \(number)", "Aprobar cotización \(number)", "\(number) teklifini onayla") }
    var consent: String {
        t("By signing, I approve this work, the price and the terms of the estimate.",
          "Al firmar, apruebo este trabajo, el precio y los términos de la cotización.",
          "İmzalayarak bu işi, fiyatı ve teklifin koşullarını onaylıyorum.")
    }
    var name: String { t("Your name", "Su nombre", "Adınız") }
    var signHere: String { t("Sign here with your finger", "Firme aquí con el dedo", "Parmağınızla buraya imzalayın") }
    var clear: String { t("Clear", "Borrar", "Temizle") }
    var approve: String { t("Approve and sign", "Aprobar y firmar", "Onayla ve imzala") }
    var total: String { t("Total", "Total", "Toplam") }
}

/// Full-screen sheet the contractor hands to the client.
struct SignatureSheet: View {
    let document: JobDocument
    var onSign: (_ png: Data, _ name: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var name: String
    @State private var canvasSize: CGSize = .zero

    init(document: JobDocument, onSign: @escaping (_ png: Data, _ name: String) -> Void) {
        self.document = document
        self.onSign = onSign
        _name = State(initialValue: document.client?.name ?? "")
    }

    private var strings: SignatureStrings { SignatureStrings(language: document.language) }
    private var hasSignature: Bool { strokes.contains { $0.count > 1 } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    if !document.title.isEmpty {
                        Text(document.title).font(.headline)
                    }
                    HStack {
                        Text(strings.total)
                        Spacer()
                        Text(Money.string(document.totals.total, locale: document.language.locale))
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                    Text(strings.consent)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                TextField(strings.name, text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                pad
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)

                Button {
                    guard let png = SignatureImage.png(strokes: strokes, in: canvasSize) else { return }
                    onSign(png, name)
                    dismiss()
                } label: {
                    Label(strings.approve, systemImage: "signature")
                }
                .buttonStyle(.primary)
                .disabled(!hasSignature)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .readableWidth(620)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(strings.title(document.displayNumber))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(strings.clear) { strokes = [] }
                        .disabled(strokes.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(hasSignature)
        // A light tap when the pen first touches and when the pad is cleared.
        .sensoryFeedback(.impact(weight: .light), trigger: strokes.isEmpty)
    }

    private var pad: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
            Rectangle()
                .fill(Color.black.opacity(0.25))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
            Text(strings.signHere)
                .font(.footnote)
                .foregroundStyle(Color.black.opacity(0.45))
                .padding(.leading, 24)
                .padding(.bottom, 20)
                .opacity(strokes.isEmpty ? 1 : 0)
            Canvas { context, _ in
                context.stroke(SignatureImage.path(strokes), with: .color(.black),
                               style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { size in
                canvasSize = size
                #if DEBUG
                // Redrawn at each size while the sheet settles, so it fits the pad's final size.
                if ScreenshotScene.current == .signature {
                    strokes = ScreenshotScene.signature(in: size)
                }
                #endif
            }
            // An empty canvas draws nothing, and SwiftUI doesn't hit-test what isn't drawn.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if value.translation == .zero || strokes.isEmpty {
                            strokes.append([value.location])
                        } else {
                            strokes[strokes.count - 1].append(value.location)
                        }
                    }
                    .onEnded { _ in strokes.append([]) }
            )
            .accessibilityLabel(strings.signHere)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(.separator)))
        .environment(\.colorScheme, .light)
    }
}

/// Turns finger strokes into the PNG stored on the document and printed on the PDF.
nonisolated enum SignatureImage {
    static func path(_ strokes: [[CGPoint]]) -> Path {
        var path = Path()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: first)
            if stroke.count == 1 {
                path.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5))
            }
            for point in stroke.dropFirst() { path.addLine(to: point) }
        }
        return path
    }

    /// Black ink on a transparent background, cropped to the ink, at 3× for a sharp print.
    static func png(strokes: [[CGPoint]], in size: CGSize) -> Data? {
        let points = strokes.flatMap { $0 }
        guard points.count > 1, size.width > 0, size.height > 0 else { return nil }
        let padding: CGFloat = 6
        let xs = points.map(\.x), ys = points.map(\.y)
        let bounds = CGRect(x: xs.min()! - padding, y: ys.min()! - padding,
                            width: xs.max()! - xs.min()! + padding * 2, height: ys.max()! - ys.min()! + padding * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: -bounds.minX, y: -bounds.minY)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(2.6)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.addPath(path(strokes).cgPath)
            cg.strokePath()
        }
        return image.pngData()
    }
}
