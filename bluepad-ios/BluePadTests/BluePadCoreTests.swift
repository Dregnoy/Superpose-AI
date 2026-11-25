import CoreBluetooth
import XCTest
@testable import BluePad

final class BluePadCoreTests: XCTestCase {

    // MARK: - 1. USB HID Report Descriptor Byte-Level Validation

    func testHIDReportDescriptorStructureAndByteAlignment() {
        let bytes = HIDReportMap.descriptorBytes
        XCTAssertFalse(bytes.isEmpty)

        var idx = 0
        var collectionDepth = 0
        var reportID: UInt8 = 0
        var reportSize = 0
        var reportCount = 0

        var inputBitsByReportID: [UInt8: Int] = [:]
        var outputBitsByReportID: [UInt8: Int] = [:]

        while idx < bytes.count {
            let header = bytes[idx]
            idx += 1

            // Long item (0xFE) not used here
            XCTAssertNotEqual(header, 0xFE, "Unexpected long HID item")

            let sizeCode = header & 0x03
            let byteSize: Int = sizeCode == 3 ? 4 : Int(sizeCode)
            let itemType = (header >> 2) & 0x03 // 0 = Main, 1 = Global, 2 = Local
            let tag = (header >> 4) & 0x0F

            XCTAssertLessThanOrEqual(idx + byteSize, bytes.count, "Truncated HID item at index \(idx)")

            var value: Int = 0
            for shiftIndex in 0..<byteSize {
                value |= Int(bytes[idx + shiftIndex]) << (8 * shiftIndex)
            }
            idx += byteSize

            if itemType == 1 {
                // Global items
                switch tag {
                case 0x07: // Report Size
                    reportSize = value
                case 0x08: // Report ID
                    reportID = UInt8(value)
                case 0x09: // Report Count
                    reportCount = value
                default:
                    break
                }
            } else if itemType == 0 {
                // Main items
                switch tag {
                case 0x0A: // Collection
                    collectionDepth += 1
                case 0x0C: // End Collection
                    collectionDepth -= 1
                    XCTAssertGreaterThanOrEqual(collectionDepth, 0, "Unbalanced End Collection")
                case 0x08: // Input
                    inputBitsByReportID[reportID, default: 0] += reportSize * reportCount
                case 0x09: // Output
                    outputBitsByReportID[reportID, default: 0] += reportSize * reportCount
                default:
                    break
                }
            }
        }

        XCTAssertEqual(collectionDepth, 0, "Unclosed HID Collection")
        XCTAssertEqual(inputBitsByReportID[1], 64, "Keyboard Input report must be 8 bytes (64 bits)")
        XCTAssertEqual(outputBitsByReportID[1], 8, "Keyboard Output LED report must be 1 byte (8 bits)")
        XCTAssertEqual(inputBitsByReportID[2], 40, "Mouse Input report must be 5 bytes (40 bits)")
        XCTAssertEqual(inputBitsByReportID[3], 16, "Consumer Input report must be 2 bytes (16 bits)")
        XCTAssertEqual(inputBitsByReportID[4], 8, "System Input report must be 1 byte (8 bits)")
        XCTAssertEqual(inputBitsByReportID[5], 56, "Gamepad Input report must be 7 bytes (56 bits)")
    }

    // MARK: - 2. Canonical 128-bit UUID Enforcement

    func testHOGPUUIDsAreFull128BitCanonical() {
        let allUUIDs: [CBUUID] = [
            HOGPUUID.deviceInformationService,
            HOGPUUID.batteryService,
            HOGPUUID.hidService,
            HOGPUUID.manufacturerName,
            HOGPUUID.modelNumber,
            HOGPUUID.pnpID,
            HOGPUUID.batteryLevel,
            HOGPUUID.hidInformation,
            HOGPUUID.reportMap,
            HOGPUUID.hidControlPoint,
            HOGPUUID.report,
            HOGPUUID.protocolMode,
            HOGPUUID.bootKeyboardInput,
            HOGPUUID.bootKeyboardOutput,
            HOGPUUID.bootMouseInput,
            HOGPUUID.reportReference
        ]

        let pattern = #"^0000[0-9A-F]{4}-0000-1000-8000-00805F9B34FB$"#
        for uuid in allUUIDs {
            XCTAssertEqual(uuid.data.count, 16, "UUID \(uuid.uuidString) must be 128-bit (16 bytes), not 16-bit")
            let matches = uuid.uuidString.uppercased().range(of: pattern, options: .regularExpression) != nil
            XCTAssertTrue(matches, "UUID \(uuid.uuidString) does not match canonical Bluetooth SIG 128-bit base format")
        }
    }

