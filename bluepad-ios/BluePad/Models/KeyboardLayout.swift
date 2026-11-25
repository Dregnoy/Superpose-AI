import Foundation

/// Supported target OS keyboard layouts for converting Unicode characters to physical USB HID scan codes.
enum KeyboardLayoutKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case turkishQ = "tr_Q"
    case turkishF = "tr_F"
    case usQWERTY = "en_US"
    case ukQWERTY = "en_GB"
    case germanQWERTZ = "de_DE"
    case frenchAZERTY = "fr_FR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turkishQ: return "Türkçe Q"
        case .turkishF: return "Türkçe F"
        case .usQWERTY: return "İngilizce (US)"
        case .ukQWERTY: return "İngilizce (UK)"
        case .germanQWERTZ: return "Almanca (QWERTZ)"
        case .frenchAZERTY: return "Fransızca (AZERTY)"
        }
    }

    var shortCode: String {
        switch self {
        case .turkishQ: return "TR-Q"
        case .turkishF: return "TR-F"
        case .usQWERTY: return "US"
        case .ukQWERTY: return "UK"
        case .germanQWERTZ: return "DE"
        case .frenchAZERTY: return "FR"
        }
    }
}

/// Physical USB HID keystroke pair (Usage ID + Modifier bitmask).
struct KeyStroke: Equatable, Sendable {
    let keyCode: UInt8
    let modifiers: HIDModifier

    init(keyCode: UInt8, modifiers: HIDModifier = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(_ code: HIDKeyCode, modifiers: HIDModifier = []) {
        self.keyCode = code.rawValue
        self.modifiers = modifiers
    }
}

/// Pure, deterministic Unicode-to-USB-HID scan code mapper.
/// Locale-independent: every uppercase/lowercase pair (including `i`/`İ` and `ı`/`I`) is registered explicitly.
enum KeyboardLayoutEngine {

    static func keyStroke(for character: Character, layout: KeyboardLayoutKind) -> KeyStroke? {
        let normalized = String(character).precomposedStringWithCanonicalMapping
        guard let canonicalChar = normalized.first, normalized.count == 1 else {
            return nil
        }
        return table(for: layout)[canonicalChar]
    }

    static func keyStrokes(for text: String, layout: KeyboardLayoutKind) -> [KeyStroke] {
        let precomposed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping

        let map = table(for: layout)
        var result: [KeyStroke] = []
        result.reserveCapacity(precomposed.count)

        for ch in precomposed {
            if let stroke = map[ch] {
                result.append(stroke)
            }
        }
        return result
    }

    // MARK: - Lookup Tables

    private static func table(for layout: KeyboardLayoutKind) -> [Character: KeyStroke] {
        switch layout {
        case .turkishQ: return turkishQTable
        case .turkishF: return turkishFTable
        case .usQWERTY: return usQWERTYTable
        case .ukQWERTY: return ukQWERTYTable
        case .germanQWERTZ: return germanQWERTZTable
        case .frenchAZERTY: return frenchAZERTYTable
        }
    }

    private static func addPair(
        _ map: inout [Character: KeyStroke],
        lower: Character,
        upper: Character,
        code: HIDKeyCode
    ) {
        map[lower] = KeyStroke(code)
        map[upper] = KeyStroke(code, modifiers: .leftShift)
    }

    private static func addKey(
        _ map: inout [Character: KeyStroke],
        base: Character?,
        shifted: Character?,
        altGr: Character? = nil,
        code: HIDKeyCode
    ) {
        if let base { map[base] = KeyStroke(code) }
        if let shifted { map[shifted] = KeyStroke(code, modifiers: .leftShift) }
        if let altGr { map[altGr] = KeyStroke(code, modifiers: .rightAlt) }
    }

    private static func addCommonControls(_ map: inout [Character: KeyStroke]) {
        map[" "] = KeyStroke(.space)
        map["\n"] = KeyStroke(.enter)
        map["\t"] = KeyStroke(.tab)
    }

    private static func addStandardDigits(_ map: inout [Character: KeyStroke], shiftedSymbols: [Character]) {
        let digitCodes: [HIDKeyCode] = [
            .digit1, .digit2, .digit3, .digit4, .digit5,
            .digit6, .digit7, .digit8, .digit9, .digit0
        ]
        let digitChars: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        for idx in 0..<10 {
            let shifted: Character? = idx < shiftedSymbols.count ? shiftedSymbols[idx] : nil
            addKey(&map, base: digitChars[idx], shifted: shifted, code: digitCodes[idx])
        }
    }

