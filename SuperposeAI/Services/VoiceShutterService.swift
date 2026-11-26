import AVFoundation
import Speech

@MainActor
@Observable
final class VoiceShutterService {
    var isListening = false
    var onTriggerShutter: (() -> Void)?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    @ObservationIgnored private var lastTriggerTime: CFAbsoluteTime = 0

    func toggle() async -> Bool {
        if isListening {
            stop()
            return false
        }
        return await start()
    }

    func start() async -> Bool {
        let speechOK = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }

        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else { return false }

        stop()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
            }
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let transcript = result?.bestTranscription.formattedString.lowercased() {
                    let triggers = ["çek", "hazır", "tamam", "cheese"]
                    let lastWord = transcript.split(separator: " ").last.map(String.init) ?? ""
                    if triggers.contains(lastWord) {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let now = CFAbsoluteTimeGetCurrent()
                            if now - self.lastTriggerTime >= 2.2 {
                                self.lastTriggerTime = now
                                self.onTriggerShutter?()
                            }
                        }
                    }
                }
                if error != nil || (result?.isFinal == true) {
                    Task { @MainActor [weak self] in
                        self?.stop()
                    }
                }
            }
            return true
        } catch {
            stop()
            return false
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }
}
