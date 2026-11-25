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
    var onDiscoveredHostsChange: (@MainActor ([DiscoveredBLEHost]) -> Void)?
    var onScanningStateChange: (@MainActor (Bool) -> Void)?
    var onGATTStatusChange: (@MainActor (HOGPServiceStatus) -> Void)?

    // MARK: Manager & Advertising State
    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var hasLoggedPlistCheck: Bool = false

    private var advertisedName: String = "BluePad"
    private var shouldAdvertise: Bool = true
    private var isPublishingServices: Bool = false
    private var servicesPublished: Bool = false
    private var hidServicePublished: Bool = false
    private var usingFallbackAdvertising: Bool = false
    private var hidRetryWithoutIncludedBattery: Bool = false

    private var batteryServiceObj: CBMutableService?
    private var deviceInfoServiceObj: CBMutableService?
    private var hidServiceObj: CBMutableService?
    private var serviceChangedDummyObj: CBMutableService?
    private var gattStatus = HOGPServiceStatus()

    // MARK: Outbound BLE Host Scanner & Link State
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var discoveredHosts: [UUID: DiscoveredBLEHost] = [:]
    private var isScanningHosts: Bool = false
    private var pendingHostScan: Bool = false
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var hostConnectTimeouts: [UUID: DispatchWorkItem] = [:]
    private var lastHostEmitUptime: TimeInterval = 0

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
    private var gamepadInputChar: CBMutableCharacteristic!

    // MARK: Subscriptions & TX Backpressure
    private var subscriptionsByCharacteristic: [ObjectIdentifier: Set<UUID>] = [:]
    private var reliableQueue: [(characteristic: CBMutableCharacteristic, payload: Data)] = []
    private var pendingMouse = PendingMouseAccumulator()
    private var pendingGamepad: Data?
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

            let isFirstStart = (self.peripheralManager == nil)
            self.logBundlePlistCheck(force: !isFirstStart)
            self.emitLog(.ble, "Bluetooth yetkisi: \(self.authorizationText(CBManager.authorization))")

            let initializeManagers: () -> Void = { [weak self] in
                guard let self else { return }

                if CBManager.authorization == .notDetermined && self.centralManager == nil {
                    self.emitLog(.ble, "CBCentralManager başlatılıyor (ilk izin)...")
                    self.centralManager = CBCentralManager(
                        delegate: self,
                        queue: nil,
                        options: [CBCentralManagerOptionShowPowerAlertKey: true]
                    )
                }

                if let manager = self.peripheralManager,
                   manager.state != .unknown,
                   manager.state != .unauthorized {
                    self.emitLog(.ble, "CBPeripheralManager durumu yenileniyor (\(self.stateName(manager.state)))...")
                    self.handleManagerState(manager)
                } else {
                    self.isPublishingServices = false
                    self.servicesPublished = false
                    self.hidServicePublished = false
                    self.hidRetryWithoutIncludedBattery = false
                    self.batteryServiceObj = nil
                    self.deviceInfoServiceObj = nil
                    self.hidServiceObj = nil
                    self.serviceChangedDummyObj = nil
                    self.gattStatus = HOGPServiceStatus()
                    self.emitGATTStatus()
                    self.peripheralManager?.delegate = nil
                    self.emitState(.initializing)
                    self.emitLog(.ble, "CBPeripheralManager başlatılıyor (ana kuyruk)...")
                    self.peripheralManager = CBPeripheralManager(
                        delegate: self,
                        queue: nil,
                        options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
                    )
                }
            }

            if isFirstStart {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: initializeManagers)
            } else {
                initializeManagers()
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
                self.gattStatus.isAdvertising = false
                self.gattStatus.advertisingMode = "Durduruldu"
                self.emitGATTStatus()
                self.emitLog(.ble, "Bluetooth yayını durduruldu.")
                if manager.state == .poweredOn {
                    self.emitState(.stopped)
                } else {
                    self.updateConnectionState(from: manager)
                }
            } else {
                self.gattStatus.isAdvertising = false
                self.gattStatus.advertisingMode = "Durduruldu"
                self.emitGATTStatus()
                self.emitState(.stopped)
            }
        }
    }

    func disconnectHIDSession() {
        runOnMain { [weak self] in
            guard let self else { return }
            self.shouldAdvertise = false

            if let manager = self.peripheralManager, manager.state == .poweredOn {
                let releasePairs: [(CBMutableCharacteristic?, Data)] = [
                    (self.activeKeyboardInputCharacteristic(), HIDReportBuilder.keyboardReport()),
                    (
                        self.activeMouseInputCharacteristic(),
                        self.currentProtocolMode == .boot
                            ? HIDReportBuilder.bootMouseReport()
                            : HIDReportBuilder.mouseReport()
                    ),
                    (self.consumerInputChar, HIDReportBuilder.consumerReport(usage: 0)),
                    (self.systemInputChar, HIDReportBuilder.systemReport(usage: [])),
                    (self.gamepadInputChar, HIDReportBuilder.gamepadReport())
                ]
                for (charOpt, payload) in releasePairs {
                    if let char = charOpt, self.hasSubscribers(for: char) {
                        _ = manager.updateValue(payload, for: char, onSubscribedCentrals: nil)
                    }
                }
                if manager.isAdvertising {
                    manager.stopAdvertising()
                }
                manager.removeAllServices()
            }

            self.currentMouseButtons = []
            self.reliableQueue.removeAll()
            self.pendingMouse.clear()
            self.pendingGamepad = nil
            self.isPublishingServices = false
            self.servicesPublished = false
            self.hidServicePublished = false
            self.hidRetryWithoutIncludedBattery = false
            self.batteryServiceObj = nil
            self.deviceInfoServiceObj = nil
            self.hidServiceObj = nil
            self.serviceChangedDummyObj = nil
            self.subscriptionsByCharacteristic.removeAll()

            for (_, timeoutItem) in self.hostConnectTimeouts {
                timeoutItem.cancel()
            }
            self.hostConnectTimeouts.removeAll()

            var updatedHosts = false
            for (hostID, var host) in self.discoveredHosts where host.linkState.isConnected || host.linkState.isConnecting {
                if let p = self.discoveredPeripherals[hostID] {
                    self.centralManager?.cancelPeripheralConnection(p)
                }
                host.linkState = .discovered
                self.discoveredHosts[hostID] = host
                updatedHosts = true
            }
            if updatedHosts {
                self.emitDiscoveredHosts(force: true)
            }

            self.gattStatus = HOGPServiceStatus(advertisingMode: "Bağlantı Kesildi")
            self.emitGATTStatus()
            if let manager = self.peripheralManager, manager.state != .poweredOn {
                self.updateConnectionState(from: manager)
            } else {
                self.emitState(.stopped)
            }
            self.emitLog(.ble, "Bluetooth HID bağlantısı kesildi (GATT servisleri kaldırıldı).")
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
            } else if !self.isPublishingServices {
                self.setupServicesSequentially(on: manager)
            }
        }
    }

    func ensureAdvertisingOnForeground() {
        runOnMain { [weak self] in
            guard let self else { return }
            guard self.shouldAdvertise,
                  self.servicesPublished,
                  self.hidServicePublished,
                  let manager = self.peripheralManager,
                  manager.state == .poweredOn,
                  !manager.isAdvertising else { return }
            self.emitLog(.ble, "Ön plana dönüldü; BLE yayını tazeleniyor...")
            self.beginAdvertising(on: manager)
        }
    }

    func triggerServiceChangedRefresh() {
        runOnMain { [weak self] in
            guard let self else { return }
            guard let manager = self.peripheralManager,
                  manager.state == .poweredOn,
                  self.hidServicePublished else { return }

            if let existing = self.serviceChangedDummyObj {
                manager.remove(existing)
                manager.add(existing)
                self.emitLog(.gatt, "GATT Service Changed tazeleniyor...")
                return
            }

            let dummyChar = CBMutableCharacteristic(
                type: HOGPUUID.serviceChangedTriggerCharacteristic,
                properties: [.read, .notifyEncryptionRequired],
                value: nil,
                permissions: [.readEncryptionRequired]
            )
            let triggerService = CBMutableService(type: HOGPUUID.serviceChangedTriggerService, primary: true)
            triggerService.characteristics = [dummyChar]
            self.serviceChangedDummyObj = triggerService
            manager.add(triggerService)
            self.emitLog(.gatt, "GATT Service Changed tetikleniyor...")
        }
    }

    // MARK: Outbound BLE Host Scanner & Connector

    func startHostScan() {
        runOnMain { [weak self] in
            guard let self else { return }

            if self.centralManager == nil {
                self.pendingHostScan = true
                self.emitLog(.ble, "Bluetooth tarama hazırlanıyor (CBCentralManager bekleniyor)...")
                self.centralManager = CBCentralManager(
                    delegate: self,
                    queue: nil,
                    options: [CBCentralManagerOptionShowPowerAlertKey: true]
                )
                return
            }

            guard let central = self.centralManager else { return }
            guard central.state == .poweredOn else {
                self.pendingHostScan = true
                self.emitLog(.ble, "Tarama beklemede (Central durumu: \(self.stateName(central.state))).")
                return
            }

            self.scanTimeoutWorkItem?.cancel()
            self.pendingHostScan = false
            self.discoveredHosts = self.discoveredHosts.filter {
                $0.value.linkState.isConnected || $0.value.linkState.isConnecting
            }
            self.refreshSystemConnectedHosts(on: central)

            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            self.isScanningHosts = true
            self.emitScanningState(true)
            self.emitLog(.ble, "Yakındaki Bluetooth cihazları taranıyor...")
            self.emitDiscoveredHosts(force: true)

            let timeoutItem = DispatchWorkItem { [weak self] in
                self?.stopHostScan()
            }
            self.scanTimeoutWorkItem = timeoutItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: timeoutItem)
        }
    }

    func stopHostScan() {
        runOnMain { [weak self] in
            guard let self else { return }
            self.scanTimeoutWorkItem?.cancel()
            self.scanTimeoutWorkItem = nil
            self.pendingHostScan = false
            self.centralManager?.stopScan()
            if self.isScanningHosts {
                self.isScanningHosts = false
                self.emitScanningState(false)
                self.emitLog(.ble, "Cihaz taraması durduruldu.")
            }
        }
    }

    func connectToHost(id: UUID) {
        runOnMain { [weak self] in
            guard let self else { return }
            guard let central = self.centralManager, central.state == .poweredOn else {
                self.emitLog(.error, "Bağlantı başlatılamadı: Bluetooth tarayıcı hazır değil.")
                return
            }

            let peripheral = self.discoveredPeripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
            guard let peripheral else {
                self.emitLog(.error, "Seçilen Bluetooth cihazı bulunamadı.")
                return
            }

            self.discoveredPeripherals[id] = peripheral
            self.stopHostScan()

            let existing = self.discoveredHosts[id]
            let trimmedPeripheralName = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fallbackName = trimmedPeripheralName.isEmpty ? "BLE Cihazı" : trimmedPeripheralName
            let displayName = existing?.name ?? fallbackName
            self.discoveredHosts[id] = DiscoveredBLEHost(
                id: id,
                name: displayName,
                hasExplicitName: existing?.hasExplicitName ?? (peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false),
                rssi: existing?.rssi ?? -60,
                isConnectable: true,
                isSystemConnected: existing?.isSystemConnected ?? false,
                linkState: .connecting,
                lastSeen: Date()
            )
            self.emitDiscoveredHosts(force: true)
            self.emitLog(.ble, "Hedef cihaza bağlanılıyor: \(displayName)...")

            central.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
            ])

            self.hostConnectTimeouts[id]?.cancel()
            let timeoutItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hostConnectTimeouts.removeValue(forKey: id)
                guard var host = self.discoveredHosts[id], host.linkState.isConnecting else { return }
                self.centralManager?.cancelPeripheralConnection(peripheral)
                host.linkState = .failed("Yanıt yok (zaman aşımı)")
                host.lastSeen = Date()
                self.discoveredHosts[id] = host
                self.emitDiscoveredHosts(force: true)
                self.emitLog(.ble, "Hedef cihaza bağlanılamadı (zaman aşımı): \(host.name)")
            }
            self.hostConnectTimeouts[id] = timeoutItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: timeoutItem)
        }
    }

    func disconnectFromHost(id: UUID) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.hostConnectTimeouts[id]?.cancel()
            self.hostConnectTimeouts.removeValue(forKey: id)
            guard let central = self.centralManager else { return }
            let peripheral = self.discoveredPeripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
            guard let peripheral else { return }

            central.cancelPeripheralConnection(peripheral)
            if var host = self.discoveredHosts[id] {
                host.linkState = .discovered
                self.discoveredHosts[id] = host
                self.emitDiscoveredHosts(force: true)
            }
            self.emitLog(.ble, "Hedef cihaz bağlantısı kesildi.")
        }
    }

    private func refreshSystemConnectedHosts(on central: CBCentralManager) {
        let connected = central.retrieveConnectedPeripherals(withServices: [
            HOGPUUID.hidService,
            HOGPUUID.batteryService,
            HOGPUUID.deviceInformationService
        ])
        let now = Date()
        for peripheral in connected {
            discoveredPeripherals[peripheral.identifier] = peripheral
            let trimmed = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let existing = discoveredHosts[peripheral.identifier]
            let resolvedName = trimmed.isEmpty ? (existing?.name ?? "Sistem Bağlı Cihaz") : trimmed
            let hasName = !trimmed.isEmpty || (existing?.hasExplicitName ?? false)
            discoveredHosts[peripheral.identifier] = DiscoveredBLEHost(
                id: peripheral.identifier,
                name: resolvedName,
                hasExplicitName: hasName,
                rssi: existing?.rssi ?? -50,
                isConnectable: true,
                isSystemConnected: true,
                linkState: existing?.linkState ?? .discovered,
                lastSeen: now
            )
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
            if self.currentProtocolMode == .report,
               let bootChar = self.bootKeyboardInputChar,
               self.hasSubscribers(for: bootChar) {
                self.enqueueReliable(report, on: bootChar, label: "Boot Klavye")
            }
        }
    }

    func tapKey(_ keyCode: UInt8, modifiers: HIDModifier = []) {
        let press = HIDReportBuilder.keyboardReport(modifiers: modifiers, keys: [keyCode])
        let release = HIDReportBuilder.keyboardReport()
        runOnMain { [weak self] in
            guard let self, let char = self.activeKeyboardInputCharacteristic() else { return }
            self.enqueueReliable(press, on: char, label: "Tuş Bas")
            self.enqueueReliable(release, on: char, label: "Tuş Bırak")
            if self.currentProtocolMode == .report,
               let bootChar = self.bootKeyboardInputChar,
               self.hasSubscribers(for: bootChar) {
                self.enqueueReliable(press, on: bootChar, label: "Boot Tuş Bas")
                self.enqueueReliable(release, on: bootChar, label: "Boot Tuş Bırak")
            }
        }
    }

    func releaseAllKeys() {
        let emptyKeyboard = HIDReportBuilder.keyboardReport()
        let emptyMouse = HIDReportBuilder.mouseReport()
        let emptyBootMouse = HIDReportBuilder.bootMouseReport()
        let emptyConsumer = HIDReportBuilder.consumerReport(usage: 0)
        let emptySystem = HIDReportBuilder.systemReport(usage: [])
        let emptyGamepad = HIDReportBuilder.gamepadReport()

        runOnMain { [weak self] in
            guard let self else { return }
            self.currentMouseButtons = []
            self.pendingMouse.clear()
            self.pendingGamepad = nil
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
            if let gamepad = self.gamepadInputChar {
                self.enqueueReliable(emptyGamepad, on: gamepad, label: "Gamepad Sıfırla")
            }
        }
    }

    func sendGamepad(_ state: HIDGamepadState) {
        let payload = HIDReportBuilder.gamepadReport(state)
        runOnMain { [weak self] in
            guard let self,
                  let char = self.gamepadInputChar,
                  let manager = self.peripheralManager,
                  manager.state == .poweredOn,
                  self.hasSubscribers(for: char) else { return }
            if manager.updateValue(payload, for: char, onSubscribedCentrals: nil) {
                self.pendingGamepad = nil
                self.notifyPacketSent()
            } else {
                self.pendingGamepad = payload
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
            if self.currentProtocolMode == .report,
               let bootChar = self.bootMouseInputChar,
               self.hasSubscribers(for: bootChar) {
                let bootPayload = HIDReportBuilder.bootMouseReport(buttons: self.currentMouseButtons)
                self.enqueueReliable(bootPayload, on: bootChar, label: pressed ? "Boot Tık Bas" : "Boot Tık Bırak")
            }
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
            if self.currentProtocolMode == .report,
               let bootChar = self.bootMouseInputChar,
               self.hasSubscribers(for: bootChar) {
                let bootDown = HIDReportBuilder.bootMouseReport(buttons: downButtons)
                let bootUp = HIDReportBuilder.bootMouseReport(buttons: upButtons)
                self.enqueueReliable(bootDown, on: bootChar, label: "Boot Tık Bas")
                self.enqueueReliable(bootUp, on: bootChar, label: "Boot Tık Bırak")
            }
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

    // MARK: GATT Database Construction (Canonical HOGP: 180F -> 180A -> 1812 with includedServices)

    private func buildBatteryService() -> CBMutableService {
        batteryLevelChar = CBMutableCharacteristic(
            type: HOGPUUID.batteryLevel,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        let service = CBMutableService(type: HOGPUUID.batteryService, primary: true)
        service.characteristics = [batteryLevelChar]
        return service
    }

    private func buildDeviceInfoService() -> CBMutableService {
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
        let service = CBMutableService(type: HOGPUUID.deviceInformationService, primary: true)
        service.characteristics = [manufacturerChar, modelNumberChar, pnpIDChar]
        return service
    }

    private func buildHIDService(includingBattery battery: CBMutableService?) -> CBMutableService {
        // CoreBluetooth HOGP rules:
        // - Full 128-bit UUIDs everywhere inside GATT DB
        // - `value: nil` on all characteristics (served dynamically in `didReceiveRead`)
        // - `.notifyEncryptionRequired` and `.readEncryptionRequired`/`.writeEncryptionRequired` so hosts bond cleanly
        // - Never set `.extendedProperties` on Protocol Mode, Boot Output, or Output Report
        hidInfoChar = CBMutableCharacteristic(
            type: HOGPUUID.hidInformation,
            properties: [.read],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        reportMapChar = CBMutableCharacteristic(
            type: HOGPUUID.reportMap,
            properties: [.read],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        hidControlPointChar = CBMutableCharacteristic(
            type: HOGPUUID.hidControlPoint,
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeEncryptionRequired]
        )
        protocolModeChar = CBMutableCharacteristic(
            type: HOGPUUID.protocolMode,
            properties: [.read, .writeWithoutResponse],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        bootKeyboardInputChar = CBMutableCharacteristic(
            type: HOGPUUID.bootKeyboardInput,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        bootKeyboardOutputChar = CBMutableCharacteristic(
            type: HOGPUUID.bootKeyboardOutput,
            properties: [.read, .write, .writeWithoutResponse],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        bootMouseInputChar = CBMutableCharacteristic(
            type: HOGPUUID.bootMouseInput,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired]
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
        gamepadInputChar = makeReportCharacteristic(
            reportID: HIDReportMap.gamepadReportID,
            isOutput: false
        )

        let hidService = CBMutableService(type: HOGPUUID.hidService, primary: true)
        if let battery {
            hidService.includedServices = [battery]
        }
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
            systemInputChar,
            gamepadInputChar
        ]
        return hidService
    }

    private func makeReportCharacteristic(reportID: UInt8, isOutput: Bool) -> CBMutableCharacteristic {
        let properties: CBCharacteristicProperties = isOutput
            ? [.read, .write, .writeWithoutResponse]
            : [.read, .notifyEncryptionRequired]
        let permissions: CBAttributePermissions = isOutput
            ? [.readEncryptionRequired, .writeEncryptionRequired]
            : [.readEncryptionRequired]

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
        isPublishingServices = true
        servicesPublished = false
        hidServicePublished = false
        hidRetryWithoutIncludedBattery = false
        batteryServiceObj = nil
        deviceInfoServiceObj = nil
        hidServiceObj = nil
        serviceChangedDummyObj = nil
        subscriptionsByCharacteristic.removeAll()
        gattStatus = HOGPServiceStatus()
        emitGATTStatus()

        if manager.isAdvertising {
            manager.stopAdvertising()
        }
        manager.removeAllServices()

        let battery = buildBatteryService()
        batteryServiceObj = battery
        emitLog(.gatt, "GATT servisleri HOGP sırasıyla ekleniyor (180F → 180A → 1812)...")
        manager.add(battery)
    }

    private func beginAdvertising(on manager: CBPeripheralManager) {
        usingFallbackAdvertising = false
        let payload: [String: Any] = [
            CBAdvertisementDataLocalNameKey: advertisedName,
            CBAdvertisementDataServiceUUIDsKey: [HOGPUUID.hidServiceAdvertising16Bit]
        ]
        gattStatus.advertisingMode = "Başlatılıyor (16-bit 0x1812)..."
        emitGATTStatus()
        emitLog(.ble, "BLE yayını başlatılıyor (16-bit 0x1812): \"\(advertisedName)\"...")
        manager.startAdvertising(payload)
    }

    private func handleManagerState(_ peripheral: CBPeripheralManager) {
        emitLog(
            .ble,
            "Peripheral durumu: \(stateName(peripheral.state)) (raw=\(peripheral.state.rawValue)), yetki: \(authorizationText(CBManager.authorization))"
        )
        switch peripheral.state {
        case .poweredOn:
            emitLog(.ble, "Bluetooth radyosu açık.")
            if !servicesPublished && !isPublishingServices {
                setupServicesSequentially(on: peripheral)
            } else if servicesPublished && hidServicePublished && shouldAdvertise && !peripheral.isAdvertising {
                beginAdvertising(on: peripheral)
            } else {
                updateConnectionState(from: peripheral)
            }
        case .poweredOff:
            isPublishingServices = false
            servicesPublished = false
            hidServicePublished = false
            batteryServiceObj = nil
            deviceInfoServiceObj = nil
            hidServiceObj = nil
            serviceChangedDummyObj = nil
            subscriptionsByCharacteristic.removeAll()
            reliableQueue.removeAll()
            pendingMouse.clear()
            gattStatus = HOGPServiceStatus(advertisingMode: "Bluetooth Kapalı")
            emitGATTStatus()
            emitState(.poweredOff)
            emitLog(.ble, "Bluetooth kapalı.")
        case .unauthorized:
            isPublishingServices = false
            gattStatus.isAdvertising = false
            gattStatus.advertisingMode = "İzin Yok"
            emitGATTStatus()
            emitState(.unauthorized)
            emitLog(.error, "Bluetooth izni reddedildi.")
        case .unsupported:
            isPublishingServices = false
            gattStatus.isAdvertising = false
            gattStatus.advertisingMode = "Desteklenmiyor"
            emitGATTStatus()
            emitState(.unsupported)
            emitLog(.error, "BLE Çevre Birimi modu bu ortamda desteklenmiyor (örn. Simülatör).")
        case .resetting:
            isPublishingServices = false
            servicesPublished = false
            hidServicePublished = false
            batteryServiceObj = nil
            deviceInfoServiceObj = nil
            hidServiceObj = nil
            serviceChangedDummyObj = nil
            subscriptionsByCharacteristic.removeAll()
            gattStatus = HOGPServiceStatus(advertisingMode: "Sıfırlanıyor")
            emitGATTStatus()
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

    private func resolveCharacteristic(_ characteristic: CBCharacteristic) -> CBMutableCharacteristic? {
        let allKnown: [CBMutableCharacteristic?] = [
            keyboardInputChar,
            keyboardOutputChar,
            mouseInputChar,
            consumerInputChar,
            systemInputChar,
            gamepadInputChar,
            bootKeyboardInputChar,
            bootKeyboardOutputChar,
            bootMouseInputChar,
            batteryLevelChar,
            manufacturerChar,
            modelNumberChar,
            pnpIDChar,
            hidInfoChar,
            reportMapChar,
            hidControlPointChar,
            protocolModeChar
        ]
        for case let candidate? in allKnown where candidate === characteristic {
            return candidate
        }

        if characteristic.uuid == HOGPUUID.report {
            if let descriptors = characteristic.descriptors,
               let refDesc = descriptors.first(where: { $0.uuid == HOGPUUID.reportReference }),
               let refData = refDesc.value as? Data,
               refData.count >= 2 {
                let reportID = refData[refData.startIndex]
                let reportType = refData[refData.startIndex + 1]
                switch (reportID, reportType) {
                case (HIDReportMap.keyboardReportID, 0x01): return keyboardInputChar
                case (HIDReportMap.keyboardReportID, 0x02): return keyboardOutputChar
                case (HIDReportMap.mouseReportID, 0x01): return mouseInputChar
                case (HIDReportMap.consumerReportID, 0x01): return consumerInputChar
                case (HIDReportMap.systemReportID, 0x01): return systemInputChar
                case (HIDReportMap.gamepadReportID, 0x01): return gamepadInputChar
                default: break
                }
            }
            return characteristic as? CBMutableCharacteristic
        }

        let uniqueByUUID: [CBMutableCharacteristic?] = [
            bootKeyboardInputChar,
            bootKeyboardOutputChar,
            bootMouseInputChar,
            batteryLevelChar,
            manufacturerChar,
            modelNumberChar,
            pnpIDChar,
            hidInfoChar,
            reportMapChar,
            hidControlPointChar,
            protocolModeChar
        ]
        for case let candidate? in uniqueByUUID where candidate.uuid == characteristic.uuid {
            return candidate
        }
        return characteristic as? CBMutableCharacteristic
    }

    private func characteristicDisplayName(_ characteristic: CBCharacteristic) -> String {
        let target: CBCharacteristic = resolveCharacteristic(characteristic) ?? characteristic
        if target === keyboardInputChar { return "Klavye (ID 1)" }
        if target === keyboardOutputChar { return "Klavye LED Çıkışı (ID 1)" }
        if target === mouseInputChar { return "Fare (ID 2)" }
        if target === consumerInputChar { return "Medya (ID 3)" }
        if target === systemInputChar { return "Sistem (ID 4)" }
        if target === gamepadInputChar { return "Gamepad (ID 5)" }
        if target === bootKeyboardInputChar { return "Boot Klavye (0x2A22)" }
        if target === bootKeyboardOutputChar { return "Boot Klavye LED (0x2A32)" }
        if target === bootMouseInputChar { return "Boot Fare (0x2A33)" }
        if target === batteryLevelChar { return "Pil (0x2A19)" }
        if target === reportMapChar { return "Report Map (0x2A4B)" }
        if target === hidInfoChar { return "HID Info (0x2A4A)" }
        if target === protocolModeChar { return "Protocol Mode (0x2A4E)" }
        if target === hidControlPointChar { return "HID Control Point (0x2A4C)" }
        return characteristic.uuid.uuidString
    }

    private func hasSubscribers(for characteristic: CBMutableCharacteristic) -> Bool {
        if let subs = subscriptionsByCharacteristic[ObjectIdentifier(characteristic)], !subs.isEmpty {
            return true
        }
        return !(characteristic.subscribedCentrals?.isEmpty ?? true)
    }

    private func totalConnectedCentrals() -> Int {
        let hidInputChars: [CBMutableCharacteristic?] = [
            keyboardInputChar,
            bootKeyboardInputChar,
            mouseInputChar,
            bootMouseInputChar,
            consumerInputChar,
            systemInputChar,
            gamepadInputChar
        ]
        var uniqueCentrals: Set<UUID> = []
        for case let char? in hidInputChars {
            if let ids = subscriptionsByCharacteristic[ObjectIdentifier(char)] {
                uniqueCentrals.formUnion(ids)
            }
            if let cbCentrals = char.subscribedCentrals {
                for central in cbCentrals {
                    uniqueCentrals.insert(central.identifier)
                }
            }
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

        let reportMouseSubscribed = mouseInputChar.map { hasSubscribers(for: $0) } ?? false
        let bootMouseSubscribed = bootMouseInputChar.map { hasSubscribers(for: $0) } ?? false
        let effectiveMouseMode: HIDProtocolMode = (currentProtocolMode == .report && reportMouseSubscribed) ? .report : .boot

        if let primaryMouseChar = (effectiveMouseMode == .report ? mouseInputChar : bootMouseInputChar),
           hasSubscribers(for: primaryMouseChar) {
            while let packet = pendingMouse.popNextPacket(protocolMode: effectiveMouseMode) {
                let sent = manager.updateValue(packet, for: primaryMouseChar, onSubscribedCentrals: nil)
                if sent {
                    notifyPacketSent()
                    if effectiveMouseMode == .report,
                       bootMouseSubscribed,
                       let bootChar = bootMouseInputChar,
                       packet.count >= 3 {
                        let bootPacket = Data([packet[0] & 0x07, packet[1], packet[2]])
                        _ = manager.updateValue(bootPacket, for: bootChar, onSubscribedCentrals: nil)
                    }
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

        if let gamepadChar = gamepadInputChar, hasSubscribers(for: gamepadChar) {
            if let packet = pendingGamepad {
                if manager.updateValue(packet, for: gamepadChar, onSubscribedCentrals: nil) {
                    pendingGamepad = nil
                    notifyPacketSent()
                }
            }
        } else {
            pendingGamepad = nil
        }
    }

    private func baselineReport(for characteristic: CBCharacteristic) -> Data? {
        let target = resolveCharacteristic(characteristic) ?? characteristic
        if target === keyboardInputChar || target === bootKeyboardInputChar {
            return HIDReportBuilder.keyboardReport()
        }
        if target === mouseInputChar {
            return HIDReportBuilder.mouseReport()
        }
        if target === bootMouseInputChar {
            return HIDReportBuilder.bootMouseReport()
        }
        if target === consumerInputChar {
            return HIDReportBuilder.consumerReport(usage: 0)
        }
        if target === systemInputChar {
            return HIDReportBuilder.systemReport(usage: [])
        }
        if target === gamepadInputChar {
            return HIDReportBuilder.gamepadReport()
        }
        if target === batteryLevelChar {
            return Data([currentBatteryLevel])
        }
        return nil
    }

    private func readPayload(for characteristic: CBCharacteristic) -> Data? {
        let target = resolveCharacteristic(characteristic) ?? characteristic
        if target === manufacturerChar { return HOGPUUID.manufacturerData }
        if target === modelNumberChar { return HOGPUUID.modelNumberData }
        if target === pnpIDChar { return HOGPUUID.pnpIDValue }
        if target === batteryLevelChar { return Data([currentBatteryLevel]) }
        if target === hidInfoChar { return HOGPUUID.hidInfoValue }
        if target === reportMapChar { return HIDReportMap.descriptorData }
        if target === protocolModeChar { return Data([currentProtocolMode.rawValue]) }
        if target === keyboardOutputChar || target === bootKeyboardOutputChar {
            return Data([0x00])
        }
        return baselineReport(for: target)
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

    private func logBundlePlistCheck(force: Bool) {
        guard force || !hasLoggedPlistCheck else { return }
        hasLoggedPlistCheck = true
        let info = Bundle.main.infoDictionary ?? [:]
        let hasBTAlways = (info["NSBluetoothAlwaysUsageDescription"] as? String)?.isEmpty == false
        let bgModes = (info["UIBackgroundModes"] as? [String]) ?? []
        let bgText = bgModes.isEmpty ? "YOK" : bgModes.joined(separator: ",")
        emitLog(.ble, "Info.plist: BTAlways=\(hasBTAlways ? "VAR" : "YOK"), ArkaPlan=\(bgText)")
    }

    private func stateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "Bilinmiyor"
        case .resetting: return "Sıfırlanıyor"
        case .unsupported: return "Desteklenmiyor"
        case .unauthorized: return "Yetkisiz"
        case .poweredOff: return "Kapalı"
        case .poweredOn: return "Açık"
        @unknown default: return "Diğer(\(state.rawValue))"
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
        return trimmed.isEmpty ? "BluePad" : String(trimmed.prefix(18))
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

    private func emitDiscoveredHosts(force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && (now - lastHostEmitUptime) < 0.35 {
            return
        }
        lastHostEmitUptime = now
        let sorted = DiscoveredBLEHost.sortForDisplay(Array(discoveredHosts.values))
        let handler = onDiscoveredHostsChange
        Task { @MainActor in
            handler?(sorted)
        }
    }

    private func emitScanningState(_ scanning: Bool) {
        let handler = onScanningStateChange
        Task { @MainActor in
            handler?(scanning)
        }
    }

    private func emitGATTStatus() {
        let snapshot = gattStatus
        let handler = onGATTStatusChange
        Task { @MainActor in
            handler?(snapshot)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEHIDPeripheralService: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        handleManagerState(peripheral)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if service === serviceChangedDummyObj || (serviceChangedDummyObj != nil && service.uuid == serviceChangedDummyObj?.uuid) {
            if let error {
                let nsError = error as NSError
                emitLog(.error, "GATT Service Changed hatası [\(nsError.domain):\(nsError.code)]: \(error.localizedDescription)")
            } else {
                emitLog(.gatt, "GATT Service Changed sinyali gönderildi.")
            }
            return
        }

        if let error {
            let nsError = error as NSError
            let errText = "\(nsError.domain):\(nsError.code) \(error.localizedDescription)"
            emitLog(
                .error,
                "GATT servisi eklenemedi (\(service.uuid.uuidString)) [\(nsError.domain):\(nsError.code)]: \(error.localizedDescription)"
            )

            switch service.uuid {
            case HOGPUUID.batteryService:
                batteryServiceObj = nil
                gattStatus.batteryAdded = false
                gattStatus.lastError = "180F: \(errText)"
                emitGATTStatus()
                let dis = buildDeviceInfoService()
                deviceInfoServiceObj = dis
                peripheral.add(dis)

            case HOGPUUID.deviceInformationService:
                deviceInfoServiceObj = nil
                gattStatus.deviceInfoAdded = false
                emitGATTStatus()
                let hid = buildHIDService(includingBattery: batteryServiceObj)
                hidServiceObj = hid
                peripheral.add(hid)

            case HOGPUUID.hidService:
                if hidServiceObj?.includedServices != nil && !hidRetryWithoutIncludedBattery {
                    hidRetryWithoutIncludedBattery = true
                    emitLog(.ble, "1812 includedServices reddedildi; bağımsız HID servisi deneniyor...")
                    let fallbackHID = buildHIDService(includingBattery: nil)
                    hidServiceObj = fallbackHID
                    peripheral.add(fallbackHID)
                    return
                }
                isPublishingServices = false
                servicesPublished = false
                hidServicePublished = false
                gattStatus.hidAdded = false
                gattStatus.lastError = "1812: \(errText)"
                emitGATTStatus()
                emitState(.failed("HID 1812: \(error.localizedDescription)"))

            default:
                break
            }
            return
        }

        emitLog(.gatt, "Servis eklendi: \(service.uuid.uuidString)")

        switch service.uuid {
        case HOGPUUID.batteryService:
            gattStatus.batteryAdded = true
            emitGATTStatus()
            let dis = buildDeviceInfoService()
            deviceInfoServiceObj = dis
            peripheral.add(dis)

        case HOGPUUID.deviceInformationService:
            gattStatus.deviceInfoAdded = true
            emitGATTStatus()
            let hid = buildHIDService(includingBattery: batteryServiceObj)
            hidServiceObj = hid
            peripheral.add(hid)

        case HOGPUUID.hidService:
            isPublishingServices = false
            hidServicePublished = true
            servicesPublished = true
            gattStatus.hidAdded = true
            gattStatus.includedBatteryInHID = (hidServiceObj?.includedServices?.isEmpty == false)
            gattStatus.lastError = nil
            emitGATTStatus()
            emitLog(.gatt, "HOGP GATT servisleri yayınlandı.")
            if shouldAdvertise {
                beginAdvertising(on: peripheral)
            } else {
                updateConnectionState(from: peripheral)
            }

        default:
            break
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            let nsError = error as NSError
            emitLog(
                .error,
                "Yayın başlatılamadı [\(nsError.domain):\(nsError.code)]: \(error.localizedDescription)"
            )
            if !usingFallbackAdvertising {
                usingFallbackAdvertising = true
                gattStatus.lastError = "16-bit 0x1812 [\(nsError.domain):\(nsError.code)]"
                gattStatus.advertisingMode = "128-bit + İsim deneniyor..."
                emitGATTStatus()
                emitLog(.ble, "16-bit 0x1812 reddedildi [\(nsError.domain):\(nsError.code)]; 128-bit + İsim moduna geçiliyor...")
                peripheral.startAdvertising([
                    CBAdvertisementDataLocalNameKey: advertisedName,
                    CBAdvertisementDataServiceUUIDsKey: [HOGPUUID.hidService]
                ])
            } else {
                gattStatus.isAdvertising = false
                gattStatus.advertisingMode = "Hata"
                gattStatus.lastError = "\(nsError.domain):\(nsError.code) \(error.localizedDescription)"
                emitGATTStatus()
                emitState(.failed("Yayın hatası: \(error.localizedDescription)"))
            }
            return
        }
        let modeText = usingFallbackAdvertising ? "Aktif (128-bit + İsim)" : "Aktif (16-bit 0x1812)"
        gattStatus.isAdvertising = peripheral.isAdvertising
        gattStatus.advertisingMode = modeText
        if !usingFallbackAdvertising {
            gattStatus.lastError = nil
        }
        emitGATTStatus()
        emitLog(.ble, "HID yayını aktif (\(modeText)): \"\(advertisedName)\"")
        updateConnectionState(from: peripheral)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        let resolved = resolveCharacteristic(characteristic)
        let key = ObjectIdentifier(resolved ?? characteristic)
        var set = subscriptionsByCharacteristic[key] ?? []
        set.insert(central.identifier)
        subscriptionsByCharacteristic[key] = set

        let label = characteristicDisplayName(characteristic)
        emitLog(.gatt, "Host abone oldu: \(label)")
        updateConnectionState(from: peripheral)

        var clearedConnecting = false
        for (hostID, var host) in discoveredHosts where host.linkState.isConnecting {
            hostConnectTimeouts[hostID]?.cancel()
            hostConnectTimeouts.removeValue(forKey: hostID)
            if let p = discoveredPeripherals[hostID] {
                centralManager?.cancelPeripheralConnection(p)
            }
            host.linkState = .discovered
            discoveredHosts[hostID] = host
            clearedConnecting = true
        }
        if clearedConnecting {
            emitDiscoveredHosts(force: true)
        }

        // Mandatory baseline input report on subscribe so Windows/macOS/Linux hosts
        // finalize HID binding immediately without stalling.
        if let mutable = resolved ?? (characteristic as? CBMutableCharacteristic),
           let baseline = baselineReport(for: mutable) {
            enqueueReliable(baseline, on: mutable, label: "Başlangıç Raporu (\(label))")
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        let resolved = resolveCharacteristic(characteristic)
        let key = ObjectIdentifier(resolved ?? characteristic)
        subscriptionsByCharacteristic[key]?.remove(central.identifier)
        if subscriptionsByCharacteristic[key]?.isEmpty == true {
            subscriptionsByCharacteristic.removeValue(forKey: key)
        }

        emitLog(.gatt, "Host aboneliği ayrıldı: \(characteristicDisplayName(characteristic))")
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

        let target = resolveCharacteristic(request.characteristic) ?? request.characteristic
        if target === reportMapChar && request.offset == 0 {
            emitLog(.gatt, "Report Map okundu (\(payload.count) bayt)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            let value = request.value ?? Data()
            let target = resolveCharacteristic(request.characteristic) ?? request.characteristic

            if target === protocolModeChar {
                if let byte = value.first, let mode = HIDProtocolMode(rawValue: byte) {
                    currentProtocolMode = mode
                    emitProtocolMode(mode)
                    emitLog(.rx, "Protokol modu değişti: \(mode.displayName)")
                }
            } else if target === hidControlPointChar {
                if let byte = value.first {
                    let msg = byte == 0x00 ? "Host Askıya Aldı (Suspend)" : "Host Uyandı (Exit Suspend)"
                    emitLog(.rx, msg)
                }
            } else if target === keyboardOutputChar || target === bootKeyboardOutputChar {
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

// MARK: - CBCentralManagerDelegate (Permission Bootstrap & Outbound Host Scanner)

extension BLEHIDPeripheralService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emitLog(
            .ble,
            "Central durumu: \(stateName(central.state)) (raw=\(central.state.rawValue)), yetki: \(authorizationText(CBManager.authorization))"
        )

        switch central.state {
        case .poweredOn:
            refreshSystemConnectedHosts(on: central)
            emitDiscoveredHosts(force: true)

            if peripheralManager == nil || peripheralManager?.state == .unknown {
                isPublishingServices = false
                servicesPublished = false
                hidServicePublished = false
                hidRetryWithoutIncludedBattery = false
                batteryServiceObj = nil
                deviceInfoServiceObj = nil
                hidServiceObj = nil
                serviceChangedDummyObj = nil
                peripheralManager?.delegate = nil
                emitLog(.ble, "Central açıldı; CBPeripheralManager başlatılıyor...")
                peripheralManager = CBPeripheralManager(
                    delegate: self,
                    queue: nil,
                    options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
                )
            } else if let manager = peripheralManager {
                handleManagerState(manager)
            }

            if pendingHostScan {
                pendingHostScan = false
                startHostScan()
            }

        case .unauthorized:
            stopHostScan()
            emitState(.unauthorized)

        case .poweredOff:
            stopHostScan()
            emitState(.poweredOff)

        case .unsupported:
            stopHostScan()
            if peripheralManager == nil || peripheralManager?.state == .unknown {
                emitState(.unsupported)
            }

        case .resetting, .unknown:
            break

        @unknown default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiValue = RSSI.intValue
        guard rssiValue != 127 else { return }

        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let periphName = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existing = discoveredHosts[peripheral.identifier]
        let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let mfgName = mfgData.flatMap { BLECompanyDirectory.companyName(from: $0) } ?? existing?.manufacturerName

        let resolvedName: String
        let hasName: Bool
        if !advName.isEmpty {
            resolvedName = advName
            hasName = true
        } else if !periphName.isEmpty {
            resolvedName = periphName
            hasName = true
        } else if let existing, existing.hasExplicitName {
            resolvedName = existing.name
            hasName = true
        } else {
            let shortID = String(peripheral.identifier.uuidString.prefix(8))
            if let mfgName {
                resolvedName = "\(mfgName) Cihazı (\(shortID))"
            } else {
                resolvedName = "Bilinmeyen BLE (\(shortID))"
            }
            hasName = false
        }

        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
        discoveredPeripherals[peripheral.identifier] = peripheral
        discoveredHosts[peripheral.identifier] = DiscoveredBLEHost(
            id: peripheral.identifier,
            name: resolvedName,
            hasExplicitName: hasName,
            rssi: rssiValue,
            isConnectable: isConnectable,
            isSystemConnected: existing?.isSystemConnected ?? false,
            manufacturerName: mfgName,
            linkState: existing?.linkState ?? .discovered,
            lastSeen: Date()
        )
        emitDiscoveredHosts(force: false)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        hostConnectTimeouts[peripheral.identifier]?.cancel()
        hostConnectTimeouts.removeValue(forKey: peripheral.identifier)
        peripheral.delegate = self
        peripheral.discoverServices(nil)

        let hostName = discoveredHosts[peripheral.identifier]?.name
            ?? peripheral.name
            ?? "BLE Cihazı"
        if var host = discoveredHosts[peripheral.identifier] {
            host.linkState = .connected
            host.lastSeen = Date()
            discoveredHosts[peripheral.identifier] = host
        } else {
            discoveredHosts[peripheral.identifier] = DiscoveredBLEHost(
                id: peripheral.identifier,
                name: hostName,
                hasExplicitName: !(peripheral.name ?? "").isEmpty,
                rssi: -50,
                isConnectable: true,
                isSystemConnected: true,
                manufacturerName: nil,
                linkState: .connected,
                lastSeen: Date()
            )
        }
        emitDiscoveredHosts(force: true)
        emitLog(.ble, "Cihaza bağlanıldı: \(hostName). Karşı cihazın HID (0x1812) servisine abone olması bekleniyor...")

        let targetID = peripheral.identifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            if self.totalConnectedCentrals() == 0,
               self.discoveredHosts[targetID]?.linkState.isConnected == true {
                self.triggerServiceChangedRefresh()
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        hostConnectTimeouts[peripheral.identifier]?.cancel()
        hostConnectTimeouts.removeValue(forKey: peripheral.identifier)
        let reason = error?.localizedDescription ?? "Bağlantı başarısız"
        let hostName = discoveredHosts[peripheral.identifier]?.name ?? peripheral.name ?? "BLE Cihazı"
        if var host = discoveredHosts[peripheral.identifier] {
            host.linkState = .failed(reason)
            discoveredHosts[peripheral.identifier] = host
            emitDiscoveredHosts(force: true)
        }
        emitLog(.error, "Hedef cihaza bağlanılamadı (\(hostName)): \(reason)")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        hostConnectTimeouts[peripheral.identifier]?.cancel()
        hostConnectTimeouts.removeValue(forKey: peripheral.identifier)
        let hostName = discoveredHosts[peripheral.identifier]?.name ?? peripheral.name ?? "BLE Cihazı"
        if var host = discoveredHosts[peripheral.identifier] {
            host.linkState = .discovered
            discoveredHosts[peripheral.identifier] = host
            emitDiscoveredHosts(force: true)
        }
        if let error {
            emitLog(.ble, "Hedef cihaz bağlantısı kesildi (\(hostName)): \(error.localizedDescription)")
        } else {
            emitLog(.ble, "Hedef cihaz bağlantısı kesildi (\(hostName)).")
        }
    }
}

// MARK: - CBPeripheralDelegate (GAP Name Refresh)

extension BLEHIDPeripheralService: CBPeripheralDelegate {

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        let clean = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clean.isEmpty, var host = discoveredHosts[peripheral.identifier] else { return }
        host.name = clean
        host.hasExplicitName = true
        host.lastSeen = Date()
        discoveredHosts[peripheral.identifier] = host
        emitDiscoveredHosts(force: true)
        emitLog(.ble, "Hedef cihaz adı güncellendi: \(clean)")
    }
}