    // MARK: - 3. HID Binary Packet Builders

    func testHIDPacketBuilders() {
        // Keyboard 6KRO deduplication + max 6 keys
        let kb = HIDReportBuilder.keyboardReport(
            modifiers: [.leftControl, .leftShift],
            keys: [0x04, 0x04, 0x05, 0x00, 0x06, 0x07, 0x08, 0x09, 0x0A]
        )
        XCTAssertEqual([UInt8](kb), [0x03, 0x00, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09])

        // 5-byte mouse report & button masking
        let mouse = HIDReportBuilder.mouseReport(
            buttons: [.left, .right],
            dx: -12,
            dy: 45,
            wheel: -3,
            hWheel: 2
        )
        XCTAssertEqual([UInt8](mouse), [0x03, UInt8(bitPattern: -12), 45, UInt8(bitPattern: -3), 2])

        // 3-byte boot mouse report
        let bootMouse = HIDReportBuilder.bootMouseReport(buttons: [.left, .middle, .back], dx: 10, dy: -5)
        XCTAssertEqual([UInt8](bootMouse), [0x05, 10, UInt8(bitPattern: -5)])

        // Large delta split
        let split = HIDReportBuilder.splitMousePackets(buttons: [.left], dx: 300, dy: -260)
        XCTAssertEqual(split.count, 3)
        let totalDX = split.reduce(0) { $0 + Int(Int8(bitPattern: $1[1])) }
        let totalDY = split.reduce(0) { $0 + Int(Int8(bitPattern: $1[2])) }
        XCTAssertEqual(totalDX, 300)
        XCTAssertEqual(totalDY, -260)

        // Consumer LE 16-bit
        let playPause = HIDReportBuilder.consumerReport(usage: HIDConsumerUsage.playPause.rawValue)
        XCTAssertEqual([UInt8](playPause), [0xCD, 0x00])

        // System report
        let sleepReport = HIDReportBuilder.systemReport(usage: .sleep)
        XCTAssertEqual([UInt8](sleepReport), [0x02])

        // Host LED output parsing
        let leds = HIDReportBuilder.parseLEDOutput(Data([0x03]))
        XCTAssertTrue(leds.contains(.numLock))
        XCTAssertTrue(leds.contains(.capsLock))
        XCTAssertFalse(leds.contains(.scrollLock))
    }

    // MARK: - 4. Turkish Q & Turkish F Keyboard Layouts

