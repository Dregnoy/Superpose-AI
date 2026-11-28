import CoreImage
import CoreML
import CoreVideo
import UIKit
import Vision

struct AestheticScoreReport: Equatable, Sendable {
    let overallScore: Double      // 0...100
    let lightingScore: Double     // 0...100
    let compositionScore: Double  // 0...100
    let sharpnessScore: Double    // 0...100
    let usedCoreMLModel: Bool

    var outOfTenText: String {
        String(format: "%.1f/10", max(0.0, min(10.0, overallScore / 10.0)))
    }

    var verdict: String {
        switch overallScore {
        case 85...: return "Stüdyo Kalitesi"
        case 72..<85: return "Çok İyi Kare"
        case 58..<72: return "İyi Denge"
        default: return "Geliştirilebilir"
        }
    }
}

/// On-device Aesthetic Scoring Engine.
/// Uses a CoreML `SuperposeAesthetic.mlmodelc` model if bundled, and seamlessly
/// combines CoreImage luminance/contrast, sharpness, and rule-of-thirds balance.
enum AestheticScoringService {
    private static let sharedContext = PhotoEnhancerService.context

    static func evaluate(
        image: UIImage,
        poseMatchScore: Int? = nil,
        subjectCenter: CGPoint? = nil
    ) -> AestheticScoreReport {
        let lighting = scoreLighting(image: image)
        let sharpness = scoreSharpness(image: image)
        let composition = scoreComposition(poseMatchScore: poseMatchScore, subjectCenter: subjectCenter)

        if let mlScore = predictWithBundledCoreML(image: image) {
            let blended = (mlScore * 0.55) + (lighting * 0.15) + (composition * 0.15) + (sharpness * 0.15)
            return AestheticScoreReport(
                overallScore: max(0, min(100, blended)),
                lightingScore: lighting,
                compositionScore: composition,
                sharpnessScore: sharpness,
                usedCoreMLModel: true
            )
        }

        let weighted = (lighting * 0.34) + (composition * 0.36) + (sharpness * 0.30)
        return AestheticScoreReport(
            overallScore: max(0, min(100, weighted)),
            lightingScore: lighting,
            compositionScore: composition,
            sharpnessScore: sharpness,
            usedCoreMLModel: false
        )
    }

    /// Attempts to load `SuperposeAesthetic.mlmodelc` from the main bundle if present.
    private static func predictWithBundledCoreML(image: UIImage) -> Double? {
        guard let modelURL = Bundle.main.url(forResource: "SuperposeAesthetic", withExtension: "mlmodelc"),
              let mlModel = try? MLModel(contentsOf: modelURL),
              let cgImage = image.cgImage else {
            return nil
        }

        let targetSize = CGSize(width: 224, height: 224)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let resizedCG = resized.cgImage,
              let imageFeature = try? MLFeatureValue(cgImage: resizedCG, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32BGRA),
              let input = try? MLDictionaryFeatureProvider(dictionary: ["image": imageFeature]),
              let output = try? mlModel.prediction(from: input),
              let score = output.featureValue(for: "aestheticScore")?.doubleValue else {
            return nil
        }
        return score <= 1.0 ? score * 100.0 : score
    }

    static func scoreLighting(image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 68.0 }
        let ciImage = CIImage(cgImage: cgImage)
        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 68.0 }
        avgFilter.setValue(ciImage, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        guard let out = avgFilter.outputImage else { return 68.0 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        sharedContext.render(
            out,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let luma = (0.299 * Double(bitmap[0]) + 0.587 * Double(bitmap[1]) + 0.114 * Double(bitmap[2])) / 255.0
        // Sweet spot around 0.45 - 0.65 luma
        let distanceFromIdeal = abs(luma - 0.52)
        let score = 96.0 - (distanceFromIdeal * 135.0)
        return max(30.0, min(98.0, score))
    }

    static func scoreSharpness(image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 70.0 }
        let raw = PoseVisionService.computeSharpnessScore(cgImage: cgImage)
        return max(35.0, min(99.0, raw * 100.0))
    }

    static func scoreComposition(poseMatchScore: Int?, subjectCenter: CGPoint?) -> Double {
        var score = 74.0
        if let poseMatchScore {
            score = (score * 0.35) + (Double(poseMatchScore) * 0.65)
        }
        if let center = subjectCenter {
            // Reward alignment near rule-of-thirds intersections (0.33 / 0.67) or clean center (0.5)
            let thirdsX = min(abs(center.x - 0.33), abs(center.x - 0.67), abs(center.x - 0.5))
            let thirdsY = min(abs(center.y - 0.33), abs(center.y - 0.67))
            let balanceBonus = max(0.0, 14.0 - (thirdsX + thirdsY) * 40.0)
            score += balanceBonus
        }
        return max(40.0, min(99.0, score))
    }
}
