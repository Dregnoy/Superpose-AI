import SwiftUI

/// Renders a wireframe silhouette, detailed contour, or translucent Ghost silhouette
/// over the live camera preview (supports both solo and 2-person Couples poses).
struct PoseOverlayView: View {
    let targetSkeleton: PoseSkeleton
    var secondaryTargetSkeleton: PoseSkeleton? = nil
    let liveSkeleton: PoseSkeleton?
    var liveSecondarySkeleton: PoseSkeleton? = nil
    var ghostMaskImage: UIImage? = nil
    let mode: OverlayMode
    let matchScore: Int?

    var body: some View {
        GeometryReader { _ in
            if mode != .off {
                ZStack {
                    if mode == .ghost, let ghostMaskImage {
                        Image(uiImage: ghostMaskImage)
                            .resizable()
                            .scaledToFill()
                            .opacity(0.28)
                            .ignoresSafeArea()
                    } else {
                        Canvas { context, size in
                            drawTargetPose(targetSkeleton, in: &context, size: size, tint: (matchScore ?? 0) >= 75 ? .green : .cyan)
                            if let secondaryTargetSkeleton {
                                drawTargetPose(secondaryTargetSkeleton, in: &context, size: size, tint: (matchScore ?? 0) >= 75 ? .green : .mint)
                            }
                            if let liveSkeleton {
                                drawLiveJoints(liveSkeleton, in: &context, size: size)
                            }
                            if let liveSecondarySkeleton {
                                drawLiveJoints(liveSecondarySkeleton, in: &context, size: size)
                            }
                        }
                    }

                    if let matchScore {
                        VStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(matchScore >= 75 ? Color.green : Color.cyan)
                                    .frame(width: 8, height: 8)
                                Text("Poz Eşleşmesi %\(matchScore)")
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 14)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func drawTargetPose(_ skeleton: PoseSkeleton, in context: inout GraphicsContext, size: CGSize, tint: Color) {
        if mode == .ghost {
            drawGhostSilhouette(skeleton, in: &context, size: size, color: tint)
            return
        }

        if mode == .detailedContour {
            drawBodyEnvelope(skeleton, in: &context, size: size, color: tint.opacity(0.28))
        }

        for (startJoint, endJoint) in PoseSkeleton.boneConnections {
            guard let p1 = skeleton.joints[startJoint],
                  let p2 = skeleton.joints[endJoint] else { continue }

            var path = Path()
            path.move(to: CGPoint(x: p1.x * size.width, y: p1.y * size.height))
            path.addLine(to: CGPoint(x: p2.x * size.width, y: p2.y * size.height))

            let lineWidth: CGFloat = mode == .detailedContour ? 5 : 3
            let style = StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                dash: mode == .fastSilhouette ? [6, 6] : []
            )
            context.stroke(path, with: .color(tint.opacity(0.85)), style: style)
        }

        if let nose = skeleton.joints[.nose] {
            let center = CGPoint(x: nose.x * size.width, y: nose.y * size.height)
            let radius: CGFloat = size.width * 0.065
            let headRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: headRect), with: .color(tint.opacity(0.9)), lineWidth: 2.5)
        }

        for (_, point) in skeleton.joints {
            let pt = CGPoint(x: point.x * size.width, y: point.y * size.height)
            let dotRect = CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dotRect), with: .color(.white))
        }
    }

    private func drawGhostSilhouette(_ skeleton: PoseSkeleton, in context: inout GraphicsContext, size: CGSize, color: Color) {
        // Translucent filled torso
        drawBodyEnvelope(skeleton, in: &context, size: size, color: color.opacity(0.22))

        // Translucent filled head
        if let nose = skeleton.joints[.nose] {
            let center = CGPoint(x: nose.x * size.width, y: nose.y * size.height)
            let radius: CGFloat = size.width * 0.075
            let headRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: headRect), with: .color(color.opacity(0.24)))
        }

        // Thick soft limb strokes to form an intuitive body shadow
        for (startJoint, endJoint) in PoseSkeleton.boneConnections {
            guard let p1 = skeleton.joints[startJoint],
                  let p2 = skeleton.joints[endJoint] else { continue }
            var path = Path()
            path.move(to: CGPoint(x: p1.x * size.width, y: p1.y * size.height))
            path.addLine(to: CGPoint(x: p2.x * size.width, y: p2.y * size.height))
            context.stroke(
                path,
                with: .color(color.opacity(0.24)),
                style: StrokeStyle(lineWidth: size.width * 0.065, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawBodyEnvelope(_ skeleton: PoseSkeleton, in context: inout GraphicsContext, size: CGSize, color: Color) {
        let torsoJoints: [BodyJoint] = [.leftShoulder, .rightShoulder, .rightHip, .leftHip]
        let points = torsoJoints.compactMap { skeleton.joints[$0] }
        guard points.count == 4 else { return }

        var torso = Path()
        torso.move(to: CGPoint(x: points[0].x * size.width, y: points[0].y * size.height))
        for p in points.dropFirst() {
            torso.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height))
        }
        torso.closeSubpath()
        context.fill(torso, with: .color(color))
    }

    private func drawLiveJoints(_ skeleton: PoseSkeleton, in context: inout GraphicsContext, size: CGSize) {
        for (_, point) in skeleton.joints {
            let pt = CGPoint(x: point.x * size.width, y: point.y * size.height)
            let rect = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: rect), with: .color(.yellow.opacity(0.7)))
        }
    }
}
