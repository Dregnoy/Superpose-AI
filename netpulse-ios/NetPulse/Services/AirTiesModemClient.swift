import Foundation

/// AirTies `/cgi-bin/webapp` çoklu `<key>/<value>` bloklarını çözen XML ayrıştırıcı.
final class AirTiesXMLParser: NSObject, XMLParserDelegate {
    private var values: [String: String] = [:]
    private var sessionError: String?

    private var rootElementSeen = false
    private var currentInstanceTag: String?
    private var currentSubTag: String?
    private var pendingKey: String?
    private var charBuffer = ""

    static func parse(_ xmlText: String) -> (values: [String: String], sessionError: String?) {
        let cleaned = xmlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let data = cleaned.data(using: .utf8) else {
            return ([:], "Modemden boş yanıt alındı.")
        }

        let handler = AirTiesXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        let ok = parser.parse()
        if !ok && handler.values.isEmpty {
            return ([:], "Modem yanıtı XML olarak çözümlenemedi (oturum kapanmış olabilir).")
        }
        return (handler.values, handler.sessionError)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if !rootElementSeen {
            rootElementSeen = true
            return
        }
        if currentInstanceTag == nil {
            currentInstanceTag = elementName
            pendingKey = nil
        } else {
            currentSubTag = elementName
            charBuffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentSubTag != nil {
            charBuffer.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let inst = currentInstanceTag else { return }
        if currentSubTag == elementName {
            let lowSub = elementName.lowercased()
            let trimmed = charBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if lowSub == "key" {
                pendingKey = trimmed
            } else if lowSub == "value", let k = pendingKey, !k.isEmpty {
                values["\(inst).\(k)"] = trimmed
                values[k] = trimmed
                if inst.lowercased() == "webapp" && k.lowercased() == "error" {
                    values["webapp.error"] = trimmed
                    // AirTies /js/ui.js kuralı: "1" oturum hatası, "4" XML sözdizimi hatası; "23" yalnızca şifre değiştirme uyarısıdır.
                    if trimmed == "1" || trimmed == "4" {
                        sessionError = trimmed
                    }
                }
                pendingKey = nil
            }
            currentSubTag = nil
            charBuffer = ""
        } else if inst == elementName {
            currentInstanceTag = nil
            pendingKey = nil
        }
    }
}

private final class LoginCookieCaptureDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [String: String] = [:]

    func ingestCookies(from response: URLResponse?) {
        guard let http = response as? HTTPURLResponse else { return }
        var pairs: [(String, String)] = []
        for (kAny, vAny) in http.allHeaderFields {
            if String(describing: kAny).lowercased() == "set-cookie" {
                let raw = String(describing: vAny)
                for chunk in raw.components(separatedBy: ",") {
                    let firstPart = chunk.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
                    let kv = firstPart.split(separator: "=", maxSplits: 1)
                    if kv.count == 2 {
                        let name = kv[0].trimmingCharacters(in: .whitespaces)
                        let val = kv[1].trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty, !val.isEmpty {
                            pairs.append((name, val))
                        }
                    }
                }
            }
        }
        guard !pairs.isEmpty else { return }
        lock.lock()
        for (k, v) in pairs { captured[k] = v }
        lock.unlock()
    }

    func cookieHeader() -> String {
        lock.lock()
        defer { lock.unlock() }
        return captured.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        ingestCookies(from: response)
        completionHandler(request)
    }
}

enum AirTiesLoginError: LocalizedError, Equatable {
    case authRejected(String)
    case networkFailure(String)

