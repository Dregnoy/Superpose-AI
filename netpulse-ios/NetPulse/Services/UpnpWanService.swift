import Foundation
import Network

private final class UpnpDescriptorParser: NSObject, XMLParserDelegate {
    var friendlyName: String?
    var services: [(serviceType: String, controlURL: String)] = []

    private var insideService = false
    private var currentTag = ""
    private var buffer = ""
    private var currentServiceType = ""
    private var currentControlURL = ""

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        currentTag = local
        buffer = ""
        if local == "service" {
            insideService = true
            currentServiceType = ""
            currentControlURL = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if local == "friendlyName", friendlyName == nil, !trimmed.isEmpty {
            friendlyName = trimmed
        } else if insideService {
            if local == "serviceType" {
                currentServiceType = trimmed
            } else if local == "controlURL" {
                currentControlURL = trimmed
            } else if local == "service" {
                if !currentServiceType.isEmpty, !currentControlURL.isEmpty {
                    services.append((currentServiceType, currentControlURL))
                }
                insideService = false
            }
        }
        buffer = ""
    }
}

private final class SoapValuesParser: NSObject, XMLParserDelegate {
    private let targetTags: Set<String>
    private var currentTag = ""
    private var buffer = ""
    var values: [String: String] = [:]

    init(tags: [String]) {
        self.targetTags = Set(tags)
    }

