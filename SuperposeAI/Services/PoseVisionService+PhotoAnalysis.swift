import Vision
import CoreImage
import UIKit
import Foundation

extension PoseVisionService {
    // MARK: - Static Image Pose Extraction (Inspo Import)

    /// Extracts a 1-person or 2-person pose skeleton, framing, and category from any imported
    /// reference photo entirely on-device with zero cloud AI cost.
    func extractPose(from image: UIImage) async -> PoseIdea? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = Self.cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                let poseRequest = VNDetectHumanBodyPoseRequest()
                let rectRequest = VNDetectHumanRectanglesRequest()
                let classifyRequest = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([poseRequest, rectRequest, classifyRequest])
                    let skeletons = (poseRequest.results ?? []).prefix(2).compactMap { Self.extractSkeleton(from: $0) }
                    guard let primary = skeletons.first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let secondary = skeletons.count > 1 ? skeletons[1] : nil

                    let hasLowerBody = primary.joints[.leftAnkle] != nil || primary.joints[.rightAnkle] != nil
                        || primary.joints[.leftKnee] != nil || primary.joints[.rightKnee] != nil
                    let hasTorso = primary.joints[.root] != nil || primary.joints[.leftHip] != nil || primary.joints[.rightHip] != nil
                    let box = rectRequest.results?.first?.boundingBox
                    let boxHeight = box?.height ?? 0

                    let framingLabel: String
                    if hasLowerBody || boxHeight > 0.65 {
                        framingLabel = "Tam Boy"
                    } else if hasTorso || boxHeight > 0.38 {
                        framingLabel = "Bel Üstü"
                    } else {
                        framingLabel = "Portre"
                    }

                    let jointXs = primary.joints.values.map(\.x)
                    let centerX = jointXs.isEmpty ? (box?.midX ?? 0.5) : (jointXs.reduce(0, +) / Double(jointXs.count))
                    let placementLabel: String
                    if centerX < 0.40 {
                        placementLabel = "Sol 1/3"
                    } else if centerX > 0.60 {
                        placementLabel = "Sağ 1/3"
                    } else {
                        placementLabel = "Orta"
                    }

                    let tags = (classifyRequest.results ?? [])
                        .filter { $0.confidence >= 0.2 }
                        .prefix(6)
                        .map { $0.identifier.lowercased() }

                    let inferredCategory: PoseCategory
                    if secondary != nil {
                        inferredCategory = .couples
                    } else if tags.contains(where: { $0.contains("beach") || $0.contains("coast") || $0.contains("ocean") || $0.contains("sea") }) {
                        inferredCategory = .beach
                    } else if tags.contains(where: { $0.contains("cafe") || $0.contains("restaurant") || $0.contains("coffee") }) {
                        inferredCategory = .cafe
                    } else if framingLabel == "Portre" {
                        inferredCategory = .portrait
                    } else {
                        inferredCategory = .street
                    }

                    let idea = PoseIdea(
                        title: secondary == nil ? "İlham Pozu (\(framingLabel))" : "İlham Çift Pozu",
                        angleLabel: "\(framingLabel) · \(placementLabel)",
                        confidenceTag: "Referans",
                        category: inferredCategory,
                        skeleton: primary,
                        secondarySkeleton: secondary,
                        coaching: CoachingTips(
                            summary: "Referans kadraj: \(framingLabel), \(placementLabel) yerleşimi.",
                            subjectTips: [
                                "Omuzlarını ve kalçanı ekrandaki silüete göre hizala.",
                                "İstersen Hayalet (Ghost) moduna geçip yarı saydam gölgeyle eşleş."
                            ],
                            photographerTips: [
                                "Öznemizi kadrajın \(placementLabel) bölgesine yerleştir (\(framingLabel) ölçeği).",
                                "Daha estetik portre oranları için 2x lensi kullan."
                            ]
                        )
                    )
                    continuation.resume(returning: idea)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    nonisolated static func cgImageOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Extracts a background-free translucent silhouette from an imported photo
    /// using Apple Vision person segmentation for Photo-to-Ghost overlays.
    func extractPersonSilhouette(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = Self.cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = .balanced
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    guard let maskBuffer = request.results?.first?.pixelBuffer else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let ciContext = Self.sharedCIContext
                    let originalCI = CIImage(cgImage: cgImage)
                    let maskCI = CIImage(cvPixelBuffer: maskBuffer)

                    let scaleX = originalCI.extent.width / maskCI.extent.width
                    let scaleY = originalCI.extent.height / maskCI.extent.height
                    let scaledMask = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

                    guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
                        continuation.resume(returning: nil)
                        return
                    }
                    blendFilter.setValue(originalCI, forKey: kCIInputImageKey)
                    blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
                    blendFilter.setValue(scaledMask, forKey: kCIInputMaskImageKey)

