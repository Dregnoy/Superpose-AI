import Darwin
import Foundation
import Network
import Security

/// Local Wi-Fi Smart TV remote service supporting:
/// - Google / Android TV Remote Protocol v2 (mTLS ports 6467/6466)
/// - Samsung Tizen Smart TV WebSocket API (`wss://:8002` / `ws://:8001` with `ProcessMouseDevice`)
/// - LG webOS SSAP + Magic Remote Pointer Input Socket (`wss://:3001` / `ws://:3000`)
/// - Vestel SmartCenter (HTTP-XML port 56789)
final class SmartTVRemoteService: NSObject {

    // MARK: Callbacks (delivered on MainActor)
    var onStateChange: (@MainActor (SmartTVConnectionState) -> Void)?
    var onDiscoveredTVsChange: (@MainActor ([SmartTVEndpoint]) -> Void)?
    var onDiagnosticEvent: (@MainActor (HIDDiagnosticEvent) -> Void)?
    var onPacketSent: (@MainActor () -> Void)?

    // MARK: Queues & Bonjour Discovery
    private let queue = DispatchQueue(label: "com.bluepad.smarttv.remote")

    // Bonjour Discovery (must stay on Main RunLoop)
    private var atvBrowser: NetServiceBrowser?
    private var castBrowser: NetServiceBrowser?
    private var samsungBrowser: NetServiceBrowser?
    private var airplayBrowser: NetServiceBrowser?
    private var resolvingServices: Set<NetService> = []
    private var discoveredByKey: [String: SmartTVEndpoint] = [:]

    // Shared Session State
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var activeHost: String = ""
    private var activeName: String = ""
    private var activeKind: SmartTVKind = .androidTV
    private var activeClientName: String = "BluePad"
    private var isRemoteConnected: Bool = false

    // Android TV Remote v2 State
    private var remoteConnection: NWConnection?
    private var pairingConnection: NWConnection?
    private var remoteBuffer = Data()
    private var pairingBuffer = Data()
    private var activeClientCert: SecCertificate?
    private var activeServerCert: SecCertificate?
    private var negotiatedFeatures: UInt64 = AndroidTVWireMessages.defaultFeatureMask
    private var imeCounter: Int32 = 0
    private var imeFieldCounter: Int32 = 0
    private var hasReceivedRemoteStart: Bool = false

    // Samsung Tizen & LG webOS WebSocket State
    private var wsSession: URLSession?
    private var mainWsTask: URLSessionWebSocketTask?
    private var pointerWsTask: URLSessionWebSocketTask?
    private var lgRequestCounter: Int = 1

    // Samsung virtual mouse state (1920x1080 logical canvas, 30 Hz coalesced)
    private var samsungPointerX: Int = 960
    private var samsungPointerY: Int = 540
    private var pendingSamsungDX: Int = 0
    private var pendingSamsungDY: Int = 0
    private var lastSamsungFlushTime: CFAbsoluteTime = 0
    private var samsungFlushScheduled: Bool = false

    // LG webOS pointer socket coalesced delta state (30 Hz)
    private var pendingLGDX: Int = 0
    private var pendingLGDY: Int = 0
    private var pendingLGButtonDown: Bool = false
    private var lastLGFlushTime: CFAbsoluteTime = 0
    private var lgFlushScheduled: Bool = false
    private var isRequestingLGPointerSocket: Bool = false

    // MARK: Discovery (Bonjour)

    func startDiscovery() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopDiscoveryOnMain()

            self.atvBrowser = self.makeBrowser(type: "_androidtvremote2._tcp.")
            self.castBrowser = self.makeBrowser(type: "_googlecast._tcp.")
            self.samsungBrowser = self.makeBrowser(type: "_samsungmsf._tcp.")
            self.airplayBrowser = self.makeBrowser(type: "_airplay._tcp.")

