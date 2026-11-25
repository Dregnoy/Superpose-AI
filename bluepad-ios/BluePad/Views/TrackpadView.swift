import SwiftUI
import UIKit

struct TrackpadView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showInlineKeyboard = false

    var body: some View {
        VStack(spacing: 12) {
            // Quick action strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickChip(
                        title: showInlineKeyboard ? "Klavyeyi Gizle" : "Canlı Klavye",
                        icon: "keyboard",
                        isActive: showInlineKeyboard
                    ) {
                        showInlineKeyboard.toggle()
                        viewModel.triggerHaptic(.light)
                    }

                    quickChip(
                        title: viewModel.isAirMouseActive ? "Hava Faresi Açık" : "Hava Faresi",
                        icon: "gyroscope",
                        isActive: viewModel.isAirMouseActive
                    ) {
                        viewModel.toggleAirMouse()
                    }

                    quickChip(title: "Panoyu Yapıştır", icon: "doc.on.clipboard") {
                        viewModel.pasteClipboard(appendEnter: false)
                    }

                    quickChip(title: "QR / Barkod", icon: "qrcode.viewfinder") {
                        viewModel.isScannerPresented = true
                    }

                    quickChip(
                        title: viewModel.isJigglerActive ? "Uyanık (\(viewModel.jigglerCountdownSeconds)s)" : "Uyanık Tut",
                        icon: "cup.and.saucer.fill",
                        isActive: viewModel.isJigglerActive
                    ) {
                        viewModel.toggleJiggler()
                    }

                    quickChip(
                        title: "Tam Ekran",
                        icon: "arrow.up.left.and.arrow.down.right"
                    ) {
                        viewModel.triggerHaptic(.light)
                        viewModel.isFullScreenTrackpad = true
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.top, 8)

            // Inline soft keyboard strip when active
            if showInlineKeyboard {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard.fill")
                        .foregroundStyle(BluePadTheme.accentCyan)
                    Text("Yazılan karakterler anında bağlı cihaza gönderilir")
                        .font(.caption)
                        .foregroundStyle(BluePadTheme.textSecondary)
                    Spacer()
                    LiveKeyInputRepresentable(
                        isActive: showInlineKeyboard,
                        onCharacter: { ch in
                            viewModel.sendTypedCharacter(ch)
                        },
                        onBackspace: {
                            viewModel.sendKey(.backspace)
                        },
                        onEnter: {
                            viewModel.sendKey(.enter)
                        }
                    )
                    .frame(width: 24, height: 24)
                    Button("Bitti") {
                        showInlineKeyboard = false
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentCyan)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BluePadTheme.bgElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BluePadTheme.accentCyan.opacity(0.45), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 14)
            }

            if viewModel.settings.touchpadButtonsOnTop {
                mouseButtonsRow
                    .padding(.horizontal, 14)
                trackpadSurfaceSection
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                trackpadSurfaceSection
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                mouseButtonsRow
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .background(BluePadTheme.bgPrimary)
        .fullScreenCover(isPresented: $viewModel.isFullScreenTrackpad) {
            FullScreenTrackpadModal(viewModel: viewModel)
        }
    }

    private var trackpadSurfaceSection: some View {
        HStack(spacing: 8) {
            ZStack {
                TrackpadSurfaceRepresentable(
                    tapToClickEnabled: viewModel.settings.tapToClick,
                    onMove: { dx, dy in
                        viewModel.handleTrackpadMove(rawDX: dx, rawDY: dy)
                    },
                    onScroll: { dx, dy in
                        viewModel.handleTrackpadScroll(rawDX: dx, rawDY: dy)
                    },
                    onTapClick: { button in
                        viewModel.clickMouse(button)
                    },
                    onMouseButton: { button, pressed in
                        viewModel.setMouseButton(button, pressed: pressed)
                    },
                    onGestureEnd: {
                        viewModel.resetTrackpadMotion()
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            viewModel.isAirMouseActive
                                ? BluePadTheme.accentMint.opacity(0.6)
                                : BluePadTheme.borderSubtle,
                            lineWidth: 1.5
                        )
                )

                // Subtle gesture legend overlay
                VStack {
                    HStack {
                        if viewModel.isAirMouseActive {
                            Label("Hava Faresi Aktif — Telefonu Hareket Ettirin", systemImage: "gyroscope")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BluePadTheme.bgPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(BluePadTheme.accentMint))
                        }
                        Spacer()
                        Text("\(viewModel.packetsSentCount) paket")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(BluePadTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(BluePadTheme.bgElevated.opacity(0.7)))
                    }
                    Spacer()
                    Text("1 Parmak: İmleç / Tık · 2 Parmak: Kaydır / Sağ Tık · Çift Dokun+Sürükle")
                        .font(.caption2)
                        .foregroundStyle(BluePadTheme.textSecondary.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(14)
                .allowsHitTesting(false)
            }

            if viewModel.settings.showScrollStrip {
                VerticalScrollStrip(
                    onScrollDelta: { dy in
                        viewModel.handleTrackpadScroll(rawDX: 0, rawDY: dy)
                    },
                    onEnd: {
                        viewModel.resetTrackpadMotion()
                    }
                )
            }
        }
    }

    private var mouseButtonsRow: some View {
        HStack(spacing: 10) {
            HoldableMouseButton(
                title: "Sol Tık",
                isActive: viewModel.pressedButtons.contains(.left),
                accent: BluePadTheme.accentCyan
            ) { pressed in
                viewModel.setMouseButton(.left, pressed: pressed)
            }

            HoldableMouseButton(
                title: "Orta",
                isActive: viewModel.pressedButtons.contains(.middle),
                accent: BluePadTheme.accentViolet,
                maxWidth: 82
            ) { pressed in
                viewModel.setMouseButton(.middle, pressed: pressed)
            }

            HoldableMouseButton(
                title: "Sağ Tık",
                isActive: viewModel.pressedButtons.contains(.right),
                accent: BluePadTheme.accentBlue
            ) { pressed in
                viewModel.setMouseButton(.right, pressed: pressed)
            }
        }
    }

    private func quickChip(
        title: String,
        icon: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isActive ? BluePadTheme.bgPrimary : BluePadTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? BluePadTheme.accentCyan : BluePadTheme.bgElevated)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isActive ? BluePadTheme.accentCyan : BluePadTheme.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HoldableMouseButton: View {
    let title: String
    let isActive: Bool
    let accent: Color
    var maxWidth: CGFloat? = nil
    let onPressChanged: (Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isActive || isPressed ? BluePadTheme.bgPrimary : BluePadTheme.textPrimary)
            .frame(maxWidth: maxWidth ?? .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive || isPressed ? accent : BluePadTheme.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isActive || isPressed ? accent : BluePadTheme.borderSubtle, lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
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

private struct VerticalScrollStrip: View {
    let onScrollDelta: (Double) -> Void
    let onEnd: () -> Void

    @State private var lastY: CGFloat?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(BluePadTheme.textSecondary)
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(BluePadTheme.accentCyan.opacity(0.45))
                .frame(width: 4, height: 34)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(BluePadTheme.textSecondary)
        }
        .padding(.vertical, 12)
        .frame(width: 28)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BluePadTheme.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BluePadTheme.borderSubtle, lineWidth: 1)
                )
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if let prev = lastY {
                        let dy = Double(value.location.y - prev)
                        if abs(dy) > 0.2 {
                            onScrollDelta(dy)
                        }
                    }
                    lastY = value.location.y
                }
                .onEnded { _ in
                    lastY = nil
                    onEnd()
                }
        )
    }
}

