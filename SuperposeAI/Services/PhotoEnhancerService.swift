import CoreImage
import UIKit

/// Applies subtle, natural on-device shadow/highlight recovery, vibrance,
/// and luminance sharpening using CoreImage—zero cloud upload.
enum PhotoEnhancerService {
    private static let context = CIContext()

    static func naturalizeAndSharpen(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        var current = CIImage(cgImage: cgImage)

        // 1. Subtle shadow lift & highlight recovery for natural dynamic range
        if let shadowHighlight = CIFilter(name: "CIHighlightShadowAdjust") {
            shadowHighlight.setValue(current, forKey: kCIInputImageKey)
            shadowHighlight.setValue(0.24, forKey: "inputShadowAmount")
            shadowHighlight.setValue(0.92, forKey: "inputHighlightAmount")
            if let out = shadowHighlight.outputImage { current = out }
        }

        // 2. Gentle natural vibrance (preserves skin tones)
        if let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(current, forKey: kCIInputImageKey)
            vibrance.setValue(0.14, forKey: "inputAmount")
            if let out = vibrance.outputImage { current = out }
        }

        // 3. Luminance-only sharpening (crisp eyes/hair without color noise)
        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(current, forKey: kCIInputImageKey)
            sharpen.setValue(0.45, forKey: kCIInputSharpnessKey)
            if let out = sharpen.outputImage { current = out }
        }

        guard let outputCG = context.createCGImage(current, from: current.extent) else {
            return image
        }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }
}
