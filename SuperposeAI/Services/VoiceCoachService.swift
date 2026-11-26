import AVFoundation

@MainActor
@Observable
final class VoiceCoachService {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenMessage: String = ""
    private var lastSpokenTime: CFAbsoluteTime = 0
    private let cooldown: CFAbsoluteTime = 4.0

    private var isTurkish: Bool { true }

    func announceIfNeeded(_ guidance: LiveGuidanceState, isEnabled: Bool, hasPinnedPose: Bool) {
        guard isEnabled else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSpokenTime >= cooldown else { return }

        let message: String? = {
            if guidance.lighting == .tooDark {
                return isTurkish ? "Işık az, daha aydınlık bir yöne dön." : "Low light. Face a brighter light source."
            }
            if guidance.framing != .great && guidance.framing != .noSubject {
                return localizedFraming(guidance.framing)
            }
            if hasPinnedPose, let score = guidance.poseMatchScore, score >= 85 {
                return isTurkish ? "Harika poz, sabit kal." : "Great pose, hold steady."
            }
            return nil
        }()

        guard let message, message != lastSpokenMessage else { return }
        speak(message)
        lastSpokenMessage = message
        lastSpokenTime = now
    }

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.50
        utterance.voice = AVSpeechSynthesisVoice(language: isTurkish ? "tr-TR" : "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func localizedFraming(_ framing: FramingStatus) -> String {
        guard isTurkish else { return framing.message }
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
