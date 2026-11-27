import SwiftUI

// MARK: - Composition Grids, Horizon Level, Face Tracking & Aspect Guides

struct CompositionGridView: View {
    let mode: GridMode

    var body: some View {
        Canvas { context, size in
            let lineColor = Color.white.opacity(0.30)
            switch mode {
            case .off:
                break
            case .ruleOfThirds:
                for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                    var vLine = Path()
                    vLine.move(to: CGPoint(x: size.width * fraction, y: 0))
                    vLine.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                    context.stroke(vLine, with: .color(lineColor), lineWidth: 0.75)

                    var hLine = Path()
                    hLine.move(to: CGPoint(x: 0, y: size.height * fraction))
                    hLine.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    context.stroke(hLine, with: .color(lineColor), lineWidth: 0.75)
                }
            case .goldenRatio:
                for fraction in [0.382, 0.618] {
                    var vLine = Path()
                    vLine.move(to: CGPoint(x: size.width * fraction, y: 0))
                    vLine.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                    context.stroke(vLine, with: .color(Color.yellow.opacity(0.35)), lineWidth: 0.8)

                    var hLine = Path()
                    hLine.move(to: CGPoint(x: 0, y: size.height * fraction))
                    hLine.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    context.stroke(hLine, with: .color(Color.yellow.opacity(0.35)), lineWidth: 0.8)
                }
            case .symmetry:
                var vMid = Path()
                vMid.move(to: CGPoint(x: size.width * 0.5, y: 0))
                vMid.addLine(to: CGPoint(x: size.width * 0.5, y: size.height))
                context.stroke(vMid, with: .color(Color.cyan.opacity(0.45)), lineWidth: 1.0)

                var hMid = Path()
                hMid.move(to: CGPoint(x: 0, y: size.height * 0.5))
                hMid.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                context.stroke(hMid, with: .color(Color.cyan.opacity(0.45)), lineWidth: 1.0)
            case .diagonal:
                var d1 = Path()
                d1.move(to: .zero)
                d1.addLine(to: CGPoint(x: size.width, y: size.height))
                context.stroke(d1, with: .color(lineColor), lineWidth: 0.85)

                var d2 = Path()
                d2.move(to: CGPoint(x: size.width, y: 0))
                d2.addLine(to: CGPoint(x: 0, y: size.height))
                context.stroke(d2, with: .color(lineColor), lineWidth: 0.85)
            case .framing:
                let insetX = size.width * 0.14
                let insetY = size.height * 0.16
                let innerRect = CGRect(
                    x: insetX,
                    y: insetY,
                    width: size.width - insetX * 2,
                    height: size.height - insetY * 2
                )
                context.stroke(
                    Path(roundedRect: innerRect, cornerRadius: 14),
                    with: .color(Color.cyan.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [6, 5])
                )
            }
        }
    }
}

struct HorizonLevelIndicatorView: View {
    let rollDegrees: Double
    let isLevel: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 72, height: 1)

            Rectangle()
                .fill(isLevel ? Color.green : Color.yellow)
                .frame(width: 48, height: isLevel ? 2 : 1.5)
                .rotationEffect(.degrees(-rollDegrees))
        }
    }
}

struct FaceTrackingBoxView: View {
    let normalizedBox: CGRect
    let isMirrored: Bool
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = normalizedBox.width * geo.size.width
            let h = normalizedBox.height * geo.size.height
            let rawX = normalizedBox.minX * geo.size.width
            let x = isMirrored ? (geo.size.width - rawX - w) : rawX
            let y = normalizedBox.minY * geo.size.height

            RoundedRectangle(cornerRadius: 8)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                .frame(width: w, height: h)
                .position(x: x + w / 2, y: y + h / 2)
                .animation(.easeOut(duration: 0.12), value: normalizedBox)
        }
    }
}

struct AspectRatioMaskView: View {
    let mode: AspectGuideMode

    var body: some View {
        GeometryReader { geo in
            let ratio: CGFloat = (mode == .feed4x5) ? (4.0 / 5.0) : (9.0 / 16.0)
            let boxWidth = min(geo.size.width, geo.size.height * ratio)
            let boxHeight = boxWidth / ratio

            ZStack {
                Color.black.opacity(0.45)
                    .mask(
                        Rectangle()
                            .overlay(
                                Rectangle()
                                    .frame(width: boxWidth, height: boxHeight)
                                    .blendMode(.destinationOut)
                            )
                    )
                    .compositingGroup()

                Rectangle()
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
                    .frame(width: boxWidth, height: boxHeight)
            }
        }
    }
}

/// Dual '+' overhead flat-lay crosshair: turns green when phone is parallel to table/floor.
struct FlatLayCrosshairView: View {
    let offsetX: Double
    let offsetY: Double
    let isAligned: Bool

    var body: some View {
        ZStack {
            Image(systemName: "plus")
                .font(.title3.weight(.light))
                .foregroundStyle(isAligned ? Color.green : Color.white.opacity(0.7))

            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isAligned ? Color.green : Color.yellow)
                .offset(x: CGFloat(offsetX * 140), y: CGFloat(-offsetY * 140))
        }
    }
}
