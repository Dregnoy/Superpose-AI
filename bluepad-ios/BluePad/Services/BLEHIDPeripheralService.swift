import CoreBluetooth
import Foundation
import UIKit

/// Serverless CoreBluetooth Peripheral implementing Bluetooth HOGP (HID over GATT Profile).
/// Presents the iPhone/iPad directly as a composite Keyboard + Mouse + Consumer + System HID device.
final class BLEHIDPeripheralService: NSObject {

    // MARK: Callbacks (delivered on MainActor)
    var onStateChange: (@MainActor (BLEConnectionState) -> Void)?
    var onLEDStateChange: (@MainActor (HIDLEDState) -> Void)?
    var onProtocolModeChange: (@MainActor (HIDProtocolMode) -> Void)?
    var onDiagnosticEvent: (@MainActor (HIDDiagnosticEvent) -> Void)?
    var onPacketSent: (@MainActor () -> Void)?

    // MARK: Manager & Advertising State
    private var peripheralManager: CBPeripheralManager?

    private var advertisedName: String = "BluePad"
    private var shouldAdvertise: Bool = true
    private var servicesPublished: Bool = false
    private var hidServicePublished: Bool = false
    private var pendingServicesToAdd: [CBMutableService] = []

    private var currentProtocolMode: HIDProtocolMode = .report
    private var currentBatteryLevel: UInt8 = 100
    private var currentMouseButtons: HIDMouseButton = []

    // MARK: Characteristics (all dynamic reads with `value: nil`)
    private var manufacturerChar: CBMutableCharacteristic!
    private var modelNumberChar: CBMutableCharacteristic!
    private var pnpIDChar: CBMutableCharacteristic!
    private var batteryLevelChar: CBMutableCharacteristic!

    private var hidInfoChar: CBMutableCharacteristic!
    private var reportMapChar: CBMutableCharacteristic!
    private var hidControlPointChar: CBMutableCharacteristic!
    private var protocolModeChar: CBMutableCharacteristic!

    private var bootKeyboardInputChar: CBMutableCharacteristic!
    private var bootKeyboardOutputChar: CBMutableCharacteristic!
    private var bootMouseInputChar: CBMutableCharacteristic!

    private var keyboardInputChar: CBMutableCharacteristic!
    private var keyboardOutputChar: CBMutableCharacteristic!
    private var mouseInputChar: CBMutableCharacteristic!
    private var consumerInputChar: CBMutableCharacteristic!
    private var systemInputChar: CBMutableCharacteristic!

    // MARK: Subscriptions & TX Backpressure
    private var subscriptionsByCharacteristic: [ObjectIdentifier: Set<UUID>] = [:]
    private var reliableQueue: [(characteristic: CBMutableCharacteristic, payload: Data)] = []
    private var pendingMouse = PendingMouseAccumulator()
    private let maxReliableQueueDepth = 256

    // MARK: Lifecycle
    override init() {
        super.init()
        readDeviceBatteryLevel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBatteryLevelNotification),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    func start(advertisedName: String) {
        let sanitized = sanitizedDeviceName(advertisedName)
        runOnMain { [weak self] in
            guard let self else { return }
            self.advertisedName = sanitized
            self.shouldAdvertise = true

            self.emitLog(.ble, "Bluetooth yetkisi: \(self.authorizationText(CBPeripheralManager.authorization))")

            if let manager = self.peripheralManager {
                self.emitLog(.ble, "CBPeripheralManager durumu yenileniyor (state=\(manager.state.rawValue))...")
                self.handleManagerState(manager)
            } else {
                self.emitState(.initializing)
                self.emitLog(.ble, "CBPeripheralManager başlatılıyor (ana kuyruk)...")
                self.peripheralManager = CBPeripheralManager(
                    delegate: self,
                    queue: nil,
                    options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
                )
            }
        }
    }

    func stop() {
        runOnMain { [weak self] in
            guard let self else { return }
            self.shouldAdvertise = false
            self.reliableQueue.removeAll()
            self.pendingMouse.clear()

            if let manager = self.peripheralManager {
                if manager.isAdvertising {
                    manager.stopAdvertising()
                }
                self.emitLog(.ble, "Bluetooth yayını durduruldu.")
                if manager.state == .poweredOn {
                    self.emitState(.stopped)
                } else {
                    self.updateConnectionState(from: manager)
                }
            } else {
                self.emitState(.stopped)
            }
        }
    }

