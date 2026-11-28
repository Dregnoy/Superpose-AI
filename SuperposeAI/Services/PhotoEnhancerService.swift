import CoreImage
import Metal
import UIKit
import Vision

/// One-tap visual look presets for Simple Mode and post-capture styling.
enum PhotoLookPreset: String, CaseIterable, Identifiable {
    case natural = "Doğal"
    case cinematic = "Sinematik"
    case goldenHour = "Altın Saat"
    case monochrome = "Siyah-Beyaz"

    var id: String { rawValue }

    var next: PhotoLookPreset {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .natural }
        return all[(idx + 1) % all.count]
    }
}

/// Applies subtle, natural on-device shadow/highlight recovery, vibrance,
/// and luminance sharpening using CoreImage—zero cloud upload.
enum PhotoEnhancerService {
    static let context: CIContext = {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let options: [CIContextOption: Any] = [
            .workingColorSpace: p3,
            .outputColorSpace: p3
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: options)
        }
        return CIContext(options: options)
    }()

    static func applyLook(_ preset: PhotoLookPreset, to image: UIImage) -> UIImage {
        guard preset != .natural else { return image }
        guard let cgImage = image.cgImage else { return image }
        var current = CIImage(cgImage: cgImage)

        switch preset {
        case .natural:
            return image
        case .cinematic:
            if let vibrance = CIFilter(name: "CIVibrance") {
                vibrance.setValue(current, forKey: kCIInputImageKey)
                vibrance.setValue(-0.12, forKey: "inputAmount")
                if let out = vibrance.outputImage { current = out }
            }
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(current, forKey: kCIInputImageKey)
                controls.setValue(1.12, forKey: kCIInputContrastKey)
                controls.setValue(-0.02, forKey: kCIInputBrightnessKey)
                if let out = controls.outputImage { current = out }
            }
        case .goldenHour:
            if let temp = CIFilter(name: "CITemperatureAndTint") {
                temp.setValue(current, forKey: kCIInputImageKey)
                temp.setValue(CIVector(x: 6800, y: 0), forKey: "inputNeutral")
                temp.setValue(CIVector(x: 5400, y: 0), forKey: "inputTargetNeutral")
                if let out = temp.outputImage { current = out }
            }
            if let vibrance = CIFilter(name: "CIVibrance") {
                vibrance.setValue(current, forKey: kCIInputImageKey)
                vibrance.setValue(0.20, forKey: "inputAmount")
                if let out = vibrance.outputImage { current = out }
            }
        case .monochrome:
            if let mono = CIFilter(name: "CIPhotoEffectNoir") {
                mono.setValue(current, forKey: kCIInputImageKey)
                if let out = mono.outputImage { current = out }
            }
        }

        guard let outputCG = context.createCGImage(current, from: current.extent) else {
            return image
        }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }

    /// One-Tap Magic ("Tek Vuruşluk Büyü"): filmic highlight roll-off, shadow denoise,
    /// skin-safe vibrance, and halo-free micro-detail on Display P3 GPU.
    static func applyOneTapMagic(_ image: UIImage, lumaHint: Double = 0.5) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        var current = CIImage(cgImage: cgImage)

        // 1. Clean shadow chroma noise before any detail/contrast boost
        if let denoise = CIFilter(name: "CINoiseReduction") {
            denoise.setValue(current, forKey: kCIInputImageKey)
            denoise.setValue(lumaHint < 0.35 ? 0.025 : 0.012, forKey: "inputNoiseLevel")
            denoise.setValue(0.40, forKey: "inputSharpness")
            if let out = denoise.outputImage { current = out }
        }

        // 2. Highlight protection + natural shadow recovery
        let shadowLift = lumaHint < 0.35 ? 0.34 : 0.24
        let highlightProtect = lumaHint > 0.72 ? 0.80 : 0.87
        if let shadowHighlight = CIFilter(name: "CIHighlightShadowAdjust") {
            shadowHighlight.setValue(current, forKey: kCIInputImageKey)
            shadowHighlight.setValue(shadowLift, forKey: "inputShadowAmount")
            shadowHighlight.setValue(highlightProtect, forKey: "inputHighlightAmount")
            if let out = shadowHighlight.outputImage { current = out }
        }

        // 3. Subtle filmic S-curve for creamy highlights and rich midtone depth
        if let toneCurve = CIFilter(name: "CIToneCurve") {
            toneCurve.setValue(current, forKey: kCIInputImageKey)
            toneCurve.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")
            toneCurve.setValue(CIVector(x: 0.25, y: 0.23), forKey: "inputPoint1")
            toneCurve.setValue(CIVector(x: 0.50, y: 0.51), forKey: "inputPoint2")
            toneCurve.setValue(CIVector(x: 0.75, y: 0.77), forKey: "inputPoint3")
            toneCurve.setValue(CIVector(x: 1.0, y: 0.99), forKey: "inputPoint4")
            if let out = toneCurve.outputImage { current = out }
        }

        // 4. Skin-preserving natural color richness
        if let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(current, forKey: kCIInputImageKey)
            vibrance.setValue(0.14, forKey: "inputAmount")
            if let out = vibrance.outputImage { current = out }
        }

        // 5. Halo-free optical micro-detail
        if let unsharp = CIFilter(name: "CIUnsharpMask") {
            unsharp.setValue(current, forKey: kCIInputImageKey)
            unsharp.setValue(1.4, forKey: kCIInputRadiusKey)
            unsharp.setValue(0.28, forKey: kCIInputIntensityKey)
            if let out = unsharp.outputImage { current = out }
        }

        guard let outputCG = context.createCGImage(current, from: current.extent) else {
            return image
        }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }

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

    /// Develops a 12-bit/16-bit DNG RAW buffer on-device using Apple's `CIRAWFilter`
    /// with balanced highlight/shadow recovery and luminance noise reduction.
    static func developRAW(_ dngData: Data) -> UIImage? {
        guard !dngData.isEmpty, let rawFilter = CIRAWFilter(imageData: dngData) else { return nil }
        if rawFilter.responds(to: NSSelectorFromString("setBoostAmount:")) {
            rawFilter.boostAmount = 0.65
        }
        if rawFilter.responds(to: NSSelectorFromString("setBoostShadowAmount:")) {
            rawFilter.boostShadowAmount = 0.45
        }
        if rawFilter.responds(to: NSSelectorFromString("setLuminanceNoiseReductionAmount:")) {
            rawFilter.luminanceNoiseReductionAmount = 0.35
        }
        if rawFilter.responds(to: NSSelectorFromString("setColorNoiseReductionAmount:")) {
            rawFilter.colorNoiseReductionAmount = 0.45
        }
        if rawFilter.responds(to: NSSelectorFromString("setSharpnessAmount:")) {
            rawFilter.sharpnessAmount = 0.35
        }

        guard var ciImage = rawFilter.outputImage else { return nil }
        if let shadowHighlight = CIFilter(name: "CIHighlightShadowAdjust") {
            shadowHighlight.setValue(ciImage, forKey: kCIInputImageKey)
            shadowHighlight.setValue(0.18, forKey: "inputShadowAmount")
            shadowHighlight.setValue(0.90, forKey: "inputHighlightAmount")
            if let out = shadowHighlight.outputImage { ciImage = out }
        }

        guard let outputCG = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: outputCG)
    }

    /// Fuses bracketed exposure frames (-1 EV, 0 EV, +1 EV) on-device to expand
    /// dynamic range on devices without Apple ProRAW (e.g. iPhone 11).
    static func fuseExposureBracket(_ images: [UIImage]) -> UIImage {
        guard let base = images.first else { return UIImage() }
        guard images.count > 1 else { return naturalizeAndSharpen(base) }

        guard let referenceCG = base.cgImage else { return base }
        let ciImages = images.compactMap { img -> CIImage? in
            guard let cg = img.cgImage else { return nil }
            return CIImage(cgImage: cg)
        }
        guard var blended = ciImages.first else { return base }
        let baseExtent = blended.extent

        for (index, nextImage) in ciImages.dropFirst().enumerated() {
            var alignedNext = nextImage
            if let nextCG = images.dropFirst().dropFirst(index).first?.cgImage {
                let regRequest = VNTranslationalImageRegistrationRequest(targetedCGImage: nextCG)
                let handler = VNImageRequestHandler(cgImage: referenceCG, options: [:])
                if (try? handler.perform([regRequest])) != nil,
                   let observation = regRequest.results?.first {
                    let tx = observation.alignmentTransform.tx
                    let ty = observation.alignmentTransform.ty
                    if abs(tx) < baseExtent.width * 0.12 && abs(ty) < baseExtent.height * 0.12 {
                        alignedNext = nextImage
                            .transformed(by: CGAffineTransform(translationX: -tx, y: -ty))
                            .cropped(to: baseExtent)
                    }
                }
            }

            let alpha = CGFloat(1.0 / Double(index + 2))
            guard let alphaFilter = CIFilter(name: "CIColorMatrix") else { continue }
            alphaFilter.setValue(alignedNext, forKey: kCIInputImageKey)
            alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: alpha), forKey: "inputAVector")
            guard let weighted = alphaFilter.outputImage,
                  let composite = CIFilter(name: "CISourceOverCompositing") else { continue }
            composite.setValue(weighted, forKey: kCIInputImageKey)
            composite.setValue(blended, forKey: kCIInputBackgroundImageKey)
            if let out = composite.outputImage {
                blended = out
            }
        }

        if let shadowHighlight = CIFilter(name: "CIHighlightShadowAdjust") {
            shadowHighlight.setValue(blended, forKey: kCIInputImageKey)
            shadowHighlight.setValue(0.28, forKey: "inputShadowAmount")
            shadowHighlight.setValue(0.88, forKey: "inputHighlightAmount")
            if let out = shadowHighlight.outputImage { blended = out }
        }

        if let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(blended, forKey: kCIInputImageKey)
            vibrance.setValue(0.12, forKey: "inputAmount")
            if let out = vibrance.outputImage { blended = out }
        }

        guard let outputCG = context.createCGImage(blended, from: blended.extent) else {
            return base
        }
        return UIImage(cgImage: outputCG, scale: base.scale, orientation: base.imageOrientation)
    }
}