            self.emitLog(.ble, "Smart TV yerel ağ keşfi başlatıldı (Android TV, Samsung, LG).")
        }
    }

    private func makeBrowser(type: String) -> NetServiceBrowser {
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.searchForServices(ofType: type, inDomain: "local.")
        return browser
    }

    func stopDiscovery() {
        DispatchQueue.main.async { [weak self] in
            self?.stopDiscoveryOnMain()
        }
    }

    private func stopDiscoveryOnMain() {
        for browser in [atvBrowser, castBrowser, samsungBrowser, airplayBrowser] {
            browser?.stop()
            browser?.delegate = nil
        }
        atvBrowser = nil
        castBrowser = nil
        samsungBrowser = nil
        airplayBrowser = nil

        for service in resolvingServices {
            service.stop()
            service.delegate = nil
        }
        resolvingServices.removeAll()
    }

    // MARK: Connect / Pairing / Disconnect

    func connect(host: String, name: String?, kind: SmartTVKind, deviceName: String) {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let resolvedName = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? name!.trimmingCharacters(in: .whitespacesAndNewlines)
            : cleanHost
        let cleanClient = deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "BluePad"
            : deviceName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanHost.isEmpty else {
            emitState(.failed("TV IP adresi boş olamaz"))
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            self.teardownAllConnections(emitDisconnected: false)
            self.activeHost = cleanHost
            self.activeName = resolvedName
            self.activeKind = kind
            self.activeClientName = cleanClient

            switch kind {
            case .androidTV:
                self.startAndroidTVRemoteSession(allowPairingFallback: true)
            case .samsungTizen:
                self.connectSamsungTizen(secure: true, allowFallback: true)
            case .lgWebOS:
                self.connectLGWebOS(secure: true, allowFallback: true)
            case .vestel:
                self.connectVestelTV()
            }
        }
    }

    func submitPairingCode(_ rawCode: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let pairingConn = self.pairingConnection else {
                self.emitState(.failed("Aktif eşleştirme oturumu bulunamadı"))
                return
            }
            guard let clientCert = self.activeClientCert,
                  let serverCert = self.activeServerCert,
                  let clientKeys = AndroidTVCrypto.extractRSAPublicKey(from: clientCert),
                  let serverKeys = AndroidTVCrypto.extractRSAPublicKey(from: serverCert) else {
                self.emitState(.failed("TV veya iPhone TLS sertifikası okunamadı"))
                return
            }

            let secretResult = AndroidTVCrypto.computePairingSecret(
                clientModulus: clientKeys.modulus,
                clientExponent: clientKeys.exponent,
                serverModulus: serverKeys.modulus,
                serverExponent: serverKeys.exponent,
                hexCode: rawCode
            )

            switch secretResult {
            case .failure(let err):
                let message = err.localizedDescription
                self.emitLog(.error, "TV PIN hatası: \(message)")
                self.emitState(.awaitingPairingCode(tvName: self.activeName, host: self.activeHost))
                return
            case .success(let digest):
                self.emitState(.verifyingCode)
                self.emitLog(.gatt, "TV PIN doğrulama özeti gönderiliyor...")
                let framed = ProtobufWire.frame(AndroidTVWireMessages.pairingSecret(digest))
                pairingConn.send(content: framed, completion: .contentProcessed { [weak self] error in
                    if let error {
                        self?.handlePairingFailure("PIN gönderilemedi: \(error.localizedDescription)")
                    }
                })
            }
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.teardownAllConnections(emitDisconnected: true)
            self.emitLog(.ble, "Smart TV bağlantısı kesildi.")
        }
    }

    private func teardownAllConnections(emitDisconnected: Bool) {
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil

        remoteConnection?.stateUpdateHandler = nil
        remoteConnection?.cancel()
        remoteConnection = nil
        remoteBuffer.removeAll()

        pairingConnection?.stateUpdateHandler = nil
        pairingConnection?.cancel()
        pairingConnection = nil
        pairingBuffer.removeAll()

        mainWsTask?.cancel(with: .normalClosure, reason: nil)
        mainWsTask = nil
        pointerWsTask?.cancel(with: .normalClosure, reason: nil)
        pointerWsTask = nil
        wsSession?.invalidateAndCancel()
        wsSession = nil

        pendingSamsungDX = 0
        pendingSamsungDY = 0
        samsungFlushScheduled = false
        samsungPointerX = 960
        samsungPointerY = 540

        pendingLGDX = 0
        pendingLGDY = 0
        pendingLGButtonDown = false
        lgFlushScheduled = false
        isRequestingLGPointerSocket = false

        activeServerCert = nil
        hasReceivedRemoteStart = false
        isRemoteConnected = false

        if emitDisconnected {
            emitState(.disconnected)
        }
    }

    // MARK: Unified Input & Mouse Pointer Routing

    func sendMouseMove(dx: Int, dy: Int, buttonDown: Bool = false) {
        guard dx != 0 || dy != 0 else { return }
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .samsungTizen:
                self.pendingSamsungDX += dx
                self.pendingSamsungDY += dy
                self.flushSamsungMouseIfNeeded()
            case .lgWebOS:
                self.pendingLGDX += dx
                self.pendingLGDY += dy
                self.pendingLGButtonDown = buttonDown
                self.flushLGMouseIfNeeded()
            case .androidTV, .vestel:
                break
            }
        }
    }

    func sendMouseClick(_ button: HIDMouseButton) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .samsungTizen:
                self.flushSamsungMouseNow()
                if button.contains(.right) || button.contains(.back) {
                    self.sendSamsungTextMessage(SamsungTizenProtocol.mouseClickPayload(rightClick: true), label: "Samsung Sağ Tık")
                } else if button.contains(.middle) {
                    self.sendSamsungTextMessage(SamsungTizenProtocol.remoteKeyPayload("KEY_HOME"), label: "Samsung Ana Sayfa")
                } else {
                    self.sendSamsungTextMessage(SamsungTizenProtocol.mouseClickPayload(rightClick: false), label: "Samsung Sol Tık")
                }
            case .lgWebOS:
                self.flushLGMouseNow()
                if button.contains(.right) || button.contains(.back) {
                    self.sendLGPointerMessage(LGWebOSProtocol.pointerButtonMessage("BACK"), label: "LG Geri")
                } else if button.contains(.middle) {
                    self.sendLGPointerMessage(LGWebOSProtocol.pointerButtonMessage("HOME"), label: "LG Ana Sayfa")
                } else {
                    self.sendLGPointerMessage(LGWebOSProtocol.pointerClickMessage(), label: "LG İmleç Tık")
                }
            case .androidTV, .vestel:
                break
            }
        }
    }

    func sendMouseScroll(wheel: Int, hWheel: Int) {
        guard wheel != 0 || hWheel != 0 else { return }
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .lgWebOS:
                self.sendLGPointerMessage(LGWebOSProtocol.pointerScrollMessage(dx: hWheel, dy: wheel), label: "LG Kaydırma")
            case .samsungTizen:
                if wheel != 0 {
                    let key = wheel > 0 ? "KEY_UP" : "KEY_DOWN"
                    for _ in 0..<min(3, abs(wheel)) {
                        self.sendSamsungTextMessage(SamsungTizenProtocol.remoteKeyPayload(key), label: "Samsung Kaydır")
                    }
                }
                if hWheel != 0 {
                    let key = hWheel > 0 ? "KEY_RIGHT" : "KEY_LEFT"
                    for _ in 0..<min(3, abs(hWheel)) {
                        self.sendSamsungTextMessage(SamsungTizenProtocol.remoteKeyPayload(key), label: "Samsung Yatay")
                    }
                }
            case .androidTV, .vestel:
                break
            }
        }
    }

    func sendKey(hidKeyCode: HIDKeyCode) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .androidTV:
                if let atvKey = AndroidTVKeyCode.from(hidKeyCode: hidKeyCode) {
                    self.sendAndroidTVKeyInternal(atvKey)
                }
            case .samsungTizen:
                if let key = SamsungTizenProtocol.keyCode(for: hidKeyCode) {
                    self.sendSamsungTextMessage(SamsungTizenProtocol.remoteKeyPayload(key), label: "Samsung \(key)")
                }
            case .lgWebOS:
                if hidKeyCode == .pageUp {
                    self.sendLGSSAPRequest(uri: "ssap://tv/channelUp", label: "LG Kanal +")
                } else if hidKeyCode == .pageDown {
                    self.sendLGSSAPRequest(uri: "ssap://tv/channelDown", label: "LG Kanal -")
                } else if hidKeyCode == .backspace {
                    self.sendLGSSAPRequest(uri: "ssap://com.webos.service.ime/deleteCharacters", payload: ["count": 1], label: "LG Sil")
                } else if let btn = LGWebOSProtocol.buttonName(for: hidKeyCode) {
                    self.sendLGPointerMessage(LGWebOSProtocol.pointerButtonMessage(btn), label: "LG \(btn)")
                }
            case .vestel:
                if let vestelKey = VestelKeyCode.from(hidKeyCode: hidKeyCode) {
                    self.sendVestelKeyInternal(vestelKey)
                }
            }
        }
    }

    func sendConsumer(_ usage: HIDConsumerUsage) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .androidTV:
                if let atvKey = AndroidTVKeyCode.from(consumerUsage: usage) {
                    self.sendAndroidTVKeyInternal(atvKey)
                }
            case .samsungTizen:
                if let key = SamsungTizenProtocol.keyCode(for: usage) {
                    self.sendSamsungTextMessage(SamsungTizenProtocol.remoteKeyPayload(key), label: "Samsung \(key)")
                }
            case .lgWebOS:
                if let cmd = LGWebOSProtocol.ssapCommand(for: usage) {
                    self.sendLGSSAPRequest(uri: cmd.uri, payload: cmd.payload, label: "LG \(usage.displayName)")
                } else if let btn = LGWebOSProtocol.buttonName(for: usage) {
                    self.sendLGPointerMessage(LGWebOSProtocol.pointerButtonMessage(btn), label: "LG \(btn)")
                }
            case .vestel:
                if let vestelKey = VestelKeyCode.from(consumerUsage: usage) {
                    self.sendVestelKeyInternal(vestelKey)
                }
            }
        }
    }

    func sendSystem(_ usage: HIDSystemUsage) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .androidTV:
                if let atvKey = AndroidTVKeyCode.from(systemUsage: usage) {
                    self.sendAndroidTVKeyInternal(atvKey)
                }
            case .samsungTizen:
                if let key = SamsungTizenProtocol.keyCode(for: usage) {
                    self.sendSamsungTextMessage(SamsungTizenProtocol.remoteKeyPayload(key), label: "Samsung \(key)")
                }
            case .lgWebOS:
                if let cmd = LGWebOSProtocol.ssapCommand(for: usage) {
                    self.sendLGSSAPRequest(uri: cmd.uri, payload: cmd.payload, label: "LG Güç")
                }
            case .vestel:
                if let vestelKey = VestelKeyCode.from(systemUsage: usage) {
                    self.sendVestelKeyInternal(vestelKey)
                }
            }
        }
    }

    func sendText(_ text: String, appendEnter: Bool = false) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .androidTV:
                if !text.isEmpty {
                    let msg = AndroidTVWireMessages.remoteImeText(
                        text,
                        imeCounter: self.imeCounter,
                        fieldCounter: self.imeFieldCounter
                    )
                    self.sendRemoteMessage(msg, label: "TV Metin (\(text.count) kr)")
                }
                if appendEnter {
                    self.sendAndroidTVKeyInternal(.enter)
                }
            case .samsungTizen:
                if !text.isEmpty {
                    self.sendSamsungTextMessage(SamsungTizenProtocol.inputStringPayload(text), label: "Samsung Metin (\(text.count) kr)")
                }
                if appendEnter {
                    self.sendSamsungTextMessage(SamsungTizenProtocol.remoteKeyPayload("KEY_ENTER"), label: "Samsung Enter")
                }
            case .lgWebOS:
                if !text.isEmpty {
                    self.sendLGSSAPRequest(
                        uri: "ssap://com.webos.service.ime/insertText",
                        payload: ["text": text, "replace": 0],
                        label: "LG Metin (\(text.count) kr)"
                    )
                }
                if appendEnter {
                    self.sendLGSSAPRequest(uri: "ssap://com.webos.service.ime/sendEnterKey", label: "LG Enter")
                }
            case .vestel:
                if appendEnter {
                    self.sendVestelKeyInternal(.ok)
                }
            }
        }
    }

    func launchApp(url: String) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .androidTV:
                let msg = AndroidTVWireMessages.remoteAppLinkLaunch(url)
                self.sendRemoteMessage(msg, label: "TV Uygulama Aç")
            case .samsungTizen:
                if let appID = SamsungTizenProtocol.appID(forAppURL: url) {
                    self.sendSamsungTextMessage(SamsungTizenProtocol.launchAppPayload(appID: appID), label: "Samsung Uygulama")
                }
            case .lgWebOS:
                if let appID = LGWebOSProtocol.appID(forAppURL: url) {
                    self.sendLGSSAPRequest(
                        uri: "ssap://system.launcher/launch",
                        payload: ["id": appID],
                        label: "LG Uygulama Aç"
                    )
                }
            case .vestel:
                break
            }
        }
    }

    func sendInputSource() {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .androidTV:
                self.sendAndroidTVKeyInternal(.tvInput)
            case .samsungTizen:
                self.sendSamsungTextMessage(SamsungTizenProtocol.remoteKeyPayload("KEY_SOURCE"), label: "Samsung Kaynak")
            case .lgWebOS:
                self.sendLGPointerMessage(LGWebOSProtocol.pointerButtonMessage("MENU"), label: "LG Menü / Kaynak")
            case .vestel:
                self.sendVestelKeyInternal(.source)
            }
        }
    }

    // MARK: Samsung Tizen WebSocket (Port 8002 WSS / 8001 WS)

    private func connectSamsungTizen(secure: Bool, allowFallback: Bool) {
        let tokenKey = "com.bluepad.samsung.token.\(activeHost)"
        let savedToken = UserDefaults.standard.string(forKey: tokenKey)
        guard let url = SamsungTizenProtocol.webSocketURL(
            host: activeHost,
            clientName: activeClientName,
            token: savedToken,
            secure: secure
        ) else {
            emitState(.failed("Geçersiz Samsung TV adresi"))
            return
        }

        mainWsTask?.cancel(with: .normalClosure, reason: nil)
        mainWsTask = nil
        wsSession?.invalidateAndCancel()

        let session = URLSession(configuration: .ephemeral, delegate: LocalNetworkTLSDelegate.shared, delegateQueue: nil)
        wsSession = session
        let task = session.webSocketTask(with: url)
        mainWsTask = task

        emitState(.connecting(activeName))
        emitLog(.ble, "Samsung TV'ye bağlanılıyor (\(url.absoluteString))...")

        connectTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.mainWsTask === task, !self.isRemoteConnected else { return }
            task.cancel(with: .normalClosure, reason: nil)
            if allowFallback && secure {
                self.emitLog(.ble, "Samsung 8002 yanıt vermedi; 8001 deneniyor...")
                self.connectSamsungTizen(secure: false, allowFallback: false)
            } else {
                self.teardownAllConnections(emitDisconnected: false)
                self.emitState(.failed("Samsung TV yanıt vermedi veya onay reddedildi"))
            }
        }
        connectTimeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + (savedToken == nil ? 25.0 : 6.0), execute: timeout)

        task.resume()
        receiveSamsungMessage(on: task, tokenKey: tokenKey, secure: secure, allowFallback: allowFallback)
    }

    private func receiveSamsungMessage(
        on task: URLSessionWebSocketTask,
        tokenKey: String,
        secure: Bool,
        allowFallback: Bool
    ) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.mainWsTask === task else { return }
                switch result {
                case .failure(let error):
                    if !self.isRemoteConnected && allowFallback && secure {
                        self.emitLog(.ble, "Samsung WSS hatası (\(error.localizedDescription)); 8001 deneniyor...")
                        self.connectSamsungTizen(secure: false, allowFallback: false)
                    } else if !self.isRemoteConnected {
                        self.teardownAllConnections(emitDisconnected: false)
                        self.emitState(.failed("Samsung TV: \(error.localizedDescription)"))
                    } else {
                        self.teardownAllConnections(emitDisconnected: true)
                        self.emitLog(.error, "Samsung TV bağlantısı kesildi: \(error.localizedDescription)")
                    }

                case .success(let message):
                    if case .string(let text) = message {
                        let parsed = SamsungTizenProtocol.parseConnectToken(from: text)
                        if parsed.connected {
                            self.connectTimeoutWorkItem?.cancel()
                            self.connectTimeoutWorkItem = nil
                            if let token = parsed.token {
                                UserDefaults.standard.set(token, forKey: tokenKey)
                            }
                            self.isRemoteConnected = true
                            self.samsungPointerX = 960
                            self.samsungPointerY = 540
                            self.emitState(.connected(tvName: self.activeName, host: self.activeHost, kind: .samsungTizen))
                            self.emitLog(.gatt, "Samsung TV bağlantısı hazır (Fare + Klavye aktif).")
                        } else if !self.isRemoteConnected && text.contains("ms.channel.unauthorized") {
                            self.teardownAllConnections(emitDisconnected: false)
                            self.emitState(.failed("Samsung TV bağlantıyı reddetti"))
                            return
                        } else if !self.isRemoteConnected {
                            self.emitState(.awaitingTVApproval(tvName: self.activeName, host: self.activeHost, kind: .samsungTizen))
                        }
                    }
                    self.receiveSamsungMessage(on: task, tokenKey: tokenKey, secure: secure, allowFallback: allowFallback)
                }
            }
        }
    }

    private func flushSamsungMouseIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        if (now - lastSamsungFlushTime) >= 0.032 {
            flushSamsungMouseNow()
        } else if !samsungFlushScheduled {
            samsungFlushScheduled = true
            let delay = max(0.01, 0.032 - (now - lastSamsungFlushTime))
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.samsungFlushScheduled = false
                self?.flushSamsungMouseNow()
            }
        }
    }

    private func flushSamsungMouseNow() {
        guard isRemoteConnected, activeKind == .samsungTizen else { return }
        let dx = pendingSamsungDX
        let dy = pendingSamsungDY
        guard dx != 0 || dy != 0 else { return }
        pendingSamsungDX = 0
        pendingSamsungDY = 0
        lastSamsungFlushTime = CFAbsoluteTimeGetCurrent()

        samsungPointerX = max(0, min(1920, samsungPointerX + dx))
        samsungPointerY = max(0, min(1080, samsungPointerY + dy))
        let tsMs = Int64(Date().timeIntervalSince1970 * 1000)
        sendSamsungTextMessage(
            SamsungTizenProtocol.mouseMovePayload(x: samsungPointerX, y: samsungPointerY, timestampMs: tsMs),
            label: nil
        )
    }

    private func sendSamsungTextMessage(_ text: String, label: String?) {
        guard let task = mainWsTask, isRemoteConnected else { return }
        task.send(.string(text)) { [weak self] error in
            if let error {
                self?.emitLog(.error, "Samsung TX hatası: \(error.localizedDescription)")
            } else {
                self?.notifyPacketSent()
                if let label {
                    self?.emitLog(.tx, label)
                }
            }
        }
    }

    // MARK: LG webOS SSAP + Pointer Socket (Port 3001 WSS / 3000 WS)

    private func connectLGWebOS(secure: Bool, allowFallback: Bool) {
        let keyStorage = "com.bluepad.lgwebos.key.\(activeHost)"
        let savedKey = UserDefaults.standard.string(forKey: keyStorage)
        guard let url = LGWebOSProtocol.ssapURL(host: activeHost, secure: secure) else {
            emitState(.failed("Geçersiz LG TV adresi"))
            return
        }

        mainWsTask?.cancel(with: .normalClosure, reason: nil)
        mainWsTask = nil
        pointerWsTask?.cancel(with: .normalClosure, reason: nil)
        pointerWsTask = nil
        wsSession?.invalidateAndCancel()

        let session = URLSession(configuration: .ephemeral, delegate: LocalNetworkTLSDelegate.shared, delegateQueue: nil)
        wsSession = session
        let task = session.webSocketTask(with: url)
        mainWsTask = task

        emitState(.connecting(activeName))
        emitLog(.ble, "LG webOS TV'ye bağlanılıyor (\(url.absoluteString))...")

        connectTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.mainWsTask === task, !self.isRemoteConnected else { return }
            task.cancel(with: .normalClosure, reason: nil)
            if allowFallback && secure {
                self.emitLog(.ble, "LG 3001 yanıt vermedi; 3000 deneniyor...")
                self.connectLGWebOS(secure: false, allowFallback: false)
            } else {
                self.teardownAllConnections(emitDisconnected: false)
                self.emitState(.failed("LG TV yanıt vermedi"))
            }
        }
        connectTimeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + (savedKey == nil ? 28.0 : 6.0), execute: timeout)

        task.resume()
        receiveLGMessage(on: task, keyStorage: keyStorage, secure: secure, allowFallback: allowFallback)

        let regPayload = LGWebOSProtocol.registerPayload(clientKey: savedKey)
        task.send(.string(regPayload)) { [weak self] error in
            if let error {
                self?.emitLog(.error, "LG kayıt gönderim hatası: \(error.localizedDescription)")
            } else {
                self?.queue.async {
                    if !((self?.isRemoteConnected) ?? true), self?.mainWsTask === task, savedKey == nil {
                        self?.emitState(.awaitingTVApproval(tvName: self?.activeName ?? "", host: self?.activeHost ?? "", kind: .lgWebOS))
                    }
                }
            }
        }
    }

    private func receiveLGMessage(
        on task: URLSessionWebSocketTask,
        keyStorage: String,
        secure: Bool,
        allowFallback: Bool
    ) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.mainWsTask === task else { return }
                switch result {
                case .failure(let error):
                    if !self.isRemoteConnected && allowFallback && secure {
                        self.emitLog(.ble, "LG WSS hatası (\(error.localizedDescription)); 3000 deneniyor...")
                        self.connectLGWebOS(secure: false, allowFallback: false)
                    } else if !self.isRemoteConnected {
                        self.teardownAllConnections(emitDisconnected: false)
                        self.emitState(.failed("LG TV: \(error.localizedDescription)"))
                    } else {
                        self.teardownAllConnections(emitDisconnected: true)
                        self.emitLog(.error, "LG TV bağlantısı kesildi: \(error.localizedDescription)")
                    }

                case .success(let message):
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let msgType = json["type"] as? String ?? ""
                        let msgId = json["id"] as? String ?? ""
                        let payload = json["payload"] as? [String: Any] ?? [:]

                        if msgType == "registered" {
                            self.connectTimeoutWorkItem?.cancel()
                            self.connectTimeoutWorkItem = nil
                            if let key = payload["client-key"] as? String, !key.isEmpty {
                                UserDefaults.standard.set(key, forKey: keyStorage)
                            }
                            self.isRemoteConnected = true
                            self.emitState(.connected(tvName: self.activeName, host: self.activeHost, kind: .lgWebOS))
                            self.emitLog(.gatt, "LG webOS bağlandı; Magic Remote imleç soketi açılıyor...")
                            self.requestLGPointerSocket()
                        } else if msgType == "error" && !self.isRemoteConnected {
                            let errMsg = json["error"] as? String ?? "Eşleştirme reddedildi"
                            self.teardownAllConnections(emitDisconnected: false)
                            self.emitState(.failed("LG TV: \(errMsg)"))
                            return
                        } else if msgId == "ptr_sock", let socketPath = payload["socketPath"] as? String {
                            self.isRequestingLGPointerSocket = false
                            self.openLGPointerSocket(urlString: socketPath)
                        } else if msgType == "response", let pairingType = payload["pairingType"] as? String, pairingType == "PROMPT" {
                            self.emitState(.awaitingTVApproval(tvName: self.activeName, host: self.activeHost, kind: .lgWebOS))
                        }
                    }
                    self.receiveLGMessage(on: task, keyStorage: keyStorage, secure: secure, allowFallback: allowFallback)
                }
            }
        }
    }

    private func requestLGPointerSocket() {
        guard let task = mainWsTask, isRemoteConnected, !isRequestingLGPointerSocket else { return }
        isRequestingLGPointerSocket = true
        let req = LGWebOSProtocol.requestPayload(
            id: "ptr_sock",
            uri: "ssap://com.webos.service.networkinput/getPointerInputSocket"
        )
        task.send(.string(req)) { [weak self] error in
            if let error {
                self?.queue.async { self?.isRequestingLGPointerSocket = false }
                self?.emitLog(.error, "LG imleç soket isteği hatası: \(error.localizedDescription)")
            }
        }
    }

    private func openLGPointerSocket(urlString: String) {
        guard let session = wsSession, let url = URL(string: urlString) else { return }
        pointerWsTask?.cancel(with: .normalClosure, reason: nil)
        let ptrTask = session.webSocketTask(with: url)
        pointerWsTask = ptrTask
        ptrTask.resume()
        receiveLGPointerEvents(on: ptrTask)
        emitLog(.gatt, "LG Magic Remote fare soketi hazır.")
    }

    private func receiveLGPointerEvents(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.pointerWsTask === task else { return }
                if case .failure = result {
                    self.pointerWsTask = nil
                    return
                }
                self.receiveLGPointerEvents(on: task)
            }
        }
    }

    private func flushLGMouseIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        if (now - lastLGFlushTime) >= 0.030 {
            flushLGMouseNow()
        } else if !lgFlushScheduled {
            lgFlushScheduled = true
            let delay = max(0.01, 0.030 - (now - lastLGFlushTime))
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.lgFlushScheduled = false
                self?.flushLGMouseNow()
            }
        }
    }

    private func flushLGMouseNow() {
        guard isRemoteConnected, activeKind == .lgWebOS else { return }
        let dx = pendingLGDX
        let dy = pendingLGDY
        guard dx != 0 || dy != 0 else { return }
        pendingLGDX = 0
        pendingLGDY = 0
        lastLGFlushTime = CFAbsoluteTimeGetCurrent()

        if pointerWsTask == nil {
            requestLGPointerSocket()
            return
        }
        sendLGPointerMessage(
            LGWebOSProtocol.pointerMoveMessage(dx: dx, dy: dy, buttonDown: pendingLGButtonDown),
            label: nil
        )
    }

    private func sendLGPointerMessage(_ message: String, label: String?) {
        guard isRemoteConnected else { return }
        guard let ptrTask = pointerWsTask else {
            requestLGPointerSocket()
            return
        }
        ptrTask.send(.string(message)) { [weak self] error in
            if let error {
                self?.queue.async { self?.pointerWsTask = nil }
                self?.emitLog(.error, "LG imleç TX hatası: \(error.localizedDescription)")
            } else {
                self?.notifyPacketSent()
                if let label {
                    self?.emitLog(.tx, label)
                }
            }
        }
    }

    private func sendLGSSAPRequest(uri: String, payload: [String: Any] = [:], label: String) {
        guard let task = mainWsTask, isRemoteConnected else { return }
        lgRequestCounter += 1
        let msg = LGWebOSProtocol.requestPayload(id: "req_\(lgRequestCounter)", uri: uri, payload: payload)
        task.send(.string(msg)) { [weak self] error in
            if let error {
                self?.emitLog(.error, "LG SSAP hatası: \(error.localizedDescription)")
            } else {
                self?.notifyPacketSent()
                self?.emitLog(.tx, label)
            }
        }
    }

    // MARK: Android TV Remote v2 (Port 6466 Session + Port 6467 Pairing)

    private func makeMutualTLSParameters(identity: SecIdentity, captureServerCert: Bool) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        let secOpts = tlsOptions.securityProtocolOptions

        if let secID = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(secOpts, secID)
        }

        sec_protocol_options_set_verify_block(
            secOpts,
            { [weak self] _, secTrust, complete in
                if captureServerCert {
                    let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
                    let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
                    if let leaf = chain?.first {
                        self?.activeServerCert = leaf
                    }
                }
                complete(true)
            },
            queue
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        return NWParameters(tls: tlsOptions, tcp: tcpOptions)
    }

    private func startAndroidTVRemoteSession(allowPairingFallback: Bool) {
        guard let loaded = AndroidTVIdentityStore.loadOrCreateIdentity() else {
            emitState(.failed("TV sertifikası oluşturulamadı"))
            emitLog(.error, "Android TV Keychain sertifikası oluşturulamadı.")
            return
        }
        activeClientCert = loaded.certificate

        remoteConnection?.stateUpdateHandler = nil
        remoteConnection?.cancel()
        remoteConnection = nil
        remoteBuffer.removeAll()
        hasReceivedRemoteStart = false
        isRemoteConnected = false

        guard let nwPort = NWEndpoint.Port(rawValue: SmartTVKind.androidTV.defaultPort) else { return }
        let params = makeMutualTLSParameters(identity: loaded.identity, captureServerCert: false)
        let conn = NWConnection(host: NWEndpoint.Host(activeHost), port: nwPort, using: params)
        remoteConnection = conn

        emitState(.connecting(activeName))
        emitLog(.ble, "Android TV Remote v2 bağlantısı deneniyor (\(activeHost):6466)...")

        connectTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.remoteConnection === conn, !self.hasReceivedRemoteStart else { return }
            conn.stateUpdateHandler = nil
            conn.cancel()
            self.remoteConnection = nil
            if allowPairingFallback {
                self.emitLog(.ble, "TV henüz eşleşmemiş görünüyor; 6467 PIN eşleştirmesine geçiliyor...")
                self.startPairing6467(identity: loaded.identity)
            } else {
                self.emitState(.failed("TV oturumu zaman aşımına uğradı"))
            }
        }
        connectTimeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + 4.5, execute: timeout)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self, self.remoteConnection === conn else { return }
            switch state {
            case .ready:
                self.emitLog(.gatt, "TV 6466 TLS tüneli açıldı; yapılandırma bekleniyor...")
                self.receiveRemoteChunk(on: conn, allowPairingFallback: allowPairingFallback, identity: loaded.identity)
            case .failed(let error):
                self.connectTimeoutWorkItem?.cancel()
                self.connectTimeoutWorkItem = nil
                conn.stateUpdateHandler = nil
                conn.cancel()
                self.remoteConnection = nil
                self.isRemoteConnected = false
                if allowPairingFallback && !self.hasReceivedRemoteStart {
                    self.emitLog(.ble, "6466 yetki/TLS reddi; 6467 eşleştirmesi başlatılıyor...")
                    self.startPairing6467(identity: loaded.identity)
                } else {
                    self.emitState(.failed(error.localizedDescription))
                    self.emitLog(.error, "TV 6466 hatası: \(error.localizedDescription)")
                }
            case .waiting(let error):
                self.connectTimeoutWorkItem?.cancel()
                self.connectTimeoutWorkItem = nil
                conn.stateUpdateHandler = nil
                conn.cancel()
                self.remoteConnection = nil
                self.isRemoteConnected = false
                self.emitState(.failed("TV erişilemiyor: \(error.localizedDescription)"))
            case .cancelled:
                break
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func receiveRemoteChunk(on conn: NWConnection, allowPairingFallback: Bool, identity: SecIdentity) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self, self.remoteConnection === conn else { return }

            if let data, !data.isEmpty {
                self.remoteBuffer.append(data)
                while let frame = ProtobufWire.extractNextFrame(from: &self.remoteBuffer) {
                    self.handleRemoteFrame(frame, on: conn)
                }
            }

            if let error {
                self.connectTimeoutWorkItem?.cancel()
                self.connectTimeoutWorkItem = nil
                conn.stateUpdateHandler = nil
                conn.cancel()
                self.remoteConnection = nil
                self.isRemoteConnected = false
                if allowPairingFallback && !self.hasReceivedRemoteStart {
                    self.emitLog(.ble, "6466 kapatıldı (\(error.localizedDescription)); 6467 eşleştirmesi deneniyor...")
                    self.startPairing6467(identity: identity)
                } else {
                    self.emitState(.failed(error.localizedDescription))
                    self.emitLog(.error, "TV oturumu koptu: \(error.localizedDescription)")
                }
                return
            }

            if isComplete {
                self.connectTimeoutWorkItem?.cancel()
                self.connectTimeoutWorkItem = nil
                conn.stateUpdateHandler = nil
                conn.cancel()
                self.remoteConnection = nil
                self.isRemoteConnected = false
                if allowPairingFallback && !self.hasReceivedRemoteStart {
                    self.startPairing6467(identity: identity)
                } else {
                    self.emitState(.disconnected)
                    self.emitLog(.ble, "TV oturumu kapandı.")
                }
                return
            }

            self.receiveRemoteChunk(on: conn, allowPairingFallback: allowPairingFallback, identity: identity)
        }
    }

    private func handleRemoteFrame(_ data: Data, on conn: NWConnection) {
        let fields = ProtobufWire.parseFields(from: data)
        for item in fields {
            switch item.field {
            case 1: // remote_configure
                let cfgFields = ProtobufWire.parseFields(from: item.bytes)
                let serverFeatures = cfgFields.first(where: { $0.field == 1 })?.varint ?? AndroidTVWireMessages.defaultFeatureMask
                negotiatedFeatures = AndroidTVWireMessages.defaultFeatureMask & serverFeatures
                if negotiatedFeatures == 0 {
                    negotiatedFeatures = AndroidTVWireMessages.defaultFeatureMask
                }
                sendFrame(AndroidTVWireMessages.remoteConfigureResponse(activeFeatures: negotiatedFeatures), on: conn)

            case 2: // remote_set_active
                sendFrame(AndroidTVWireMessages.remoteSetActive(negotiatedFeatures), on: conn)

            case 8: // remote_ping_request
                let pingFields = ProtobufWire.parseFields(from: item.bytes)
                let val1 = pingFields.first(where: { $0.field == 1 })?.varint ?? 0
                sendFrame(AndroidTVWireMessages.remotePingResponse(val1: val1), on: conn)

            case 20: // remote_ime_key_inject
                let injectFields = ProtobufWire.parseFields(from: item.bytes)
                if let appInfo = injectFields.first(where: { $0.field == 1 })?.bytes,
                   let c = ProtobufWire.parseFields(from: appInfo).first(where: { $0.field == 1 })?.varint {
                    imeCounter = Int32(truncatingIfNeeded: c)
                }
                if let status = injectFields.first(where: { $0.field == 2 })?.bytes,
                   let fc = ProtobufWire.parseFields(from: status).first(where: { $0.field == 1 })?.varint {
                    imeFieldCounter = Int32(truncatingIfNeeded: fc)
                }

            case 21: // remote_ime_batch_edit
                let batchFields = ProtobufWire.parseFields(from: item.bytes)
                if imeCounter == 0, let c = batchFields.first(where: { $0.field == 1 })?.varint {
                    imeCounter = Int32(truncatingIfNeeded: c)
                }
                if imeFieldCounter == 0, let fc = batchFields.first(where: { $0.field == 2 })?.varint {
                    imeFieldCounter = Int32(truncatingIfNeeded: fc)
                }

            case 22: // remote_ime_show_request
                let showFields = ProtobufWire.parseFields(from: item.bytes)
                if let status = showFields.first(where: { $0.field == 2 })?.bytes,
                   let fc = ProtobufWire.parseFields(from: status).first(where: { $0.field == 1 })?.varint {
                    imeFieldCounter = Int32(truncatingIfNeeded: fc)
                }

            case 40: // remote_start
                hasReceivedRemoteStart = true
                isRemoteConnected = true
                connectTimeoutWorkItem?.cancel()
                connectTimeoutWorkItem = nil
                emitState(.connected(tvName: activeName, host: activeHost, kind: .androidTV))
                emitLog(.gatt, "Android TV / Google TV bağlantısı hazır: \(activeName)")

            default:
                break
            }
        }
    }

    private func startPairing6467(identity: SecIdentity) {
        pairingConnection?.stateUpdateHandler = nil
        pairingConnection?.cancel()
        pairingConnection = nil
        pairingBuffer.removeAll()
        activeServerCert = nil

        guard let nwPort = NWEndpoint.Port(rawValue: 6467) else { return }
        let params = makeMutualTLSParameters(identity: identity, captureServerCert: true)
        let conn = NWConnection(host: NWEndpoint.Host(activeHost), port: nwPort, using: params)
        pairingConnection = conn

        emitState(.connecting("\(activeName) (Eşleştirme)"))

        connectTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pairingConnection === conn else { return }
            self.handlePairingFailure("Eşleştirme 6467 zaman aşımına uğradı")
        }
        connectTimeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + 8.0, execute: timeout)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self, self.pairingConnection === conn else { return }
            switch state {
            case .ready:
                self.connectTimeoutWorkItem?.cancel()
                self.connectTimeoutWorkItem = nil
                self.emitLog(.gatt, "TV 6467 eşleştirme kanalı açıldı; istek gönderiliyor...")
                self.sendFrame(AndroidTVWireMessages.pairingRequest(clientName: self.activeClientName), on: conn)
                self.receivePairingChunk(on: conn)
            case .failed(let error):
                self.handlePairingFailure("6467 hatası: \(error.localizedDescription)")
            case .waiting(let error):
                self.handlePairingFailure("TV 6467 erişilemiyor: \(error.localizedDescription)")
            case .cancelled:
                break
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func receivePairingChunk(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self, self.pairingConnection === conn else { return }

            if let data, !data.isEmpty {
                self.pairingBuffer.append(data)
                while let frame = ProtobufWire.extractNextFrame(from: &self.pairingBuffer) {
                    self.handlePairingFrame(frame, on: conn)
                }
            }

            if let error {
                self.handlePairingFailure("Eşleştirme kesildi: \(error.localizedDescription)")
                return
            }

            if isComplete && self.pairingConnection === conn {
                self.handlePairingFailure("TV eşleştirmeyi kapattı")
                return
            }

            self.receivePairingChunk(on: conn)
        }
    }

    private func handlePairingFrame(_ data: Data, on conn: NWConnection) {
        let fields = ProtobufWire.parseFields(from: data)
        let status = fields.first(where: { $0.field == 2 })?.varint ?? 200
        guard status == 200 else {
            handlePairingFailure("TV eşleştirme reddi (kod: \(status))")
            return
        }

        for item in fields {
            switch item.field {
            case 11: // pairing_request_ack
                let ackFields = ProtobufWire.parseFields(from: item.bytes)
                if let srvBytes = ackFields.first(where: { $0.field == 1 })?.bytes,
                   let srvName = String(data: srvBytes, encoding: .utf8),
                   !srvName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    activeName = srvName.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                sendFrame(AndroidTVWireMessages.pairingOptions(), on: conn)

            case 20: // options
                sendFrame(AndroidTVWireMessages.pairingConfiguration(), on: conn)

            case 31: // configuration_ack
                emitState(.awaitingPairingCode(tvName: activeName, host: activeHost))
                emitLog(.gatt, "TV ekranında 6 haneli PIN gösteriliyor.")

            case 41: // secret_ack
                conn.stateUpdateHandler = nil
                conn.cancel()
                pairingConnection = nil
                pairingBuffer.removeAll()
                emitLog(.gatt, "TV PIN doğrulandı! Kumanda oturumu açılıyor...")
                queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.startAndroidTVRemoteSession(allowPairingFallback: false)
                }

            default:
                break
            }
        }
    }

    private func handlePairingFailure(_ message: String) {
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        pairingConnection?.stateUpdateHandler = nil
        pairingConnection?.cancel()
        pairingConnection = nil
        pairingBuffer.removeAll()
        emitLog(.error, message)
        emitState(.failed(message))
    }

    private func sendFrame(_ message: Data, on conn: NWConnection) {
        let framed = ProtobufWire.frame(message)
        conn.send(content: framed, completion: .contentProcessed { _ in })
    }

    private func sendRemoteMessage(_ message: Data, label: String) {
        guard let conn = remoteConnection, isRemoteConnected else { return }
        let framed = ProtobufWire.frame(message)
        conn.send(content: framed, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.emitLog(.error, "TV TX hatası: \(error.localizedDescription)")
            } else {
                self?.notifyPacketSent()
                self?.emitLog(.tx, label)
            }
        })
    }

    private func sendAndroidTVKeyInternal(_ keyCode: AndroidTVKeyCode) {
        let msg = AndroidTVWireMessages.remoteKeyInject(keyCode: keyCode.rawValue, direction: 3)
        sendRemoteMessage(msg, label: "TV Tuş (\(keyCode.rawValue))")
    }

    // MARK: Vestel SmartCenter (HTTP POST Port 56789)

    private func connectVestelTV() {
        guard let nwPort = NWEndpoint.Port(rawValue: SmartTVKind.vestel.defaultPort) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(activeHost), port: nwPort, using: .tcp)
        emitState(.connecting(activeName))
        emitLog(.ble, "Vestel SmartCenter bağlantısı kontrol ediliyor (\(activeHost):56789)...")

        let timeout = DispatchWorkItem { [weak self] in
            conn.stateUpdateHandler = nil
            conn.cancel()
            guard let self, !self.isRemoteConnected else { return }
            self.emitState(.failed("Vestel TV (port 56789) yanıt vermedi"))
        }
        connectTimeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + 3.0, execute: timeout)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.connectTimeoutWorkItem?.cancel()
                self.connectTimeoutWorkItem = nil
                conn.stateUpdateHandler = nil
                conn.cancel()
                self.isRemoteConnected = true
                self.emitState(.connected(tvName: self.activeName, host: self.activeHost, kind: .vestel))
                self.emitLog(.gatt, "Vestel Smart TV hazır: \(self.activeName)")
            case .failed(let error):
                self.connectTimeoutWorkItem?.cancel()
                self.connectTimeoutWorkItem = nil
                conn.stateUpdateHandler = nil
                conn.cancel()
                self.emitState(.failed("Vestel TV hatası: \(error.localizedDescription)"))
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func sendVestelKeyInternal(_ code: VestelKeyCode) {
        guard let url = URL(string: "http://\(activeHost):\(SmartTVKind.vestel.defaultPort)/apps/SmartCenter") else { return }
        var req = URLRequest(url: url, timeoutInterval: 3.0)
        req.httpMethod = "POST"
        req.setValue("text/plain; charset=ISO-8859-1", forHTTPHeaderField: "Content-Type")
        let body = "<?xml version='1.0' ?><remote><key code='\(code.rawValue)'/></remote>"
        req.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            if let error {
                self?.emitLog(.error, "Vestel TX hatası: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                self?.notifyPacketSent()
                self?.emitLog(.tx, "Vestel Tuş (\(code.rawValue))")
            }
        }.resume()
    }

    // MARK: Bonjour Classification & Helpers

    private static func classifyTVService(name: String, type: String, txtLower: String) -> SmartTVKind? {
        let lowerName = name.lowercased()
        if type.contains("_samsungmsf") || lowerName.contains("samsung") || txtLower.contains("samsung") || txtLower.contains("tizen") {
            return .samsungTizen
        }
        if lowerName.contains("lg ") || lowerName.hasPrefix("lg") || lowerName.contains("webos") || lowerName.contains("oled") || lowerName.contains("nanocell") || lowerName.contains("qned") || txtLower.contains("webos") || txtLower.contains("lge") {
            return .lgWebOS
        }
        if type.contains("_androidtvremote2") || type.contains("_googlecast") {
            return .androidTV
        }
        if lowerName.contains("vestel") || txtLower.contains("vestel") {
            return .vestel
        }
        return nil
    }

    private static func extractIPv4(from addresses: [Data]?) -> String? {
        guard let addresses else { return nil }
        for addrData in addresses {
            let ip: String? = addrData.withUnsafeBytes { rawBuf in
                guard rawBuf.count >= MemoryLayout<sockaddr_in>.size,
                      let base = rawBuf.baseAddress else { return nil }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                guard Int32(sa.pointee.sa_family) == AF_INET else { return nil }
                var addrIn = base.assumingMemoryBound(to: sockaddr_in.self).pointee
                var cString = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                let ptr = inet_ntop(AF_INET, &addrIn.sin_addr, &cString, socklen_t(INET_ADDRSTRLEN))
                return ptr.map { String(cString: $0) }
            }
            if let ip, !ip.isEmpty {
                return ip
            }
        }
        return nil
    }

    private func emitDiscoveredTVs() {
        let sorted = discoveredByKey.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let handler = onDiscoveredTVsChange
        Task { @MainActor in
            handler?(sorted)
        }
    }

    private func emitState(_ state: SmartTVConnectionState) {
        let handler = onStateChange
        Task { @MainActor in
            handler?(state)
        }
    }

    private func emitLog(_ category: HIDDiagnosticEvent.Category, _ message: String) {
        let event = HIDDiagnosticEvent(category: category, message: message)
        let handler = onDiagnosticEvent
        Task { @MainActor in
            handler?(event)
        }
    }

    private func notifyPacketSent() {
        let handler = onPacketSent
        Task { @MainActor in
            handler?()
        }
    }
}

