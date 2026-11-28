import Foundation
#if canImport(WatchConnectivity)
@preconcurrency import WatchConnectivity
#endif

/// Bridges live pose-match % and lighting readiness to the Apple Watch companion
/// and handles remote shutter commands from the wrist.
@MainActor
@Observable
final class WatchRemoteService: NSObject {
    private(set) var isWatchReachable = false
    private(set) var isWatchPaired = false

    @ObservationIgnored private var onRemoteCapture: (@MainActor (Int) -> Void)?
    @ObservationIgnored private var lastSentTime: CFAbsoluteTime = 0

    func start(onRemoteCapture: @escaping @MainActor (Int) -> Void) {
        self.onRemoteCapture = onRemoteCapture
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    func sendLiveStatus(
        matchScore: Int?,
        lightingMessage: String,
        isShotReady: Bool,
        isRecording: Bool,
        threshold: Int
    ) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSentTime >= 0.25 else { return }
        lastSentTime = now

        var payload: [String: Any] = [
            "lighting": lightingMessage,
            "isShotReady": isShotReady,
            "isRecording": isRecording,
            "threshold": threshold
        ]
        if let matchScore {
            payload["matchScore"] = matchScore
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        try? session.updateApplicationContext(payload)
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchRemoteService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let paired = session.isPaired
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isWatchPaired = paired
            self?.isWatchReachable = reachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isWatchReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        let timerSeconds = (command == "timer3") ? 3 : 0
        Task { @MainActor [weak self] in
            self?.onRemoteCapture?(timerSeconds)
        }
    }
}
#endif
