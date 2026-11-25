import Foundation

/// USB HID 1.11 composite Report Map descriptor and binary packet builders.
/// Defines 4 Report IDs:
/// - Report ID 1: Standard Keyboard (8-byte Input + 1-byte LED Output)
/// - Report ID 2: 5-Button Relative Mouse + Vertical & Horizontal Wheel (5-byte Input)
/// - Report ID 3: Consumer Control Multimedia Keys (2-byte LE Input)
/// - Report ID 4: Generic Desktop System Control (1-byte Input)
/// - Report ID 5: Gamepad (16 Buttons + 8-Way Hat + Dual Analog Sticks, 7-byte Input)
enum HIDReportMap {
    static let keyboardReportID: UInt8 = 1
    static let mouseReportID: UInt8    = 2
    static let consumerReportID: UInt8 = 3
    static let systemReportID: UInt8   = 4
    static let gamepadReportID: UInt8  = 5

    static let descriptorBytes: [UInt8] = [
        // -----------------------------------------------------------------
        // Report ID 1: Keyboard (8-byte Input + 1-byte Output LEDs)
        // -----------------------------------------------------------------
        0x05, 0x01,       // Usage Page (Generic Desktop)
        0x09, 0x06,       // Usage (Keyboard)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x01,       //   Report ID (1)
        0x05, 0x07,       //   Usage Page (Keyboard/Keypad)
        0x19, 0xE0,       //   Usage Minimum (Left Control)
        0x29, 0xE7,       //   Usage Maximum (Right GUI)
        0x15, 0x00,       //   Logical Minimum (0)
        0x25, 0x01,       //   Logical Maximum (1)
        0x75, 0x01,       //   Report Size (1)
        0x95, 0x08,       //   Report Count (8)
        0x81, 0x02,       //   Input (Data, Var, Abs) - Modifier byte (8 bits)
        0x95, 0x01,       //   Report Count (1)
        0x75, 0x08,       //   Report Size (8)
        0x81, 0x03,       //   Input (Const, Var, Abs) - Reserved byte (8 bits)
        0x95, 0x05,       //   Report Count (5)
        0x75, 0x01,       //   Report Size (1)
        0x05, 0x08,       //   Usage Page (LEDs)
        0x19, 0x01,       //   Usage Minimum (Num Lock)
        0x29, 0x05,       //   Usage Maximum (Kana)
        0x91, 0x02,       //   Output (Data, Var, Abs) - 5 LED bits
        0x95, 0x01,       //   Report Count (1)
        0x75, 0x03,       //   Report Size (3)
        0x91, 0x03,       //   Output (Const, Var, Abs) - 3 LED padding bits
        0x95, 0x06,       //   Report Count (6)
        0x75, 0x08,       //   Report Size (8)
        0x15, 0x00,       //   Logical Minimum (0)
        0x26, 0xFF, 0x00, //   Logical Maximum (255)
        0x05, 0x07,       //   Usage Page (Keyboard/Keypad)
        0x19, 0x00,       //   Usage Minimum (0)
        0x2A, 0xFF, 0x00, //   Usage Maximum (255)
        0x81, 0x00,       //   Input (Data, Array, Abs) - 6KRO key array (48 bits)
        0xC0,             // End Collection

        // -----------------------------------------------------------------
        // Report ID 2: 5-Button Mouse + Vertical & Horizontal Wheel (5-byte Input)
        // -----------------------------------------------------------------
        0x05, 0x01,       // Usage Page (Generic Desktop)
        0x09, 0x02,       // Usage (Mouse)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x02,       //   Report ID (2)
        0x09, 0x01,       //   Usage (Pointer)
        0xA1, 0x00,       //   Collection (Physical)
        0x05, 0x09,       //     Usage Page (Button)
        0x19, 0x01,       //     Usage Minimum (Button 1)
        0x29, 0x05,       //     Usage Maximum (Button 5)
        0x15, 0x00,       //     Logical Minimum (0)
        0x25, 0x01,       //     Logical Maximum (1)
        0x95, 0x05,       //     Report Count (5)
        0x75, 0x01,       //     Report Size (1)
        0x81, 0x02,       //     Input (Data, Var, Abs) - 5 buttons
        0x95, 0x01,       //     Report Count (1)
        0x75, 0x03,       //     Report Size (3)
        0x81, 0x03,       //     Input (Const, Var, Abs) - 3 padding bits
        0x05, 0x01,       //     Usage Page (Generic Desktop)
        0x09, 0x30,       //     Usage (X)
        0x09, 0x31,       //     Usage (Y)
        0x09, 0x38,       //     Usage (Wheel)
        0x15, 0x81,       //     Logical Minimum (-127)
        0x25, 0x7F,       //     Logical Maximum (127)
        0x75, 0x08,       //     Report Size (8)
        0x95, 0x03,       //     Report Count (3)
        0x81, 0x06,       //     Input (Data, Var, Rel) - X, Y, Wheel (24 bits)
        0x05, 0x0C,       //     Usage Page (Consumer)
        0x0A, 0x38, 0x02, //     Usage (AC Pan / Horizontal Wheel)
        0x15, 0x81,       //     Logical Minimum (-127)
        0x25, 0x7F,       //     Logical Maximum (127)
        0x75, 0x08,       //     Report Size (8)
        0x95, 0x01,       //     Report Count (1)
        0x81, 0x06,       //     Input (Data, Var, Rel) - Horizontal Wheel (8 bits)
        0xC0,             //   End Collection (Physical)
        0xC0,             // End Collection (Application)

        // -----------------------------------------------------------------
        // Report ID 3: Consumer Control (2-byte Input)
        // -----------------------------------------------------------------
        0x05, 0x0C,       // Usage Page (Consumer)
        0x09, 0x01,       // Usage (Consumer Control)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x03,       //   Report ID (3)
        0x15, 0x00,       //   Logical Minimum (0)
        0x26, 0xFF, 0x03, //   Logical Maximum (1023)
        0x19, 0x00,       //   Usage Minimum (0)
        0x2A, 0xFF, 0x03, //   Usage Maximum (1023)
        0x75, 0x10,       //   Report Size (16)
        0x95, 0x01,       //   Report Count (1)
        0x81, 0x00,       //   Input (Data, Array, Abs) - 16-bit LE usage
        0xC0,             // End Collection

        // -----------------------------------------------------------------
        // Report ID 4: System Control (1-byte Input)
        // -----------------------------------------------------------------
        0x05, 0x01,       // Usage Page (Generic Desktop)
        0x09, 0x80,       // Usage (System Control)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x04,       //   Report ID (4)
        0x15, 0x00,       //   Logical Minimum (0)
        0x25, 0x01,       //   Logical Maximum (1)
        0x09, 0x81,       //   Usage (System Power Down)
        0x09, 0x82,       //   Usage (System Sleep)
        0x09, 0x83,       //   Usage (System Wake Up)
        0x75, 0x01,       //   Report Size (1)
        0x95, 0x03,       //   Report Count (3)
        0x81, 0x02,       //   Input (Data, Var, Abs)
        0x75, 0x05,       //   Report Size (5)
        0x95, 0x01,       //   Report Count (1)
        0x81, 0x03,       //   Input (Const, Var, Abs)
        0xC0,             // End Collection

        // -----------------------------------------------------------------
        // Report ID 5: Gamepad (7-byte Input: 16 Buttons, 4-bit Hat + 4-bit pad, 4x 8-bit Axes)
        // -----------------------------------------------------------------
        0x05, 0x01,       // Usage Page (Generic Desktop)
        0x09, 0x05,       // Usage (Game Pad)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x05,       //   Report ID (5)
        0x05, 0x09,       //   Usage Page (Button)
        0x19, 0x01,       //   Usage Minimum (Button 1)
        0x29, 0x10,       //   Usage Maximum (Button 16)
        0x15, 0x00,       //   Logical Minimum (0)
        0x25, 0x01,       //   Logical Maximum (1)
        0x75, 0x01,       //   Report Size (1)
        0x95, 0x10,       //   Report Count (16)
        0x81, 0x02,       //   Input (Data, Var, Abs)
        0x05, 0x01,       //   Usage Page (Generic Desktop)
        0x09, 0x39,       //   Usage (Hat switch)
        0x15, 0x00,       //   Logical Minimum (0)
        0x25, 0x07,       //   Logical Maximum (7)
        0x35, 0x00,       //   Physical Minimum (0)
        0x46, 0x3B, 0x01, //   Physical Maximum (315)
        0x65, 0x14,       //   Unit (Eng Rot: Angular Pos)
        0x75, 0x04,       //   Report Size (4)
        0x95, 0x01,       //   Report Count (1)
        0x81, 0x42,       //   Input (Data, Var, Abs, Null)
        0x65, 0x00,       //   Unit (None)
        0x75, 0x04,       //   Report Size (4)
        0x95, 0x01,       //   Report Count (1)
        0x81, 0x03,       //   Input (Const, Var, Abs)
        0x35, 0x00,       //   Physical Minimum (0 - reset to Logical)
        0x45, 0x00,       //   Physical Maximum (0 - reset to Logical)
        0x09, 0x30,       //   Usage (X)
        0x09, 0x31,       //   Usage (Y)
        0x09, 0x32,       //   Usage (Z)
        0x09, 0x35,       //   Usage (Rz)
        0x15, 0x81,       //   Logical Minimum (-127)
        0x25, 0x7F,       //   Logical Maximum (127)
        0x75, 0x08,       //   Report Size (8)
        0x95, 0x04,       //   Report Count (4)
        0x81, 0x02,       //   Input (Data, Var, Abs)
        0xC0              // End Collection
    ]

