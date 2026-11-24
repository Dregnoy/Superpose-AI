import Foundation

enum JigglerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case microMouse
    case shiftPulse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microMouse: return "Mikro Fare (±1px)"
        case .shiftPulse: return "Shift Darbesi"
        }
    }
}

struct BluePadSettings: Codable, Equatable, Sendable {
    var advertisedName: String
    var keyboardLayout: KeyboardLayoutKind
    var hostOS: HostOSProfile
    var pointerSensitivity: Double
    var pointerAcceleration: Bool
    var scrollSensitivity: Double
    var naturalScrolling: Bool
    var tapToClick: Bool
    var hapticsEnabled: Bool
    var typingDelayMs: Int
    var airMouseSensitivity: Double
    var jigglerIntervalSeconds: Int
    var jigglerMode: JigglerMode
    var scannerAutoEnter: Bool

    static let `default` = BluePadSettings(
        advertisedName: "BluePad",
        keyboardLayout: .turkishQ,
        hostOS: .windows,
        pointerSensitivity: 1.35,
        pointerAcceleration: true,
        scrollSensitivity: 1.0,
        naturalScrolling: true,
        tapToClick: true,
        hapticsEnabled: true,
        typingDelayMs: 18,
        airMouseSensitivity: 1.2,
        jigglerIntervalSeconds: 45,
        jigglerMode: .microMouse,
        scannerAutoEnter: true
    )

    mutating func clampToValidRanges() {
        let trimmed = advertisedName.trimmingCharacters(in: .whitespacesAndNewlines)
        advertisedName = trimmed.isEmpty ? "BluePad" : String(trimmed.prefix(22))
        pointerSensitivity = min(3.5, max(0.3, pointerSensitivity))
        scrollSensitivity = min(3.0, max(0.3, scrollSensitivity))
        typingDelayMs = min(80, max(5, typingDelayMs))
        airMouseSensitivity = min(3.0, max(0.4, airMouseSensitivity))
        jigglerIntervalSeconds = min(300, max(10, jigglerIntervalSeconds))
    }
}

enum MacroCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case general
    case media
    case coding
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "Sistem"
        case .media: return "Medya"
        case .coding: return "Geliştirici"
        case .custom: return "Özel"
        }
    }
}

enum MacroAction: Codable, Equatable, Hashable, Sendable {
    case keyCombo(keyCode: UInt8, modifiersRaw: UInt8)
    case typeText(text: String, appendEnter: Bool)
    case consumerKey(usageRaw: UInt16)
    case systemKey(usageRaw: UInt8)

    var summaryLabel: String {
        switch self {
        case .keyCombo(let keyCode, let modifiersRaw):
            let mods = HIDModifier(rawValue: modifiersRaw).displayTokens
            let keyName = HIDKeyCode(rawValue: keyCode)?.displayName ?? String(format: "0x%02X", keyCode)
            return (mods + [keyName]).joined(separator: " + ")
        case .typeText(let text, let appendEnter):
            let preview = text.count > 18 ? String(text.prefix(18)) + "…" : text
            return appendEnter ? "\"\(preview)\" + ⏎" : "\"\(preview)\""
        case .consumerKey(let usageRaw):
            return HIDConsumerUsage(rawValue: usageRaw)?.displayName ?? String(format: "Medya 0x%04X", usageRaw)
        case .systemKey(let usageRaw):
            let sys = HIDSystemUsage(rawValue: usageRaw)
            if sys.contains(.sleep) { return "Sistem Uyku" }
            if sys.contains(.powerDown) { return "Sistem Güç" }
            if sys.contains(.wakeUp) { return "Sistemi Uyandır" }
            return "Sistem Tuşu"
        }
    }
}

