import Foundation

/// USB HID Keyboard modifier bitmask (Report ID 1, Byte 0).
struct HIDModifier: OptionSet, Sendable, Hashable, Codable {
    let rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    static let leftControl  = HIDModifier(rawValue: 1 << 0)
    static let leftShift    = HIDModifier(rawValue: 1 << 1)
    static let leftAlt      = HIDModifier(rawValue: 1 << 2)
    static let leftGUI      = HIDModifier(rawValue: 1 << 3)
    static let rightControl = HIDModifier(rawValue: 1 << 4)
    static let rightShift   = HIDModifier(rawValue: 1 << 5)
    static let rightAlt     = HIDModifier(rawValue: 1 << 6) // AltGr on European/TR layouts
    static let rightGUI     = HIDModifier(rawValue: 1 << 7)

    var displayTokens: [String] {
        var tokens: [String] = []
        if contains(.leftControl) || contains(.rightControl) { tokens.append("Ctrl") }
        if contains(.leftShift) || contains(.rightShift) { tokens.append("Shift") }
        if contains(.leftAlt) { tokens.append("Alt") }
        if contains(.rightAlt) { tokens.append("AltGr") }
        if contains(.leftGUI) || contains(.rightGUI) { tokens.append("Win/⌘") }
        return tokens
    }
}

/// USB HID Mouse button bitmask (Report ID 2, Byte 0, bits 0...4).
struct HIDMouseButton: OptionSet, Sendable, Hashable, Codable {
    let rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue & 0x1F
    }

    static let left    = HIDMouseButton(rawValue: 1 << 0)
    static let right   = HIDMouseButton(rawValue: 1 << 1)
    static let middle  = HIDMouseButton(rawValue: 1 << 2)
    static let back    = HIDMouseButton(rawValue: 1 << 3)
    static let forward = HIDMouseButton(rawValue: 1 << 4)
}

/// Host-to-peripheral keyboard LED output report state (Report ID 1 Output, Byte 0).
struct HIDLEDState: OptionSet, Sendable, Hashable {
    let rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue & 0x1F
    }

    static let numLock    = HIDLEDState(rawValue: 1 << 0)
    static let capsLock   = HIDLEDState(rawValue: 1 << 1)
    static let scrollLock = HIDLEDState(rawValue: 1 << 2)
    static let compose    = HIDLEDState(rawValue: 1 << 3)
    static let kana       = HIDLEDState(rawValue: 1 << 4)
}

/// USB HID Usage Page 0x07 (Keyboard/Keypad) scan codes.
enum HIDKeyCode: UInt8, Sendable, CaseIterable, Codable {
    case none = 0x00

    case a = 0x04, b = 0x05, c = 0x06, d = 0x07
    case e = 0x08, f = 0x09, g = 0x0A, h = 0x0B
    case i = 0x0C, j = 0x0D, k = 0x0E, l = 0x0F
    case m = 0x10, n = 0x11, o = 0x12, p = 0x13
    case q = 0x14, r = 0x15, s = 0x16, t = 0x17
    case u = 0x18, v = 0x19, w = 0x1A, x = 0x1B
    case y = 0x1C, z = 0x1D

    case digit1 = 0x1E, digit2 = 0x1F, digit3 = 0x20, digit4 = 0x21
    case digit5 = 0x22, digit6 = 0x23, digit7 = 0x24, digit8 = 0x25
    case digit9 = 0x26, digit0 = 0x27

    case enter = 0x28
    case escape = 0x29
    case backspace = 0x2A
    case tab = 0x2B
    case space = 0x2C
    case minus = 0x2D
    case equal = 0x2E
    case leftBracket = 0x2F
    case rightBracket = 0x30
    case backslash = 0x31
    case nonUSHash = 0x32
    case semicolon = 0x33
    case apostrophe = 0x34
    case grave = 0x35
    case comma = 0x36
    case period = 0x37
    case slash = 0x38
    case capsLock = 0x39

    case f1 = 0x3A, f2 = 0x3B, f3 = 0x3C, f4 = 0x3D
    case f5 = 0x3E, f6 = 0x3F, f7 = 0x40, f8 = 0x41
    case f9 = 0x42, f10 = 0x43, f11 = 0x44, f12 = 0x45

    case printScreen = 0x46
    case scrollLock = 0x47
    case pause = 0x48
    case insert = 0x49
    case home = 0x4A
    case pageUp = 0x4B
    case deleteForward = 0x4C
    case end = 0x4D
    case pageDown = 0x4E

    case rightArrow = 0x4F
    case leftArrow = 0x50
    case downArrow = 0x51
    case upArrow = 0x52

