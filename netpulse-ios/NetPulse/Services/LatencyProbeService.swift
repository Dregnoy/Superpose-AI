import Foundation
import Network

/// CheckedContinuation'ın birden fazla kez resume edilmesini kesin olarak önleyen kilit bayrağı.
internal final class LockedOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func tryClaim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

enum LatencyProbeService {
    /// Belirtilen IP/alan adına TCP el sıkışma (SYN -> SYN/ACK) süresiyle gerçek RTT ve jitter ölçer.
    static func measureTCPLatency(
        host: String,
        port: UInt16 = 443,
        count: Int = 3,
        timeoutSec: TimeInterval = 2.0
    ) async -> ProbeMetrics {
        let samples = max(1, min(10, count))
        var rtts: [Double] = []
        rtts.reserveCapacity(samples)

        for idx in 0..<samples {
            if let rtt = await singleTCPConnectRTT(host: host, port: port, timeoutSec: timeoutSec) {
                rtts.append(rtt)
            }
            if idx + 1 < samples {
                try? await Task.sleep(for: .milliseconds(90))
            }
        }

        let received = rtts.count
        let lossPct = Double(samples - received) / Double(samples) * 100.0
        guard !rtts.isEmpty else {
            return ProbeMetrics.unreachable(host, sent: samples)
        }

        let avg = rtts.reduce(0, +) / Double(rtts.count)
        let maxVal = rtts.max() ?? avg
        var jitter: Double = 0.0
        if rtts.count >= 2 {
            var diffs: [Double] = []
            for i in 1..<rtts.count {
                diffs.append(abs(rtts[i] - rtts[i - 1]))
            }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        }

        return ProbeMetrics(
            target: host,
            sent: samples,
            received: received,
            lossPct: (lossPct * 10).rounded() / 10,
            avgMs: (avg * 10).rounded() / 10,
            maxMs: (maxVal * 10).rounded() / 10,
            jitterMs: (jitter * 10).rounded() / 10,
            reachable: true
        )
    }

    static func singleTCPConnectRTT(
        host: String,
        port: UInt16,
        timeoutSec: TimeInterval = 2.0
    ) async -> Double? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let nwHost = NWEndpoint.Host(host)

        return await withCheckedContinuation { continuation in
            let once = LockedOnce()
            let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
            let q = DispatchQueue(label: "com.netpulse.ios.tcpprobe.\(UUID().uuidString.prefix(8))")
            let started = DispatchTime.now().uptimeNanoseconds

            let timeoutWork = DispatchWorkItem {
                if once.tryClaim() {
                    conn.cancel()
                    continuation.resume(returning: nil)
                }
            }
            q.asyncAfter(deadline: .now() + timeoutSec, execute: timeoutWork)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.tryClaim() {
                        timeoutWork.cancel()
                        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000.0
                        conn.cancel()
                        continuation.resume(returning: (elapsedMs * 10).rounded() / 10)
                    }
                case .failed, .cancelled:
                    if once.tryClaim() {
                        timeoutWork.cancel()
                        conn.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }
            conn.start(queue: q)
        }
    }

    static func runPeeringTest(profile: PeeringProfile) async -> PeeringReport {
        let targets: [(name: String, host: String, port: UInt16)]
        switch profile {
        case .oyun:
            targets = [
                ("Cloudflare Edge (Anycast)", "1.1.1.1", 443),
                ("Riot / LoL EU Frankfurt", "185.40.65.1", 443),
                ("Valve Steam EU", "store.steampowered.com", 443),
                ("AWS Europe (Frankfurt)", "dynamodb.eu-central-1.amazonaws.com", 443),
            ]
        case .toplanti:
            targets = [
                ("Zoom Real-Time", "zoom.us", 443),
                ("Microsoft Teams", "teams.microsoft.com", 443),
                ("Google Meet", "meet.google.com", 443),
                ("Cloudflare TURN/Anycast", "1.1.1.1", 443),
            ]
        case .yayin:
            targets = [
                ("YouTube CDN", "www.youtube.com", 443),
                ("Twitch Ingest", "www.twitch.tv", 443),
                ("Netflix Fast CDN", "fast.com", 443),
                ("Cloudflare 1.1.1.1", "1.1.1.1", 443),
            ]
        }

        let results: [PeeringTargetResult] = await withTaskGroup(of: (Int, PeeringTargetResult).self) { group in
            for (idx, item) in targets.enumerated() {
                group.addTask {
                    let probe = await measureTCPLatency(host: item.host, port: item.port, count: 3, timeoutSec: 2.5)
                    return (
                        idx,
                        PeeringTargetResult(
                            name: item.name,
                            host: item.host,
                            port: item.port,
                            reachable: probe.reachable,
                            rttMs: probe.avgMs,
                            protocolName: "TCP \(item.port)"
                        )
                    )
                }
            }
            var ordered: [(Int, PeeringTargetResult)] = []
            for await pair in group {
                ordered.append(pair)
            }
            return ordered.sorted(by: { $0.0 < $1.0 }).map(\.1)
        }

        let reachable = results.filter(\.reachable)
        let summary: String
        if reachable.isEmpty {
            summary = "Seçili peering sunucularına ulaşılamadı."
        } else {
            let avg = reachable.compactMap(\.rttMs).reduce(0, +) / Double(reachable.count)
            summary = String(format: "%@ profili ortalama TCP gecikmesi: %.1f ms (%d/%d erişilebilir).", profile.title, avg, reachable.count, results.count)
        }

        return PeeringReport(
            timestamp: Date().timeIntervalSince1970,
            profile: profile,
            results: results,
            summary: summary
        )
    }
}