                    guard let output = blendFilter.outputImage,
                          let resultCG = ciContext.createCGImage(output, from: originalCI.extent) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: UIImage(cgImage: resultCG, scale: image.scale, orientation: image.imageOrientation))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    struct ShotQualityBreakdown: Sendable, Equatable {
        let totalScore: Double
        let faceQuality: Double
        let sharpnessScore: Double
        let poseMatchScore: Double?
        let eyesClosed: Bool
        let isSmiling: Bool

        init(
            totalScore: Double,
            faceQuality: Double,
            sharpnessScore: Double,
            poseMatchScore: Double?,
            eyesClosed: Bool = false,
            isSmiling: Bool = false
        ) {
            self.totalScore = totalScore
            self.faceQuality = faceQuality
            self.sharpnessScore = sharpnessScore
            self.poseMatchScore = poseMatchScore
            self.eyesClosed = eyesClosed
            self.isSmiling = isSmiling
        }
    }

    /// Evaluates face capture quality, edge sharpness, and optional pose alignment
    /// on-device for a single captured photo.
    func evaluateShotQuality(image: UIImage, targetPose: PoseIdea? = nil) async -> ShotQualityBreakdown {
        await withCheckedContinuation { continuation in
            visionQueue.async {
                let breakdown = Self.evaluateShotSync(image: image, targetPose: targetPose)
                continuation.resume(returning: breakdown)
            }
        }
    }

    /// Evaluates face capture quality, sharpness, and optional pose alignment across
    /// multiple shots and returns the best frame on-device.
    func pickBestShot(from images: [UIImage], targetPose: PoseIdea? = nil) async -> UIImage? {
        guard images.count > 1 else { return images.first }

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                var bestImage = images[0]
                var bestScore: Double = -1.0

                for image in images {
                    let breakdown = Self.evaluateShotSync(image: image, targetPose: targetPose)
                    if breakdown.totalScore > bestScore {
                        bestScore = breakdown.totalScore
                        bestImage = image
                    }
                }
                continuation.resume(returning: bestImage)
            }
        }
    }

    nonisolated private static func evaluateShotSync(image: UIImage, targetPose: PoseIdea?) -> ShotQualityBreakdown {
        guard let cgImage = image.cgImage else {
            return ShotQualityBreakdown(totalScore: 0, faceQuality: 0, sharpnessScore: 0, poseMatchScore: nil)
        }

        let orientation = cgImageOrientation(from: image.imageOrientation)
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        var requests: [VNRequest] = [faceRequest, landmarksRequest]
        let poseRequest: VNDetectHumanBodyPoseRequest?
        if targetPose != nil {
            let pr = VNDetectHumanBodyPoseRequest()
            poseRequest = pr
            requests.append(pr)
        } else {
            poseRequest = nil
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try? handler.perform(requests)

        let hasFace = !(faceRequest.results?.isEmpty ?? true)
        let faceQuality = Double(faceRequest.results?.first?.faceCaptureQuality ?? 0.0)
        let eyesClosed = areEyesClosed(in: landmarksRequest.results)
        let smiling = !eyesClosed && isSmiling(in: landmarksRequest.results)
        let sharpness = computeSharpnessScore(cgImage: cgImage)

        var poseMatchScore: Double? = nil
        if let target = targetPose,
           let detected = extractSkeleton(from: poseRequest?.results?.first) {
            poseMatchScore = Double(computePoseMatchScore(live: detected, target: target.skeleton))
        }

        var totalScore: Double
        if hasFace, let poseScore = poseMatchScore {
            totalScore = 0.45 * (faceQuality * 100.0) + 0.35 * (sharpness * 100.0) + 0.20 * poseScore
        } else if hasFace {
            totalScore = 0.55 * (faceQuality * 100.0) + 0.45 * (sharpness * 100.0)
        } else if let poseScore = poseMatchScore {
            totalScore = 0.65 * (sharpness * 100.0) + 0.35 * poseScore
        } else {
            totalScore = sharpness * 100.0
        }

        if eyesClosed {
            totalScore -= 35.0
        } else if smiling {
            totalScore += 12.0
        }

        return ShotQualityBreakdown(
            totalScore: min(100.0, max(0.0, totalScore)),
            faceQuality: faceQuality,
            sharpnessScore: sharpness,
            poseMatchScore: poseMatchScore,
            eyesClosed: eyesClosed,
            isSmiling: smiling
        )
    }

    nonisolated static func computeSharpnessScore(cgImage: CGImage) -> Double {
        let ciImage = CIImage(cgImage: cgImage)
        let maxDim = max(ciImage.extent.width, ciImage.extent.height)
        let scale = maxDim > 512 ? 512.0 / maxDim : 1.0
        let scaled = scale < 1.0
            ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : ciImage

        guard let edgesFilter = CIFilter(name: "CIEdges") else { return 0.5 }
        edgesFilter.setValue(scaled, forKey: kCIInputImageKey)
        edgesFilter.setValue(2.0, forKey: kCIInputIntensityKey)
        guard let edgeOutput = edgesFilter.outputImage else { return 0.5 }

        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        avgFilter.setValue(edgeOutput, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: edgeOutput.extent), forKey: kCIInputExtentKey)
        guard let avgOutput = avgFilter.outputImage else { return 0.5 }

        var pixel = [UInt8](repeating: 0, count: 4)
        sharedCIContext.render(
            avgOutput,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let avgIntensity = (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3.0 * 255.0)
        return min(1.0, max(0.0, avgIntensity / 0.14))
    }

    /// Classifies the environment on-device using Apple Vision (e.g. "outdoor", "beach", "cafe")
    /// so only anonymous text tags—never pixels—are shared with AI.
    func classifySceneTags(from image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = Self.cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    let tags = (request.results ?? [])
                        .filter { $0.confidence >= 0.25 }
                        .prefix(4)
                        .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
                    continuation.resume(returning: Array(tags))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Applies subtle on-device portrait background blur using person segmentation.
    static func applyPortraitBokeh(to image: UIImage, blurSigma: Double = 10.0) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = .balanced
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    guard let maskBuffer = request.results?.first?.pixelBuffer else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let ciContext = Self.sharedCIContext
                    let originalCI = CIImage(cgImage: cgImage)
                    let maskCI = CIImage(cvPixelBuffer: maskBuffer)
                    let scaleX = originalCI.extent.width / maskCI.extent.width
                    let scaleY = originalCI.extent.height / maskCI.extent.height
                    let scaledMask = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

                    let blurredBG = originalCI
                        .clampedToExtent()
                        .applyingGaussianBlur(sigma: max(2.0, min(24.0, blurSigma)))
                        .cropped(to: originalCI.extent)

                    guard let blend = CIFilter(name: "CIBlendWithMask") else {
                        continuation.resume(returning: nil)
                        return
                    }
                    blend.setValue(originalCI, forKey: kCIInputImageKey)
                    blend.setValue(blurredBG, forKey: kCIInputBackgroundImageKey)
                    blend.setValue(scaledMask, forKey: kCIInputMaskImageKey)

                    guard let output = blend.outputImage,
                          let resultCG = ciContext.createCGImage(output, from: originalCI.extent) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: UIImage(cgImage: resultCG, scale: image.scale, orientation: image.imageOrientation))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
