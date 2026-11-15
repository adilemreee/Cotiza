import MessageUI
import PDFKit
import SwiftData
import SwiftUI

struct PDFPreviewView: View {
    @Bindable var document: JobDocument
    let profile: BusinessProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionStore.self) private var store
    @State private var fileURL: URL?
    @State private var message = ""
    @State private var failed = false
    @State private var showsMessageComposer = false
    @State private var showsWhatsAppShare = false

    private var canText: Bool { MFMessageComposeViewController.canSendText() || Self.showsAllSendButtons }
    private var canWhatsApp: Bool {
        (URL(string: "whatsapp://").map { UIApplication.shared.canOpenURL($0) } ?? false) || Self.showsAllSendButtons
    }

    /// `-CotizaShowSendButtons YES` (DEBUG): shows WhatsApp and Text message in the simulator, which has neither.
    private static var showsAllSendButtons: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "CotizaShowSendButtons")
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if let fileURL {
                    PDFKitView(url: fileURL)
                        .ignoresSafeArea(edges: .bottom)
                } else if failed {
                    ContentUnavailableView("Couldn't create the PDF", systemImage: "exclamationmark.triangle", description: Text("Free up some storage and try again."))
                } else {
                    ProgressView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(document.displayNumber)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let fileURL {
                    sendBar(fileURL)
                }
            }
            .sheet(isPresented: $showsMessageComposer) {
                if let fileURL {
                    MessageComposer(recipient: document.client?.phone ?? "", body: message, attachment: fileURL) { sent in
                        if sent { markSent() }
                    }
                    .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showsWhatsAppShare) {
                if let fileURL {
                    ActivityView(items: [fileURL, message]) { completed in
                        if completed { markSent() }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .task { render() }
            .sensoryFeedback(.success, trigger: document.status) { old, new in old == .draft && new == .sent }
            .sensoryFeedback(.error, trigger: failed) { _, new in new }
        }
    }

    @ViewBuilder
    private func sendBar(_ fileURL: URL) -> some View {
        VStack(spacing: 10) {
            if canText || canWhatsApp {
                HStack(spacing: 10) {
                    if canWhatsApp {
                        Button {
                            showsWhatsAppShare = true
                        } label: {
                            Label("WhatsApp", systemImage: "phone.bubble.fill")
                                .sideBySideLabel()
                        }
                        .buttonStyle(.primary)
                    }
                    if canText {
                        Button {
                            showsMessageComposer = true
                        } label: {
                            Label("Text message", systemImage: "message.fill")
                                .sideBySideLabel()
                        }
                        .buttonStyle(.primary)
                    }
                }
                ShareLink(item: fileURL, message: Text(message)) {
                    Label("Email or other apps", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .simultaneousGesture(TapGesture().onEnded { markSent() })
            } else {
                ShareLink(item: fileURL, message: Text(message)) {
                    Label("Send to client", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
                .simultaneousGesture(TapGesture().onEnded { markSent() })
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func render() {
        let snapshot = DocumentSnapshot(document: document, profile: profile, showsBranding: !store.isPro)
        message = ClientMessage.text(for: snapshot)
        do {
            fileURL = try PDFRenderer().writeFile(snapshot)
            DocumentFactory(context: context).learnPrices(from: document)
            try? context.save()
        } catch {
            failed = true
        }
    }

    private func markSent() {
        guard document.status == .draft else { return }
        document.apply(status: .sent)
        try? context.save()
        ReviewPrompt.goodMoment()
        Task {
            // The first document sent is when reminders become useful, so that's when Cotiza asks.
            await ReminderScheduler.requestPermissionIfNeeded()
            await ReminderScheduler.sync()
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemGroupedBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

/// Messages with the client's number, the note and the PDF already filled in.
private struct MessageComposer: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    let attachment: URL
    var onFinish: (_ sent: Bool) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        if !recipient.trimmingCharacters(in: .whitespaces).isEmpty { controller.recipients = [recipient] }
        controller.body = body
        controller.addAttachmentURL(attachment, withAlternateFilename: attachment.lastPathComponent)
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish(result == .sent)
            controller.dismiss(animated: true)
        }
    }
}

private extension View {
    /// Two buttons share the row, so a long label ("Mensaje de texto") shrinks a little instead of wrapping.
    func sideBySideLabel() -> some View {
        lineLimit(1).minimumScaleFactor(0.7)
    }
}
