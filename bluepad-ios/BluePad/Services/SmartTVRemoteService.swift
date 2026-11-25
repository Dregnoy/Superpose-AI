import Darwin
import Foundation
import Network
import Security

/// Local Wi-Fi Smart TV remote service supporting Android TV / Google TV Remote Protocol v2
/// (mDNS discovery + TLS mutual-auth ports 6467/6466) and Vestel SmartCenter (HTTP-XML port 56789).
final class SmartTVRemoteService: NSObject {

    // MARK: Callbacks (delivered on MainActor)
    var onStateChange: (@MainActor (SmartTVConnectionState) -> Void)?
    var onDiscoveredTVsChange: (@MainActor ([SmartTVEndpoint]) -> Void)?
    var onDiagnosticEvent: (@MainActor (HIDDiagnosticEvent) -> Void)?
    var onPacketSent: (@MainActor () -> Void)?

    // MARK: State & Queues
    private let queue = DispatchQueue(label: "com.bluepad.smarttv.remote")

    // Bonjour Discovery (must stay on Main RunLoop)
    private var atvBrowser: NetServiceBrowser?
    private var castBrowser: NetServiceBrowser?
    private var resolvingServices: Set<NetService> = []
    private var discoveredByKey: [String: SmartTVEndpoint] = [:]

    // Android TV Remote v2 Session State
    private var remoteConnection: NWConnection?
    private var pairingConnection: NWConnection?
    private var remoteBuffer = Data()
    private var pairingBuffer = Data()
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var activeClientCert: SecCertificate?
    private var activeServerCert: SecCertificate?

    private var activeHost: String = ""
    private var activeName: String = ""
    private var activeKind: SmartTVKind = .androidTV
    private var activeClientName: String = "BluePad"
    private var negotiatedFeatures: UInt64 = AndroidTVWireMessages.defaultFeatureMask
    private var imeCounter: Int32 = 0
    private var imeFieldCounter: Int32 = 0
    private var hasReceivedRemoteStart: Bool = false
    private var isRemoteConnected: Bool = false

    // MARK: Discovery (Bonjour)

    func startDiscovery() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopDiscoveryOnMain()

            let atv = NetServiceBrowser()
            atv.delegate = self
            atv.includesPeerToPeer = true
            self.atvBrowser = atv
            atv.searchForServices(ofType: "_androidtvremote2._tcp.", inDomain: "local.")

            let cast = NetServiceBrowser()
            cast.delegate = self
            cast.includesPeerToPeer = true
            self.castBrowser = cast
            cast.searchForServices(ofType: "_googlecast._tcp.", inDomain: "local.")

            self.emitLog(.ble, "Smart TV yerel ağ keşfi başlatıldı (Bonjour).")
        }
    }

    func stopDiscovery() {
        DispatchQueue.main.async { [weak self] in
            self?.stopDiscoveryOnMain()
        }
    }

    private func stopDiscoveryOnMain() {
        atvBrowser?.stop()
        atvBrowser?.delegate = nil
        atvBrowser = nil
        castBrowser?.stop()
        castBrowser?.delegate = nil
        castBrowser = nil
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

        activeServerCert = nil
        hasReceivedRemoteStart = false
        isRemoteConnected = false

        if emitDisconnected {
            emitState(.disconnected)
        }
    }

    // MARK: Unified Input Routing

    func sendKey(hidKeyCode: HIDKeyCode) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected else { return }
            switch self.activeKind {
            case .androidTV:
                if let atvKey = AndroidTVKeyCode.from(hidKeyCode: hidKeyCode) {
                    self.sendAndroidTVKeyInternal(atvKey)
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
            case .vestel:
                if appendEnter {
                    self.sendVestelKeyInternal(.ok)
                }
            }
        }
    }

    func launchApp(url: String) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected, self.activeKind == .androidTV else { return }
            let msg = AndroidTVWireMessages.remoteAppLinkLaunch(url)
            self.sendRemoteMessage(msg, label: "TV Uygulama Aç")
        }
    }

    func sendAndroidTVDirectKey(_ keyCode: AndroidTVKeyCode) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected, self.activeKind == .androidTV else { return }
            self.sendAndroidTVKeyInternal(keyCode)
        }
    }

    func sendVestelDirectKey(_ keyCode: VestelKeyCode) {
        queue.async { [weak self] in
            guard let self, self.isRemoteConnected, self.activeKind == .vestel else { return }
            self.sendVestelKeyInternal(keyCode)
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

    // MARK: Bonjour Address Extraction & Dispatch Helpers

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
        let isATVRemote2 = sender.type.contains("_androidtvremote2")

        queue.async { [weak self] in
            guard let self else { return }
            let key = "\(SmartTVKind.androidTV.rawValue):\(ip)"
            if let existing = self.discoveredByKey[key], !isATVRemote2 && existing.isBonjourDiscovered {
                // Keep friendlier name from _androidtvremote2._tcp if already discovered
                return
            }
            self.discoveredByKey[key] = SmartTVEndpoint(
                name: displayName,
                host: ip,
                kind: .androidTV,
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
