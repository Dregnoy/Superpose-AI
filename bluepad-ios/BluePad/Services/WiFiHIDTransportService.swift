import Foundation
import Network

/// Zero-cloud local LAN transport (`Network.framework` UDP discovery + noDelay TCP JSON-lines).
/// Works with `tools/bluepad_receiver.py` on Windows/macOS/Linux when iOS BLE HOGP is hidden by host OS filters.
final class WiFiHIDTransportService {

    // MARK: Callbacks (delivered on MainActor)
    var onStateChange: (@MainActor (WiFiConnectionState) -> Void)?
    var onDiscoveredHostsChange: (@MainActor ([WiFiHostEndpoint]) -> Void)?
    var onDiagnosticEvent: (@MainActor (HIDDiagnosticEvent) -> Void)?
    var onPacketSent: (@MainActor () -> Void)?

    static let defaultTCPPort: UInt16 = 8765
    static let discoveryUDPPort: UInt16 = 8766

    private let queue = DispatchQueue(label: "com.bluepad.wifi.transport")
    private var udpListener: NWListener?
    private var tcpConnection: NWConnection?
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var receiveBuffer = Data()

    private var discoveredHosts: [String: WiFiHostEndpoint] = [:]
    private var isAuthenticated: Bool = false
    private var pendingTargetAddress: String = ""
    private var pendingTargetHostName: String = ""
    private var pendingPIN: String = ""
    private var pendingDeviceName: String = "BluePad"

    // MARK: QR Pairing Parser

    /// Parses `"bluepad://192.168.1.25:8765/4829"` or `"bluepad://192.168.1.25/4829"`.
    static func parsePairingQR(_ raw: String) -> (host: String, port: UInt16, pin: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "bluepad",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        let portVal: UInt16
        if let explicitPort = url.port, explicitPort > 0, explicitPort <= Int(UInt16.max) {
            portVal = UInt16(explicitPort)
        } else {
            portVal = defaultTCPPort
        }

        let pathParts = url.pathComponents.filter { $0 != "/" }
        let pin = pathParts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pin.isEmpty else { return nil }

        return (host: host, port: portVal, pin: pin)
    }

    // MARK: UDP LAN Discovery

    func startDiscovery() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopDiscoveryInternal()

            guard let port = NWEndpoint.Port(rawValue: Self.discoveryUDPPort) else { return }
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true