// MARK: - Local Network Self-Signed TLS Trust Delegate (LAN Smart TVs)

private final class LocalNetworkTLSDelegate: NSObject, URLSessionDelegate {
    static let shared = LocalNetworkTLSDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - NetServiceBrowserDelegate & NetServiceDelegate

extension SmartTVRemoteService: NetServiceBrowserDelegate, NetServiceDelegate {

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        resolvingServices.insert(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        defer {
            sender.stop()
            sender.delegate = nil
            resolvingServices.remove(sender)
        }
        guard let ip = Self.extractIPv4(from: sender.addresses) else { return }

        let serviceName = sender.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = serviceName.isEmpty ? ip : serviceName
        let txtString: String
        if let txtData = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            txtString = dict.map { key, val in
                let v = String(data: val, encoding: .utf8) ?? ""
                return "\(key)=\(v)"
            }.joined(separator: " ").lowercased()
        } else {
            txtString = ""
        }

        guard let kind = Self.classifyTVService(name: displayName, type: sender.type, txtLower: txtString) else {
            return
        }
        let isATVRemote2 = sender.type.contains("_androidtvremote2")

        queue.async { [weak self] in
            guard let self else { return }
            let key = "\(kind.rawValue):\(ip)"
            if let existing = self.discoveredByKey[key], !isATVRemote2 && existing.isBonjourDiscovered {
                return
            }
            self.discoveredByKey[key] = SmartTVEndpoint(
                name: displayName,
                host: ip,
                kind: kind,
                isBonjourDiscovered: true
            )
            self.emitDiscoveredTVs()
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        sender.stop()
        sender.delegate = nil
        resolvingServices.remove(sender)
    }
}