private struct FullScreenTrackpadModal: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TrackpadSurfaceRepresentable(
                    tapToClickEnabled: viewModel.settings.tapToClick,
                    onMove: { dx, dy in
                        viewModel.handleTrackpadMove(rawDX: dx, rawDY: dy)
                    },
                    onScroll: { dx, dy in
                        viewModel.handleTrackpadScroll(rawDX: dx, rawDY: dy)
                    },
                    onTapClick: { button in
                        viewModel.clickMouse(button)
                    },
                    onMouseButton: { button, pressed in
                        viewModel.setMouseButton(button, pressed: pressed)
                    },
                    onGestureEnd: {
                        viewModel.resetTrackpadMotion()
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(BluePadTheme.borderSubtle, lineWidth: 1.5)
                )

                if viewModel.settings.showScrollStrip {
                    VerticalScrollStrip(
                        onScrollDelta: { dy in
                            viewModel.handleTrackpadScroll(rawDX: 0, rawDY: dy)
                        },
                        onEnd: {
                            viewModel.resetTrackpadMotion()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                HoldableMouseButton(
                    title: "Sol Tık",
                    isActive: viewModel.pressedButtons.contains(.left),
                    accent: BluePadTheme.accentCyan
                ) { pressed in
                    viewModel.setMouseButton(.left, pressed: pressed)
                }

                Button {
                    viewModel.triggerHaptic(.light)
                    viewModel.isFullScreenTrackpad = false
                } label: {
                    Label("Çık", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.bgPrimary)
                        .frame(width: 82, height: 54)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BluePadTheme.accentMint))
                }
                .buttonStyle(.plain)

                HoldableMouseButton(
                    title: "Sağ Tık",
                    isActive: viewModel.pressedButtons.contains(.right),
                    accent: BluePadTheme.accentBlue
                ) { pressed in
                    viewModel.setMouseButton(.right, pressed: pressed)
                }
            }
        }
        .padding(12)
        .background(BluePadTheme.bgPrimary.ignoresSafeArea())
    }
}

// MARK: - UIKit Multi-Touch Trackpad Bridge

struct TrackpadSurfaceRepresentable: UIViewRepresentable {
    var tapToClickEnabled: Bool
    var onMove: (Double, Double) -> Void
    var onScroll: (Double, Double) -> Void
    var onTapClick: (HIDMouseButton) -> Void
    var onMouseButton: (HIDMouseButton, Bool) -> Void
    var onGestureEnd: () -> Void

