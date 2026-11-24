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
    let airMouseService: AirMouseMotionService
    let dictationService: SpeechDictationService
    private let storageService: MacroStorageService
    private var motionProcessor = MouseMotionProcessor()

    // MARK: Published State
    @Published var selectedTab: AppTab = .trackpad
    @Published private(set) var connectionState: BLEConnectionState = .unknown
    @Published private(set) var protocolMode: HIDProtocolMode = .report
    @Published private(set) var ledState: HIDLEDState = []

    @Published var settings: BluePadSettings {
        didSet {
            var clamped = settings
            clamped.clampToValidRanges()
            if clamped != settings {
                settings = clamped
                return
            }
            storageService.saveSettings(settings)
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
    @Published private(set) var diagnosticEvents: [HIDDiagnosticEvent] = []
    @Published var toastMessage: String?

    // MARK: Private Tasks & Haptics
    private var jigglerTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
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
        self.airMouseService = AirMouseMotionService()
        self.dictationService = SpeechDictationService()
        self.jigglerCountdownSeconds = self.settings.jigglerIntervalSeconds

        wireBLECallbacks()
    }

    private func wireBLECallbacks() {
        bleService.onStateChange = { [weak self] state in
            self?.connectionState = state
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
    }

    // MARK: Bluetooth Lifecycle

    func startBluetoothIfNeeded() {
        guard !hasStartedBLE else { return }
        hasStartedBLE = true
        bleService.start(advertisedName: settings.advertisedName)
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
        armedModifiers = []
        lockedModifiers = []
        pressedButtons = []
        motionProcessor.reset()
        bleService.releaseAllKeys()
        triggerHaptic(.rigid)
        showToast("Tüm tuşlar serbest bırakıldı")
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
        }
    }

    func resetTrackpadMotion() {
        motionProcessor.reset()
    }

    func clickMouse(_ button: HIDMouseButton) {
        triggerHaptic(.light)
        bleService.clickMouseButton(button)
    }

    func setMouseButton(_ button: HIDMouseButton, pressed: Bool) {
        if pressed {
            pressedButtons.insert(button)
            triggerHaptic(.light)
        } else {
            pressedButtons.remove(button)
        }
        bleService.setMouseButton(button, pressed: pressed)
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

        if let stroke = KeyboardLayoutEngine.keyStroke(for: character, layout: settings.keyboardLayout) {
            let activeMods = effectiveModifiers
            // When user armed Ctrl/Alt/Win for a hotkey while iOS keyboard sent an uppercase letter,
            // avoid adding accidental Shift unless user explicitly armed/locked Shift.
            let hasCommandMod = !activeMods.intersection([.leftControl, .rightControl, .leftAlt, .leftGUI, .rightGUI]).isEmpty
            let baseMods = hasCommandMod ? activeMods : stroke.modifiers.union(activeMods)
            bleService.tapKey(stroke.keyCode, modifiers: baseMods)
            armedModifiers = []
            triggerHaptic(.light)
        } else {
            showToast("Bu düzende eşlenemeyen karakter: \(character)")
        }
    }

    func typeText(_ text: String, appendEnter: Bool = false) {
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
        lastScannedBarcode = code
        isScannerPresented = false
        triggerHaptic(.medium)
        showToast("Tarandı ve yazılıyor: \(code)")
        typeText(code, appendEnter: settings.scannerAutoEnter)
    }

    // MARK: Media & System Keys

    func tapConsumer(_ usage: HIDConsumerUsage) {
        triggerHaptic(.light)
        bleService.tapConsumer(usage)
    }

    func pressConsumer(_ usage: HIDConsumerUsage) {
        triggerHaptic(.light)
        bleService.sendConsumerPress(usage)
    }

    func releaseConsumer() {
        bleService.sendConsumerRelease()
    }

    func tapSystem(_ usage: HIDSystemUsage) {
        triggerHaptic(.medium)
        bleService.tapSystem(usage)
    }

    // MARK: Macros

    func runMacro(_ macro: CustomMacro) {
        triggerHaptic(.medium)
        switch macro.action {
        case .keyCombo(let keyCode, let modifiersRaw):
            bleService.tapKey(keyCode, modifiers: HIDModifier(rawValue: modifiersRaw))
            showToast("Makro: \(macro.title)")
        case .typeText(let text, let appendEnter):
            showToast("Yazılıyor: \(macro.title)")
            typeText(text, appendEnter: appendEnter)
        case .consumerKey(let usageRaw):
            if let usage = HIDConsumerUsage(rawValue: usageRaw) {
                bleService.tapConsumer(usage)
                showToast("Medya: \(macro.title)")
            }
        case .systemKey(let usageRaw):
            bleService.tapSystem(HIDSystemUsage(rawValue: usageRaw))
            showToast("Sistem: \(macro.title)")
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
        UIApplication.shared.isIdleTimerDisabled = true
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
        UIApplication.shared.isIdleTimerDisabled = false
        triggerHaptic(.light)
        showToast("Uyanık Tut durduruldu")
    }

    private func performJigglePulse() {
        switch settings.jigglerMode {
        case .microMouse:
            bleService.sendMouseMove(dx: 1, dy: 0)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000)
                self?.bleService.sendMouseMove(dx: -1, dy: 0)
            }
        case .shiftPulse:
            bleService.tapKey(HIDKeyCode.none.rawValue, modifiers: .leftShift)
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
