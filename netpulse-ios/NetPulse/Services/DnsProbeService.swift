import Foundation
import Network

enum DnsProbeService {
    struct DnsCandidate: Sendable {
        let id: String
        let name: String
        let primaryIP: String
        let secondaryIP: String?
        let dohURL: String
    }

    static let providers: [DnsCandidate] = [
        DnsCandidate(
            id: "cloudflare",
            name: "Cloudflare",
            primaryIP: "1.1.1.1",
            secondaryIP: "1.0.0.1",
            dohURL: "https://cloudflare-dns.com/dns-query"
        ),
        DnsCandidate(
            id: "google",
            name: "Google DNS",
            primaryIP: "8.8.8.8",
            secondaryIP: "8.8.4.4",
            dohURL: "https://dns.google/dns-query"
        ),
        DnsCandidate(
            id: "quad9",
            name: "Quad9",
            primaryIP: "9.9.9.9",
            secondaryIP: "149.112.112.112",
            dohURL: "https://dns.quad9.net/dns-query"
        ),
        DnsCandidate(
            id: "opendns",
            name: "OpenDNS",
            primaryIP: "208.67.222.222",
            secondaryIP: "208.67.220.220",
            dohURL: "https://doh.opendns.com/dns-query"
        ),
        DnsCandidate(
            id: "adguard",
            name: "AdGuard DNS",
            primaryIP: "94.140.14.14",
            secondaryIP: "94.140.15.15",
            dohURL: "https://dns.adguard-dns.com/dns-query"
        ),
    ]

    /// Saf Swift RFC 1035 UDP DNS "A" kaydı sorgu paketi oluşturur.
    static func buildDnsQueryPacket(domain: String = "cloudflare.com", transactionID: UInt16 = UInt16.random(in: 1...UInt16.max)) -> Data {
        var packet = Data()
        var tx = transactionID.bigEndian
        packet.append(Data(bytes: &tx, count: 2))
        // Flags: 0x0100 (Standard query + Recursion Desired)
        packet.append(contentsOf: [0x01, 0x00])
        // QDCOUNT=1, ANCOUNT=0, NSCOUNT=0, ARCOUNT=0
        packet.append(contentsOf: [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        for label in domain.split(separator: ".") {
            let bytes = Array(label.utf8)
            guard bytes.count < 64 else { continue }
            packet.append(UInt8(bytes.count))
            packet.append(contentsOf: bytes)
        }
        packet.append(0x00) // QNAME sonlandırıcı
        // QTYPE = A (1), QCLASS = IN (1)
        packet.append(contentsOf: [0x00, 0x01, 0x00, 0x01])
        return packet
    }

    /// RFC 1035 DNS yanıt paketinden ilk A kaydı IPv4 adresini ve işlem kimliği uyumunu çözer.
    static func parseDnsResponseIPv4(data: Data, expectedTransactionID: UInt16) -> String? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data)
        let tx = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        guard tx == expectedTransactionID else { return nil }
        let qdCount = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
        let anCount = (UInt16(bytes[6]) << 8) | UInt16(bytes[7])
        guard anCount > 0 else { return nil }

        var offset = 12
        for _ in 0..<qdCount {
            guard let next = skipDnsName(bytes: bytes, start: offset) else { return nil }
            offset = next + 4
            guard offset <= bytes.count else { return nil }
        }

        for _ in 0..<anCount {
            guard let nameEnd = skipDnsName(bytes: bytes, start: offset),
                  nameEnd + 10 <= bytes.count else { return nil }
            let rrType = (UInt16(bytes[nameEnd]) << 8) | UInt16(bytes[nameEnd + 1])
            let rdLen = Int((UInt16(bytes[nameEnd + 8]) << 8) | UInt16(bytes[nameEnd + 9]))
            let rdataStart = nameEnd + 10
            guard rdataStart + rdLen <= bytes.count else { return nil }
            if rrType == 1 && rdLen == 4 {
                return "\(bytes[rdataStart]).\(bytes[rdataStart + 1]).\(bytes[rdataStart + 2]).\(bytes[rdataStart + 3])"
            }
            offset = rdataStart + rdLen
        }
        return nil
    }

    private static func skipDnsName(bytes: [UInt8], start: Int) -> Int? {
        var pos = start
        var jumps = 0
        while pos < bytes.count {
            let len = Int(bytes[pos])
            if len == 0 {
                return pos + 1
            }
            if (len & 0xC0) == 0xC0 {
                return pos + 2 <= bytes.count ? pos + 2 : nil
            }
            pos += 1 + len
            jumps += 1
            if jumps > 64 { return nil }
        }
        return nil
    }

