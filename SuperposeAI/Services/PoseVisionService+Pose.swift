import Vision
import Foundation

extension PoseVisionService {
    // MARK: - Vision Body Pose Extraction

    nonisolated static func extractSkeleton(from observation: VNHumanBodyPoseObservation?) -> PoseSkeleton? {
        guard let observation else { return nil }

        let mapping: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .nose),
            (.neck, .neck),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.root, .root),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle)
        ]

        var joints: [BodyJoint: NormalizedPoint] = [:]
        for (joint, vnName) in mapping {
            if let point = try? observation.recognizedPoint(vnName), point.confidence > 0.25 {
                // Vision origin is bottom-left; SwiftUI origin is top-left.
                joints[joint] = NormalizedPoint(x: point.location.x, y: 1.0 - point.location.y)
            }
        }

        return joints.isEmpty ? nil : PoseSkeleton(joints: joints)
    }

    // MARK: - Framing & Composition Rules

    nonisolated static func evaluateFraming(
        from rectObservation: VNHumanObservation?,
        skeleton: PoseSkeleton?,
        upperBodyOnly: Bool = false
    ) -> FramingStatus {
        guard let rect = rectObservation?.boundingBox else {
            return skeleton == nil ? .noSubject : .great
        }

        // Vision rect origin is bottom-left
        let area = rect.width * rect.height
        let centerX = rect.midX
        let topEdge = 1.0 - rect.maxY // distance from top of frame

        let maxArea = upperBodyOnly ? 0.86 : 0.72
        if area > maxArea { return .tooClose }
        if area < 0.08 { return .tooFar }
        if centerX < 0.34 { return .moveRight }
        if centerX > 0.66 { return .moveLeft }
        if topEdge > 0.28 { return .tiltDown }

        return .great
    }

    // MARK: - Eye Blink, Smile & Face Angle Detection

    nonisolated static func areEyesClosed(in faces: [VNFaceObservation]?) -> Bool {
        guard let face = faces?.first, let landmarks = face.landmarks else { return false }
        let ratios = [landmarks.leftEye, landmarks.rightEye].compactMap { eye -> CGFloat? in
            guard let pts = eye?.normalizedPoints, pts.count >= 4 else { return nil }
            let xs = pts.map(\.x), ys = pts.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return nil }
            let width = maxX - minX
            guard width > 0.01 else { return nil }
            return (maxY - minY) / width
        }
        guard !ratios.isEmpty else { return false }
        let avgEAR = ratios.reduce(0, +) / CGFloat(ratios.count)
        return avgEAR < 0.14
    }

    nonisolated static func faceAngleHint(in faces: [VNFaceObservation]?) -> String? {
        guard let face = faces?.first else { return nil }
        if let roll = face.roll?.doubleValue, abs(roll) > 0.28 {
            return "Başını biraz düz tut"
        }
        if let yaw = face.yaw?.doubleValue, abs(yaw) > 0.55 {
            return "Yüzünü biraz kameraya dön"
        }
        return nil
    }

    nonisolated static func leadRoomHint(in faces: [VNFaceObservation]?) -> String? {
        guard let face = faces?.first, let yaw = face.yaw?.doubleValue else { return nil }
        let midX = face.boundingBox.midX
        if yaw < -0.25 && midX < 0.42 {
            return "Baktığın yönde biraz boşluk bırak"
        }
        if yaw > 0.25 && midX > 0.58 {
            return "Baktığın yönde biraz boşluk bırak"
        }
        return nil
    }

    nonisolated static func isSmiling(in faces: [VNFaceObservation]?) -> Bool {
        guard let face = faces?.first,
              let lips = face.landmarks?.outerLips?.normalizedPoints,
              lips.count >= 6 else { return false }
        let xs = lips.map(\.x)
        let ys = lips.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return false }
        let mouthWidth = maxX - minX
        let mouthHeight = maxY - minY
        guard mouthWidth >= 0.40, mouthHeight > 0.02 else { return false }

        if let leftEyePts = face.landmarks?.leftEye?.normalizedPoints,
           let rightEyePts = face.landmarks?.rightEye?.normalizedPoints,
           let minEyeX = leftEyePts.map(\.x).min(),
           let maxEyeX = rightEyePts.map(\.x).max() {
            let eyeSpan = maxEyeX - minEyeX
            if eyeSpan > 0.1 && mouthWidth < eyeSpan * 0.88 {
                return false
            }
        }

        let leftCorner = lips.min(by: { $0.x < $1.x })
        let rightCorner = lips.max(by: { $0.x < $1.x })
        let midY = (minY + maxY) / 2.0
        let cornerAvgY = ((leftCorner?.y ?? midY) + (rightCorner?.y ?? midY)) / 2.0
        return cornerAvgY > midY + 0.012
    }

    // MARK: - Multi-Person & Couples Balance Coach

    nonisolated static func evaluateCouplesBalance(first: PoseSkeleton?, second: PoseSkeleton?) -> String? {
        guard let first, let second,
              let n1 = first.joints[.neck], let r1 = first.joints[.root],
              let n2 = second.joints[.neck], let r2 = second.joints[.root] else {
            return nil
        }

        let horizontalGap = abs(n1.x - n2.x)
        if horizontalGap > 0.48 {
            return "2 kişi algılandı — birbirinize biraz yaklaşın"
        }

        let minX = min(n1.x, n2.x)
        let maxX = max(n1.x, n2.x)
        if minX < 0.16 { return "Soldaki kişi kadraja biraz yaklaşsın" }
        if maxX > 0.84 { return "Sağdaki kişi kadraja biraz yaklaşsın" }

        let h1 = abs(r1.y - n1.y)
        let h2 = abs(r2.y - n2.y)
        guard h1 > 0.05, h2 > 0.05 else { return nil }

        let leftIsFirst = n1.x < n2.x
        let leftH = leftIsFirst ? h1 : h2
        let rightH = leftIsFirst ? h2 : h1

        if leftH < rightH * 0.78 { return "Soldaki yarım adım öne gelsin" }
        if rightH < leftH * 0.78 { return "Sağdaki yarım adım öne gelsin" }
        return nil
    }

    // MARK: - Scale-Independent Pose Similarity Score (0 - 100%)

    nonisolated static func computePoseMatchScore(live: PoseSkeleton, target: PoseSkeleton) -> Int {
        var angleScoreSum = 0.0
        var angleCount = 0

        for (start, end) in PoseSkeleton.boneConnections {
            guard let la = live.joints[start], let lb = live.joints[end],
                  let ta = target.joints[start], let tb = target.joints[end] else {
                continue
            }

            let ldx = lb.x - la.x
            let ldy = lb.y - la.y
            let tdx = tb.x - ta.x
            let tdy = tb.y - ta.y

            let lMag = hypot(ldx, ldy)
            let tMag = hypot(tdx, tdy)
            guard lMag > 0.01, tMag > 0.01 else { continue }

            let dot = (ldx * tdx + ldy * tdy) / (lMag * tMag)
            let clampedDot = max(-1.0, min(1.0, dot))
            let boneSimilarity = (clampedDot + 1.0) / 2.0
            angleScoreSum += boneSimilarity
            angleCount += 1
        }

        guard angleCount >= 4 else { return 0 }
        let avgSimilarity = angleScoreSum / Double(angleCount)
        let adjusted = max(0.0, min(1.0, (avgSimilarity - 0.35) / 0.65))
        return Int((adjusted * 100.0).rounded())
    }
}
