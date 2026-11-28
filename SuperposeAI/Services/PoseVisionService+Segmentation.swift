import CoreImage
import CoreVideo

extension PoseVisionService {
    nonisolated func renderFocusPeakingMask(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let scaled = CIImage(cvPixelBuffer: pixelBuffer)
            .transformed(by: CGAffineTransform(scaleX: 0.35, y: 0.35))
        guard let edges = CIFilter(name: "CIEdges") else { return nil }
        edges.setValue(scaled, forKey: kCIInputImageKey)
        edges.setValue(4.0, forKey: kCIInputIntensityKey)
        guard let edgeOut = edges.outputImage else { return nil }

        guard let contrast = CIFilter(name: "CIColorControls") else { return nil }
        contrast.setValue(edgeOut, forKey: kCIInputImageKey)
        contrast.setValue(2.0, forKey: kCIInputContrastKey)
        contrast.setValue(-0.25, forKey: kCIInputBrightnessKey)
        contrast.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let contrastOut = contrast.outputImage else { return nil }

        guard let alphaMask = CIFilter(name: "CIMaskToAlpha") else { return nil }
        alphaMask.setValue(contrastOut, forKey: kCIInputImageKey)
        guard let finalCI = alphaMask.outputImage else { return nil }

        return Self.sharedCIContext.createCGImage(finalCI, from: scaled.extent)
    }
}