    func testTurkishQAndTurkishFKeyboardLayouts() {
        // TR-Q critical Turkish letters
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "i", layout: .turkishQ), KeyStroke(.apostrophe))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "İ", layout: .turkishQ), KeyStroke(.apostrophe, modifiers: .leftShift))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "ı", layout: .turkishQ), KeyStroke(.i))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "I", layout: .turkishQ), KeyStroke(.i, modifiers: .leftShift))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "ğ", layout: .turkishQ), KeyStroke(.leftBracket))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "Ğ", layout: .turkishQ), KeyStroke(.leftBracket, modifiers: .leftShift))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "ü", layout: .turkishQ), KeyStroke(.rightBracket))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "ş", layout: .turkishQ), KeyStroke(.semicolon))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "ö", layout: .turkishQ), KeyStroke(.comma))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "ç", layout: .turkishQ), KeyStroke(.period))

        // TR-Q AltGr symbols
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "@", layout: .turkishQ), KeyStroke(.q, modifiers: .rightAlt))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "€", layout: .turkishQ), KeyStroke(.e, modifiers: .rightAlt))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "₺", layout: .turkishQ), KeyStroke(.t, modifiers: .rightAlt))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "\\", layout: .turkishQ), KeyStroke(.minus, modifiers: .rightAlt))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "{", layout: .turkishQ), KeyStroke(.digit7, modifiers: .rightAlt))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "[", layout: .turkishQ), KeyStroke(.digit8, modifiers: .rightAlt))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "]", layout: .turkishQ), KeyStroke(.digit9, modifiers: .rightAlt))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "}", layout: .turkishQ), KeyStroke(.digit0, modifiers: .rightAlt))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "|", layout: .turkishQ), KeyStroke(.equal, modifiers: .rightAlt))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "~", layout: .turkishQ), KeyStroke(.rightBracket, modifiers: .rightAlt))

        // Decomposed Unicode handling (g + combining breve -> ğ)
        let decomposed = "g\u{0306}"
        let decomposedStrokes = KeyboardLayoutEngine.keyStrokes(for: decomposed, layout: .turkishQ)
        XCTAssertEqual(decomposedStrokes, [KeyStroke(.leftBracket)])

        // TR-F key placements
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "f", layout: .turkishF), KeyStroke(.q))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "u", layout: .turkishF), KeyStroke(.a))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "a", layout: .turkishF), KeyStroke(.f))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "@", layout: .turkishF), KeyStroke(.q, modifiers: .rightAlt))
    }

    // MARK: - 5. International Keyboard Layouts

    func testInternationalKeyboardLayouts() {
        // US QWERTY
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "@", layout: .usQWERTY), KeyStroke(.digit2, modifiers: .leftShift))
        // UK QWERTY
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "£", layout: .ukQWERTY), KeyStroke(.digit3, modifiers: .leftShift))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "\"", layout: .ukQWERTY), KeyStroke(.digit2, modifiers: .leftShift))
        // German QWERTZ
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "z", layout: .germanQWERTZ), KeyStroke(.y))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "y", layout: .germanQWERTZ), KeyStroke(.z))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "ß", layout: .germanQWERTZ), KeyStroke(.minus))
        // French AZERTY
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "a", layout: .frenchAZERTY), KeyStroke(.q))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "q", layout: .frenchAZERTY), KeyStroke(.a))
        XCTAssertEqual(KeyboardLayoutEngine.keyStroke(for: "1", layout: .frenchAZERTY), KeyStroke(.digit1, modifiers: .leftShift))

        // CRLF + Tab normalization
        let textStrokes = KeyboardLayoutEngine.keyStrokes(for: "ab\r\n\t", layout: .usQWERTY)
        XCTAssertEqual(textStrokes, [KeyStroke(.a), KeyStroke(.b), KeyStroke(.enter), KeyStroke(.tab)])
    }

    // MARK: - 6. Mouse Motion Processor & Coalescing Buffer

    func testMouseMotionProcessorAndCoalescingBuffer() {
        var processor = MouseMotionProcessor()
        var totalStepX = 0
        for _ in 0..<4 {
            let step = processor.processMove(rawDX: 0.3, rawDY: 0, sensitivity: 1.0, acceleration: false)
            totalStepX += step.dx
        }
        XCTAssertEqual(totalStepX, 1)
        XCTAssertEqual(processor.remainderX, 0.2, accuracy: 0.0001)

        // Natural scrolling vs standard scrolling
        var scrollProc = MouseMotionProcessor()
        let natural = scrollProc.processScroll(rawDX: 0, rawDY: 20, sensitivity: 1.0, naturalScrolling: true)
        XCTAssertGreaterThan(natural.wheel, 0)

        var classicProc = MouseMotionProcessor()
        let classic = classicProc.processScroll(rawDX: 0, rawDY: 20, sensitivity: 1.0, naturalScrolling: false)
        XCTAssertLessThan(classic.wheel, 0)

        // PendingMouseAccumulator drainage
        var acc = PendingMouseAccumulator()
        acc.accumulate(buttons: [.left], dx: 200, dy: -150, wheel: 2, hWheel: 0)
        let first = acc.popNextPacket(protocolMode: .report)
        let second = acc.popNextPacket(protocolMode: .report)
        let third = acc.popNextPacket(protocolMode: .report)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNil(third)
        XCTAssertEqual(first?[0], 0x01)
        XCTAssertEqual(Int8(bitPattern: first![1]), 127)
        XCTAssertEqual(Int8(bitPattern: second![1]), 73)
    }

    // MARK: - 7. Persistence & Macro Round-Trip

    func testMacroSerializationRoundTrip() throws {
        XCTAssertFalse(CustomMacro.defaultPresets.isEmpty)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BluePadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = MacroStorageService(baseDirectory: tempDir)
        var settings = BluePadSettings.default
        settings.advertisedName = "TestPad"
        settings.keyboardLayout = .turkishF
        settings.pointerSensitivity = 2.1
        storage.saveSettings(settings)

        let loadedSettings = storage.loadSettings()
        XCTAssertEqual(loadedSettings, settings)

        let sampleMacros: [CustomMacro] = [
            CustomMacro(
                title: "Combo",
                subtitle: "Ctrl+C",
                sfSymbol: "doc.on.doc",
                accentHex: "#38BDF8",
                category: .coding,
                action: .keyCombo(keyCode: HIDKeyCode.c.rawValue, modifiersRaw: HIDModifier.leftControl.rawValue)
            ),
            CustomMacro(
                title: "Text",
                subtitle: "Merhaba",
                sfSymbol: "text.bubble",
                accentHex: "#34D399",
                category: .custom,
                action: .typeText(text: "Merhaba Dünya", appendEnter: true)
            ),
            CustomMacro(
                title: "Media",
                subtitle: "Play",
                sfSymbol: "playpause.fill",
                accentHex: "#FBBF24",
                category: .media,
                action: .consumerKey(usageRaw: HIDConsumerUsage.playPause.rawValue)
            ),
            CustomMacro(
                title: "Sleep",
                subtitle: "Sleep",
                sfSymbol: "moon.fill",
                accentHex: "#A78BFA",
                category: .general,
                action: .systemKey(usageRaw: HIDSystemUsage.sleep.rawValue)
            )
        ]

        storage.saveMacros(sampleMacros)
        let loadedMacros = storage.loadMacros()
        XCTAssertEqual(loadedMacros, sampleMacros)
    }

    // MARK: - 8. Advertising UUID, HOGP Status & Outbound Host Sorting

    func testAdvertisingUUIDAndDiscoveredHostSorting() {
        XCTAssertEqual(HOGPUUID.hidServiceAdvertising16Bit.data.count, 2)
        XCTAssertEqual(HOGPUUID.hidServiceAdvertising16Bit.uuidString.uppercased(), "1812")

        let defaultStatus = HOGPServiceStatus()
        XCTAssertFalse(defaultStatus.batteryAdded)
        XCTAssertFalse(defaultStatus.deviceInfoAdded)
        XCTAssertFalse(defaultStatus.hidAdded)
        XCTAssertFalse(defaultStatus.includedBatteryInHID)
        XCTAssertFalse(defaultStatus.isAdvertising)
        XCTAssertEqual(defaultStatus.advertisingMode, "Bekliyor")
        XCTAssertNil(defaultStatus.lastError)

        let now = Date()
        let unnamedStrong = DiscoveredBLEHost(
            id: UUID(),
            name: "Bilinmeyen BLE",
            hasExplicitName: false,
            rssi: -35,
            isConnectable: true,
            isSystemConnected: false,
            linkState: .discovered,
            lastSeen: now
        )
        let namedWeak = DiscoveredBLEHost(
            id: UUID(),
            name: "Z-PC",
            hasExplicitName: true,
            rssi: -75,
            isConnectable: true,
            isSystemConnected: false,
            linkState: .discovered,
            lastSeen: now
        )
        let namedStrong = DiscoveredBLEHost(
            id: UUID(),
            name: "A-MacBook",
            hasExplicitName: true,
            rssi: -45,
            isConnectable: true,
            isSystemConnected: false,
            linkState: .discovered,
            lastSeen: now
        )
        let systemHost = DiscoveredBLEHost(
            id: UUID(),
            name: "Sistem Cihazı",
            hasExplicitName: true,
            rssi: -80,
            isConnectable: true,
            isSystemConnected: true,
            linkState: .discovered,
            lastSeen: now
        )
        let connectingHost = DiscoveredBLEHost(
            id: UUID(),
            name: "Bağlanan TV",
            hasExplicitName: true,
            rssi: -85,
            isConnectable: true,
            isSystemConnected: false,
            linkState: .connecting,
            lastSeen: now
        )
        let connectedHost = DiscoveredBLEHost(
            id: UUID(),
            name: "Bağlı Windows",
            hasExplicitName: true,
            rssi: -90,
            isConnectable: true,
            isSystemConnected: false,
            linkState: .connected,
            lastSeen: now
        )

        let sorted = DiscoveredBLEHost.sortForDisplay([
            unnamedStrong, namedWeak, namedStrong, systemHost, connectingHost, connectedHost
        ])
        XCTAssertEqual(sorted.map(\.name), [
            "Bağlı Windows",
            "Bağlanan TV",
            "Sistem Cihazı",
            "A-MacBook",
            "Z-PC",
            "Bilinmeyen BLE"
        ])
    }

    // MARK: - 9. Gamepad Report, Manufacturer Directory, Wi-Fi QR & Settings Backwards Compatibility

    func testGamepadPacketBuilderAndCompanyDirectoryAndWiFiQR() throws {
        let gp = HIDGamepadState(
            buttons: [.a, .r1, .start],
            hat: .upRight,
            leftX: -120,
            leftY: 64,
            rightX: 127,
            rightY: -127
        )
        let bytes = [UInt8](HIDReportBuilder.gamepadReport(gp))
        XCTAssertEqual(bytes.count, 7)
        // buttons raw = (1<<0) | (1<<5) | (1<<9) = 0x0221 -> low=0x21, high=0x02
        XCTAssertEqual(bytes[0], 0x21)
        XCTAssertEqual(bytes[1], 0x02)
        XCTAssertEqual(bytes[2], HIDGamepadHat.upRight.rawValue)
        XCTAssertEqual(Int8(bitPattern: bytes[3]), -120)
        XCTAssertEqual(Int8(bitPattern: bytes[4]), 64)
        XCTAssertEqual(Int8(bitPattern: bytes[5]), 127)
        XCTAssertEqual(Int8(bitPattern: bytes[6]), -127)

        XCTAssertEqual(BLECompanyDirectory.companyName(from: Data([0x4C, 0x00, 0x10])), "Apple")
        XCTAssertEqual(BLECompanyDirectory.companyName(from: Data([0x06, 0x00, 0x01])), "Microsoft / Windows")
        XCTAssertEqual(BLECompanyDirectory.companyName(from: Data([0x75, 0x00])), "Samsung")
        XCTAssertEqual(BLECompanyDirectory.companyName(from: Data([0xC4, 0x00])), "LG")
        XCTAssertEqual(BLECompanyDirectory.companyName(from: Data([0x2D, 0x01])), "Sony")
        XCTAssertNil(BLECompanyDirectory.companyName(from: Data([0xFF])))
        XCTAssertNil(BLECompanyDirectory.companyName(from: Data([0xFE, 0xFE])))

        let qr = WiFiHIDTransportService.parsePairingQR("bluepad://192.168.1.42:8765/1234")
        XCTAssertNotNil(qr)
        XCTAssertEqual(qr?.host, "192.168.1.42")
        XCTAssertEqual(qr?.port, 8765)
        XCTAssertEqual(qr?.pin, "1234")

        let defaultPortQR = WiFiHIDTransportService.parsePairingQR("bluepad://10.0.0.5/9999")
        XCTAssertEqual(defaultPortQR?.port, WiFiHIDTransportService.defaultTCPPort)
        XCTAssertEqual(defaultPortQR?.pin, "9999")

        XCTAssertNil(WiFiHIDTransportService.parsePairingQR("https://example.com/1234"))
        XCTAssertNil(WiFiHIDTransportService.parsePairingQR("bluepad://192.168.1.42:8765"))

        // Verify legacy settings JSON without new keys decodes cleanly
        let legacyJSON = """
        {
          "advertisedName": "OldPad",
          "keyboardLayout": "turkishQ",
          "hostOS": "windows",
          "pointerSensitivity": 1.5,
          "pointerAcceleration": true,
          "scrollSensitivity": 1.0,
          "naturalScrolling": true,
          "tapToClick": true,
          "hapticsEnabled": true,
          "typingDelayMs": 20,
          "airMouseSensitivity": 1.2,
          "jigglerIntervalSeconds": 45,
          "jigglerMode": "microMouse",
          "scannerAutoEnter": true
        }
        """
        let decodedLegacy = try JSONDecoder().decode(BluePadSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decodedLegacy.advertisedName, "OldPad")
        XCTAssertFalse(decodedLegacy.touchpadButtonsOnTop)
        XCTAssertTrue(decodedLegacy.showScrollStrip)
        XCTAssertEqual(decodedLegacy.macroGridColumns, 2)

        // Verify sequence macro Codable round-trip
        let seqMacro = CustomMacro(
            title: "Build",
            subtitle: "3 adım",
            sfSymbol: "hammer.fill",
            accentHex: "#38BDF8",
            category: .coding,
            fullWidth: true,
            action: .sequence(steps: [
                .keyCombo(keyCode: HIDKeyCode.c.rawValue, modifiersRaw: HIDModifier.leftControl.rawValue),
                .delayMs(150),
                .typeText(text: "run", appendEnter: true)
            ])
        )
        let encoded = try JSONEncoder().encode(seqMacro)
        let decodedMacro = try JSONDecoder().decode(CustomMacro.self, from: encoded)
        XCTAssertEqual(decodedMacro, seqMacro)
    }
}