    func restartAdvertising(name: String) {
        let sanitized = sanitizedDeviceName(name)
        runOnMain { [weak self] in
            guard let self else { return }
            self.advertisedName = sanitized
            self.shouldAdvertise = true
            guard let manager = self.peripheralManager, manager.state == .poweredOn else { return }

            if manager.isAdvertising {
                manager.stopAdvertising()
            }
            if self.servicesPublished && self.hidServicePublished {
                self.beginAdvertising(on: manager)
            } else if self.pendingServicesToAdd.isEmpty {
                self.setupServicesSequentially(on: manager)
            }
        }
    }

    func updateBatteryLevel(_ percentage: UInt8) {
        let clamped = min(percentage, 100)
        runOnMain { [weak self] in
            guard let self else { return }
            self.currentBatteryLevel = clamped
            guard let manager = self.peripheralManager,
                  let char = self.batteryLevelChar,
                  self.hasSubscribers(for: char) else { return }
            _ = manager.updateValue(Data([clamped]), for: char, onSubscribedCentrals: nil)
        }
    }

    // MARK: HID Input Sending API

    func sendKeyboard(modifiers: HIDModifier, keys: [UInt8]) {
        let report = HIDReportBuilder.keyboardReport(modifiers: modifiers, keys: keys)
        runOnMain { [weak self] in
            guard let self, let char = self.activeKeyboardInputCharacteristic() else { return }
            self.enqueueReliable(report, on: char, label: "Klavye")
        }
    }

    func tapKey(_ keyCode: UInt8, modifiers: HIDModifier = []) {
        let press = HIDReportBuilder.keyboardReport(modifiers: modifiers, keys: [keyCode])
        let release = HIDReportBuilder.keyboardReport()
        runOnMain { [weak self] in
            guard let self, let char = self.activeKeyboardInputCharacteristic() else { return }
            self.enqueueReliable(press, on: char, label: "Tuş Bas")
            self.enqueueReliable(release, on: char, label: "Tuş Bırak")
        }
    }

    func releaseAllKeys() {
        let emptyKeyboard = HIDReportBuilder.keyboardReport()
        let emptyMouse = HIDReportBuilder.mouseReport()
        let emptyBootMouse = HIDReportBuilder.bootMouseReport()
        let emptyConsumer = HIDReportBuilder.consumerReport(usage: 0)
        let emptySystem = HIDReportBuilder.systemReport(usage: [])

        runOnMain { [weak self] in
            guard let self else { return }
            self.currentMouseButtons = []
            self.pendingMouse.clear()
            if let kb = self.activeKeyboardInputCharacteristic() {
                self.enqueueReliable(emptyKeyboard, on: kb, label: "Klavye Sıfırla")
            }
            if let mouse = self.activeMouseInputCharacteristic() {
                let payload = self.currentProtocolMode == .boot ? emptyBootMouse : emptyMouse
                self.enqueueReliable(payload, on: mouse, label: "Fare Sıfırla")
            }
            if let consumer = self.consumerInputChar {
                self.enqueueReliable(emptyConsumer, on: consumer, label: "Medya Sıfırla")
            }
            if let sys = self.systemInputChar {
                self.enqueueReliable(emptySystem, on: sys, label: "Sistem Sıfırla")
            }
        }
    }

    func sendMouseMove(dx: Int, dy: Int, wheel: Int = 0, hWheel: Int = 0) {
        guard dx != 0 || dy != 0 || wheel != 0 || hWheel != 0 else { return }
        runOnMain { [weak self] in
            guard let self else { return }
            self.pendingMouse.accumulate(
                buttons: self.currentMouseButtons,
                dx: dx,
                dy: dy,
                wheel: wheel,
                hWheel: hWheel
            )
            self.flushQueues()
        }
    }

