import AVFoundation
import Foundation
import Speech

enum DictationLocale: String, CaseIterable, Identifiable, Sendable {
    case turkish = "tr-TR"
    case english = "en-US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turkish: return "Türkçe (TR)"
        case .english: return "English (US)"
        }
    }
}

/// Live speech-to-text service built on `SFSpeechRecognizer` + `AVAudioEngine`.
@MainActor
final class SpeechDictationService: ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published var transcript: String = ""
    @Published private(set) var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func toggleRecording(locale: DictationLocale) {
        if isRecording {
            stop()
        } else {
            Task {
                await start(locale: locale)
            }
        }
    }

    func start(locale: DictationLocale) async {
        guard !isRecording else { return }
        errorMessage = nil

        let speechAllowed = await requestSpeechPermission()
        guard speechAllowed else {
            errorMessage = "Konuşma tanıma izni verilmedi."
            return
        }

        let micAllowed = await requestMicrophonePermission()
        guard micAllowed else {
            errorMessage = "Mikrofon izni verilmedi."
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale.rawValue)),
              recognizer.isAvailable else {
            errorMessage = "Konuşma tanıma servisi şu anda kullanılamıyor."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.recognitionRequest = request
            self.isRecording = true

            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stop()
                    }
                }
            }
        } catch {
            stop()
            errorMessage = "Ses kaydı başlatılamadı: \(error.localizedDescription)"
        }
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