    // MARK: Türkçe Q (TS-4405 / Windows & macOS TR-Q)
    private static let turkishQTable: [Character: KeyStroke] = {
        var map: [Character: KeyStroke] = [:]
        addCommonControls(&map)
        addStandardDigits(&map, shiftedSymbols: ["!", "'", "^", "+", "%", "&", "/", "(", ")", "="])

        // Standard Latin letters sharing US physical positions (except i / ı!)
        let sharedLetters: [(Character, Character, HIDKeyCode)] = [
            ("a", "A", .a), ("b", "B", .b), ("c", "C", .c), ("d", "D", .d),
            ("e", "E", .e), ("f", "F", .f), ("g", "G", .g), ("h", "H", .h),
            ("j", "J", .j), ("k", "K", .k), ("l", "L", .l), ("m", "M", .m),
            ("n", "N", .n), ("o", "O", .o), ("p", "P", .p), ("q", "Q", .q),
            ("r", "R", .r), ("s", "S", .s), ("t", "T", .t), ("u", "U", .u),
            ("v", "V", .v), ("w", "W", .w), ("x", "X", .x), ("y", "Y", .y),
            ("z", "Z", .z)
        ]
        for (l, u, c) in sharedLetters {
            addPair(&map, lower: l, upper: u, code: c)
        }

        // Turkish-specific letter positions on TR-Q
        addPair(&map, lower: "ı", upper: "I", code: .i)           // US I key -> ı / I
        addPair(&map, lower: "i", upper: "İ", code: .apostrophe)  // US ' key -> i / İ
        addPair(&map, lower: "ğ", upper: "Ğ", code: .leftBracket)
        addPair(&map, lower: "ü", upper: "Ü", code: .rightBracket)
        addPair(&map, lower: "ş", upper: "Ş", code: .semicolon)
        addPair(&map, lower: "ö", upper: "Ö", code: .comma)
        addPair(&map, lower: "ç", upper: "Ç", code: .period)

        // Punctuation on TR-Q
        addKey(&map, base: "\"", shifted: "é", code: .grave)
        addKey(&map, base: "*", shifted: "?", altGr: "\\", code: .minus)
        addKey(&map, base: "-", shifted: "_", altGr: "|", code: .equal)
        addKey(&map, base: ",", shifted: ";", altGr: "`", code: .backslash)
        addKey(&map, base: ".", shifted: ":", code: .slash)
        addKey(&map, base: "<", shifted: ">", code: .nonUSBackslash)

        // AltGr symbols on TR-Q
        map["@"] = KeyStroke(.q, modifiers: .rightAlt)
        map["€"] = KeyStroke(.e, modifiers: .rightAlt)
        map["₺"] = KeyStroke(.t, modifiers: .rightAlt)
        map["£"] = KeyStroke(.digit2, modifiers: .rightAlt)
        map["#"] = KeyStroke(.digit3, modifiers: .rightAlt)
        map["$"] = KeyStroke(.digit4, modifiers: .rightAlt)
        map["½"] = KeyStroke(.digit5, modifiers: .rightAlt)
        map["{"] = KeyStroke(.digit7, modifiers: .rightAlt)
        map["["] = KeyStroke(.digit8, modifiers: .rightAlt)
        map["]"] = KeyStroke(.digit9, modifiers: .rightAlt)
        map["}"] = KeyStroke(.digit0, modifiers: .rightAlt)
        map["~"] = KeyStroke(.rightBracket, modifiers: .rightAlt)
        return map
    }()

