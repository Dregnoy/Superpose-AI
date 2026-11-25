import SwiftUI

struct GamepadView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Header bar with quick reset
            HStack {
                Label("Oyun Kolu (HID Report 5)", systemImage: "gamecontroller.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentCyan)
                Spacer()
                Button {
                    viewModel.resetGamepad()
                } label: {
                    Label("Sıfırla", systemImage: "arrow.counterclockwise")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BluePadTheme.accentRose)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(BluePadTheme.accentRose.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            .glassCard(cornerRadius: 14, padding: 10)

            // Shoulder + System Row (L2 L1 | Select Home Start | R1 R2)
            HStack(spacing: 8) {
                shoulderBtn("L2", button: .l2, accent: BluePadTheme.accentBlue)
                shoulderBtn("L1", button: .l1, accent: BluePadTheme.accentCyan)

                Spacer(minLength: 2)

                miniSystemBtn("SEL", button: .select)
                miniSystemBtn("HOME", button: .home)
                miniSystemBtn("STR", button: .start)

                Spacer(minLength: 2)

                shoulderBtn("R1", button: .r1, accent: BluePadTheme.accentCyan)
                shoulderBtn("R2", button: .r2, accent: BluePadTheme.accentBlue)
            }

            // Middle Row: 8-Way D-Pad + Diamond A/B/X/Y Buttons
            HStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text("D-PAD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BluePadTheme.textSecondary)

                    GamepadDPadControl(activeHat: viewModel.gamepadState.hat) { hat in
                        viewModel.setGamepadHat(hat)
                    }
                }
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 20, padding: 12)

                VStack(spacing: 6) {
                    Text("EYLEM TUŞLARI")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BluePadTheme.textSecondary)

                    VStack(spacing: 6) {
                        faceButton("Y", button: .y, color: BluePadTheme.accentAmber)
                        HStack(spacing: 28) {
                            faceButton("X", button: .x, color: BluePadTheme.accentBlue)
                            faceButton("B", button: .b, color: BluePadTheme.accentRose)
                        }
                        faceButton("A", button: .a, color: BluePadTheme.accentMint)
                    }
                    .frame(height: 152)
                }
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 20, padding: 12)
            }

            // Bottom Row: Dual Analog Thumbsticks + L3/R3
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack {
                        Text("SOL ANALOG")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BluePadTheme.textSecondary)
                        Spacer()
                        Text("\(viewModel.gamepadState.leftX),\(viewModel.gamepadState.leftY)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(BluePadTheme.accentCyan)
                    }

                    AnalogStickControl(accent: BluePadTheme.accentCyan) { x, y in
                        viewModel.setGamepadLeftStick(x: x, y: y)
                    }

                    HoldableGamepadButton(
                        title: "L3",
                        isActive: viewModel.gamepadState.buttons.contains(.l3),
                        accent: BluePadTheme.accentCyan,
                        height: 30
                    ) { pressed in
                        viewModel.setGamepadButton(.l3, pressed: pressed)
                    }
                }
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 20, padding: 12)

                VStack(spacing: 8) {
                    HStack {
                        Text("SAĞ ANALOG")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BluePadTheme.textSecondary)
                        Spacer()
                        Text("\(viewModel.gamepadState.rightX),\(viewModel.gamepadState.rightY)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(BluePadTheme.accentViolet)
                    }

                    AnalogStickControl(accent: BluePadTheme.accentViolet) { x, y in
                        viewModel.setGamepadRightStick(x: x, y: y)
                    }

                    HoldableGamepadButton(
                        title: "R3",
                        isActive: viewModel.gamepadState.buttons.contains(.r3),
                        accent: BluePadTheme.accentViolet,
                        height: 30
                    ) { pressed in
                        viewModel.setGamepadButton(.r3, pressed: pressed)
                    }
                }
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 20, padding: 12)
            }
        }
    }

    private func shoulderBtn(_ title: String, button: HIDGamepadButton, accent: Color) -> some View {
        HoldableGamepadButton(
            title: title,
            isActive: viewModel.gamepadState.buttons.contains(button),
            accent: accent,
            height: 40
        ) { pressed in
            viewModel.setGamepadButton(button, pressed: pressed)
        }
        .frame(width: 48)
    }

    private func miniSystemBtn(_ title: String, button: HIDGamepadButton) -> some View {
        HoldableGamepadButton(
            title: title,
            isActive: viewModel.gamepadState.buttons.contains(button),
            accent: BluePadTheme.accentMint,
            height: 34,
            fontSize: 10
        ) { pressed in
            viewModel.setGamepadButton(button, pressed: pressed)
        }
        .frame(width: 44)
    }

    private func faceButton(_ title: String, button: HIDGamepadButton, color: Color) -> some View {
        HoldableGamepadButton(
            title: title,
            isActive: viewModel.gamepadState.buttons.contains(button),
            accent: color,
            height: 46,
            isCircular: true,
            fontSize: 16
        ) { pressed in
            viewModel.setGamepadButton(button, pressed: pressed)
        }
        .frame(width: 46)
    }
}