    func setMouseButton(_ button: HIDMouseButton, pressed: Bool) {
        runOnMain { [weak self] in
            guard let self, let char = self.activeMouseInputCharacteristic() else { return }
            if pressed {
                self.currentMouseButtons.insert(button)
            } else {
                self.currentMouseButtons.remove(button)
            }
            let payload: Data = self.currentProtocolMode == .boot
                ? HIDReportBuilder.bootMouseReport(buttons: self.currentMouseButtons)
                : HIDReportBuilder.mouseReport(buttons: self.currentMouseButtons)
            self.enqueueReliable(payload, on: char, label: pressed ? "Fare Tık Bas" : "Fare Tık Bırak")
        }
    }

    func clickMouseButton(_ button: HIDMouseButton) {
        runOnMain { [weak self] in
            guard let self, let char = self.activeMouseInputCharacteristic() else { return }
            let downButtons = self.currentMouseButtons.union(button)
            let upButtons = self.currentMouseButtons.subtracting(button)
            let downPayload: Data = self.currentProtocolMode == .boot
                ? HIDReportBuilder.bootMouseReport(buttons: downButtons)
                : HIDReportBuilder.mouseReport(buttons: downButtons)
            let upPayload: Data = self.currentProtocolMode == .boot
                ? HIDReportBuilder.bootMouseReport(buttons: upButtons)
                : HIDReportBuilder.mouseReport(buttons: upButtons)

            self.enqueueReliable(downPayload, on: char, label: "Tık Bas")
            self.enqueueReliable(upPayload, on: char, label: "Tık Bırak")
        }
    }

    func sendConsumerPress(_ usage: HIDConsumerUsage) {
        let data = HIDReportBuilder.consumerReport(usage: usage.rawValue)
        runOnMain { [weak self] in
            guard let self, let char = self.consumerInputChar else { return }
            self.enqueueReliable(data, on: char, label: "Medya Bas")
        }
    }

    func sendConsumerRelease() {
        let data = HIDReportBuilder.consumerReport(usage: 0)
        runOnMain { [weak self] in
            guard let self, let char = self.consumerInputChar else { return }
            self.enqueueReliable(data, on: char, label: "Medya Bırak")
        }
    }

    func tapConsumer(_ usage: HIDConsumerUsage) {
        let down = HIDReportBuilder.consumerReport(usage: usage.rawValue)
        let up = HIDReportBuilder.consumerReport(usage: 0)
        runOnMain { [weak self] in
            guard let self, let char = self.consumerInputChar else { return }
            self.enqueueReliable(down, on: char, label: usage.displayName)
            self.enqueueReliable(up, on: char, label: "Medya Bırak")
        }
    }

    func tapSystem(_ usage: HIDSystemUsage) {
        let down = HIDReportBuilder.systemReport(usage: usage)
        let up = HIDReportBuilder.systemReport(usage: [])
        runOnMain { [weak self] in
            guard let self, let char = self.systemInputChar else { return }
            self.enqueueReliable(down, on: char, label: "Sistem Komutu")
            self.enqueueReliable(up, on: char, label: "Sistem Bırak")
        }
    }

    // MARK: GATT Database Construction

