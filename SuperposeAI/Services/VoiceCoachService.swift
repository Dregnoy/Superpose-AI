import AVFoundation

@MainActor
@Observable
final class VoiceCoachService {
    var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var lastSpokenMessage: String = ""
    @ObservationIgnored private var lastSpokenTime: CFAbsoluteTime = 0
    @ObservationIgnored private let cooldown: CFAbsoluteTime = 4.0

    func announceIfNeeded(_ guidance: LiveGuidanceState, isEnabled: Bool, hasPinnedPose: Bool) {
        guard isEnabled else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSpokenTime >= cooldown else { return }

        let message: String? = {
            if guidance.lighting == .tooDark {
                return "Işık az, daha aydınlık bir yöne dön."
            }
            if guidance.framing != .great && guidance.framing != .noSubject {
                return localizedFraming(guidance.framing)
            }
            if hasPinnedPose, let score = guidance.poseMatchScore, score >= 85 {
                return "Harika poz, sabit kal."
            }
            return nil
        }()

        guard let message, message != lastSpokenMessage else { return }
        speak(message)
        lastSpokenMessage = message
        lastSpokenTime = now
    }

    func speakCoaching(for pose: PoseIdea) {
        let subjectText = pose.coaching.subjectTips.joined(separator: ". ")
        let photoText = pose.coaching.photographerTips.joined(separator: ". ")
        let fullText = "\(pose.title). Poz veren için: \(subjectText). Fotoğrafçı için: \(photoText)"
        speak(fullText)
    }

    func speak(_ text: String) {
        configureAudioSessionForSpeech()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.50
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func configureAudioSessionForSpeech() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
    }

    private func localizedFraming(_ framing: FramingStatus) -> String {
        switch framing {
        case .noSubject: return "Kadraja gir."
        case .tooClose: return "Biraz geri çekil."
        case .tooFar: return "Biraz yaklaş."
        case .moveLeft: return "Biraz sola kay."
        case .moveRight: return "Biraz sağa kay."
        case .tiltDown: return "Baş üstünde biraz daha az boşluk bırak."
        case .great: return "Harika kadraj."
        }
    }
}
