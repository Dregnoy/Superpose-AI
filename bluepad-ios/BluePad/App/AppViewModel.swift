import Foundation
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Hashable {
    case trackpad
    case keyboard
    case remote
    case tools
    case connection
}

/// Central @MainActor coordinator connecting CoreBluetooth HOGP, Motion, Speech, Storage, and UI.
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: Services
    let bleService: BLEHIDPeripheralService
    let wifiService: WiFiHIDTransportService
    let tvService: SmartTVRemoteService
    let airMouseService: AirMouseMotionService
    let dictationService: SpeechDictationService
    private let storageService: MacroStorageService
    private var motionProcessor = MouseMotionProcessor()
    private var tvTrackpadNavigator = TVTrackpadNavigator()

    // MARK: Published State
    @Published var selectedTab: AppTab = .trackpad
    @Published private(set) var connectionState: BLEConnectionState = .unknown
    @Published private(set) var protocolMode: HIDProtocolMode = .report
    @Published private(set) var ledState: HIDLEDState = []

    @Published private(set) var wifiState: WiFiConnectionState = .disconnected
    @Published private(set) var wifiHosts: [WiFiHostEndpoint] = []
    @Published private(set) var isScanningWiFi: Bool = false
    @Published private(set) var tvState: SmartTVConnectionState = .disconnected
    @Published private(set) var discoveredTVs: [SmartTVEndpoint] = []
    @Published private(set) var selectedTVKind: SmartTVKind = .androidTV
    @Published private(set) var connectedBLEHostName: String? = nil
    @Published private(set) var gamepadState = HIDGamepadState()
    @Published var isFullScreenTrackpad: Bool = false

    var activeTarget: ActiveConnectionTarget {
        if connectionState.isConnected {
            let fallbackName = discoveredHosts.first(where: { $0.linkState.isConnected || $0.isSystemConnected })?.name ?? "Bluetooth Cihazı"
            return .bluetooth(hostName: connectedBLEHostName ?? fallbackName)
        }
        if case .connected(let hostName, _) = wifiState {
            return .wifiPC(hostName: hostName)
        }
        if case .connecting(let target) = wifiState {
            return .wifiPC(hostName: target)
        }
        switch tvState {
        case .connected(let tvName, _, let kind):
            return .smartTV(name: tvName, kind: kind)
        case .connecting(let target):
            return .smartTV(name: target, kind: selectedTVKind)
        case .awaitingPairingCode(let tvName, _):
            return .smartTV(name: tvName, kind: .androidTV)
        case .awaitingTVApproval(let tvName, _, let kind):
            return .smartTV(name: tvName, kind: kind)
        case .verifyingCode:
            return .smartTV(name: "TV Doğrulama", kind: selectedTVKind)
        case .disconnected, .failed:
            return .none
        }
    }

    var isAnyTransportConnected: Bool {
        connectionState.isConnected || wifiState.isConnected || tvState.isConnected
    }

    var combinedStatusText: String {
        switch activeTarget {
        case .bluetooth(let hostName):
            return "BLE Bağlı · \(hostName)"
        case .wifiPC:
            return wifiState.statusText
        case .smartTV:
            return tvState.statusText
        case .none:
            return connectionState.statusText
        }
    }

    @Published var settings: BluePadSettings {
        didSet {
            var clamped = settings
            clamped.clampToValidRanges()
            if clamped != settings {
                settings = clamped
                return
            }
            storageService.saveSettings(settings)
            updateIdleTimer()
        }
    }

    @Published var macros: [CustomMacro] {
        didSet {
            storageService.saveMacros(macros)
        }
    }

    @Published private(set) var armedModifiers: HIDModifier = []
    @Published private(set) var lockedModifiers: HIDModifier = []
    @Published var pressedButtons: HIDMouseButton = []

    @Published private(set) var isJigglerActive: Bool = false
    @Published private(set) var jigglerCountdownSeconds: Int = 45
    @Published private(set) var isAirMouseActive: Bool = false
    @Published private(set) var isTypingText: Bool = false
    @Published private(set) var typingProgress: Double = 0

    @Published var lastScannedBarcode: String = ""
    @Published var isScannerPresented: Bool = false

    @Published private(set) var packetsSentCount: Int = 0
    @Published private(set) var discoveredHosts: [DiscoveredBLEHost] = []
    @Published private(set) var isScanningHosts: Bool = false
    @Published private(set) var gattStatus: HOGPServiceStatus = HOGPServiceStatus()
    @Published private(set) var diagnosticEvents: [HIDDiagnosticEvent] = []
    @Published var toastMessage: String?

    // MARK: Private Tasks & Haptics
    private var jigglerTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
    private var macroTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var hasStartedBLE = false

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)

    // MARK: Init
    init(storageService: MacroStorageService = MacroStorageService()) {
        self.storageService = storageService
        self.settings = storageService.loadSettings()
        self.macros = storageService.loadMacros()
        self.bleService = BLEHIDPeripheralService()
        self.wifiService = WiFiHIDTransportService()
        self.tvService = SmartTVRemoteService()
        self.airMouseService = AirMouseMotionService()
        self.dictationService = SpeechDictationService()
        self.jigglerCountdownSeconds = self.settings.jigglerIntervalSeconds

        wireBLECallbacks()
    }

    private func wireBLECallbacks() {
        bleService.onStateChange = { [weak self] state in
            self?.connectionState = state
            self?.updateIdleTimer()
        }
        bleService.onLEDStateChange = { [weak self] led in
            self?.ledState = led
        }
        bleService.onProtocolModeChange = { [weak self] mode in
            self?.protocolMode = mode
        }
        bleService.onPacketSent = { [weak self] in
            self?.packetsSentCount += 1
        }
        bleService.onDiagnosticEvent = { [weak self] event in
            self?.appendDiagnostic(event)
        }
        bleService.onDiscoveredHostsChange = { [weak self] hosts in
            self?.discoveredHosts = hosts
        }
        bleService.onScanningStateChange = { [weak self] scanning in
            self?.isScanningHosts = scanning
        }
        bleService.onGATTStatusChange = { [weak self] status in
            self?.gattStatus = status
        }
        bleService.onConnectedHostNameChange = { [weak self] hostName in
            self?.connectedBLEHostName = hostName
        }

        wifiService.onStateChange = { [weak self] state in
            self?.wifiState = state
        }
        wifiService.onDiscoveredHostsChange = { [weak self] hosts in
            self?.wifiHosts = hosts
        }
        wifiService.onDiagnosticEvent = { [weak self] event in
            self?.appendDiagnostic(event)
        }
        wifiService.onPacketSent = { [weak self] in
            self?.packetsSentCount += 1
        }

        tvService.onStateChange = { [weak self] state in
            self?.tvState = state
        }
        tvService.onDiscoveredTVsChange = { [weak self] tvs in
            self?.discoveredTVs = tvs
        }
        tvService.onDiagnosticEvent = { [weak self] event in
            self?.appendDiagnostic(event)
        }
        tvService.onPacketSent = { [weak self] in
            self?.packetsSentCount += 1
        }
    }

    // MARK: Bluetooth, Wi-Fi & Exclusive Single-Target Lifecycle

    func startBluetoothIfNeeded() {
        guard !hasStartedBLE else { return }
        hasStartedBLE = true
        bleService.start(advertisedName: settings.advertisedName)
        startWiFiDiscovery()
        tvService.startDiscovery()
    }

    private func ensureNoOtherActiveTarget(for intended: String) -> Bool {
        guard activeTarget.isActive else { return true }
        triggerHaptic(.rigid)
        showToast("Önce mevcut bağlantıyı (\(activeTarget.displayName)) kesin.")
        appendDiagnostic(
            HIDDiagnosticEvent(
                category: .ble,
                message: "Tek cihaz kilidi: '\(intended)' reddedildi (Aktif: \(activeTarget.displayName))."
            )
        )
        return false
    }

    func disconnectActiveTarget() {
        triggerHaptic(.medium)
        switch activeTarget {
        case .bluetooth(let name):
            bleService.disconnectHIDSession()
            showToast("Bluetooth bağlantısı kesildi (\(name))")
        case .wifiPC(let name):
            wifiService.disconnect()
            showToast("Wi-Fi bağlantısı kesildi (\(name))")
        case .smartTV(let name, _):
            tvService.disconnect()
            showToast("TV bağlantısı kesildi (\(name))")
        case .none:
            if connectionState.isActiveRadio {
                bleService.stop()
                showToast("Bluetooth yayını durduruldu")
            }
        }
    }

    func toggleBluetoothAdvertising() {
        triggerHaptic(.medium)
        if connectionState.isConnected {
            bleService.disconnectHIDSession()
            showToast("Bluetooth HID bağlantısı kesildi")
        } else if connectionState.isActiveRadio {
            bleService.stop()
            showToast("Bluetooth yayını durduruldu")
        } else {
            guard ensureNoOtherActiveTarget(for: "Bluetooth Yayını") else { return }
            hasStartedBLE = true
            bleService.start(advertisedName: settings.advertisedName)
            showToast("Bluetooth yayını başlatıldı")
        }
    }

    func applyAdvertisedName(_ name: String) {
        var updated = settings
        updated.advertisedName = name
        updated.clampToValidRanges()
        settings = updated
        bleService.restartAdvertising(name: settings.advertisedName)
        triggerHaptic(.light)
        showToast("Yayın adı güncellendi: \(settings.advertisedName)")
    }

    func releaseAllInputs() {
        macroTask?.cancel()
        armedModifiers = []
        lockedModifiers = []
        pressedButtons = []
        gamepadState = HIDGamepadState()
        motionProcessor.reset()
        tvTrackpadNavigator.reset()
        switch activeTarget {
        case .bluetooth:
            bleService.releaseAllKeys()
        case .wifiPC:
            wifiService.releaseAll()
        case .smartTV, .none:
            break
        }
        triggerHaptic(.rigid)
        showToast("Tüm tuşlar serbest bırakıldı")
    }

    // MARK: Wi-Fi Local Network Transport

    func startWiFiDiscovery() {
        isScanningWiFi = true
        wifiService.startDiscovery()
    }

    func stopWiFiDiscovery() {
        isScanningWiFi = false
        wifiService.stopDiscovery()
    }

    func connectWiFi(host: String, port: UInt16, pin: String) {
        guard ensureNoOtherActiveTarget(for: "Wi-Fi PC") else { return }
        bleService.stop()
        triggerHaptic(.medium)
        wifiService.connect(host: host, port: port, pin: pin, deviceName: settings.advertisedName)
        showToast("Wi-Fi bağlantısı başlatılıyor: \(host):\(port)")
    }

    func disconnectWiFi() {
        triggerHaptic(.light)
        wifiService.disconnect()
        showToast("Wi-Fi bağlantısı kesildi")
    }

    // MARK: Smart TV / Google / Samsung / LG / Vestel Wi-Fi Remote

    func refreshTVDiscovery() {
        triggerHaptic(.light)
        tvService.startDiscovery()
        showToast("Smart TV ağı yeniden taranıyor...")
    }

    func connectSmartTV(host: String, name: String? = nil, kind: SmartTVKind = .androidTV) {
        guard ensureNoOtherActiveTarget(for: kind.displayName) else { return }
        selectedTVKind = kind
        bleService.stop()
        triggerHaptic(.medium)
        tvService.connect(host: host, name: name, kind: kind, deviceName: settings.advertisedName)
        showToast("TV bağlantısı başlatılıyor: \(name ?? host)")
    }

    func submitTVPairingCode(_ code: String) {
        triggerHaptic(.medium)
        tvService.submitPairingCode(code)
    }

    func disconnectSmartTV() {
        triggerHaptic(.light)
        tvService.disconnect()
        showToast("TV bağlantısı kesildi")
    }

    func launchTVApp(url: String, title: String) {
        triggerHaptic(.medium)
        tvService.launchApp(url: url)
        showToast("TV'de açılıyor: \(title)")
    }

    func sendTVInputSource() {
        triggerHaptic(.light)
        guard tvState.isConnected else { return }
        tvService.sendInputSource()
    }

    func runConnectionTestPulse() {
        triggerHaptic(.medium)
        switch activeTarget {
        case .bluetooth:
            appendDiagnostic(HIDDiagnosticEvent(category: .tx, message: "Bluetooth bağlantı testi (±36 px)."))
            bleService.sendMouseMove(dx: 36, dy: 0)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.bleService.sendMouseMove(dx: -36, dy: 0)
            }
            showToast("Bluetooth test sinyali gönderildi")
        case .wifiPC:
            appendDiagnostic(HIDDiagnosticEvent(category: .tx, message: "Wi-Fi bağlantı testi (±36 px)."))
            wifiService.sendMouseMove(dx: 36, dy: 0)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.wifiService.sendMouseMove(dx: -36, dy: 0)
            }
            showToast("Wi-Fi test sinyali gönderildi")
        case .smartTV(_, let kind):
            if kind.supportsDirectPointer {
                appendDiagnostic(HIDDiagnosticEvent(category: .tx, message: "\(kind.shortLabel) imleç testi (±48 px)."))
                tvService.sendMouseMove(dx: 48, dy: 0)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    self?.tvService.sendMouseMove(dx: -48, dy: 0)
                }
            } else {
                appendDiagnostic(HIDDiagnosticEvent(category: .tx, message: "\(kind.shortLabel) yön testi (Sağ/Sol)."))
                tvService.sendKey(hidKeyCode: .rightArrow)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    self?.tvService.sendKey(hidKeyCode: .leftArrow)
                }
            }
            showToast("\(kind.shortLabel) test sinyali gönderildi")
        case .none:
            showToast("Önce bir cihaza bağlanın")
        }
    }

    func toggleHostScan() {
        triggerHaptic(.light)
        if isScanningHosts {
            bleService.stopHostScan()
            showToast("Cihaz taraması durduruldu")
        } else {
            bleService.startHostScan()
            showToast("Yakındaki cihazlar taranıyor...")
        }
    }

    func connectToHost(_ host: DiscoveredBLEHost) {
        guard ensureNoOtherActiveTarget(for: "Bluetooth (\(host.name))") else { return }
        if host.manufacturerName?.contains("Microsoft") == true {
            triggerHaptic(.medium)
            showToast("Windows'ta PC tarafındaki Bluetooth ekranından veya BluePad_Windows_Esle.bat ile eşleştirin.")
            appendDiagnostic(
                HIDDiagnosticEvent(
                    category: .ble,
                    message: "Windows PC (\(host.name)) giden taramadan değil bilgisayardan eşleştirilir."
                )
            )
            return
        }
        triggerHaptic(.medium)
        bleService.connectToHost(id: host.id)
        showToast("Bağlanılıyor: \(host.name)")
    }

    func disconnectFromHost(_ host: DiscoveredBLEHost) {
        triggerHaptic(.light)
        bleService.disconnectFromHost(id: host.id)
        showToast("Bağlantı kesildi: \(host.name)")
    }

    func disconnectHostOrHID(_ host: DiscoveredBLEHost) {
        triggerHaptic(.medium)
        if connectionState.isConnected && (host.isSystemConnected || host.linkState.isConnected) {
            bleService.disconnectHIDSession()
            showToast("Bluetooth HID bağlantısı kesildi: \(host.name)")
        } else {
            bleService.disconnectFromHost(id: host.id)
            showToast("Bağlantı kesildi: \(host.name)")
        }
    }

    func triggerServiceChangedRefresh() {
        triggerHaptic(.light)
        bleService.triggerServiceChangedRefresh()
        showToast("GATT Service Changed gönderildi")
    }

    func handleAppDidBecomeActive() {
        if !activeTarget.isActive || activeTarget.isBluetooth {
            bleService.ensureAdvertisingOnForeground()
        }
        updateIdleTimer()
    }

    // MARK: Trackpad & Mouse (Exclusive Target Routing)

    func handleTrackpadMove(rawDX: Double, rawDY: Double) {
        switch activeTarget {
        case .bluetooth:
            let step = motionProcessor.processMove(
                rawDX: rawDX,
                rawDY: rawDY,
                sensitivity: settings.pointerSensitivity,
                acceleration: settings.pointerAcceleration
            )
            if step.dx != 0 || step.dy != 0 {
                bleService.sendMouseMove(dx: step.dx, dy: step.dy)
            }
        case .wifiPC:
            let step = motionProcessor.processMove(
                rawDX: rawDX,
                rawDY: rawDY,
                sensitivity: settings.pointerSensitivity,
                acceleration: settings.pointerAcceleration
            )
            if step.dx != 0 || step.dy != 0 {
                wifiService.sendMouseMove(dx: step.dx, dy: step.dy)
            }
        case .smartTV(_, let kind):
            if kind.supportsDirectPointer {
                let step = motionProcessor.processMove(
                    rawDX: rawDX,
                    rawDY: rawDY,
                    sensitivity: settings.pointerSensitivity,
                    acceleration: settings.pointerAcceleration
                )
                if step.dx != 0 || step.dy != 0 {
                    tvService.sendMouseMove(
                        dx: step.dx,
                        dy: step.dy,
                        buttonDown: pressedButtons.contains(.left)
                    )
                }
            } else {
                let navKeys = tvTrackpadNavigator.processSwipe(
                    rawDX: rawDX,
                    rawDY: rawDY,
                    sensitivity: settings.pointerSensitivity
                )
                for key in navKeys {
                    tvService.sendKey(hidKeyCode: key)
                    triggerHaptic(.light)
                }
            }
        case .none:
            break
        }
    }

    func handleTrackpadScroll(rawDX: Double, rawDY: Double) {
        let step = motionProcessor.processScroll(
            rawDX: rawDX,
            rawDY: rawDY,
            sensitivity: settings.scrollSensitivity,
            naturalScrolling: settings.naturalScrolling
        )
        guard step.wheel != 0 || step.hWheel != 0 else { return }
        switch activeTarget {
        case .bluetooth:
            bleService.sendMouseMove(dx: 0, dy: 0, wheel: step.wheel, hWheel: step.hWheel)
        case .wifiPC:
            wifiService.sendMouseMove(dx: 0, dy: 0, wheel: step.wheel, hWheel: step.hWheel)
        case .smartTV(_, let kind):
            if kind.supportsDirectPointer {
                tvService.sendMouseScroll(wheel: step.wheel, hWheel: step.hWheel)
            } else {
                if step.wheel != 0 {
                    let key: HIDKeyCode = step.wheel > 0 ? .upArrow : .downArrow
                    for _ in 0..<min(4, abs(step.wheel)) {
                        tvService.sendKey(hidKeyCode: key)
                    }
                }
                if step.hWheel != 0 {
                    let key: HIDKeyCode = step.hWheel > 0 ? .rightArrow : .leftArrow
                    for _ in 0..<min(4, abs(step.hWheel)) {
                        tvService.sendKey(hidKeyCode: key)
                    }
                }
            }
        case .none:
            break
        }
    }

    func resetTrackpadMotion() {
        motionProcessor.reset()
        tvTrackpadNavigator.reset()
    }

    func clickMouse(_ button: HIDMouseButton) {
        triggerHaptic(.light)
        switch activeTarget {
        case .bluetooth:
            bleService.clickMouseButton(button)
        case .wifiPC:
            wifiService.clickMouseButton(button)
        case .smartTV(_, let kind):
            if kind.supportsDirectPointer {
                tvService.sendMouseClick(button)
            } else {
                sendTVTrackpadButton(button)
            }
        case .none:
            break
        }
    }

    func setMouseButton(_ button: HIDMouseButton, pressed: Bool) {
        if pressed {
            pressedButtons.insert(button)
            triggerHaptic(.light)
        } else {
            pressedButtons.remove(button)
        }
        switch activeTarget {
        case .bluetooth:
            bleService.setMouseButton(button, pressed: pressed)
        case .wifiPC:
            wifiService.sendMouseButton(button, pressed: pressed)
        case .smartTV(_, let kind):
            if pressed {
                if kind.supportsDirectPointer {
                    tvService.sendMouseClick(button)
                } else {
                    sendTVTrackpadButton(button)
                }
            }
        case .none:
            break
        }
    }

    private func sendTVTrackpadButton(_ button: HIDMouseButton) {
        if button.contains(.left) || button.contains(.forward) {
            tvService.sendKey(hidKeyCode: .enter)
        } else if button.contains(.right) || button.contains(.back) {
            tvService.sendKey(hidKeyCode: .escape)
        } else if button.contains(.middle) {
            tvService.sendKey(hidKeyCode: .home)
        }
    }

    // MARK: Gamepad Controls

    func setGamepadButton(_ button: HIDGamepadButton, pressed: Bool) {
        if pressed {
            gamepadState.buttons.insert(button)
            triggerHaptic(.light)
        } else {
            gamepadState.buttons.remove(button)
        }
        pushGamepadState()
    }

    func setGamepadHat(_ hat: HIDGamepadHat) {
        guard gamepadState.hat != hat else { return }
        if hat != .center {
            triggerHaptic(.light)
        }
        gamepadState.hat = hat
        pushGamepadState()
    }

    func setGamepadLeftStick(x: Int8, y: Int8) {
        guard gamepadState.leftX != x || gamepadState.leftY != y else { return }
        gamepadState.leftX = x
        gamepadState.leftY = y
        pushGamepadState()
    }

    func setGamepadRightStick(x: Int8, y: Int8) {
        guard gamepadState.rightX != x || gamepadState.rightY != y else { return }
        gamepadState.rightX = x
        gamepadState.rightY = y
        pushGamepadState()
    }

    func resetGamepad() {
        gamepadState = HIDGamepadState()
        pushGamepadState()
        triggerHaptic(.medium)
        showToast("Gamepad sıfırlandı")
    }

    private func pushGamepadState() {
        switch activeTarget {
        case .bluetooth:
            bleService.sendGamepad(gamepadState)
        case .wifiPC:
            wifiService.sendGamepad(gamepadState)
        case .smartTV, .none:
            break
        }
    }

    // MARK: Air Mouse (Gyroscope)

    func toggleAirMouse() {
        if isAirMouseActive {
            stopAirMouse()
        } else {
            startAirMouse()
        }
    }

    func startAirMouse() {
        guard airMouseService.isAvailable else {
            showToast("Jiroskop sensörü bu cihazda kullanılamıyor")
            return
        }
        motionProcessor.reset()
        isAirMouseActive = true
        triggerHaptic(.medium)
        airMouseService.start(
            sensitivityProvider: { [weak self] in
                self?.settings.airMouseSensitivity ?? 1.2
            },
            onDelta: { [weak self] dx, dy in
                guard let self else { return }
                let step = self.motionProcessor.processMove(
                    rawDX: dx,
                    rawDY: dy,
                    sensitivity: 1.0,
                    acceleration: false
                )
                guard step.dx != 0 || step.dy != 0 else { return }
                switch self.activeTarget {
                case .bluetooth:
                    self.bleService.sendMouseMove(dx: step.dx, dy: step.dy)
                case .wifiPC:
                    self.wifiService.sendMouseMove(dx: step.dx, dy: step.dy)
                case .smartTV(_, let kind):
                    if kind.supportsDirectPointer {
                        self.tvService.sendMouseMove(dx: step.dx, dy: step.dy)
                    }
                case .none:
                    break
                }
            }
        )
        showToast("Hava Faresi aktif")
    }

    func stopAirMouse() {
        guard isAirMouseActive else { return }
        airMouseService.stop()
        motionProcessor.reset()
        isAirMouseActive = false
        triggerHaptic(.light)
    }

    // MARK: Modifiers & Keyboard

    var effectiveModifiers: HIDModifier {
        armedModifiers.union(lockedModifiers)
    }

    func tapModifier(_ modifier: HIDModifier) {
        triggerHaptic(.light)
        if lockedModifiers.contains(modifier) {
            lockedModifiers.remove(modifier)
            armedModifiers.remove(modifier)
        } else if armedModifiers.contains(modifier) {
            armedModifiers.remove(modifier)
        } else {
            armedModifiers.insert(modifier)
        }
    }

    func toggleLockModifier(_ modifier: HIDModifier) {
        triggerHaptic(.medium)
        armedModifiers.remove(modifier)
        if lockedModifiers.contains(modifier) {
            lockedModifiers.remove(modifier)
        } else {
            lockedModifiers.insert(modifier)
        }
    }

    func sendKey(_ keyCode: HIDKeyCode, extraModifiers: HIDModifier = []) {
        sendRawKey(keyCode.rawValue, extraModifiers: extraModifiers)
    }

    func sendRawKey(_ keyCode: UInt8, extraModifiers: HIDModifier = []) {
        let combined = effectiveModifiers.union(extraModifiers)
        switch activeTarget {
        case .bluetooth:
            bleService.tapKey(keyCode, modifiers: combined)
        case .wifiPC:
            wifiService.tapKey(keyCode, modifiers: combined)
        case .smartTV:
            if let key = HIDKeyCode(rawValue: keyCode) {
                tvService.sendKey(hidKeyCode: key)
            }
        case .none:
            break
        }
        armedModifiers = []
        triggerHaptic(.light)
    }

    func sendTypedCharacter(_ character: Character) {
        if character == "\n" {
            sendKey(.enter)
            return
        }
        if character == "\t" {
            sendKey(.tab)
            return
        }

        let activeMods = effectiveModifiers
        let hasCommandMod = !activeMods.intersection([.leftControl, .rightControl, .leftAlt, .leftGUI, .rightGUI]).isEmpty

        switch activeTarget {
        case .bluetooth:
            if let stroke = KeyboardLayoutEngine.keyStroke(for: character, layout: settings.keyboardLayout) {
                let baseMods = hasCommandMod ? activeMods : stroke.modifiers.union(activeMods)
                bleService.tapKey(stroke.keyCode, modifiers: baseMods)
                armedModifiers = []
                triggerHaptic(.light)
            } else {
                showToast("Bu düzende eşlenemeyen karakter: \(character)")
            }
        case .wifiPC:
            if hasCommandMod, let stroke = KeyboardLayoutEngine.keyStroke(for: character, layout: settings.keyboardLayout) {
                wifiService.tapKey(stroke.keyCode, modifiers: activeMods)
            } else {
                wifiService.sendText(String(character), appendEnter: false)
            }
            armedModifiers = []
            triggerHaptic(.light)
        case .smartTV:
            tvService.sendText(String(character), appendEnter: false)
            armedModifiers = []
            triggerHaptic(.light)
        case .none:
            if KeyboardLayoutEngine.keyStroke(for: character, layout: settings.keyboardLayout) == nil {
                showToast("Bu düzende eşlenemeyen karakter: \(character)")
            }
        }
    }

    func typeText(_ text: String, appendEnter: Bool = false) {
        switch activeTarget {
        case .wifiPC:
            wifiService.sendText(text, appendEnter: appendEnter)
            return
        case .smartTV:
            tvService.sendText(text, appendEnter: appendEnter)
            return
        case .none:
            return
        case .bluetooth:
            break
        }

        let payload = appendEnter ? text + "\n" : text
        let strokes = KeyboardLayoutEngine.keyStrokes(for: payload, layout: settings.keyboardLayout)

        guard !strokes.isEmpty else {
            showToast("Gönderilecek desteklenen metin bulunamadı")
            return
        }

        typingTask?.cancel()
        isTypingText = true
        typingProgress = 0
        let delayMs = max(5, settings.typingDelayMs)
        let total = strokes.count

        typingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isTypingText = false
                self.typingProgress = 0
                self.bleService.sendKeyboard(modifiers: [], keys: [])
            }

            let halfDelayNs = UInt64(delayMs) * 500_000
            for (index, stroke) in strokes.enumerated() {
                if Task.isCancelled { break }
                self.bleService.sendKeyboard(modifiers: stroke.modifiers, keys: [stroke.keyCode])
                try? await Task.sleep(nanoseconds: halfDelayNs)
                if Task.isCancelled { break }
                self.bleService.sendKeyboard(modifiers: [], keys: [])
                try? await Task.sleep(nanoseconds: halfDelayNs)
                self.typingProgress = Double(index + 1) / Double(total)
            }
        }
    }

    func cancelTyping() {
        typingTask?.cancel()
        typingTask = nil
        isTypingText = false
        typingProgress = 0
        bleService.sendKeyboard(modifiers: [], keys: [])
        showToast("Metin gönderimi durduruldu")
    }

    func pasteClipboard(appendEnter: Bool = false) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            showToast("iPhone panosu boş")
            return
        }
        triggerHaptic(.medium)
        showToast("Pano yazılıyor (\(text.count) karakter)")
        typeText(text, appendEnter: appendEnter)
    }

    func handleScannedBarcode(_ code: String) {
        isScannerPresented = false
        if let pairing = WiFiHIDTransportService.parsePairingQR(code) {
            triggerHaptic(.medium)
            connectWiFi(host: pairing.host, port: pairing.port, pin: pairing.pin)
            showToast("Wi-Fi QR algılandı: \(pairing.host)")
            return
        }

        lastScannedBarcode = code
        triggerHaptic(.medium)
        showToast("Tarandı ve yazılıyor: \(code)")
        typeText(code, appendEnter: settings.scannerAutoEnter)
    }

    // MARK: Media & System Keys

    func tapConsumer(_ usage: HIDConsumerUsage) {
        triggerHaptic(.light)
        switch activeTarget {
        case .bluetooth:
            bleService.tapConsumer(usage)
        case .wifiPC:
            wifiService.tapConsumer(usage)
        case .smartTV:
            tvService.sendConsumer(usage)
        case .none:
            break
        }
    }

    func pressConsumer(_ usage: HIDConsumerUsage) {
        triggerHaptic(.light)
        switch activeTarget {
        case .bluetooth:
            bleService.sendConsumerPress(usage)
        case .wifiPC:
            wifiService.tapConsumer(usage)
        case .smartTV:
            tvService.sendConsumer(usage)
        case .none:
            break
        }
    }

    func releaseConsumer() {
        if activeTarget.isBluetooth {
            bleService.sendConsumerRelease()
        }
    }

    func tapSystem(_ usage: HIDSystemUsage) {
        triggerHaptic(.medium)
        switch activeTarget {
        case .bluetooth:
            bleService.tapSystem(usage)
        case .wifiPC:
            wifiService.tapSystem(usage)
        case .smartTV:
            tvService.sendSystem(usage)
        case .none:
            break
        }
    }

    // MARK: Macros

    func runMacro(_ macro: CustomMacro) {
        triggerHaptic(.medium)
        switch macro.action {
        case .keyCombo(let keyCode, let modifiersRaw):
            let mods = HIDModifier(rawValue: modifiersRaw)
            switch activeTarget {
            case .bluetooth:
                bleService.tapKey(keyCode, modifiers: mods)
            case .wifiPC:
                wifiService.tapKey(keyCode, modifiers: mods)
            case .smartTV:
                if let key = HIDKeyCode(rawValue: keyCode) {
                    tvService.sendKey(hidKeyCode: key)
                }
            case .none:
                break
            }
            showToast("Makro: \(macro.title)")
        case .typeText(let text, let appendEnter):
            showToast("Yazılıyor: \(macro.title)")
            typeText(text, appendEnter: appendEnter)
        case .consumerKey(let usageRaw):
            if let usage = HIDConsumerUsage(rawValue: usageRaw) {
                switch activeTarget {
                case .bluetooth:
                    bleService.tapConsumer(usage)
                case .wifiPC:
                    wifiService.tapConsumer(usage)
                case .smartTV:
                    tvService.sendConsumer(usage)
                case .none:
                    break
                }
                showToast("Medya: \(macro.title)")
            }
        case .systemKey(let usageRaw):
            let sys = HIDSystemUsage(rawValue: usageRaw)
            switch activeTarget {
            case .bluetooth:
                bleService.tapSystem(sys)
            case .wifiPC:
                wifiService.tapSystem(sys)
            case .smartTV:
                tvService.sendSystem(sys)
            case .none:
                break
            }
            showToast("Sistem: \(macro.title)")
        case .sequence(let steps):
            showToast("Dizi çalıştırılıyor: \(macro.title)")
            runMacroSequence(steps)
        }
    }

    private func runMacroSequence(_ steps: [MacroStep]) {
        macroTask?.cancel()
        macroTask = Task { [weak self] in
            guard let self else { return }
            for step in steps {
                if Task.isCancelled { break }
                switch step {
                case .keyCombo(let keyCode, let modifiersRaw):
                    let mods = HIDModifier(rawValue: modifiersRaw)
                    switch self.activeTarget {
                    case .bluetooth:
                        self.bleService.tapKey(keyCode, modifiers: mods)
                    case .wifiPC:
                        self.wifiService.tapKey(keyCode, modifiers: mods)
                    case .smartTV:
                        if let key = HIDKeyCode(rawValue: keyCode) {
                            self.tvService.sendKey(hidKeyCode: key)
                        }
                    case .none:
                        break
                    }
                case .typeText(let text, let appendEnter):
                    self.typeText(text, appendEnter: appendEnter)
                    if self.activeTarget.isBluetooth {
                        let charCount = text.count + (appendEnter ? 1 : 0)
                        let estNs = UInt64(max(60, charCount * max(5, self.settings.typingDelayMs) + 40)) * 1_000_000
                        try? await Task.sleep(nanoseconds: estNs)
                    }
                case .consumerKey(let usageRaw):
                    if let usage = HIDConsumerUsage(rawValue: usageRaw) {
                        switch self.activeTarget {
                        case .bluetooth:
                            self.bleService.tapConsumer(usage)
                        case .wifiPC:
                            self.wifiService.tapConsumer(usage)
                        case .smartTV:
                            self.tvService.sendConsumer(usage)
                        case .none:
                            break
                        }
                    }
                case .delayMs(let ms):
                    let clamped = min(5_000, max(10, ms))
                    try? await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000)
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    func addOrUpdateMacro(_ macro: CustomMacro) {
        if let idx = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[idx] = macro
        } else {
            macros.append(macro)
        }
        triggerHaptic(.light)
    }

    func deleteMacro(id: UUID) {
        macros.removeAll { $0.id == id }
        triggerHaptic(.light)
    }

    func resetDefaultMacros() {
        macros = CustomMacro.defaultPresets
        triggerHaptic(.medium)
        showToast("Varsayılan makrolar geri yüklendi")
    }

    // MARK: Keep-Alive / Mouse Jiggler

    func toggleJiggler() {
        if isJigglerActive {
            stopJiggler()
        } else {
            startJiggler()
        }
    }

    func startJiggler() {
        jigglerTask?.cancel()
        isJigglerActive = true
        jigglerCountdownSeconds = settings.jigglerIntervalSeconds
        updateIdleTimer()
        triggerHaptic(.medium)
        showToast("Uyanık Tut (Jiggler) başlatıldı")

        jigglerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isJigglerActive {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled || !self.isJigglerActive { break }

                if self.jigglerCountdownSeconds > 1 {
                    self.jigglerCountdownSeconds -= 1
                } else {
                    self.performJigglePulse()
                    self.jigglerCountdownSeconds = self.settings.jigglerIntervalSeconds
                }
            }
        }
    }

    func stopJiggler() {
        jigglerTask?.cancel()
        jigglerTask = nil
        isJigglerActive = false
        updateIdleTimer()
        triggerHaptic(.light)
        showToast("Uyanık Tut durduruldu")
    }

    private func updateIdleTimer() {
        let keepAwake = isJigglerActive || (settings.keepScreenAwakeWhileAdvertising && connectionState.isActiveRadio)
        UIApplication.shared.isIdleTimerDisabled = keepAwake
    }

    private func performJigglePulse() {
        switch settings.jigglerMode {
        case .microMouse:
            switch activeTarget {
            case .bluetooth:
                bleService.sendMouseMove(dx: 1, dy: 0)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    self?.bleService.sendMouseMove(dx: -1, dy: 0)
                }
            case .wifiPC:
                wifiService.sendMouseMove(dx: 1, dy: 0)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    self?.wifiService.sendMouseMove(dx: -1, dy: 0)
                }
            case .smartTV(_, let kind) where kind.supportsDirectPointer:
                tvService.sendMouseMove(dx: 1, dy: 0)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    self?.tvService.sendMouseMove(dx: -1, dy: 0)
                }
            case .smartTV, .none:
                break
            }
        case .shiftPulse:
            switch activeTarget {
            case .bluetooth:
                bleService.tapKey(HIDKeyCode.none.rawValue, modifiers: .leftShift)
            case .wifiPC:
                wifiService.tapKey(HIDKeyCode.none.rawValue, modifiers: .leftShift)
            case .smartTV, .none:
                break
            }
        }
    }

    // MARK: Diagnostics & Helpers

    func clearDiagnostics() {
        diagnosticEvents.removeAll()
        triggerHaptic(.light)
    }

    func diagnosticsLogText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return diagnosticEvents.map { event in
            let time = formatter.string(from: event.timestamp)
            if let hex = event.hexPayload {
                return "[\(time)] [\(event.category.rawValue)] \(event.message) | \(hex)"
            }
            return "[\(time)] [\(event.category.rawValue)] \(event.message)"
        }.joined(separator: "\n")
    }

    private func appendDiagnostic(_ event: HIDDiagnosticEvent) {
        diagnosticEvents.insert(event, at: 0)
        if diagnosticEvents.count > 120 {
            diagnosticEvents.removeLast(diagnosticEvents.count - 120)
        }
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            toastMessage = message
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.toastMessage = nil
            }
        }
    }

    func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard settings.hapticsEnabled else { return }
        switch style {
        case .light:
            lightImpact.impactOccurred()
        case .medium:
            mediumImpact.impactOccurred()
        default:
            rigidImpact.impactOccurred()
        }
    }
}