private struct HoldableGamepadButton: View {
    let title: String
    let isActive: Bool
    let accent: Color
    var height: CGFloat = 42
    var isCircular: Bool = false
    var fontSize: CGFloat = 12
    let onPressChanged: (Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        let active = isActive || isPressed
        Text(title)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(active ? BluePadTheme.bgPrimary : BluePadTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if isCircular {
                    Circle()
                        .fill(active ? accent : BluePadTheme.bgKeycap)
                        .overlay(Circle().stroke(active ? accent : accent.opacity(0.45), lineWidth: 1.5))
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(active ? accent : BluePadTheme.bgKeycap)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(active ? accent : BluePadTheme.borderSubtle, lineWidth: 1)
                        )
                }
            }
            .scaleEffect(isPressed ? 0.93 : 1.0)
            .animation(.easeOut(duration: 0.06), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPressChanged(true)
                        }
                    }
                    .onEnded { _ in
                        if isPressed {
                            isPressed = false
                            onPressChanged(false)
                        }
                    }
            )
    }
}

private struct GamepadDPadControl: View {
    let activeHat: HIDGamepadHat
    let onHatChange: (HIDGamepadHat) -> Void

    private let size: CGFloat = 148

    var body: some View {
        ZStack {
            Circle()
                .fill(BluePadTheme.bgPrimary)
                .overlay(Circle().stroke(BluePadTheme.borderSubtle, lineWidth: 1.5))

            VStack(spacing: 4) {
                dpadArrow("chevron.up", active: isUpActive)
                HStack(spacing: 4) {
                    dpadArrow("chevron.left", active: isLeftActive)
                    Circle()
                        .fill(BluePadTheme.bgKeycap)
                        .frame(width: 28, height: 28)
                    dpadArrow("chevron.right", active: isRightActive)
                }
                dpadArrow("chevron.down", active: isDownActive)
            }
        }
        .frame(width: size, height: size)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onHatChange(hatFromPoint(value.location, size: size))
                }
                .onEnded { _ in
                    onHatChange(.center)
                }
        )
    }

    private var isUpActive: Bool {
        activeHat == .up || activeHat == .upLeft || activeHat == .upRight
    }

    private var isDownActive: Bool {
        activeHat == .down || activeHat == .downLeft || activeHat == .downRight
    }

    private var isLeftActive: Bool {
        activeHat == .left || activeHat == .upLeft || activeHat == .downLeft
    }

    private var isRightActive: Bool {
        activeHat == .right || activeHat == .upRight || activeHat == .downRight
    }

    private func dpadArrow(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(active ? BluePadTheme.bgPrimary : BluePadTheme.textPrimary)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? BluePadTheme.accentCyan : BluePadTheme.bgKeycap)
            )
    }

    private func hatFromPoint(_ pt: CGPoint, size: CGFloat) -> HIDGamepadHat {
        let dx = pt.x - size / 2
        let dy = pt.y - size / 2
        let dist = hypot(dx, dy)
        if dist < 14 { return .center }

        // Angle in degrees where 0 = Up, 90 = Right, 180 = Down, 270 = Left
        var deg = atan2(dx, -dy) * 180.0 / .pi
        if deg < 0 { deg += 360.0 }
        let sector = Int((deg + 22.5) / 45.0) % 8
        return HIDGamepadHat(rawValue: UInt8(sector)) ?? .center
    }
}

private struct AnalogStickControl: View {
    let accent: Color
    let onStickChange: (Int8, Int8) -> Void

    @State private var dragOffset: CGSize = .zero

    private let baseRadius: CGFloat = 56
    private let knobRadius: CGFloat = 23

    var body: some View {
        ZStack {
            Circle()
                .fill(BluePadTheme.bgPrimary)
                .overlay(Circle().stroke(BluePadTheme.borderSubtle, lineWidth: 1.5))

            Circle()
                .stroke(accent.opacity(0.22), lineWidth: 1)
                .frame(width: baseRadius, height: baseRadius)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: knobRadius * 2, height: knobRadius * 2)
                .shadow(color: accent.opacity(0.35), radius: 6)
                .offset(dragOffset)
        }
        .frame(width: baseRadius * 2, height: baseRadius * 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let maxTravel = baseRadius - knobRadius + 4
                    let dx = value.location.x - baseRadius
                    let dy = value.location.y - baseRadius
                    let dist = hypot(dx, dy)
                    let clampedDist = min(dist, maxTravel)
                    let nx = dist > 0 ? (dx / dist) * clampedDist : 0
                    let ny = dist > 0 ? (dy / dist) * clampedDist : 0
                    dragOffset = CGSize(width: nx, height: ny)

                    let outX = HIDReportBuilder.clampToHIDSignedByte(Int((nx / maxTravel * 127.0).rounded()))
                    let outY = HIDReportBuilder.clampToHIDSignedByte(Int((ny / maxTravel * 127.0).rounded()))
                    onStickChange(outX, outY)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                    onStickChange(0, 0)
                }
        )
    }
}