    func parse(_ data: Data) -> [String: String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        currentTag = targetTags.contains(local) ? local : ""
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !currentTag.isEmpty {
            buffer.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if !currentTag.isEmpty, local == currentTag {
            values[currentTag] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            currentTag = ""
        }
        buffer = ""
    }
}

actor UpnpWanService {
    private var cachedHost: String?
    private var commonControlURL: URL?
    private var commonServiceType = "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1"
    private var wanControlURL: URL?
    private var wanServiceType = "urn:schemas-upnp-org:service:WANIPConnection:1"
    private var routerName: String?

    private var prevBytesRx: UInt64?
    private var prevBytesTx: UInt64?
    private var prevTimestamp: TimeInterval?

    static func computeU32Delta(previous: UInt64, current: UInt64) -> UInt64 {
        if current >= previous {
            return current - previous
        }
        return (0x1_0000_0000 - previous) + current
    }

    func sample(gatewayIP: String?) async -> UpnpRouterInfo {
        guard let rawGW = gatewayIP?.trimmingCharacters(in: .whitespacesAndNewlines),
              let cleanHost = try? validatePrivateLANHost(rawGW) else {
            return UpnpRouterInfo(available: false, note: "Yerel ağ geçidi (modem IP) bulunamadı.")
        }

        if cachedHost != cleanHost || (commonControlURL == nil && wanControlURL == nil) {
            await discover(host: cleanHost)
        }

        guard commonControlURL != nil || wanControlURL != nil else {
            return UpnpRouterInfo(
                available: false,
                routerName: routerName,
                note: "Modem UPnP/IGD portu yanıt vermedi veya kapalı."
            )
        }

        var accessType: String?
        var maxDown: Double?
        var maxUp: Double?
        var routerDown = 0.0
        var routerUp = 0.0

        if let ctrl = commonControlURL {
            if let props = await soapCall(
                controlURL: ctrl,
                serviceType: commonServiceType,
                action: "GetCommonLinkProperties",
                tags: ["NewWANAccessType", "NewLayer1DownstreamMaxBitRate", "NewLayer1UpstreamMaxBitRate"]
            ) {
                accessType = props["NewWANAccessType"]
                if let bps = props["NewLayer1DownstreamMaxBitRate"].flatMap(Double.init), bps > 0 {
                    maxDown = ((bps / 1_000_000.0) * 10).rounded() / 10
                }
                if let bps = props["NewLayer1UpstreamMaxBitRate"].flatMap(Double.init), bps > 0 {
                    maxUp = ((bps / 1_000_000.0) * 10).rounded() / 10
                }
            }

            let rxDict = await soapCall(controlURL: ctrl, serviceType: commonServiceType, action: "GetTotalBytesReceived", tags: ["NewTotalBytesReceived"])
            let txDict = await soapCall(controlURL: ctrl, serviceType: commonServiceType, action: "GetTotalBytesSent", tags: ["NewTotalBytesSent"])
            let now = Date().timeIntervalSince1970
            if let rx = rxDict?["NewTotalBytesReceived"].flatMap(UInt64.init),
               let tx = txDict?["NewTotalBytesSent"].flatMap(UInt64.init) {
                if let pRx = prevBytesRx, let pTx = prevBytesTx, let pTs = prevTimestamp, now > pTs {
                    let dt = now - pTs
                    let dRx = Self.computeU32Delta(previous: pRx, current: rx)
                    let dTx = Self.computeU32Delta(previous: pTx, current: tx)
                    routerDown = (((Double(dRx) * 8.0 / dt) / 1_000_000.0) * 100).rounded() / 100
                    routerUp = (((Double(dTx) * 8.0 / dt) / 1_000_000.0) * 100).rounded() / 100
                }
                prevBytesRx = rx
                prevBytesTx = tx
                prevTimestamp = now
            }
        }

        var wanStatus: String?
        var wanLastError: String?
        var wanUptimeSec: Int?
        var wanExternalIP: String?
        if let wCtrl = wanControlURL {
            if let st = await soapCall(
                controlURL: wCtrl,
                serviceType: wanServiceType,
                action: "GetStatusInfo",
                tags: ["NewConnectionStatus", "NewLastConnectionError", "NewUptime"]
            ) {
                wanStatus = st["NewConnectionStatus"]
                wanLastError = st["NewLastConnectionError"]
                wanUptimeSec = st["NewUptime"].flatMap(Int.init)
            }
            if let ext = await soapCall(
                controlURL: wCtrl,
                serviceType: wanServiceType,
                action: "GetExternalIPAddress",
                tags: ["NewExternalIPAddress"]
            ) {
                wanExternalIP = ext["NewExternalIPAddress"]
            }
        }

        return UpnpRouterInfo(
            available: true,
            routerName: routerName ?? "Modem UPnP",
            accessType: accessType,
            maxDownMbps: maxDown,
            maxUpMbps: maxUp,
            routerDownMbps: routerDown,
            routerUpMbps: routerUp,
            wanStatus: wanStatus,
            wanLastError: wanLastError,
            wanUptimeSec: wanUptimeSec,
            wanExternalIP: wanExternalIP,
            wanControlAvailable: wanControlURL != nil,
            note: nil
        )
    }

    func reconnectWAN(gatewayIP: String?, confirmed: Bool) async -> (ok: Bool, message: String) {
        guard confirmed else {
            return (false, "WAN bağlantısını yenilemek için kullanıcı onayı gereklidir.")
        }
        guard let rawGW = gatewayIP?.trimmingCharacters(in: .whitespacesAndNewlines),
              let cleanHost = try? validatePrivateLANHost(rawGW) else {
            return (false, "Geçerli bir yerel modem IP adresi bulunamadı.")
        }
        if cachedHost != cleanHost || wanControlURL == nil {
            await discover(host: cleanHost)
        }
        guard let wCtrl = wanControlURL else {
            return (false, "Modemde UPnP WANIPConnection/WANPPPConnection kontrol servisi bulunamadı.")
        }

        _ = await soapCall(controlURL: wCtrl, serviceType: wanServiceType, action: "ForceTermination", tags: [])
        try? await Task.sleep(for: .milliseconds(650))
        let reqRes = await soapCall(controlURL: wCtrl, serviceType: wanServiceType, action: "RequestConnection", tags: [])
        if reqRes != nil {
            return (true, "Modeme UPnP WAN bağlantısını yenileme komutu gönderildi; yeni IP/bağlantı kurulması 5–15 sn sürebilir.")
        }
        return (false, "Modem UPnP RequestConnection komutunu reddetti veya desteklemiyor.")
    }

    private func discover(host: String) async {
        cachedHost = host
        commonControlURL = nil
        wanControlURL = nil

        var candidateDescURLs: [URL] = [
            "http://\(host):5555/rootDesc.xml",
            "http://\(host):5000/rootDesc.xml",
            "http://\(host):49152/gatedesc.xml",
            "http://\(host):1900/igd.xml",
        ].compactMap(URL.init(string:))

        if let ssdpLoc = await unicastSSDPLocation(host: host) {
            candidateDescURLs.insert(ssdpLoc, at: 0)
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2.0
        cfg.timeoutIntervalForResource = 3.0
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        for descURL in candidateDescURLs {
            guard let descHost = descURL.host,
                  (try? validatePrivateLANHost(descHost)) == host else {
                continue
            }
            guard let (data, resp) = try? await session.data(from: descURL),
                  let httpResp = resp as? HTTPURLResponse,
                  (200..<300).contains(httpResp.statusCode) else {
                continue
            }

            let parser = UpnpDescriptorParser()
            parser.parse(data)
            if parser.services.isEmpty { continue }

            routerName = parser.friendlyName ?? host
            let base = URL(string: "\(descURL.scheme ?? "http")://\(descURL.host ?? host)\(descURL.port.map { ":\($0)" } ?? "")")
            for svc in parser.services {
                let resolved = URL(string: svc.controlURL, relativeTo: base ?? descURL)?.absoluteURL
                if svc.serviceType.contains("WANCommonInterfaceConfig") {
                    commonServiceType = svc.serviceType
                    commonControlURL = resolved
                } else if svc.serviceType.contains("WANIPConnection") || svc.serviceType.contains("WANPPPConnection") {
                    if wanControlURL == nil || svc.serviceType.contains("WANIPConnection") {
                        wanServiceType = svc.serviceType
                        wanControlURL = resolved
                    }
                }
            }
            if commonControlURL != nil || wanControlURL != nil {
                return
            }
        }
    }

    /// Multicast entitlement gerektirmeden doğrudan modem unicast UDP:1900'e tekil M-SEARCH dener.
    private func unicastSSDPLocation(host: String) async -> URL? {
        guard let port = NWEndpoint.Port(rawValue: 1900) else { return nil }
        let msg = "M-SEARCH * HTTP/1.1\r\nHOST: \(host):1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n"
        guard let payload = msg.data(using: .utf8) else { return nil }

        return await withCheckedContinuation { continuation in
            let once = LockedOnce()
            let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
            let q = DispatchQueue(label: "com.netpulse.ios.ssdp.\(UUID().uuidString.prefix(8))")

            let timeoutWork = DispatchWorkItem {
                if once.tryClaim() {
                    conn.cancel()
                    continuation.resume(returning: nil)
                }
            }
            q.asyncAfter(deadline: .now() + 1.1, execute: timeoutWork)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: payload, completion: .contentProcessed { err in
                        if err != nil {
                            if once.tryClaim() {
                                timeoutWork.cancel()
                                conn.cancel()
                                continuation.resume(returning: nil)
                            }
                            return
                        }
                        conn.receiveMessage { data, _, _, _ in
                            var found: URL?
                            if let data, let text = String(data: data, encoding: .utf8) {
                                for line in text.split(whereSeparator: \.isNewline) {
                                    let str = String(line).trimmingCharacters(in: .whitespaces)
                                    if str.lowercased().hasPrefix("location:") {
                                        let urlText = str.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                                        found = URL(string: urlText)
                                        break
                                    }
                                }
                            }
                            if once.tryClaim() {
                                timeoutWork.cancel()
                                conn.cancel()
                                continuation.resume(returning: found)
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

    private func soapCall(controlURL: URL, serviceType: String, action: String, tags: [String]) async -> [String: String]? {
        let envelope = """
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:\(action) xmlns:u="\(serviceType)"/>
  </s:Body>
</s:Envelope>
"""
        var req = URLRequest(url: controlURL)
        req.httpMethod = "POST"
        req.httpBody = envelope.data(using: .utf8)
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.timeoutInterval = 3.0

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3.0
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        guard let (data, resp) = try? await session.data(for: req),
              let httpResp = resp as? HTTPURLResponse,
              (200..<300).contains(httpResp.statusCode) else {
            return nil
        }
        return SoapValuesParser(tags: tags).parse(data)
    }
}