struct CustomMacro: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String
    var sfSymbol: String
    var accentHex: String
    var category: MacroCategory
    var action: MacroAction

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        sfSymbol: String,
        accentHex: String,
        category: MacroCategory,
        action: MacroAction
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.sfSymbol = sfSymbol
        self.accentHex = accentHex
        self.category = category
        self.action = action
    }

    static let defaultPresets: [CustomMacro] = [
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            title: "Ekranı Kilitle",
            subtitle: "Win + L",
            sfSymbol: "lock.fill",
            accentHex: "#38BDF8",
            category: .general,
            action: .keyCombo(keyCode: HIDKeyCode.l.rawValue, modifiersRaw: HIDModifier.leftGUI.rawValue)
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
            title: "Masaüstü Göster",
            subtitle: "Win + D",
            sfSymbol: "macwindow.on.rectangle",
            accentHex: "#60A5FA",
            category: .general,
            action: .keyCombo(keyCode: HIDKeyCode.d.rawValue, modifiersRaw: HIDModifier.leftGUI.rawValue)
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!,
            title: "Görev Yöneticisi",
            subtitle: "Ctrl + Shift + Esc",
            sfSymbol: "cpu.fill",
            accentHex: "#F59E0B",
            category: .general,
            action: .keyCombo(
                keyCode: HIDKeyCode.escape.rawValue,
                modifiersRaw: HIDModifier([.leftControl, .leftShift]).rawValue
            )
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000004")!,
            title: "Ekran Görüntüsü",
            subtitle: "Win + Shift + S",
            sfSymbol: "camera.viewfinder",
            accentHex: "#A78BFA",
            category: .general,
            action: .keyCombo(
                keyCode: HIDKeyCode.s.rawValue,
                modifiersRaw: HIDModifier([.leftGUI, .leftShift]).rawValue
            )
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000005")!,
            title: "Sekme Kapat",
            subtitle: "Ctrl + W",
            sfSymbol: "xmark.square.fill",
            accentHex: "#FB7185",
            category: .coding,
            action: .keyCombo(keyCode: HIDKeyCode.w.rawValue, modifiersRaw: HIDModifier.leftControl.rawValue)
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000006")!,
            title: "Yenile",
            subtitle: "F5",
            sfSymbol: "arrow.clockwise",
            accentHex: "#34D399",
            category: .coding,
            action: .keyCombo(keyCode: HIDKeyCode.f5.rawValue, modifiersRaw: 0)
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000007")!,
            title: "Tam Ekran",
            subtitle: "F11",
            sfSymbol: "arrow.up.left.and.arrow.down.right",
            accentHex: "#2DD4BF",
            category: .media,
            action: .keyCombo(keyCode: HIDKeyCode.f11.rawValue, modifiersRaw: 0)
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000008")!,
            title: "Sesi Kapat",
            subtitle: "Sessiz",
            sfSymbol: "speaker.slash.fill",
            accentHex: "#F43F5E",
            category: .media,
            action: .consumerKey(usageRaw: HIDConsumerUsage.mute.rawValue)
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000009")!,
            title: "Oynat / Duraklat",
            subtitle: "Medya",
            sfSymbol: "playpause.fill",
            accentHex: "#38BDF8",
            category: .media,
            action: .consumerKey(usageRaw: HIDConsumerUsage.playPause.rawValue)
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000010")!,
            title: "Kopyala",
            subtitle: "Ctrl + C",
            sfSymbol: "doc.on.doc.fill",
            accentHex: "#818CF8",
            category: .coding,
            action: .keyCombo(keyCode: HIDKeyCode.c.rawValue, modifiersRaw: HIDModifier.leftControl.rawValue)
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000011")!,
            title: "Yapıştır",
            subtitle: "Ctrl + V",
            sfSymbol: "doc.on.clipboard.fill",
            accentHex: "#34D399",
            category: .coding,
            action: .keyCombo(keyCode: HIDKeyCode.v.rawValue, modifiersRaw: HIDModifier.leftControl.rawValue)
        ),
        CustomMacro(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000012")!,
            title: "Geri Al",
            subtitle: "Ctrl + Z",
            sfSymbol: "arrow.uturn.backward",
            accentHex: "#FBBF24",
            category: .coding,
            action: .keyCombo(keyCode: HIDKeyCode.z.rawValue, modifiersRaw: HIDModifier.leftControl.rawValue)
        )
    ]
}
