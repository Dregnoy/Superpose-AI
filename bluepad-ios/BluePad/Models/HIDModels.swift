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

/// Outbound BLE connection status for host devices discovered via CBCentralManager.
enum BLEHostLinkState: Equatable, Sendable {
    case discovered
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .discovered:
            return "Bulundu"
        case .connecting:
            return "Bağlanıyor..."
        case .connected:
            return "GATT Açık (HID Yok)"
        case .failed(let reason):
            return "Hata: \(reason)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}

/// Nearby BLE host device discovered by the iPhone scanner or already connected at OS level.
struct DiscoveredBLEHost: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var hasExplicitName: Bool
    var rssi: Int
    var isConnectable: Bool
    var isSystemConnected: Bool
    var manufacturerName: String?
    var linkState: BLEHostLinkState
    var lastSeen: Date

    init(
        id: UUID,
        name: String,
        hasExplicitName: Bool,
        rssi: Int,
        isConnectable: Bool,
        isSystemConnected: Bool,
        manufacturerName: String? = nil,
        linkState: BLEHostLinkState,
        lastSeen: Date
    ) {
        self.id = id
        self.name = name
        self.hasExplicitName = hasExplicitName
        self.rssi = rssi
        self.isConnectable = isConnectable
        self.isSystemConnected = isSystemConnected
        self.manufacturerName = manufacturerName
        self.linkState = linkState
        self.lastSeen = lastSeen
    }

    var proximityLabel: String {
        if rssi >= -55 { return "Çok Yakın" }
        if rssi >= -72 { return "Yakın" }
        if rssi >= -85 { return "Orta" }
        return "Uzak"
    }