    private func buildServices() -> [CBMutableService] {
        // 1. HID Service (0x1812) — Registered FIRST so HID binding is guaranteed even if optional services fail.
        // CoreBluetooth HOGP rules:
        // - Full 128-bit UUIDs everywhere
        // - `value: nil` on all characteristics (served dynamically in `didReceiveRead`)
        // - Combine `.readable`/`.writeable` with encryption permissions explicitly
        // - Avoid extendedProperties on Protocol Mode, Boot Output, and Output Report
        hidInfoChar = CBMutableCharacteristic(
            type: HOGPUUID.hidInformation,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        reportMapChar = CBMutableCharacteristic(
            type: HOGPUUID.reportMap,
            properties: [.read],
            value: nil,
            permissions: [.readable, .readEncryptionRequired]
        )
        hidControlPointChar = CBMutableCharacteristic(
            type: HOGPUUID.hidControlPoint,
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        protocolModeChar = CBMutableCharacteristic(
            type: HOGPUUID.protocolMode,
            properties: [.read, .writeWithoutResponse],
            value: nil,
            permissions: [.readable, .writeable]
        )
        bootKeyboardInputChar = CBMutableCharacteristic(
            type: HOGPUUID.bootKeyboardInput,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable, .readEncryptionRequired]
        )
        bootKeyboardOutputChar = CBMutableCharacteristic(
            type: HOGPUUID.bootKeyboardOutput,
            properties: [.read, .write, .writeWithoutResponse],
            value: nil,
            permissions: [.readable, .readEncryptionRequired, .writeable, .writeEncryptionRequired]
        )
        bootMouseInputChar = CBMutableCharacteristic(
            type: HOGPUUID.bootMouseInput,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable, .readEncryptionRequired]
        )

        keyboardInputChar = makeReportCharacteristic(
            reportID: HIDReportMap.keyboardReportID,
            isOutput: false
        )
        keyboardOutputChar = makeReportCharacteristic(
            reportID: HIDReportMap.keyboardReportID,
            isOutput: true
        )
        mouseInputChar = makeReportCharacteristic(
            reportID: HIDReportMap.mouseReportID,
            isOutput: false
        )
        consumerInputChar = makeReportCharacteristic(
            reportID: HIDReportMap.consumerReportID,
            isOutput: false
        )
        systemInputChar = makeReportCharacteristic(
            reportID: HIDReportMap.systemReportID,
            isOutput: false
        )

        let hidService = CBMutableService(type: HOGPUUID.hidService, primary: true)
        hidService.characteristics = [
            hidInfoChar,
            reportMapChar,
            hidControlPointChar,
            protocolModeChar,
            bootKeyboardInputChar,
            bootKeyboardOutputChar,
            bootMouseInputChar,
            keyboardInputChar,
            keyboardOutputChar,
            mouseInputChar,
            consumerInputChar,
            systemInputChar
        ]

        // 2. Battery Service (0x180F)
        batteryLevelChar = CBMutableCharacteristic(
            type: HOGPUUID.batteryLevel,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable, .readEncryptionRequired]
        )
        let batteryService = CBMutableService(type: HOGPUUID.batteryService, primary: true)
        batteryService.characteristics = [batteryLevelChar]

