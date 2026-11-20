import SwiftData
import SwiftUI
import Translation

/// Describe the job by voice or typing, then turn it into an estimate.
struct CaptureView: View {
    let profile: BusinessProfile
    var onCreated: (JobDocument) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionStore.self) private var store

    @State private var recorder = SpeechRecorder()
    @State private var text = ""
    /// What was already in the field when the current recording started.
    @State private var textBeforeRecording = ""
    @State private var isGenerating = false
    @State private var pendingDraft: EstimateDraft?
    @State private var translation: TranslationSession.Configuration?
    @AppStorage("speechLanguage") private var speechLanguageRaw = CaptureView.defaultSpeechLanguage.rawValue
    @FocusState private var editing: Bool

    private static var defaultSpeechLanguage: DocumentLanguage { .device }

    private var speechLanguage: DocumentLanguage {
        DocumentLanguage(rawValue: speechLanguageRaw) ?? .spanish
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcriptArea
                controls
            }
            .readableWidth(720)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { close() }
                        .disabled(isGenerating)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("I speak", selection: $speechLanguageRaw) {
                            ForEach(DocumentLanguage.allCases) { language in
                                Text(language.label).tag(language.rawValue)
                            }
                        }
                    } label: {
                        Label(speechLanguage.code, systemImage: "globe")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(recorder.isRecording)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editing = false }
                }
            }
            .overlay {
                if isGenerating { generatingOverlay }
            }
            .onChange(of: recorder.transcript) { _, spoken in
                guard recorder.isRecording || !spoken.isEmpty else { return }
                text = [textBeforeRecording, spoken].filter { !$0.isEmpty }.joined(separator: " ")
            }
            .translationTask(translation) { @concurrent session in
                guard let pending = await takePendingDraft() else { return }
                let translated = await Self.translate(pending.draft, to: pending.target, with: session)
                await finish(with: translated, transcript: trimmedText)
            }
            .interactiveDismissDisabled(isGenerating || recorder.isRecording)
            #if DEBUG
            .onAppear {
                // `-CotizaDemoTranscript "…"` pre-fills the job description for QA and screenshots.
                if text.isEmpty, let demo = UserDefaults.standard.string(forKey: "CotizaDemoTranscript") {
                    text = demo
                }
            }
            #endif
        }
    }

    // MARK: Sections

    private var transcriptArea: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($editing)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .disabled(recorder.isRecording)
            if text.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Describe the job and your prices.")
                        .font(.title3.weight(.semibold))
                    Text("Example:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                    Text(speechLanguage.text(
                        "“Paint two bedrooms at 350 each, install 3 doors at 120 dollars each and 8 hours of labor at 45 an hour. Client Maria Lopez.”",
                        "“Pintar dos recámaras a 350 cada una, instalar 3 puertas a 120 dólares cada una y 8 horas de mano de obra a 45 la hora. Cliente María López.”",
                        Money.currencyCode == "TRY"
                            ? "“2 yatak odası boyama tanesi 3.500 lira, 3 kapı takma tanesi 1.200 lira ve 8 saat işçilik saati 450. Müşteri Ayşe Yılmaz.”"
                            : "“2 yatak odası boyama tanesi 350, 3 kapı takma tanesi 120 dolar ve 8 saat işçilik saati 45. Müşteri Ayşe Yılmaz.”"))
                        .font(.body)
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 21)
                .padding(.top, 20)
                .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            statusLine
            MicButton(isRecording: recorder.isRecording, level: recorder.level) {
                toggleRecording()
            }
            .disabled(isGenerating)

            Button {
                generate()
            } label: {
                Label("Create estimate", systemImage: "sparkles")
            }
            .buttonStyle(.primary)
            .disabled(trimmedText.isEmpty || isGenerating || recorder.isRecording)

            Button("Start with a blank estimate") {
                finish(with: EstimateDraft(title: "", clientName: nil, items: []), transcript: "")
            }
            .font(.subheadline)
            .disabled(isGenerating || recorder.isRecording)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch recorder.state {
        case .recording:
            Text("Listening… tap to stop")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tint)
        case .permissionDenied:
            VStack(spacing: 4) {
                Text("Microphone access is off. You can still type the job.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                        .font(.subheadline.weight(.semibold))
                }
            }
        case .heardNothing:
            Text("Didn't catch that. Tap to try again, or type the job.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        case .unavailable:
            Text("Voice isn't available right now. Type the job instead.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        case .idle:
            Text(text.isEmpty ? "Tap to speak" : "Tap to add more")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.secondary)
        }
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Writing your estimate…")
                    .font(.headline)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .transition(.opacity)
    }

    // MARK: Actions

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            editing = false
            textBeforeRecording = trimmedText
            Task { await recorder.start(locale: speechLanguage.locale) }
        }
    }

    private func close() {
        recorder.reset()
        dismiss()
    }

    private func generate() {
        let transcript = trimmedText
        guard !transcript.isEmpty, !isGenerating else { return }
        editing = false
        withAnimation { isGenerating = true }
        let hints = DocumentFactory(context: context).priceHints()
        let trade = profile.tradeDescription
        let target = profile.documentLanguage
        let spoken = speechLanguage
        let currency = profile.currency

        Task {
            let draft = await EstimateEngine().makeDraft(transcript: transcript, trade: trade, language: target, spoken: spoken,
                                                          currency: currency, priceBook: hints)
            guard draft.textLanguage != target, !draft.items.isEmpty else {
                finish(with: draft, transcript: transcript)
                return
            }
            // The basic parser keeps the spoken language. Translate on device when the languages are available.
            let status = await LanguageAvailability().status(from: draft.textLanguage.language, to: target.language)
            switch status {
            case .installed, .supported:
                pendingDraft = draft
                translation = TranslationSession.Configuration(source: draft.textLanguage.language, target: target.language)
                Task {
                    // If translation never starts (download declined, no connection), don't leave the spinner up.
                    try? await Task.sleep(for: .seconds(25))
                    if let pending = takePendingDraft() {
                        finish(with: pending.draft, transcript: transcript)
                    }
                }
            default:
                finish(with: draft, transcript: transcript)
            }
        }
    }

    private func takePendingDraft() -> (draft: EstimateDraft, target: DocumentLanguage)? {
        guard let draft = pendingDraft else { return nil }
        pendingDraft = nil
        translation = nil
        return (draft, profile.documentLanguage)
    }

    /// Runs off the main actor: the translation session is not sendable and does its own work in the background.
    @concurrent
    private nonisolated static func translate(_ draft: EstimateDraft, to target: DocumentLanguage, with session: TranslationSession) async -> EstimateDraft {
        var draft = draft
        var requests = draft.items.enumerated().map { index, item in
            TranslationSession.Request(sourceText: item.text, clientIdentifier: "item-\(index)")
        }
        if !draft.title.isEmpty {
            requests.append(TranslationSession.Request(sourceText: draft.title, clientIdentifier: "title"))
        }
        do {
            for response in try await session.translations(from: requests) {
                guard let identifier = response.clientIdentifier else { continue }
                if identifier == "title" {
                    draft.title = response.targetText
                } else if let index = Int(identifier.dropFirst("item-".count)), draft.items.indices.contains(index) {
                    draft.items[index].text = response.targetText
                }
            }
            draft.textLanguage = target
        } catch {
            // Translation is a convenience: on failure the estimate keeps the spoken wording.
        }
        return draft
    }

    private func finish(with draft: EstimateDraft, transcript: String) {
        recorder.reset()
        let document = DocumentFactory(context: context).makeEstimate(from: draft, transcript: transcript, profile: profile)
        try? context.save()
        store.recordEstimateCreated()
        isGenerating = false
        onCreated(document)
    }
}

// MARK: - Mic button

private struct MicButton: View {
    let isRecording: Bool
    let level: Double
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 84, height: 84)
                    .scaleEffect(isRecording && !reduceMotion ? 1.1 + level * 0.55 : 1)
                    .animation(.smooth(duration: 0.12), value: level)
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 84, height: 84)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 130, height: 110)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
        .accessibilityLabel(isRecording ? Text("Stop recording") : Text("Start recording"))
    }
}