    static func queryDnsUDP(serverIP: String, domain: String = "cloudflare.com", timeoutSec: TimeInterval = 2.0) async -> Double? {
        let txID = UInt16.random(in: 1...UInt16.max)
        let queryData = buildDnsQueryPacket(domain: domain, transactionID: txID)
        guard let port = NWEndpoint.Port(rawValue: 53) else { return nil }

        return await withCheckedContinuation { continuation in
            let once = LockedOnce()
            let conn = NWConnection(host: NWEndpoint.Host(serverIP), port: port, using: .udp)
            let q = DispatchQueue(label: "com.netpulse.ios.dnsprobe.\(UUID().uuidString.prefix(8))")
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
                    conn.send(content: queryData, completion: .contentProcessed { sendErr in
                        if sendErr != nil {
                            if once.tryClaim() {
                                timeoutWork.cancel()
                                conn.cancel()
                                continuation.resume(returning: nil)
                            }
                            return
                        }
                        conn.receiveMessage { data, _, _, recvErr in
                            if recvErr == nil,
                               let payload = data,
                               parseDnsResponseIPv4(data: payload, expectedTransactionID: txID) != nil {
                                if once.tryClaim() {
                                    timeoutWork.cancel()
                                    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000.0
                                    conn.cancel()
                                    continuation.resume(returning: (elapsedMs * 10).rounded() / 10)
                                }
                            } else if once.tryClaim() {
                                timeoutWork.cancel()
                                conn.cancel()
                                continuation.resume(returning: nil)
                            }
                        }
                    })
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

    static func benchmarkAll() async -> DnsBenchmarkSummary {
        let results: [DnsProviderResult] = await withTaskGroup(of: (Int, DnsProviderResult).self) { group in
            for (idx, p) in providers.enumerated() {
                group.addTask {
                    var times: [Double] = []
                    for _ in 0..<2 {
                        if let ms = await queryDnsUDP(serverIP: p.primaryIP, domain: "cloudflare.com", timeoutSec: 2.0) {
                            times.append(ms)
                        }
                    }
                    let avg = times.isEmpty ? nil : (times.reduce(0, +) / Double(times.count) * 10).rounded() / 10
                    return (
                        idx,
                        DnsProviderResult(
                            id: p.id,
                            name: p.name,
                            primaryIP: p.primaryIP,
                            secondaryIP: p.secondaryIP,
                            dohURL: p.dohURL,
                            reachable: !times.isEmpty,
                            avgMs: avg,
                            minMs: times.min(),
                            maxMs: times.max()
                        )
                    )
                }
            }
            var pairs: [(Int, DnsProviderResult)] = []
            for await item in group { pairs.append(item) }
            return pairs.sorted(by: { $0.0 < $1.0 }).map(\.1)
        }

        let fastest = results
            .filter { $0.reachable && $0.avgMs != nil }
            .min(by: { ($0.avgMs ?? .infinity) < ($1.avgMs ?? .infinity) })

        return DnsBenchmarkSummary(
            timestamp: Date().timeIntervalSince1970,
            fastestProvider: fastest,
            results: results
        )
    }

    /// iOS Ayarlar -> Genel -> VPN ve Aygıt Yönetimi üzerinden kurulabilen resmi Apple DoH (.mobileconfig) profili üretir.
    static func generateDoHMobileConfig(providerName: String, primaryIP: String, secondaryIP: String?, dohURL: String) -> String {
        let profileUUID = UUID().uuidString.uppercased()
        let dnsUUID = UUID().uuidString.uppercased()
        let escName = xmlEscape(providerName)
        let escPrimary = xmlEscape(primaryIP)
        let escDoh = xmlEscape(dohURL)
        let secondaryXML = secondaryIP.map { "\t\t\t\t\t<string>\(xmlEscape($0))</string>\n" } ?? ""

        return """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>PayloadContent</key>
	<array>
		<dict>
			<key>DNSSettings</key>
			<dict>
				<key>DNSProtocol</key>
				<string>HTTPS</string>
				<key>ServerAddresses</key>
				<array>
					<string>\(escPrimary)</string>
\(secondaryXML)\t\t\t\t</array>
				<key>ServerURL</key>
				<string>\(escDoh)</string>
			</dict>
			<key>PayloadDescription</key>
			<string>NetPulse tarafından önerilen şifreli DNS (DoH) ayarı.</string>
			<key>PayloadDisplayName</key>
			<string>NetPulse DoH - \(escName)</string>
			<key>PayloadIdentifier</key>
			<string>com.netpulse.ios.doh.\(dnsUUID)</string>
			<key>PayloadType</key>
			<string>com.apple.dnsSettings.managed</string>
			<key>PayloadUUID</key>
			<string>\(dnsUUID)</string>
			<key>PayloadVersion</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>PayloadDescription</key>
	<string>\(escName) DNS-over-HTTPS profili (Ayarlar &gt; İndirilen Profil üzerinden kurulabilir).</string>
	<key>PayloadDisplayName</key>
	<string>NetPulse DNS - \(escName)</string>
	<key>PayloadIdentifier</key>
	<string>com.netpulse.ios.profile.\(profileUUID)</string>
	<key>PayloadType</key>
	<string>Configuration</string>
	<key>PayloadUUID</key>
	<string>\(profileUUID)</string>
	<key>PayloadVersion</key>
	<integer>1</integer>
</dict>
</plist>
"""
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