        // 3. Device Information Service (0x180A)
        manufacturerChar = CBMutableCharacteristic(
            type: HOGPUUID.manufacturerName,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        modelNumberChar = CBMutableCharacteristic(
            type: HOGPUUID.modelNumber,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        pnpIDChar = CBMutableCharacteristic(
            type: HOGPUUID.pnpID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        let disService = CBMutableService(type: HOGPUUID.deviceInformationService, primary: true)
        disService.characteristics = [manufacturerChar, modelNumberChar, pnpIDChar]

        return [hidService, batteryService, disService]
    }

    private func makeReportCharacteristic(reportID: UInt8, isOutput: Bool) -> CBMutableCharacteristic {
        let properties: CBCharacteristicProperties = isOutput
            ? [.read, .write, .writeWithoutResponse]
            : [.read, .notify]
        let permissions: CBAttributePermissions = isOutput
            ? [.readable, .readEncryptionRequired, .writeable, .writeEncryptionRequired]
            : [.readable, .readEncryptionRequired]

        let characteristic = CBMutableCharacteristic(
            type: HOGPUUID.report,
            properties: properties,
            value: nil,
            permissions: permissions
        )

        let reportType: UInt8 = isOutput ? 0x02 : 0x01
        let referenceDescriptor = CBMutableDescriptor(
            type: HOGPUUID.reportReference,
            value: Data([reportID, reportType])
        )
        characteristic.descriptors = [referenceDescriptor]
        return characteristic
    }

    private func setupServicesSequentially(on manager: CBPeripheralManager) {
        emitState(.initializing)
        servicesPublished = false
        hidServicePublished = false
        subscriptionsByCharacteristic.removeAll()
        if manager.isAdvertising {
            manager.stopAdvertising()
        }
        manager.removeAllServices()
        pendingServicesToAdd = buildServices()
        emitLog(.gatt, "GATT servisleri sırayla ekleniyor (1812, 180F, 180A)...")
        addNextPendingService(on: manager)
    }

    private func addNextPendingService(on manager: CBPeripheralManager) {
        guard !pendingServicesToAdd.isEmpty else {
            if hidServicePublished {
                servicesPublished = true
                emitLog(.gatt, "HOGP GATT servisleri yayınlandı.")
                if shouldAdvertise {
                    beginAdvertising(on: manager)
                } else {
                    updateConnectionState(from: manager)
                }
            }
            return
        }
        let next = pendingServicesToAdd.removeFirst()
        manager.add(next)
    }

    private func beginAdvertising(on manager: CBPeripheralManager) {
        let payload: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [HOGPUUID.hidService],
            CBAdvertisementDataLocalNameKey: advertisedName
        ]
        emitLog(.ble, "BLE yayını başlatılıyor: \"\(advertisedName)\"...")
        manager.startAdvertising(payload)
    }

    private func handleManagerState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            emitLog(.ble, "Bluetooth radyosu açık.")
            if !servicesPublished && pendingServicesToAdd.isEmpty {
                setupServicesSequentially(on: peripheral)
            } else if servicesPublished && hidServicePublished && shouldAdvertise && !peripheral.isAdvertising {
                beginAdvertising(on: peripheral)
            } else {
                updateConnectionState(from: peripheral)
            }
        case .poweredOff:
            servicesPublished = false
            hidServicePublished = false
            pendingServicesToAdd.removeAll()
            subscriptionsByCharacteristic.removeAll()
            reliableQueue.removeAll()
            pendingMouse.clear()
            emitState(.poweredOff)
            emitLog(.ble, "Bluetooth kapalı.")
        case .unauthorized:
            emitState(.unauthorized)
            emitLog(.error, "Bluetooth izni reddedildi.")
        case .unsupported:
            emitState(.unsupported)
            emitLog(.error, "BLE Çevre Birimi modu bu ortamda desteklenmiyor (örn. Simülatör).")
        case .resetting:
            servicesPublished = false
            hidServicePublished = false
            pendingServicesToAdd.removeAll()
            subscriptionsByCharacteristic.removeAll()
            emitState(.initializing)
            emitLog(.ble, "Bluetooth yığını sıfırlanıyor...")
        case .unknown:
            emitState(.unknown)
        @unknown default:
            emitState(.unknown)
        }
    }

    // MARK: TX Queue & Routing Helpers

    private func activeKeyboardInputCharacteristic() -> CBMutableCharacteristic? {
        currentProtocolMode == .boot ? bootKeyboardInputChar : keyboardInputChar
    }

    private func activeMouseInputCharacteristic() -> CBMutableCharacteristic? {
        currentProtocolMode == .boot ? bootMouseInputChar : mouseInputChar
    }

    private func hasSubscribers(for characteristic: CBMutableCharacteristic) -> Bool {
        guard let subs = subscriptionsByCharacteristic[ObjectIdentifier(characteristic)] else { return false }
        return !subs.isEmpty
    }

    private func totalConnectedCentrals() -> Int {
        var uniqueCentrals: Set<UUID> = []
        for ids in subscriptionsByCharacteristic.values {
            uniqueCentrals.formUnion(ids)
        }
        return uniqueCentrals.count
    }

    private func enqueueReliable(_ data: Data, on characteristic: CBMutableCharacteristic, label: String) {
        guard let manager = peripheralManager, manager.state == .poweredOn else { return }
        guard hasSubscribers(for: characteristic) else { return }

        if reliableQueue.count >= maxReliableQueueDepth {
            reliableQueue.removeFirst()
            emitLog(.error, "TX kuyruğu dolu; en eski rapor düşürüldü.")
        }
        reliableQueue.append((characteristic, data))
        flushQueues(lastLabel: label)
    }

    private func flushQueues(lastLabel: String? = nil) {
        guard let manager = peripheralManager, manager.state == .poweredOn else { return }

        while !reliableQueue.isEmpty {
            let item = reliableQueue[0]
            if !hasSubscribers(for: item.characteristic) {
                reliableQueue.removeFirst()
                continue
            }
            let sent = manager.updateValue(item.payload, for: item.characteristic, onSubscribedCentrals: nil)
            if sent {
                reliableQueue.removeFirst()
                notifyPacketSent()
                if let lastLabel, reliableQueue.isEmpty {
                    emitLog(.tx, lastLabel, hex: hexString(item.payload))
                }
            } else {
                return
            }
        }

        if let mouseChar = activeMouseInputCharacteristic(), hasSubscribers(for: mouseChar) {
            while let packet = pendingMouse.popNextPacket(protocolMode: currentProtocolMode) {
                let sent = manager.updateValue(packet, for: mouseChar, onSubscribedCentrals: nil)
                if sent {
                    notifyPacketSent()
                } else {
                    if packet.count == 5 {
                        let rx = Int(Int8(bitPattern: packet[1]))
                        let ry = Int(Int8(bitPattern: packet[2]))
                        let rw = Int(Int8(bitPattern: packet[3]))
                        let rh = Int(Int8(bitPattern: packet[4]))
                        pendingMouse.accumulate(buttons: currentMouseButtons, dx: rx, dy: ry, wheel: rw, hWheel: rh)
                    } else if packet.count == 3 {
                        let rx = Int(Int8(bitPattern: packet[1]))
                        let ry = Int(Int8(bitPattern: packet[2]))
                        pendingMouse.accumulate(buttons: currentMouseButtons, dx: rx, dy: ry)
                    }
                    return
                }
            }
        } else {
            pendingMouse.clear()
        }
    }

    private func baselineReport(for characteristic: CBCharacteristic) -> Data? {
        if characteristic === keyboardInputChar || characteristic === bootKeyboardInputChar {
            return HIDReportBuilder.keyboardReport()
        }
        if characteristic === mouseInputChar {
            return HIDReportBuilder.mouseReport()
        }
        if characteristic === bootMouseInputChar {
            return HIDReportBuilder.bootMouseReport()
        }
        if characteristic === consumerInputChar {
            return HIDReportBuilder.consumerReport(usage: 0)
        }
        if characteristic === systemInputChar {
            return HIDReportBuilder.systemReport(usage: [])
        }
        if characteristic === batteryLevelChar {
            return Data([currentBatteryLevel])
        }
        return nil
    }

    private func readPayload(for characteristic: CBCharacteristic) -> Data? {
        if characteristic === manufacturerChar { return HOGPUUID.manufacturerData }
        if characteristic === modelNumberChar { return HOGPUUID.modelNumberData }
        if characteristic === pnpIDChar { return HOGPUUID.pnpIDValue }
        if characteristic === batteryLevelChar { return Data([currentBatteryLevel]) }
        if characteristic === hidInfoChar { return HOGPUUID.hidInfoValue }
        if characteristic === reportMapChar { return HIDReportMap.descriptorData }
        if characteristic === protocolModeChar { return Data([currentProtocolMode.rawValue]) }
        if characteristic === keyboardOutputChar || characteristic === bootKeyboardOutputChar {
            return Data([0x00])
        }
        return baselineReport(for: characteristic)
    }

    private func updateConnectionState(from manager: CBPeripheralManager) {
        let count = totalConnectedCentrals()
        if count > 0 {
            emitState(.connected(centralCount: count))
        } else if manager.isAdvertising {
            emitState(.advertising)
        } else {
            switch manager.state {
            case .poweredOn:
                emitState(shouldAdvertise ? .initializing : .stopped)
            case .poweredOff:
                emitState(.poweredOff)
            case .unauthorized:
                emitState(.unauthorized)
            case .unsupported:
                emitState(.unsupported)
            default:
                emitState(.unknown)
            }
        }
    }

    private func authorizationText(_ auth: CBManagerAuthorization) -> String {
        switch auth {
        case .allowedAlways: return "İzinli"
        case .notDetermined: return "Belirlenmemiş"
        case .denied: return "Reddedildi"
        case .restricted: return "Kısıtlı"
        @unknown default: return "Bilinmiyor"
        }
    }

    private func sanitizedDeviceName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "BluePad" : String(trimmed.prefix(22))
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: Battery Monitoring

    @objc private func handleBatteryLevelNotification() {
        readDeviceBatteryLevel()
        updateBatteryLevel(currentBatteryLevel)
    }

    private func readDeviceBatteryLevel() {
        runOnMain { [weak self] in
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            let pct: UInt8 = level >= 0 ? UInt8(min(100, max(1, Int((level * 100).rounded())))) : 100
            self?.currentBatteryLevel = pct
        }
    }

    // MARK: MainActor Callback Dispatchers

    private func emitState(_ state: BLEConnectionState) {
        let handler = onStateChange
        Task { @MainActor in
            handler?(state)
        }
    }

    private func emitLED(_ led: HIDLEDState) {
        let handler = onLEDStateChange
        Task { @MainActor in
            handler?(led)
        }
    }

    private func emitProtocolMode(_ mode: HIDProtocolMode) {
        let handler = onProtocolModeChange
        Task { @MainActor in
            handler?(mode)
        }
    }

    private func emitLog(_ category: HIDDiagnosticEvent.Category, _ message: String, hex: String? = nil) {
        let handler = onDiagnosticEvent
        let event = HIDDiagnosticEvent(category: category, message: message, hexPayload: hex)
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

// MARK: - CBPeripheralManagerDelegate

extension BLEHIDPeripheralService: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        handleManagerState(peripheral)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            let nsError = error as NSError
            emitLog(
                .error,
                "GATT servisi eklenemedi (\(service.uuid.uuidString)) [\(nsError.domain):\(nsError.code)]: \(error.localizedDescription)"
            )
            if service.uuid == HOGPUUID.hidService {
                pendingServicesToAdd.removeAll()
                servicesPublished = false
                hidServicePublished = false
                emitState(.failed("HID 1812: \(error.localizedDescription)"))
            } else {
                // Optional auxiliary services (180F / 180A) must not block primary HID service advertising.
                addNextPendingService(on: peripheral)
            }
            return
        }

        if service.uuid == HOGPUUID.hidService {
            hidServicePublished = true
        }
        emitLog(.gatt, "Servis eklendi: \(service.uuid.uuidString)")
        addNextPendingService(on: peripheral)
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            let nsError = error as NSError
            emitLog(
                .error,
                "Yayın başlatılamadı [\(nsError.domain):\(nsError.code)]: \(error.localizedDescription)"
            )
            emitState(.failed("Yayın hatası: \(error.localizedDescription)"))
            return
        }
        emitLog(.ble, "HID yayını aktif: \"\(advertisedName)\"")
        updateConnectionState(from: peripheral)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        let key = ObjectIdentifier(characteristic)
        var set = subscriptionsByCharacteristic[key] ?? []
        set.insert(central.identifier)
        subscriptionsByCharacteristic[key] = set

        emitLog(.gatt, "Host abone oldu: \(characteristic.uuid.uuidString)")
        updateConnectionState(from: peripheral)

        // Mandatory baseline input report on subscribe so Windows/macOS/Linux hosts
        // finalize HID binding immediately without stalling.
        if let mutable = characteristic as? CBMutableCharacteristic,
           let baseline = baselineReport(for: characteristic) {
            enqueueReliable(baseline, on: mutable, label: "Başlangıç Raporu")
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        let key = ObjectIdentifier(characteristic)
        subscriptionsByCharacteristic[key]?.remove(central.identifier)
        if subscriptionsByCharacteristic[key]?.isEmpty == true {
            subscriptionsByCharacteristic.removeValue(forKey: key)
        }

        emitLog(.gatt, "Host aboneliği ayrıldı: \(characteristic.uuid.uuidString)")
        if totalConnectedCentrals() == 0 {
            currentMouseButtons = []
            reliableQueue.removeAll()
            pendingMouse.clear()
        }
        updateConnectionState(from: peripheral)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard let payload = readPayload(for: request.characteristic) else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        if request.offset > payload.count {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = payload.subdata(in: request.offset..<payload.count)
        peripheral.respond(to: request, withResult: .success)

        if request.characteristic === reportMapChar && request.offset == 0 {
            emitLog(.gatt, "Report Map okundu (\(payload.count) bayt)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            let value = request.value ?? Data()

            if request.characteristic === protocolModeChar {
                if let byte = value.first, let mode = HIDProtocolMode(rawValue: byte) {
                    currentProtocolMode = mode
                    emitProtocolMode(mode)
                    emitLog(.rx, "Protokol modu değişti: \(mode.displayName)")
                }
            } else if request.characteristic === hidControlPointChar {
                if let byte = value.first {
                    let msg = byte == 0x00 ? "Host Askıya Aldı (Suspend)" : "Host Uyandı (Exit Suspend)"
                    emitLog(.rx, msg)
                }
            } else if request.characteristic === keyboardOutputChar || request.characteristic === bootKeyboardOutputChar {
                let led = HIDReportBuilder.parseLEDOutput(value)
                emitLED(led)
                emitLog(.rx, "Klavye LED güncellendi", hex: hexString(value))
            }
        }

        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        flushQueues()
    }
}