    static let descriptorData = Data(descriptorBytes)
}

/// Pure HID report packet serializers matching `HIDReportMap`.
enum HIDReportBuilder {
    static func keyboardReport(modifiers: HIDModifier = [], keys: [UInt8] = []) -> Data {
        var payload: [UInt8] = [modifiers.rawValue, 0x00]
        var seen: Set<UInt8> = []
        var uniqueKeys: [UInt8] = []
        uniqueKeys.reserveCapacity(6)

        for key in keys where key != 0 && !seen.contains(key) {
            seen.insert(key)
            uniqueKeys.append(key)
            if uniqueKeys.count == 6 { break }
        }

        while uniqueKeys.count < 6 {
            uniqueKeys.append(0x00)
        }
        payload.append(contentsOf: uniqueKeys)
        return Data(payload)
    }

    static func mouseReport(
        buttons: HIDMouseButton = [],
        dx: Int8 = 0,
        dy: Int8 = 0,
        wheel: Int8 = 0,
        hWheel: Int8 = 0
    ) -> Data {
        let clampedDX = clampToHIDSignedByte(Int(dx))
        let clampedDY = clampToHIDSignedByte(Int(dy))
        let clampedWheel = clampToHIDSignedByte(Int(wheel))
        let clampedHWheel = clampToHIDSignedByte(Int(hWheel))
        return Data([
            buttons.rawValue & 0x1F,
            UInt8(bitPattern: clampedDX),
            UInt8(bitPattern: clampedDY),
            UInt8(bitPattern: clampedWheel),
            UInt8(bitPattern: clampedHWheel)
        ])
    }

