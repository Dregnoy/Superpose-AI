import SwiftUI

extension Color {
    static let npBg = Color(red: 11 / 255, green: 16 / 255, blue: 27 / 255)
    static let npSurface = Color(red: 18 / 255, green: 26 / 255, blue: 42 / 255)
    static let npSurfaceSoft = Color(red: 23 / 255, green: 33 / 255, blue: 54 / 255)
    static let npBorder = Color.white.opacity(0.11)
    static let npMuted = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    static let npGreen = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
    static let npAmber = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
    static let npRed = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    static let npBlue = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)
    static let npPurple = Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255)
}

struct NetPulseCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.npSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.npBorder, lineWidth: 1)
            )
    }
}

extension View {
    func npCard() -> some View {
        modifier(NetPulseCardModifier())
    }
}

enum PillTone {
    case safe
    case warn
    case bad
    case muted

    var fg: Color {
        switch self {
        case .safe: return Color(red: 110 / 255, green: 231 / 255, blue: 183 / 255)
        case .warn: return Color(red: 252 / 255, green: 211 / 255, blue: 77 / 255)
        case .bad: return Color(red: 252 / 255, green: 165 / 255, blue: 165 / 255)
        case .muted: return Color.npMuted
        }
    }

    var bg: Color {
        switch self {
        case .safe: return Color.npGreen.opacity(0.16)
        case .warn: return Color.npAmber.opacity(0.18)
        case .bad: return Color.npRed.opacity(0.18)
        case .muted: return Color.npMuted.opacity(0.14)
        }
    }
}

struct StatusPill: View {
    let text: String
    let tone: PillTone

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tone.fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tone.bg)
            .clipShape(Capsule())
    }
}