            do {
                let listener = try NWListener(using: params, on: port)
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.emitLog(.ble, "Wi-Fi yerel ağ taraması aktif (UDP:\(Self.discoveryUDPPort)).")
                    case .failed(let error):
                        self.emitLog(.error, "Wi-Fi UDP tarama hatası: \(error.localizedDescription)")
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] incoming in
                    self?.handleDiscoveryPacket(from: incoming)
                }
                self.udpListener = listener
                listener.start(queue: self.queue)
            } catch {
                self.emitLog(.error, "Wi-Fi tarayıcı başlatılamadı: \(error.localizedDescription)")
            }
        }
    }

    func stopDiscovery() {
        queue.async { [weak self] in
            self?.stopDiscoveryInternal()
        }
    }

    private func stopDiscoveryInternal() {
        udpListener?.cancel()
        udpListener = nil
    }

    private func handleDiscoveryPacket(from incoming: NWConnection) {
        let senderIP = Self.extractIPAddress(from: incoming.endpoint)
        incoming.start(queue: queue)
        incoming.receiveMessage { [weak self] data, _, _, _ in
            defer { incoming.cancel() }
            guard let self, let data, !data.isEmpty else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["type"] as? String) == "bluepad_host" else {
                return
            }

            let explicitHost = (json["ip"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedIP: String?
            if let explicitHost, !explicitHost.isEmpty {
                resolvedIP = explicitHost
            } else {
                resolvedIP = senderIP
            }
            guard let ip = resolvedIP, !ip.isEmpty else { return }

            let portNum = (json["port"] as? NSNumber)?.uint16Value ?? Self.defaultTCPPort
            let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let osName = (json["os"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let endpoint = WiFiHostEndpoint(
                name: (name?.isEmpty == false ? name! : ip),
                host: ip,
                port: portNum,
                osName: (osName?.isEmpty == false ? osName! : "Windows"),
                lastSeen: Date()
            )
            self.discoveredHosts[endpoint.id] = endpoint
            self.emitDiscoveredHosts()
        }
    }

    // MARK: TCP Session Lifecycle

    func connect(host: String, port: UInt16, pin: String, deviceName: String) {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let cleanPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanHost.isEmpty, port > 0, !cleanPIN.isEmpty else {
            emitState(.failed("IP, port ve PIN boş olamaz"))
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            self.disconnectInternal(emitDisconnected: false)

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                self.emitState(.failed("Geçersiz port"))
                return
            }

            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            let params = NWParameters(tls: nil, tcp: tcpOptions)

            let conn = NWConnection(host: NWEndpoint.Host(cleanHost), port: nwPort, using: params)
            self.tcpConnection = conn
            self.receiveBuffer.removeAll()
            self.isAuthenticated = false
            self.pendingTargetAddress = "\(cleanHost):\(port)"
            self.pendingTargetHostName = cleanHost
            self.pendingPIN = cleanPIN
            self.pendingDeviceName = cleanName.isEmpty ? "BluePad" : cleanName

            self.emitState(.connecting(self.pendingTargetAddress))
            self.emitLog(.ble, "Wi-Fi bağlantısı kuruluyor: \(self.pendingTargetAddress)...")

            conn.stateUpdateHandler = { [weak self] state in
                self?.handleTCPState(state, connection: conn)
            }
            conn.start(queue: self.queue)

            let timeoutWork = DispatchWorkItem { [weak self] in
                guard let self, self.tcpConnection === conn, !self.isAuthenticated else { return }
                let addr = self.pendingTargetAddress
                self.disconnectInternal(emitDisconnected: false)
                self.emitState(.failed("Zaman aşımı — PC alıcısı yanıt vermedi"))
                self.emitLog(.error, "Wi-Fi bağlantı zaman aşımı: \(addr)")
            }
            self.connectTimeoutWorkItem = timeoutWork
            self.queue.asyncAfter(deadline: .now() + 6.0, execute: timeoutWork)
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.disconnectInternal(emitDisconnected: true)
            self?.emitLog(.ble, "Wi-Fi bağlantısı kapatıldı.")
        }
    }

    private func disconnectInternal(emitDisconnected: Bool) {
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        isAuthenticated = false
        receiveBuffer.removeAll()
        tcpConnection?.stateUpdateHandler = nil
        tcpConnection?.cancel()
        tcpConnection = nil
        if emitDisconnected {
            emitState(.disconnected)
        }
    }

    private func handleTCPState(_ state: NWConnection.State, connection: NWConnection) {
        guard tcpConnection === connection else { return }
        switch state {
        case .ready:
            sendRawDictionary([
                "t": "auth",
                "pin": pendingPIN,
                "name": pendingDeviceName
            ])
            receiveNextChunk(on: connection)

        case .waiting(let error):
            let msg = error.localizedDescription
            disconnectInternal(emitDisconnected: false)
            emitState(.failed("PC erişilemiyor: \(msg)"))
            emitLog(.error, "Wi-Fi erişim yok: \(msg)")

        case .failed(let error):
            let msg = error.localizedDescription
            disconnectInternal(emitDisconnected: false)
            emitState(.failed(msg))
            emitLog(.error, "Wi-Fi bağlantı hatası: \(msg)")

        case .cancelled:
            break

        default:
            break
        }
    }

    private func receiveNextChunk(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, self.tcpConnection === connection else { return }

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.drainIncomingLines(on: connection)
            }

            if let error {
                let msg = error.localizedDescription
                self.disconnectInternal(emitDisconnected: false)
                self.emitState(.failed(msg))
                self.emitLog(.error, "Wi-Fi okuma hatası: \(msg)")
                return
            }

            if isComplete {
                self.disconnectInternal(emitDisconnected: true)
                self.emitLog(.ble, "Karşı bilgisayar Wi-Fi bağlantısını kapattı.")
                return
            }

            self.receiveNextChunk(on: connection)
        }
    }

    private func drainIncomingLines(on connection: NWConnection) {
        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = receiveBuffer.subdata(in: receiveBuffer.startIndex..<newlineIndex)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...newlineIndex)

            guard !lineData.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let kind = obj["t"] as? String else {
                continue
            }

            if kind == "ok" {
                connectTimeoutWorkItem?.cancel()
                connectTimeoutWorkItem = nil
                let hostName = (obj["host"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolved = (hostName?.isEmpty == false ? hostName! : pendingTargetHostName)
                isAuthenticated = true
                emitState(.connected(hostName: resolved, address: pendingTargetAddress))
                emitLog(.gatt, "Wi-Fi oturumu onaylandı: \(resolved) (\(pendingTargetAddress))")
            } else if kind == "err" {
                let reason = (obj["msg"] as? String) ?? "PIN hatalı veya reddedildi"
                disconnectInternal(emitDisconnected: false)
                emitState(.failed(reason))
                emitLog(.error, "Wi-Fi doğrulama reddedildi: \(reason)")
                return
            }
        }
    }

    // MARK: HID Event Senders

    func sendMouseMove(dx: Int, dy: Int, wheel: Int = 0, hWheel: Int = 0) {
        guard dx != 0 || dy != 0 || wheel != 0 || hWheel != 0 else { return }
        sendIfReady(["t": "m", "dx": dx, "dy": dy, "w": wheel, "hw": hWheel], countPacket: true)
    }

    func sendMouseButton(_ button: HIDMouseButton, pressed: Bool) {
        sendIfReady(["t": "mb", "b": Int(button.rawValue), "p": pressed], countPacket: true)
    }

    func clickMouseButton(_ button: HIDMouseButton) {
        sendIfReady(["t": "mc", "b": Int(button.rawValue)], countPacket: true)
    }

    func tapKey(_ keyCode: UInt8, modifiers: HIDModifier = []) {
        sendIfReady(["t": "k", "c": Int(keyCode), "m": Int(modifiers.rawValue)], countPacket: true)
    }

    func sendText(_ text: String, appendEnter: Bool = false) {
        guard !text.isEmpty || appendEnter else { return }
        sendIfReady(["t": "txt", "s": text, "e": appendEnter], countPacket: true)
    }

    func tapConsumer(_ usage: HIDConsumerUsage) {
        sendIfReady(["t": "c", "u": Int(usage.rawValue)], countPacket: true)
    }

    func tapSystem(_ usage: HIDSystemUsage) {
        sendIfReady(["t": "s", "u": Int(usage.rawValue)], countPacket: true)
    }

    func sendGamepad(_ state: HIDGamepadState) {
        sendIfReady([
            "t": "g",
            "b": Int(state.buttons.rawValue),
            "h": Int(state.hat.rawValue),
            "lx": Int(state.leftX),
            "ly": Int(state.leftY),
            "rx": Int(state.rightX),
            "ry": Int(state.rightY)
        ], countPacket: true)
    }

    func releaseAll() {
        sendIfReady(["t": "rel"], countPacket: false)
    }

    private func sendIfReady(_ payload: [String: Any], countPacket: Bool) {
        queue.async { [weak self] in
            guard let self, self.isAuthenticated, let conn = self.tcpConnection else { return }
            guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
            data.append(0x0A)
            conn.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.emitLog(.error, "Wi-Fi TX hatası: \(error.localizedDescription)")
                } else if countPacket {
                    self?.notifyPacketSent()
                }
            })
        }
    }

    private func sendRawDictionary(_ payload: [String: Any]) {
        guard let conn = tcpConnection,
              var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        data.append(0x0A)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: Helpers & MainActor Dispatch

    private static func extractIPAddress(from endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        let raw = "\(host)"
        let clean = raw.split(separator: "%").first.map(String.init) ?? raw
        if clean.hasPrefix("::ffff:") {
            return String(clean.dropFirst(7))
        }
        return clean
    }

    private func emitState(_ state: WiFiConnectionState) {
        let handler = onStateChange
        Task { @MainActor in
            handler?(state)
        }
    }

    private func emitDiscoveredHosts() {
        let sorted = discoveredHosts.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let handler = onDiscoveredHostsChange
        Task { @MainActor in
            handler?(sorted)
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
