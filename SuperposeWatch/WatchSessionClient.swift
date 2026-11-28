import Foundation
import WatchConnectivity
import WatchKit

@MainActor
@Observable
final class WatchSessionClient: NSObject {
    var matchScore: Int? = nil
    var lightingMessage: String = "Hazır"
    var isShotReady: Bool = false
    var threshold: Int = 85
    var isReachable: Bool = false

    private var didPlayReadyHaptic = false

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func sendCaptureCommand(timerSeconds: Int = 0) {
        WKInterfaceDevice.current().play(.click)
        guard WCSession.isSupported() else { return }
        let command = timerSeconds > 0 ? "timer3" : "capture"
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(["command": command], replyHandler: nil, errorHandler: nil)
        }
    }

    private func applyPayload(_ payload: [String: Any]) {
        if let score = payload["matchScore"] as? Int {
            matchScore = score
        } else {
            matchScore = nil
        }
        if let lighting = payload["lighting"] as? String {
            lightingMessage = lighting
        }
        if let ready = payload["isShotReady"] as? Bool {
            isShotReady = ready
        }
        if let thresh = payload["threshold"] as? Int {
            threshold = thresh
        }

        let matchedNow = (matchScore ?? 0) >= threshold || isShotReady
        if matchedNow && !didPlayReadyHaptic {
            didPlayReadyHaptic = true
            WKInterfaceDevice.current().play(.success)
        } else if !matchedNow {
            didPlayReadyHaptic = false
        }
    }
}

extension WatchSessionClient: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        let context = session.receivedApplicationContext
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
            if !context.isEmpty {
                self?.applyPayload(context)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.applyPayload(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.applyPayload(applicationContext)
        }
    }
}
