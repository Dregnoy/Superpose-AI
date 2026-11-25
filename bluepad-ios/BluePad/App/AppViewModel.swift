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
    let airMouseService: AirMouseMotionService
    let dictationService: SpeechDictationService
    private let storageService: MacroStorageService
    private var motionProcessor = MouseMotionProcessor()

    // MARK: Published State
    @Published var selectedTab: AppTab = .trackpad
    @Published private(set) var connectionState: BLEConnectionState = .unknown
    @Published private(set) var protocolMode: HIDProtocolMode = .report
    @Published private(set) var ledState: HIDLEDState = []

    @Published private(set) var wifiState: WiFiConnectionState = .disconnected
    @Published private(set) var wifiHosts: [WiFiHostEndpoint] = []
    @Published private(set) var isScanningWiFi: Bool = false
    @Published private(set) var gamepadState = HIDGamepadState()
    @Published var isFullScreenTrackpad: Bool = false

    var isAnyTransportConnected: Bool {
        connectionState.isConnected || wifiState.isConnected
    }

    var combinedStatusText: String {
        if connectionState.isConnected && wifiState.isConnected {
            return "BLE + Wi-Fi Bağlı"
        }
        if wifiState.isConnected {
            return wifiState.statusText
        }
        return connectionState.statusText
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
    }

    // MARK: Bluetooth & Wi-Fi Lifecycle

    func startBluetoothIfNeeded() {
        guard !hasStartedBLE else { return }
        hasStartedBLE = true
        bleService.start(advertisedName: settings.advertisedName)
        startWiFiDiscovery()
    }

    func toggleBluetoothAdvertising() {
        triggerHaptic(.medium)
        if connectionState.isActiveRadio {
            bleService.stop()
            showToast("Bluetooth yayını durduruldu")
        } else {
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
        bleService.releaseAllKeys()
        if wifiState.isConnected {
            wifiService.releaseAll()
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
        triggerHaptic(.medium)
        wifiService.connect(host: host, port: port, pin: pin, deviceName: settings.advertisedName)
        showToast("Wi-Fi bağlantısı başlatılıyor: \(host):\(port)")
    }

    func disconnectWiFi() {
        triggerHaptic(.light)
        wifiService.disconnect()
        showToast("Wi-Fi bağlantısı kesildi")
    }

    func runConnectionTestPulse() {
        triggerHaptic(.medium)
        appendDiagnostic(HIDDiagnosticEvent(category: .tx, message: "Bağlantı testi sinyali gönderildi (±36 px)."))
        bleService.sendMouseMove(dx: 36, dy: 0)
        if wifiState.isConnected {
            wifiService.sendMouseMove(dx: 36, dy: 0)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self else { return }
            self.bleService.sendMouseMove(dx: -36, dy: 0)
            if self.wifiState.isConnected {
                self.wifiService.sendMouseMove(dx: -36, dy: 0)
            }
        }
        showToast("Test sinyali gönderildi")
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
        triggerHaptic(.medium)
        bleService.connectToHost(id: host.id)
        showToast("Bağlanılıyor: \(host.name)")
    }

    func disconnectFromHost(_ host: DiscoveredBLEHost) {
        triggerHaptic(.light)
        bleService.disconnectFromHost(id: host.id)
        showToast("Bağlantı kesildi: \(host.name)")
    }

    func triggerServiceChangedRefresh() {
        triggerHaptic(.light)
        bleService.triggerServiceChangedRefresh()
        showToast("GATT Service Changed gönderildi")
    }

    func handleAppDidBecomeActive() {
        bleService.ensureAdvertisingOnForeground()
        updateIdleTimer()
    }

    // MARK: Trackpad & Mouse

    func handleTrackpadMove(rawDX: Double, rawDY: Double) {
        let step = motionProcessor.processMove(
            rawDX: rawDX,
            rawDY: rawDY,
            sensitivity: settings.pointerSensitivity,
            acceleration: settings.pointerAcceleration
        )
        if step.dx != 0 || step.dy != 0 {
            bleService.sendMouseMove(dx: step.dx, dy: step.dy)
            if wifiState.isConnected {
                wifiService.sendMouseMove(dx: step.dx, dy: step.dy)
            }
        }
    }

    func handleTrackpadScroll(rawDX: Double, rawDY: Double) {
        let step = motionProcessor.processScroll(
            rawDX: rawDX,
            rawDY: rawDY,
            sensitivity: settings.scrollSensitivity,
            naturalScrolling: settings.naturalScrolling
        )
        if step.wheel != 0 || step.hWheel != 0 {
            bleService.sendMouseMove(dx: 0, dy: 0, wheel: step.wheel, hWheel: step.hWheel)
            if wifiState.isConnected {
                wifiService.sendMouseMove(dx: 0, dy: 0, wheel: step.wheel, hWheel: step.hWheel)
            }
        }
    }

    func resetTrackpadMotion() {
        motionProcessor.reset()
    }

    func clickMouse(_ button: HIDMouseButton) {
        triggerHaptic(.light)
        bleService.clickMouseButton(button)
        if wifiState.isConnected {
            wifiService.clickMouseButton(button)
        }
    }

    func setMouseButton(_ button: HIDMouseButton, pressed: Bool) {
        if pressed {
            pressedButtons.insert(button)
            triggerHaptic(.light)
        } else {
            pressedButtons.remove(button)
        }
        bleService.setMouseButton(button, pressed: pressed)
        if wifiState.isConnected {
            wifiService.sendMouseButton(button, pressed: pressed)
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
        bleService.sendGamepad(gamepadState)
        if wifiState.isConnected {
            wifiService.sendGamepad(gamepadState)
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
                if step.dx != 0 || step.dy != 0 {
                    self.bleService.sendMouseMove(dx: step.dx, dy: step.dy)
                    if self.wifiState.isConnected {
                        self.wifiService.sendMouseMove(dx: step.dx, dy: step.dy)
                    }
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
        bleService.tapKey(keyCode, modifiers: combined)
        if wifiState.isConnected {
            wifiService.tapKey(keyCode, modifiers: combined)
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

        if let stroke = KeyboardLayoutEngine.keyStroke(for: character, layout: settings.keyboardLayout) {
            // When user armed Ctrl/Alt/Win for a hotkey while iOS keyboard sent an uppercase letter,
            // avoid adding accidental Shift unless user explicitly armed/locked Shift.
            let baseMods = hasCommandMod ? activeMods : stroke.modifiers.union(activeMods)
            bleService.tapKey(stroke.keyCode, modifiers: baseMods)
            if wifiState.isConnected {
                if hasCommandMod {
                    wifiService.tapKey(stroke.keyCode, modifiers: baseMods)
                } else {
                    wifiService.sendText(String(character), appendEnter: false)
                }
            }
            armedModifiers = []
            triggerHaptic(.light)
        } else if wifiState.isConnected {
            wifiService.sendText(String(character), appendEnter: false)
            armedModifiers = []
            triggerHaptic(.light)
        } else {
            showToast("Bu düzende eşlenemeyen karakter: \(character)")
        }
    }

    func typeText(_ text: String, appendEnter: Bool = false) {
        if wifiState.isConnected {
            wifiService.sendText(text, appendEnter: appendEnter)
        }

        let payload = appendEnter ? text + "\n" : text
        let strokes = KeyboardLayoutEngine.keyStrokes(for: payload, layout: settings.keyboardLayout)

        if !connectionState.isConnected {
            if !wifiState.isConnected && strokes.isEmpty {
                showToast("Gönderilecek desteklenen metin bulunamadı")
            }
            return
        }

        guard !strokes.isEmpty else {
            if !wifiState.isConnected {
                showToast("Gönderilecek desteklenen metin bulunamadı")
            }
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
        bleService.tapConsumer(usage)
        if wifiState.isConnected {
            wifiService.tapConsumer(usage)
        }
    }

    func pressConsumer(_ usage: HIDConsumerUsage) {
        triggerHaptic(.light)
        bleService.sendConsumerPress(usage)
        if wifiState.isConnected {
            wifiService.tapConsumer(usage)
        }
    }

    func releaseConsumer() {
        bleService.sendConsumerRelease()
    }

    func tapSystem(_ usage: HIDSystemUsage) {
        triggerHaptic(.medium)
        bleService.tapSystem(usage)
        if wifiState.isConnected {
            wifiService.tapSystem(usage)
        }
    }

    // MARK: Macros

    func runMacro(_ macro: CustomMacro) {
        triggerHaptic(.medium)
        switch macro.action {
        case .keyCombo(let keyCode, let modifiersRaw):
            let mods = HIDModifier(rawValue: modifiersRaw)
            bleService.tapKey(keyCode, modifiers: mods)
            if wifiState.isConnected {
                wifiService.tapKey(keyCode, modifiers: mods)
            }
            showToast("Makro: \(macro.title)")
        case .typeText(let text, let appendEnter):
            showToast("Yazılıyor: \(macro.title)")
            typeText(text, appendEnter: appendEnter)
        case .consumerKey(let usageRaw):
            if let usage = HIDConsumerUsage(rawValue: usageRaw) {
                bleService.tapConsumer(usage)
                if wifiState.isConnected {
                    wifiService.tapConsumer(usage)
                }
                showToast("Medya: \(macro.title)")
            }
        case .systemKey(let usageRaw):
            let sys = HIDSystemUsage(rawValue: usageRaw)
            bleService.tapSystem(sys)
            if wifiState.isConnected {
                wifiService.tapSystem(sys)
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
                    self.bleService.tapKey(keyCode, modifiers: mods)
                    if self.wifiState.isConnected {
                        self.wifiService.tapKey(keyCode, modifiers: mods)
                    }
                case .typeText(let text, let appendEnter):
                    self.typeText(text, appendEnter: appendEnter)
                    if self.connectionState.isConnected {
                        let charCount = text.count + (appendEnter ? 1 : 0)
                        let estNs = UInt64(max(60, charCount * max(5, self.settings.typingDelayMs) + 40)) * 1_000_000
                        try? await Task.sleep(nanoseconds: estNs)
                    }
                case .consumerKey(let usageRaw):
                    if let usage = HIDConsumerUsage(rawValue: usageRaw) {
                        self.bleService.tapConsumer(usage)
                        if self.wifiState.isConnected {
                            self.wifiService.tapConsumer(usage)
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
            bleService.sendMouseMove(dx: 1, dy: 0)
            if wifiState.isConnected {
                wifiService.sendMouseMove(dx: 1, dy: 0)
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard let self else { return }
                self.bleService.sendMouseMove(dx: -1, dy: 0)
                if self.wifiState.isConnected {
                    self.wifiService.sendMouseMove(dx: -1, dy: 0)
                }
            }
        case .shiftPulse:
            bleService.tapKey(HIDKeyCode.none.rawValue, modifiers: .leftShift)
            if wifiState.isConnected {
                wifiService.tapKey(HIDKeyCode.none.rawValue, modifiers: .leftShift)
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