    static func sortForDisplay(_ hosts: [DiscoveredBLEHost]) -> [DiscoveredBLEHost] {
        hosts.sorted { lhs, rhs in
            let lRank = sortRank(lhs)
            let rRank = sortRank(rhs)
            if lRank != rRank {
                return lRank < rRank
            }
            if lhs.rssi != rhs.rssi {
                return lhs.rssi > rhs.rssi
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func sortRank(_ host: DiscoveredBLEHost) -> Int {
        if host.linkState.isConnected { return 0 }
        if host.linkState.isConnecting { return 1 }
        if host.isSystemConnected { return 2 }
        if host.hasExplicitName { return 3 }
        return 4
    }
}

/// Live HOGP GATT service registration & advertising diagnostics.
struct HOGPServiceStatus: Equatable, Sendable {
    var batteryAdded: Bool = false
    var deviceInfoAdded: Bool = false
    var hidAdded: Bool = false
    var includedBatteryInHID: Bool = false
    var isAdvertising: Bool = false
    var advertisingMode: String = "Bekliyor"
    var lastError: String? = nil
}

/// USB HID Gamepad button bitmask (Report ID 5, 16-bit LE).
struct HIDGamepadButton: OptionSet, Sendable, Hashable, Codable {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    static let a      = HIDGamepadButton(rawValue: 1 << 0)
    static let b      = HIDGamepadButton(rawValue: 1 << 1)
    static let x      = HIDGamepadButton(rawValue: 1 << 2)
    static let y      = HIDGamepadButton(rawValue: 1 << 3)
    static let l1     = HIDGamepadButton(rawValue: 1 << 4)
    static let r1     = HIDGamepadButton(rawValue: 1 << 5)
    static let l2     = HIDGamepadButton(rawValue: 1 << 6)
    static let r2     = HIDGamepadButton(rawValue: 1 << 7)
    static let select = HIDGamepadButton(rawValue: 1 << 8)
    static let start  = HIDGamepadButton(rawValue: 1 << 9)
    static let l3     = HIDGamepadButton(rawValue: 1 << 10)
    static let r3     = HIDGamepadButton(rawValue: 1 << 11)
    static let home   = HIDGamepadButton(rawValue: 1 << 12)
}

/// 8-way D-Pad Hat Switch direction + centered null state (0x08).
enum HIDGamepadHat: UInt8, Sendable, Hashable, Codable {
    case up        = 0
    case upRight   = 1
    case right     = 2
    case downRight = 3
    case down      = 4
    case downLeft  = 5
    case left      = 6
    case upLeft    = 7
    case center    = 8
}

/// Complete live Gamepad input state (Report ID 5, 7 bytes).
struct HIDGamepadState: Equatable, Sendable {
    var buttons: HIDGamepadButton = []
    var hat: HIDGamepadHat = .center
    var leftX: Int8 = 0
    var leftY: Int8 = 0
    var rightX: Int8 = 0
    var rightY: Int8 = 0
}

/// Bluetooth SIG assigned Company Identifier decoder for BLE Manufacturer Specific Data.
enum BLECompanyDirectory {
    static func companyName(from manufacturerData: Data) -> String? {
        guard manufacturerData.count >= 2 else { return nil }
        let start = manufacturerData.startIndex
        let companyID = UInt16(manufacturerData[start]) | (UInt16(manufacturerData[start + 1]) << 8)
        switch companyID {
        case 0x004C: return "Apple"
        case 0x0006: return "Microsoft / Windows"
        case 0x0075: return "Samsung"
        case 0x00E0: return "Google / Android"
        case 0x00C4: return "LG"
        case 0x012D: return "Sony"
        case 0x038F: return "Xiaomi"
        case 0x027D: return "Huawei"
        case 0x0002: return "Intel"
        case 0x005D: return "Realtek"
        case 0x000A: return "Qualcomm"
        case 0x000F: return "Broadcom"
        case 0x0059: return "Nordic"
        case 0x00DA: return "Logitech"
        case 0x0553: return "Nintendo"
        case 0x009E: return "Bose"
        case 0x0057: return "Harman / JBL"
        case 0x0046: return "MediaTek"
        case 0x0171: return "Amazon"
        case 0x0087: return "Garmin"
        case 0x0157: return "Amazfit"
        default: return nil
        }
    }
}

/// Zero-cloud LAN Wi-Fi receiver discovered via local UDP beacon.
struct WiFiHostEndpoint: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var name: String
    var host: String
    var port: UInt16
    var osName: String
    var lastSeen: Date

    init(name: String, host: String, port: UInt16, osName: String = "Windows", lastSeen: Date = Date()) {
        self.id = "\(host):\(port)"
        self.name = name
        self.host = host
        self.port = port
        self.osName = osName
        self.lastSeen = lastSeen
    }
}

/// Connection status of the local Wi-Fi LAN TCP link.
enum WiFiConnectionState: Equatable, Sendable {
    case disconnected
    case connecting(String)
    case connected(hostName: String, address: String)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .disconnected:
            return "Bağlı Değil"
        case .connecting(let target):
            return "Bağlanıyor: \(target)"
        case .connected(let hostName, _):
            return "Wi-Fi Bağlı · \(hostName)"
        case .failed(let reason):
            return "Wi-Fi Hatası: \(reason)"
        }
    }
}

/// Enforces single-target exclusivity across Bluetooth HID, Wi-Fi PC, and Smart TV transports.
enum ActiveConnectionTarget: Equatable, Sendable {
    case none
    case bluetooth(hostName: String)
    case wifiPC(hostName: String)
    case smartTV(name: String, kind: SmartTVKind)

    var isActive: Bool {
        if case .none = self { return false }
        return true
    }

    var isBluetooth: Bool {
        if case .bluetooth = self { return true }
        return false
    }

    var isWiFiPC: Bool {
        if case .wifiPC = self { return true }
        return false
    }

    var isSmartTV: Bool {
        if case .smartTV = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .none:
            return "Bağlı Değil"
        case .bluetooth(let hostName):
            return hostName.isEmpty ? "Bluetooth Cihazı" : "Bluetooth · \(hostName)"
        case .wifiPC(let hostName):
            return hostName.isEmpty ? "Wi-Fi PC" : "Wi-Fi · \(hostName)"
        case .smartTV(let name, let kind):
            let clean = name.isEmpty ? kind.shortLabel : name
            return "\(kind.shortLabel) · \(clean)"
        }
    }

    var supportsMouseCursor: Bool {
        switch self {
        case .none:
            return false
        case .bluetooth, .wifiPC:
            return true
        case .smartTV(_, let kind):
            return kind.supportsDirectPointer
        }
    }
}