    case numLock = 0x53
    case kpDivide = 0x54
    case kpMultiply = 0x55
    case kpMinus = 0x56
    case kpPlus = 0x57
    case kpEnter = 0x58
    case kp1 = 0x59, kp2 = 0x5A, kp3 = 0x5B, kp4 = 0x5C, kp5 = 0x5D
    case kp6 = 0x5E, kp7 = 0x5F, kp8 = 0x60, kp9 = 0x61, kp0 = 0x62
    case kpPeriod = 0x63
    case nonUSBackslash = 0x64
    case application = 0x65

    var displayName: String {
        switch self {
        case .none: return "Yok"
        case .enter: return "Enter"
        case .escape: return "Esc"
        case .backspace: return "Backspace"
        case .tab: return "Tab"
        case .space: return "Space"
        case .deleteForward: return "Delete"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        case .insert: return "Insert"
        case .printScreen: return "PrtSc"
        case .pause: return "Pause"
        case .capsLock: return "CapsLock"
        case .numLock: return "NumLock"
        case .scrollLock: return "ScrollLock"
        case .upArrow: return "Yukarı Ok"
        case .downArrow: return "Aşağı Ok"
        case .leftArrow: return "Sol Ok"
        case .rightArrow: return "Sağ Ok"
        case .application: return "Menü"
        default:
            return String(describing: self).uppercased()
        }
    }
}

/// USB HID Usage Page 0x0C (Consumer Control) usages (Report ID 3, 2-byte LE).
enum HIDConsumerUsage: UInt16, Sendable, CaseIterable, Codable {
    case none = 0x0000
    case power = 0x0030
    case menu = 0x0040
    case menuPick = 0x0041
    case menuUp = 0x0042
    case menuDown = 0x0043
    case menuLeft = 0x0044
    case menuRight = 0x0045
    case menuEscape = 0x0046

    case brightnessIncrement = 0x006F
    case brightnessDecrement = 0x0070

    case fastForward = 0x00B3
    case rewind = 0x00B4
    case scanNextTrack = 0x00B5
    case scanPreviousTrack = 0x00B6
    case stop = 0x00B7
    case eject = 0x00B8
    case playPause = 0x00CD

    case mute = 0x00E2
    case volumeIncrement = 0x00E9
    case volumeDecrement = 0x00EA

    case alCalculator = 0x0192
    case alFileBrowser = 0x0194
    case acSearch = 0x0221
    case acHome = 0x0223
    case acBack = 0x0224
    case acForward = 0x0225
    case acRefresh = 0x0227

    var displayName: String {
        switch self {
        case .none: return "Yok"
        case .power: return "Güç"
        case .menu: return "Menü"
        case .menuPick: return "Tamam / Seç"
        case .menuUp: return "Menü Yukarı"
        case .menuDown: return "Menü Aşağı"
        case .menuLeft: return "Menü Sol"
        case .menuRight: return "Menü Sağ"
        case .menuEscape: return "Menü Çıkış"
        case .brightnessIncrement: return "Parlaklık Artır"
        case .brightnessDecrement: return "Parlaklık Azalt"
        case .fastForward: return "İleri Sar"
        case .rewind: return "Geri Sar"
        case .scanNextTrack: return "Sonraki Parça"
        case .scanPreviousTrack: return "Önceki Parça"
        case .stop: return "Durdur"
        case .eject: return "Çıkar"
        case .playPause: return "Oynat / Duraklat"
        case .mute: return "Sesi Kapat"
        case .volumeIncrement: return "Sesi Aç"
        case .volumeDecrement: return "Sesi Kıs"
        case .alCalculator: return "Hesap Makinesi"
        case .alFileBrowser: return "Dosya Gezgini"
        case .acSearch: return "Ara"
        case .acHome: return "Ana Sayfa"
        case .acBack: return "Geri"
        case .acForward: return "İleri"
        case .acRefresh: return "Yenile"
        }
    }
}

/// Generic Desktop System Control usage bits (Report ID 4, 1 byte).
struct HIDSystemUsage: OptionSet, Sendable, Hashable, Codable {
    let rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue & 0x07
    }

    static let powerDown = HIDSystemUsage(rawValue: 1 << 0)
    static let sleep     = HIDSystemUsage(rawValue: 1 << 1)
    static let wakeUp    = HIDSystemUsage(rawValue: 1 << 2)
}

/// HOGP Protocol Mode characteristic (0x2A4E) state.
enum HIDProtocolMode: UInt8, Sendable {
    case boot = 0x00
    case report = 0x01

    var displayName: String {
        switch self {
        case .boot: return "Boot Modu (0x00)"
        case .report: return "Rapor Modu (0x01)"
        }
    }
}

