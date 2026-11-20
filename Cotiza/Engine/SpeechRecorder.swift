import AVFoundation
import Foundation
import Observation
import Speech
import os

/// Live speech-to-text for describing a job. Recognition runs on device when the language supports it.
@Observable
final class SpeechRecorder {
    enum State: Equatable {
        case idle
        case recording
        case permissionDenied
        case unavailable
        /// Recognition ended with an error before any words were heard.
        case heardNothing
    }

    private(set) var state: State = .idle
    /// Input loudness from 0 to 1, for the recording animation.
    private(set) var level: Double = 0
    /// Text recognised in the current recording session.
    private(set) var transcript: String = ""

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var committed = ""
    private var partial = ""
    private var session = 0

    private static let logger = Logger(subsystem: "com.cotiza.app", category: "speech")

    var isRecording: Bool { state == .recording }

    /// Trade words the recognizer would otherwise mishear ("metrekare", "alçıpan", "tablaroca").
    static func vocabulary(for locale: Locale) -> [String] {
        switch locale.language.languageCode {
        case .turkish:
            ["metrekare", "metrekaresi", "tanesi", "adedi", "saati", "işçilik", "lira", "TL", "kapora", "alçıpan",
             "boya", "badana", "fayans", "seramik", "parke", "laminat", "sıva", "kombi", "batarya", "lavabo",
             "klozet", "priz", "izolasyon", "su yalıtımı", "çatı", "oluk", "kiremit", "tesisat", "müşteri", "tadilat"]
        case .spanish:
            ["recámara", "tablaroca", "pies cuadrados", "pies lineales", "mano de obra", "anticipo", "cotización",
             "impermeabilizar", "resanar", "galones", "zoclo", "azulejo", "cliente"]
        default:
            ["drywall", "square feet", "linear feet", "labor", "deposit", "trim", "caulk", "vanity", "grout",
             "baseboard", "gallons", "client"]
        }
    }

    func start(locale: Locale) async {
        guard state != .recording else { return }
        transcript = ""
        committed = ""
        partial = ""

        guard await Self.requestPermissions() else {
            state = .permissionDenied
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            state = .unavailable
            return
        }

        session += 1
        let currentSession = session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.contextualStrings = Self.vocabulary(for: locale)

            let engine = AVAudioEngine()
            try Self.installTap(on: engine, feeding: request) { [weak self] level in
                Task { @MainActor in
                    guard let self, self.session == currentSession else { return }
                    self.level = level
                }
            }
            task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, finished, failed in
                Task { @MainActor in
                    guard let self, self.session == currentSession else { return }
                    if let text { self.absorb(text) }
                    guard finished else { return }
                    if failed, self.transcript.isEmpty {
                        // Without this the mic button would silently reset and the user wouldn't know why.
                        self.teardown()
                        self.state = .heardNothing
                    } else {
                        self.finish()
                    }
                }
            }
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.request = request
            state = .recording
        } catch {
            Self.logger.error("Could not start recording: \(error.localizedDescription, privacy: .public)")
            teardown()
            state = .unavailable
        }
    }

    func stop() {
        guard state == .recording else { return }
        finish()
    }

    func reset() {
        teardown()
        state = .idle
        transcript = ""
    }

    // MARK: - Private

    /// The on-device recogniser restarts its text after a long pause. Keep what was already said.
    private func absorb(_ text: String) {
        let restarted = !partial.isEmpty && text.count < partial.count && !partial.hasPrefix(String(text.prefix(12)))
        if restarted {
            committed = [committed, partial].filter { !$0.isEmpty }.joined(separator: " ")
        }
        partial = text
        transcript = [committed, partial].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func finish() {
        teardown()
        state = .idle
    }

    private func teardown() {
        session += 1
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // The callbacks below fire on audio and recognition queues, so they are built in
    // nonisolated functions: a closure created on the main actor would trap when called there.

    private nonisolated static func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// `SFSpeechAudioBufferRecognitionRequest.append` is documented as safe to call from the audio thread.
    private nonisolated final class RequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    }

    private nonisolated static func installTap(
        on engine: AVAudioEngine,
        feeding request: SFSpeechAudioBufferRecognitionRequest,
        level: @escaping @Sendable (Double) -> Void
    ) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Cotiza.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio input available"])
        }
        let box = RequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
            level(Self.loudness(of: buffer))
        }
    }

    private nonisolated static func loudness(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        // Map roughly -50 dB…0 dB onto 0…1.
        let decibels = 20 * log10(max(rms, 0.000_01))
        return Double(min(max((decibels + 50) / 50, 0), 1))
    }

    private nonisolated static func startTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        update: @escaping @Sendable (_ text: String?, _ finished: Bool, _ failed: Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            update(text, finished, error != nil)
        }
    }
}