    static func bootMouseReport(buttons: HIDMouseButton = [], dx: Int8 = 0, dy: Int8 = 0) -> Data {
        let clampedDX = clampToHIDSignedByte(Int(dx))
        let clampedDY = clampToHIDSignedByte(Int(dy))
        return Data([
            buttons.rawValue & 0x07,
            UInt8(bitPattern: clampedDX),
            UInt8(bitPattern: clampedDY)
        ])
    }

    /// Splits arbitrary integer pointer/scroll deltas into ordered 5-byte HID reports
    /// clamped to -127...127 per packet without losing movement.
    static func splitMousePackets(
        buttons: HIDMouseButton,
        dx: Int,
        dy: Int,
        wheel: Int = 0,
        hWheel: Int = 0
    ) -> [Data] {
        var remX = dx
        var remY = dy
        var remW = wheel
        var remH = hWheel

        if remX == 0 && remY == 0 && remW == 0 && remH == 0 {
            return [mouseReport(buttons: buttons)]
        }

        var packets: [Data] = []
        while remX != 0 || remY != 0 || remW != 0 || remH != 0 {
            let stepX = clampToHIDSignedByte(remX)
            let stepY = clampToHIDSignedByte(remY)
            let stepW = clampToHIDSignedByte(remW)
            let stepH = clampToHIDSignedByte(remH)

            packets.append(mouseReport(
                buttons: buttons,
                dx: stepX,
                dy: stepY,
                wheel: stepW,
                hWheel: stepH
            ))

            remX -= Int(stepX)
            remY -= Int(stepY)
            remW -= Int(stepW)
            remH -= Int(stepH)
        }
        return packets
    }

    static func consumerReport(usage: UInt16) -> Data {
        let clamped = min(usage, 0x03FF)
        return Data([
            UInt8(clamped & 0xFF),
            UInt8((clamped >> 8) & 0xFF)
        ])
    }

    static func systemReport(usage: HIDSystemUsage) -> Data {
        Data([usage.rawValue & 0x07])
    }

    static func gamepadReport(_ state: HIDGamepadState = HIDGamepadState()) -> Data {
        let btnLow = UInt8(state.buttons.rawValue & 0xFF)
        let btnHigh = UInt8((state.buttons.rawValue >> 8) & 0xFF)
        let hatByte = state.hat.rawValue & 0x0F
        let lx = UInt8(bitPattern: clampToHIDSignedByte(Int(state.leftX)))
        let ly = UInt8(bitPattern: clampToHIDSignedByte(Int(state.leftY)))
        let rx = UInt8(bitPattern: clampToHIDSignedByte(Int(state.rightX)))
        let ry = UInt8(bitPattern: clampToHIDSignedByte(Int(state.rightY)))
        return Data([btnLow, btnHigh, hatByte, lx, ly, rx, ry])
    }

    static func parseLEDOutput(_ data: Data) -> HIDLEDState {
        guard let first = data.first else { return [] }
        return HIDLEDState(rawValue: first)
    }

    static func clampToHIDSignedByte(_ value: Int) -> Int8 {
        Int8(clamping: min(127, max(-127, value)))
    }
}