    func makeUIView(context: Context) -> TrackpadTouchView {
        let view = TrackpadTouchView()
        syncCallbacks(view)
        return view
    }

    func updateUIView(_ uiView: TrackpadTouchView, context: Context) {
        syncCallbacks(uiView)
    }

    private func syncCallbacks(_ view: TrackpadTouchView) {
        view.tapToClickEnabled = tapToClickEnabled
        view.onMove = onMove
        view.onScroll = onScroll
        view.onTapClick = onTapClick
        view.onMouseButton = onMouseButton
        view.onGestureEnd = onGestureEnd
    }
}

final class TrackpadTouchView: UIView {
    var tapToClickEnabled: Bool = true
    var onMove: ((Double, Double) -> Void)?
    var onScroll: ((Double, Double) -> Void)?
    var onTapClick: ((HIDMouseButton) -> Void)?
    var onMouseButton: ((HIDMouseButton, Bool) -> Void)?
    var onGestureEnd: (() -> Void)?

    private var activeTouches: [UITouch] = []
    private var lastCentroid: CGPoint?
    private var gestureStartTime: Date = .distantPast
    private var gesturePeakFingerCount: Int = 0
    private var gestureTotalMovement: Double = 0

    private var lastSingleTapTime: Date = .distantPast
    private var lastSingleTapPoint: CGPoint = .zero
    private var isTapToDragActive: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(red: 0.071, green: 0.094, blue: 0.165, alpha: 1.0)
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Subtle tactile dot-grid texture
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.06).cgColor)
        let spacing: CGFloat = 22
        var y: CGFloat = spacing
        while y < rect.height - 10 {
            var x: CGFloat = spacing
            while x < rect.width - 10 {
                ctx.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                x += spacing
            }
            y += spacing
        }

        // Active finger feedback rings
        for touch in activeTouches {
            let pt = touch.location(in: self)
            let outer = CGRect(x: pt.x - 28, y: pt.y - 28, width: 56, height: 56)
            ctx.setFillColor(UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.18).cgColor)
            ctx.fillEllipse(in: outer)

            let inner = CGRect(x: pt.x - 10, y: pt.y - 10, width: 20, height: 20)
            ctx.setStrokeColor(UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.75).cgColor)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: inner)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasEmpty = activeTouches.isEmpty
        for touch in touches where !activeTouches.contains(touch) {
            activeTouches.append(touch)
        }

        if wasEmpty {
            gestureStartTime = Date()
            gestureTotalMovement = 0
            gesturePeakFingerCount = activeTouches.count

            if tapToClickEnabled,
               activeTouches.count == 1,
               let pt = activeTouches.first?.location(in: self),
               Date().timeIntervalSince(lastSingleTapTime) < 0.24,
               hypot(pt.x - lastSingleTapPoint.x, pt.y - lastSingleTapPoint.y) < 30 {
                isTapToDragActive = true
                onMouseButton?(.left, true)
            }
        } else {
            gesturePeakFingerCount = max(gesturePeakFingerCount, activeTouches.count)
        }

        lastCentroid = centroid(of: activeTouches)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !activeTouches.isEmpty, let current = centroid(of: activeTouches) else { return }
        if let prev = lastCentroid {
            let dx = Double(current.x - prev.x)
            let dy = Double(current.y - prev.y)
            gestureTotalMovement += hypot(dx, dy)

            if activeTouches.count == 1 {
                onMove?(dx, dy)
            } else if activeTouches.count >= 2 {
                onScroll?(dx, dy)
            }
        }
        lastCentroid = current
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishTouches(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishTouches(touches, cancelled: true)
    }

    private func finishTouches(_ touches: Set<UITouch>, cancelled: Bool) {
        let endingCentroid = centroid(of: activeTouches)
        activeTouches.removeAll { touches.contains($0) }

        if activeTouches.isEmpty {
            if isTapToDragActive {
                isTapToDragActive = false
                onMouseButton?(.left, false)
            } else if !cancelled,
                      tapToClickEnabled,
                      gestureTotalMovement < 14.0,
                      Date().timeIntervalSince(gestureStartTime) < 0.30 {
                switch gesturePeakFingerCount {
                case 1:
                    lastSingleTapTime = Date()
                    lastSingleTapPoint = endingCentroid ?? .zero
                    onTapClick?(.left)
                case 2:
                    onTapClick?(.right)
                default:
                    onTapClick?(.middle)
                }
            }

            gesturePeakFingerCount = 0
            gestureTotalMovement = 0
            lastCentroid = nil
            onGestureEnd?()
        } else {
            lastCentroid = centroid(of: activeTouches)
        }
        setNeedsDisplay()
    }

    private func centroid(of touches: [UITouch]) -> CGPoint? {
        guard !touches.isEmpty else { return nil }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for touch in touches {
            let loc = touch.location(in: self)
            sumX += loc.x
            sumY += loc.y
        }
        let count = CGFloat(touches.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }
}