/// Host operating system profile for adaptive keyboard shortcuts.
enum HostOSProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case windows
    case macOS
    case linux
    case androidTV
    case iPadOS

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .windows: return "Windows"
        case .macOS: return "macOS"
        case .linux: return "Linux / SteamOS"
        case .androidTV: return "Android / TV"
        case .iPadOS: return "iPadOS / iOS"
        }
    }

    var shortLabel: String {
        switch self {
        case .windows: return "Win"
        case .macOS: return "Mac"
        case .linux: return "Linux"
        case .androidTV: return "TV"
        case .iPadOS: return "iPad"
        }
    }

    var sfSymbol: String {
        switch self {
        case .windows: return "desktopcomputer"
        case .macOS: return "laptopcomputer"
        case .linux: return "terminal.fill"
        case .androidTV: return "tv.fill"
        case .iPadOS: return "ipad"
        }
    }

    /// Primary command modifier (`Cmd` on Apple platforms, `Ctrl` elsewhere).
    var primaryModifier: HIDModifier {
        switch self {
        case .macOS, .iPadOS:
            return .leftGUI
        case .windows, .linux, .androidTV:
            return .leftControl
        }
    }

    var primaryModifierLabel: String {
        switch self {
        case .macOS, .iPadOS: return "⌘"
        case .windows, .linux, .androidTV: return "Ctrl"
        }
    }

    var lockScreenCombo: (keyCode: UInt8, modifiers: HIDModifier) {
        switch self {
        case .macOS:
            return (HIDKeyCode.q.rawValue, [.leftControl, .leftGUI])
        case .iPadOS:
            return (HIDKeyCode.h.rawValue, .leftGUI)
        case .windows, .linux:
            return (HIDKeyCode.l.rawValue, .leftGUI)
        case .androidTV:
            return (HIDKeyCode.l.rawValue, .leftGUI)
        }
    }

    var taskSwitcherCombo: (keyCode: UInt8, modifiers: HIDModifier) {
        switch self {
        case .macOS, .iPadOS:
            return (HIDKeyCode.tab.rawValue, .leftGUI)
        case .windows, .linux, .androidTV:
            return (HIDKeyCode.tab.rawValue, .leftAlt)
        }
    }

    var screenshotCombo: (keyCode: UInt8, modifiers: HIDModifier) {
        switch self {
        case .macOS, .iPadOS:
            return (HIDKeyCode.digit4.rawValue, [.leftGUI, .leftShift])
        case .windows:
            return (HIDKeyCode.s.rawValue, [.leftGUI, .leftShift])
        case .linux, .androidTV:
            return (HIDKeyCode.printScreen.rawValue, [])
        }
    }

    var showDesktopCombo: (keyCode: UInt8, modifiers: HIDModifier) {
        switch self {
        case .macOS:
            return (HIDKeyCode.f11.rawValue, [])
        case .iPadOS:
            return (HIDKeyCode.h.rawValue, .leftGUI)
        case .windows, .linux, .androidTV:
            return (HIDKeyCode.d.rawValue, .leftGUI)
        }
    }

    var taskManagerCombo: (keyCode: UInt8, modifiers: HIDModifier) {
        switch self {
        case .macOS:
            return (HIDKeyCode.escape.rawValue, [.leftGUI, .leftAlt])
        case .iPadOS:
            return (HIDKeyCode.tab.rawValue, .leftGUI)
        case .windows, .linux, .androidTV:
            return (HIDKeyCode.escape.rawValue, [.leftControl, .leftShift])
        }
    }
}

/// CoreBluetooth peripheral connection & advertising state.
enum BLEConnectionState: Equatable, Sendable {
    case unknown
    case poweredOff
    case unauthorized
    case unsupported
    case initializing
    case advertising
    case stopped
    case failed(String)
    case connected(centralCount: Int)

    var statusText: String {
        switch self {
        case .unknown:
            return "Hazırlanıyor..."
        case .poweredOff:
            return "Bluetooth Kapalı"
        case .unauthorized:
            return "Bluetooth İzni Yok"
        case .unsupported:
            return "Simülatör / Desteklenmiyor"
        case .initializing:
            return "GATT Kuruluyor..."
        case .advertising:
            return "Eşleştirmeye Hazır"
        case .stopped:
            return "Yayın Durduruldu"
        case .failed(let reason):
            return "Hata: \(reason)"
        case .connected(let count):
            return count == 1 ? "Bağlı (1 cihaz)" : "Bağlı (\(count) cihaz)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isActiveRadio: Bool {
        switch self {
        case .advertising, .connected:
            return true
        default:
            return false
        }
    }
}

/// Live GATT / HID diagnostic log entry.
struct HIDDiagnosticEvent: Identifiable, Sendable {
    enum Category: String, Sendable {
        case ble = "BLE"
        case gatt = "GATT"
        case tx = "TX"
        case rx = "RX"
        case error = "HATA"
    }

    let id: UUID
    let timestamp: Date
    let category: Category
    let message: String
    let hexPayload: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: Category,
        message: String,
        hexPayload: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
        self.hexPayload = hexPayload
    }
}