    var errorDescription: String? {
        switch self {
        case .authRejected(let msg): return msg
        case .networkFailure(let msg): return msg
        }
    }
}

/// AirTies (Air5650TT / Air5650v3TT vb.) gerçek web RPC istemcisi.
final class AirTiesModemClient: Sendable {
    static func parseLoginErrorMessage(finalURL: String, body: String) -> String? {
        let combined = "\(finalURL)\n\(body)"
        if let regex = try? NSRegularExpression(pattern: #"errorcode=(\d+)"#, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)),
           let range = Range(match.range(at: 1), in: combined) {
            let code = String(combined[range])
            switch code {
            case "6":
                return "Modem kullanıcı adı veya şifre hatalı (ErrorCode=6). Modem arayüzüne girdiğiniz bilgileri kontrol edin."
            case "2":
                return "Modem giriş isteği reddedildi (ErrorCode=2)."
            default:
                return "Modem girişi reddedildi (ErrorCode=\(code)). Çok fazla hatalı deneme yaptıysanız 5 dakika bekleyip tekrar deneyin."
            }
        }

        let lowBody = body.lowercased()
        if lowBody.contains("uipostpassword") || lowBody.contains("login_error") || lowBody.contains("login_timer_error") {
            return "Modem kullanıcı adı veya şifre doğrulanamadı."
        }
        return nil
    }

    static func buildDslQueryXML() -> String {
        let queries: [(String, String)] = [
            ("dsl-0", "status"),
            ("dsl-0", "physLinkStatus"),
            ("dsl-0", "downlink"),
            ("dsl-0", "uplink"),
            ("dsl-0", "CRCErrors"),
            ("dsl-0", "ATUCCRCErrors"),
            ("sysmgr-0", "fwversion"),
            ("sysmgr-0", "productid"),
            ("sysmgr-0", "productname"),
        ]
        let inner = queries
            .map { "<query inst=\"\($0.0)\"><key>\($0.1)</key><value></value></query>" }
            .joined(separator: "\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xmlrequest version=\"1.0.1\">\n\(inner)\n</xmlrequest>"
    }

    static func buildRebootXML() -> String {
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xmlrequest version=\"1.0.1\">\n<command inst=\"sysmgr-0\"><key>reboot</key><value></value></command>\n</xmlrequest>"
    }

    func readDslStats(host: String, username: String, password: String) async -> ModemDslStats {
        let now = Date().timeIntervalSince1970
        let cleanHost: String
        do {
            cleanHost = try validatePrivateLANHost(host)
        } catch {
            return ModemDslStats(connected: false, readAt: now, error: error.localizedDescription)
        }

        let delegate = LoginCookieCaptureDelegate()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8.0
        cfg.timeoutIntervalForResource = 12.0
        cfg.httpShouldSetCookies = true
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        do {
            let fallbackCookie = try await login(session: session, delegate: delegate, host: cleanHost, username: username, password: password)
            let rawXML = try await postWebapp(
                session: session,
                host: cleanHost,
                xmlBody: Self.buildDslQueryXML(),
                fallbackCookie: fallbackCookie,
                timeoutSec: 8.0
            )

            let parsed = AirTiesXMLParser.parse(rawXML)
            if parsed.sessionError == "1" {
                return ModemDslStats(connected: false, readAt: now, error: "Modem oturumu doğrulanamadı (webapp error=1). Kullanıcı adı veya şifreyi kontrol edin.")
            }
            if parsed.sessionError == "4" {
                return ModemDslStats(connected: false, readAt: now, error: "Modem XML isteğini çözümleyemedi (webapp error=4).")
            }
            if let err = parsed.sessionError {
                return ModemDslStats(connected: false, readAt: now, error: "Modem oturum/XML hatası: \(err)")
            }

            let vals = parsed.values
            let dslStatus = vals["dsl-0.status.training_stat"] ?? vals["dsl-0.status"] ?? vals["dsl-0.physLinkStatus"]
            let physStatus = vals["dsl-0.physLinkStatus"] ?? vals["dsl-0.status.mode"]
            let downKbps = parseFirstInt(vals["dsl-0.downlink.rate"] ?? vals["dsl-0.downlink"])
            let upKbps = parseFirstInt(vals["dsl-0.uplink.rate"] ?? vals["dsl-0.uplink"])
            let snrDown = parseFirstDouble(vals["dsl-0.downlink.snr"] ?? vals["dsl-0.downlinkSNR"])
            let snrUp = parseFirstDouble(vals["dsl-0.uplink.snr"] ?? vals["dsl-0.uplinkSNR"])
            let attenDown = parseFirstDouble(vals["dsl-0.downlink.attn"] ?? vals["dsl-0.downlinkAttenuation"])
            let attenUp = parseFirstDouble(vals["dsl-0.uplink.attn"] ?? vals["dsl-0.uplinkAttenuation"])
            let crc = parseFirstInt(vals["dsl-0.CRCErrors"])
            let atucCrc = parseFirstInt(vals["dsl-0.ATUCCRCErrors"])
            let model = vals["sysmgr-0.productid"] ?? vals["sysmgr-0.productname"] ?? "AirTies"
            let fw = vals["sysmgr-0.fwversion"]

            var (health, note) = evaluateDslHealth(status: dslStatus, snrDown: snrDown, crcErrors: crc)
            if vals["webapp.error"] == "23",
               dslStatus == nil, snrDown == nil, crc == nil, downKbps == nil {
                health = .unknown
                note = "Modem girişi doğrulandı; modem varsayılan şifre uyarısı (kod 23) döndürdüğü için DSL verileri kısıtlı olabilir."
            }

            return ModemDslStats(
                connected: true,
                routerModel: model,
                firmware: fw,
                dslStatus: dslStatus,
                physLinkStatus: physStatus,
                downlinkKbps: downKbps,
                uplinkKbps: upKbps,
                crcErrors: crc,
                atucCrcErrors: atucCrc,
                snrDownDb: snrDown,
                snrUpDb: snrUp,
                attenDownDb: attenDown,
                attenUpDb: attenUp,
                lineHealth: health,
                healthNote: note,
                readAt: now,
                error: nil
            )
        } catch let authErr as AirTiesLoginError {
            return ModemDslStats(connected: false, readAt: now, error: authErr.localizedDescription)
        } catch {
            return ModemDslStats(connected: false, readAt: now, error: "Modeme erişilemedi: \(error.localizedDescription)")
        }
    }

    func rebootModem(host: String, username: String, password: String, confirmed: Bool) async -> (ok: Bool, message: String) {
        guard confirmed else {
            return (false, "Modemi yeniden başlatmak tüm ev internetini 60–90 sn keser; onay gereklidir.")
        }
        guard let cleanHost = try? validatePrivateLANHost(host) else {
            return (false, "Geçerli bir yerel modem IPv4 adresi gereklidir.")
        }

        let delegate = LoginCookieCaptureDelegate()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8.0
        cfg.httpShouldSetCookies = true
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let fallbackCookie: String
        do {
            fallbackCookie = try await login(session: session, delegate: delegate, host: cleanHost, username: username, password: password)
        } catch {
            return (false, error.localizedDescription)
        }

        do {
            let raw = try await postWebapp(
                session: session,
                host: cleanHost,
                xmlBody: Self.buildRebootXML(),
                fallbackCookie: fallbackCookie,
                timeoutSec: 5.0
            )
            let parsed = AirTiesXMLParser.parse(raw)
            if let err = parsed.sessionError {
                return (false, "Modem yeniden başlatma reddedildi (hata kodu \(err)).")
            }
        } catch {
            // Modem reboot komutunu alınca soketi erken kapatabilir.
        }
        return (true, "Modem yeniden başlatma komutu gönderildi; bağlantının geri gelmesi 60–90 sn sürebilir.")
    }

    private func login(
        session: URLSession,
        delegate: LoginCookieCaptureDelegate,
        host: String,
        username: String,
        password: String
    ) async throws -> String {
        guard let url = URL(string: "http://\(host)/cgi-bin/login") else {
            throw AirTiesLoginError.networkFailure("Geçersiz modem giriş URL'i.")
        }

        let pairs: [(String, String)] = [
            ("redirect", ""),
            ("self", ""),
            ("user", username),
            ("password", password),
            ("gonder", "Tamam"),
        ]
        let formStr = pairs.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = formStr.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("http://\(host)/loginmain.html", forHTTPHeaderField: "Referer")
        req.setValue("http://\(host)", forHTTPHeaderField: "Origin")
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.setValue("NetPulse-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        delegate.ingestCookies(from: resp)
        let finalURL = resp.url?.absoluteString ?? ""
        let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""

        if let errMsg = Self.parseLoginErrorMessage(finalURL: finalURL, body: body) {
            throw AirTiesLoginError.authRejected(errMsg)
        }

        let jarCookies = session.configuration.httpCookieStorage?.cookies(for: url) ?? []
        if !jarCookies.isEmpty {
            return ""
        }
        return delegate.cookieHeader()
    }

    private func postWebapp(
        session: URLSession,
        host: String,
        xmlBody: String,
        fallbackCookie: String,
        timeoutSec: TimeInterval
    ) async throws -> String {
        guard let url = URL(string: "http://\(host)/cgi-bin/webapp") else {
            throw AirTiesLoginError.networkFailure("Geçersiz modem XML adresi.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = xmlBody.data(using: .utf8)
        req.timeoutInterval = timeoutSec
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("http://\(host)/internet/status.html", forHTTPHeaderField: "Referer")
        req.setValue("close", forHTTPHeaderField: "Connection")
        if !fallbackCookie.isEmpty {
            req.setValue(fallbackCookie, forHTTPHeaderField: "Cookie")
        }

        let (data, _) = try await session.data(for: req)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? ""
    }

    private func parseFirstInt(_ text: String?) -> Int? {
        guard let text,
              let regex = try? NSRegularExpression(pattern: #"-?\d+"#),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range, in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private func parseFirstDouble(_ text: String?) -> Double? {
        guard let text,
              let regex = try? NSRegularExpression(pattern: #"-?\d+(?:[.,]\d+)?"#),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range, in: text) else {
            return nil
        }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    private func evaluateDslHealth(status: String?, snrDown: Double?, crcErrors: Int?) -> (DslLineHealth, String) {
        let low = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !low.isEmpty && !["up", "showtime", "connect", "active", "1"].contains(where: { low.contains($0) }) {
            return (.bad, "DSL fiziksel hattı bağlı görünmüyor (Durum: \(status ?? "—")).")
        }
        if (snrDown ?? 99) < 6.0 || (crcErrors ?? 0) >= 1000 {
            return (.bad, "DSL hattında ciddi gürültü (düşük SNR) veya yüksek CRC hatası var.")
        }
        if (snrDown ?? 99) < 9.0 || (crcErrors ?? 0) >= 200 {
            return (.warn, "DSL hattında orta düzey gürültü veya CRC hata birikimi görülüyor.")
        }
        if status != nil || snrDown != nil || crcErrors != nil {
            return (.good, "DSL fiziksel hat değerleri sağlıklı.")
        }
        return (.unknown, "DSL hat değerleri modemden kısmi okundu.")
    }
}