    // MARK: Türkçe F (TS-2117)
    private static let turkishFTable: [Character: KeyStroke] = {
        var map: [Character: KeyStroke] = [:]
        addCommonControls(&map)
        addStandardDigits(&map, shiftedSymbols: ["!", "\"", "^", "$", "%", "&", "'", "(", ")", "="])

        let fLetters: [(Character, Character, HIDKeyCode)] = [
            // Top row: F G Ğ I O D R N H P Q W X
            ("f", "F", .q), ("g", "G", .w), ("ğ", "Ğ", .e), ("ı", "I", .r),
            ("o", "O", .t), ("d", "D", .y), ("r", "R", .u), ("n", "N", .i),
            ("h", "H", .o), ("p", "P", .p), ("q", "Q", .leftBracket), ("w", "W", .rightBracket),
            ("x", "X", .backslash),
            // Home row: U İ E A Ü T K M L Y Ş
            ("u", "U", .a), ("i", "İ", .s), ("e", "E", .d), ("a", "A", .f),
            ("ü", "Ü", .g), ("t", "T", .h), ("k", "K", .j), ("m", "M", .k),
            ("l", "L", .l), ("y", "Y", .semicolon), ("ş", "Ş", .apostrophe),
            // Bottom row: J Ö V C Ç Z S B
            ("j", "J", .z), ("ö", "Ö", .x), ("v", "V", .c), ("c", "C", .v),
            ("ç", "Ç", .b), ("z", "Z", .n), ("s", "S", .m), ("b", "B", .comma)
        ]
        for (l, u, c) in fLetters {
            addPair(&map, lower: l, upper: u, code: c)
        }

        // Punctuation on TR-F
        addKey(&map, base: "+", shifted: "*", code: .grave)
        addKey(&map, base: "/", shifted: "?", altGr: "\\", code: .minus)
        addKey(&map, base: "-", shifted: "_", altGr: "|", code: .equal)
        addKey(&map, base: ".", shifted: ":", code: .period)
        addKey(&map, base: ",", shifted: ";", code: .slash)
        addKey(&map, base: "<", shifted: ">", code: .nonUSBackslash)

        // AltGr symbols on TR-F
        map["@"] = KeyStroke(.q, modifiers: .rightAlt)
        map["€"] = KeyStroke(.d, modifiers: .rightAlt)
        map["₺"] = KeyStroke(.h, modifiers: .rightAlt)
        map["£"] = KeyStroke(.digit2, modifiers: .rightAlt)
        map["#"] = KeyStroke(.digit3, modifiers: .rightAlt)
        map["{"] = KeyStroke(.digit7, modifiers: .rightAlt)
        map["["] = KeyStroke(.digit8, modifiers: .rightAlt)
        map["]"] = KeyStroke(.digit9, modifiers: .rightAlt)
        map["}"] = KeyStroke(.digit0, modifiers: .rightAlt)
        map["~"] = KeyStroke(.rightBracket, modifiers: .rightAlt)
        map["`"] = KeyStroke(.backslash, modifiers: .rightAlt)
        return map
    }()

