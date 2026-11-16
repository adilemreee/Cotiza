import PhotosUI
import SwiftUI
import VisionKit

/// Photograph or pick a store receipt, review what was read, add the chosen lines as materials.
struct ReceiptScanView: View {
    /// Markup to start from, usually the business default. The contractor can change it here.
    var markup: Double
    var onAdd: (_ lines: [ReceiptLine], _ markup: Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .choose
    @State private var lines: [ReceiptLine] = []
    @State private var selected: Set<UUID> = []
    @State private var photo: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var markupPercent: Double?

    private enum Phase { case choose, reading, review, nothingFound }

    private var chosen: [ReceiptLine] { lines.filter { selected.contains($0.id) } }
    private var percent: Double { markupPercent ?? markup }

    private func price(_ line: ReceiptLine) -> Double {
        Money.round(line.quantity * Money.withMarkup(line.unitPrice, percent: percent))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .choose: chooser
                case .reading: ProgressView("Reading the receipt…")
                case .review: review
                case .nothingFound:
                    ContentUnavailableView {
                        Label("No prices found", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("Try again with the whole receipt flat, in good light.")
                    } actions: {
                        Button("Try again") { phase = .choose }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scan a receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            DocumentCamera { images in
                showsCamera = false
                if !images.isEmpty { read(images.compactMap(\.cgImage)) }
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: phase) { _, new in new == .review }
        .sensoryFeedback(.warning, trigger: phase) { _, new in new == .nothingFound }
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.selection, trigger: markupPercent)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            phase = .reading
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)?.normalizedCGImage else {
                    phase = .nothingFound
                    return
                }
                read([image])
            }
        }
    }

    private var chooser: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .padding(.bottom, 6)
            Text("Add materials from a receipt")
                .font(.title3.bold())
            Text("Precia reads the items and prices on your phone. You choose which ones to add.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
            if VNDocumentCameraViewController.isSupported {
                Button {
                    showsCamera = true
                } label: {
                    Label("Take a photo", systemImage: "camera.fill")
                }
                .buttonStyle(.primary)
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .padding(.vertical, 10)
            }
        }
        .padding(28)
        .frame(maxWidth: 520)
    }

    private var review: some View {
        List {
            Section {
                Stepper(value: Binding(get: { percent }, set: { markupPercent = $0 }), in: 0...200, step: 5) {
                    LabeledContent("Markup on materials", value: "\(Int(percent))%")
                }
            } footer: {
                Text("Your cost is saved for your profit report. The client only sees the price with markup.")
            }
            Section {
                ForEach($lines) { $line in
                    let isOn = selected.contains(line.id)
                    HStack(spacing: 12) {
                        Button {
                            if isOn { selected.remove(line.id) } else { selected.insert(line.id) }
                        } label: {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isOn ? "Selected" : "Not selected")
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Description", text: $line.text)
                            if line.quantity != 1 {
                                Text("\(Money.quantity(line.quantity)) × \(Money.string(line.unitPrice, locale: .current))")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Money.string(price(line), locale: .current))
                                .monospacedDigit()
                                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                            if percent > 0 {
                                Text("Cost \(Money.string(line.total, locale: .current))")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            } header: {
                Text("Found on the receipt")
            } footer: {
                Text("Totals, tax and payment lines are left out. Check each price before sending.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onAdd(chosen, percent)
                dismiss()
            } label: {
                Text("Add \(chosen.count) items · \(Money.string(chosen.reduce(0) { $0 + price($1) }, locale: .current))")
            }
            .buttonStyle(.primary)
            .disabled(chosen.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private func read(_ images: [CGImage]) {
        phase = .reading
        Task {
            var text: [String] = []
            for image in images {
                text += (try? await ReceiptReader.lines(in: image)) ?? []
            }
            let found = ReceiptParser.parse(text)
            lines = found
            selected = Set(found.map(\.id))
            phase = found.isEmpty ? .nothingFound : .review
        }
    }
}

/// The system document scanner: finds the receipt's edges and flattens it.
private struct DocumentCamera: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map(scan.imageOfPage(at:)))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}

private extension UIImage {
    /// Photos can be stored rotated with an orientation flag; Vision needs the pixels upright.
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(at: .zero) }.cgImage
    }
}
