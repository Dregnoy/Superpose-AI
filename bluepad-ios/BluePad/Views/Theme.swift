import SwiftUI

enum BluePadTheme {
    static let bgPrimary    = Color(red: 0.043, green: 0.055, blue: 0.102) // #0B0E1A
    static let bgCard       = Color(red: 0.078, green: 0.102, blue: 0.176) // #141A2D
    static let bgElevated   = Color(red: 0.114, green: 0.149, blue: 0.247) // #1D263F
    static let bgKeycap     = Color(red: 0.133, green: 0.173, blue: 0.278) // #222C47

    static let accentBlue   = Color(red: 0.220, green: 0.560, blue: 0.980)
    static let accentCyan   = Color(red: 0.220, green: 0.741, blue: 0.973) // #38BDF8
    static let accentMint   = Color(red: 0.204, green: 0.827, blue: 0.600) // #34D399
    static let accentAmber  = Color(red: 0.984, green: 0.749, blue: 0.141) // #FBBF24
    static let accentRose   = Color(red: 0.984, green: 0.443, blue: 0.522) // #FB7185
    static let accentViolet = Color(red: 0.655, green: 0.545, blue: 0.980) // #A78BFA

    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.66)
    static let borderSubtle  = Color.white.opacity(0.10)
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        if cleaned.count == 6 {
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        } else {
            (r, g, b) = (56, 189, 248)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BluePadTheme.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(BluePadTheme.borderSubtle, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 14) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

struct KeycapButtonStyle: ButtonStyle {
    var fill: Color = BluePadTheme.bgKeycap
    var border: Color = BluePadTheme.borderSubtle
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? fill.opacity(0.65) : fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(configuration.isPressed ? BluePadTheme.accentCyan.opacity(0.7) : border, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ToastBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(BluePadTheme.accentCyan)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(BluePadTheme.bgElevated.opacity(0.96))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(BluePadTheme.accentCyan.opacity(0.45), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        .padding(.horizontal, 20)
    }
}