    // MARK: US QWERTY
    private static let usQWERTYTable: [Character: KeyStroke] = {
        var map: [Character: KeyStroke] = [:]
        addCommonControls(&map)
        addStandardDigits(&map, shiftedSymbols: ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"])

        let letters: [(Character, Character, HIDKeyCode)] = [
            ("a", "A", .a), ("b", "B", .b), ("c", "C", .c), ("d", "D", .d),
            ("e", "E", .e), ("f", "F", .f), ("g", "G", .g), ("h", "H", .h),
            ("i", "I", .i), ("j", "J", .j), ("k", "K", .k), ("l", "L", .l),
            ("m", "M", .m), ("n", "N", .n), ("o", "O", .o), ("p", "P", .p),
            ("q", "Q", .q), ("r", "R", .r), ("s", "S", .s), ("t", "T", .t),
            ("u", "U", .u), ("v", "V", .v), ("w", "W", .w), ("x", "X", .x),
            ("y", "Y", .y), ("z", "Z", .z)
        ]
        for (l, u, c) in letters {
            addPair(&map, lower: l, upper: u, code: c)
        }

        addKey(&map, base: "-", shifted: "_", code: .minus)
        addKey(&map, base: "=", shifted: "+", code: .equal)
        addKey(&map, base: "[", shifted: "{", code: .leftBracket)
        addKey(&map, base: "]", shifted: "}", code: .rightBracket)
        addKey(&map, base: "\\", shifted: "|", code: .backslash)
        addKey(&map, base: ";", shifted: ":", code: .semicolon)
        addKey(&map, base: "'", shifted: "\"", code: .apostrophe)
        addKey(&map, base: "`", shifted: "~", code: .grave)
        addKey(&map, base: ",", shifted: "<", code: .comma)
        addKey(&map, base: ".", shifted: ">", code: .period)
        addKey(&map, base: "/", shifted: "?", code: .slash)
        return map
    }()

    // MARK: UK QWERTY
    private static let ukQWERTYTable: [Character: KeyStroke] = {
        var map = usQWERTYTable
        map["\""] = KeyStroke(.digit2, modifiers: .leftShift)
        map["£"]  = KeyStroke(.digit3, modifiers: .leftShift)
        map["@"]  = KeyStroke(.apostrophe, modifiers: .leftShift)
        map["'"]  = KeyStroke(.apostrophe)
        map["#"]  = KeyStroke(.nonUSHash)
        map["~"]  = KeyStroke(.nonUSHash, modifiers: .leftShift)
        map["\\"] = KeyStroke(.nonUSBackslash)
        map["|"]  = KeyStroke(.nonUSBackslash, modifiers: .leftShift)
        map["€"]  = KeyStroke(.digit4, modifiers: .rightAlt)
        return map
    }()

    // MARK: German QWERTZ
    private static let germanQWERTZTable: [Character: KeyStroke] = {
        var map = usQWERTYTable
        addPair(&map, lower: "z", upper: "Z", code: .y)
        addPair(&map, lower: "y", upper: "Y", code: .z)
        addStandardDigits(&map, shiftedSymbols: ["!", "\"", "§", "$", "%", "&", "/", "(", ")", "="])

        addPair(&map, lower: "ü", upper: "Ü", code: .leftBracket)
        addPair(&map, lower: "ö", upper: "Ö", code: .semicolon)
        addPair(&map, lower: "ä", upper: "Ä", code: .apostrophe)
        addKey(&map, base: "ß", shifted: "?", altGr: "\\", code: .minus)
        addKey(&map, base: "+", shifted: "*", altGr: "~", code: .rightBracket)
        addKey(&map, base: "#", shifted: "'", code: .backslash)
        addKey(&map, base: ",", shifted: ";", code: .comma)
        addKey(&map, base: ".", shifted: ":", code: .period)
        addKey(&map, base: "-", shifted: "_", code: .slash)
        addKey(&map, base: "<", shifted: ">", altGr: "|", code: .nonUSBackslash)
        addKey(&map, base: "^", shifted: "°", code: .grave)

        map["@"] = KeyStroke(.q, modifiers: .rightAlt)
        map["€"] = KeyStroke(.e, modifiers: .rightAlt)
        map["{"] = KeyStroke(.digit7, modifiers: .rightAlt)
        map["["] = KeyStroke(.digit8, modifiers: .rightAlt)
        map["]"] = KeyStroke(.digit9, modifiers: .rightAlt)
        map["}"] = KeyStroke(.digit0, modifiers: .rightAlt)
        return map
    }()

    // MARK: French AZERTY
    private static let frenchAZERTYTable: [Character: KeyStroke] = {
        var map: [Character: KeyStroke] = [:]
        addCommonControls(&map)

        let baseDigits: [Character] = ["&", "é", "\"", "'", "(", "-", "è", "_", "ç", "à"]
        let shiftDigits: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let digitCodes: [HIDKeyCode] = [
            .digit1, .digit2, .digit3, .digit4, .digit5,
            .digit6, .digit7, .digit8, .digit9, .digit0
        ]
        for idx in 0..<10 {
            addKey(&map, base: baseDigits[idx], shifted: shiftDigits[idx], code: digitCodes[idx])
        }

        let azertyLetters: [(Character, Character, HIDKeyCode)] = [
            ("a", "A", .q), ("z", "Z", .w), ("e", "E", .e), ("r", "R", .r),
            ("t", "T", .t), ("y", "Y", .y), ("u", "U", .u), ("i", "I", .i),
            ("o", "O", .o), ("p", "P", .p),
            ("q", "Q", .a), ("s", "S", .s), ("d", "D", .d), ("f", "F", .f),
            ("g", "G", .g), ("h", "H", .h), ("j", "J", .j), ("k", "K", .k),
            ("l", "L", .l), ("m", "M", .semicolon),
            ("w", "W", .z), ("x", "X", .x), ("c", "C", .c), ("v", "V", .v),
            ("b", "B", .b), ("n", "N", .n)
        ]
        for (l, u, c) in azertyLetters {
            addPair(&map, lower: l, upper: u, code: c)
        }

        addKey(&map, base: ")", shifted: "°", altGr: "]", code: .minus)
        addKey(&map, base: "=", shifted: "+", altGr: "}", code: .equal)
        addKey(&map, base: "$", shifted: "£", code: .rightBracket)
        addKey(&map, base: "ù", shifted: "%", code: .apostrophe)
        addKey(&map, base: "*", shifted: "µ", code: .backslash)
        addKey(&map, base: ",", shifted: "?", code: .m)
        addKey(&map, base: ";", shifted: ".", code: .comma)
        addKey(&map, base: ":", shifted: "/", code: .period)
        addKey(&map, base: "!", shifted: "§", code: .slash)
        addKey(&map, base: "<", shifted: ">", code: .nonUSBackslash)

        map["~"] = KeyStroke(.digit2, modifiers: .rightAlt)
        map["#"] = KeyStroke(.digit3, modifiers: .rightAlt)
        map["{"] = KeyStroke(.digit4, modifiers: .rightAlt)
        map["["] = KeyStroke(.digit5, modifiers: .rightAlt)
        map["|"] = KeyStroke(.digit6, modifiers: .rightAlt)
        map["`"] = KeyStroke(.digit7, modifiers: .rightAlt)
        map["\\"] = KeyStroke(.digit8, modifiers: .rightAlt)
        map["^"] = KeyStroke(.digit9, modifiers: .rightAlt)
        map["@"] = KeyStroke(.digit0, modifiers: .rightAlt)
        map["€"] = KeyStroke(.e, modifiers: .rightAlt)
        return map
    }()
}
