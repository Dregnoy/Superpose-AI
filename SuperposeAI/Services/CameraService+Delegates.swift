import AVFoundation
import UIKit

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor [weak self] in
            self?.onVideoFrame?(pixelBuffer)
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let isRaw = photo.isRawPhoto
        let data = photo.fileDataRepresentation()
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.pendingPhotoError = error
                return
            }
            if self.expectedBracketCount > 0 {
                if let data, let image = UIImage(data: data) {
                    self.pendingBracketImages.append(image)
                }
                return
            }
            if isRaw {
                self.pendingRawDNGData = data
            } else if let data, let image = UIImage(data: data) {
                self.pendingProcessedImage = image
            }
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.expectedBracketCount > 0 {
                let images = self.pendingBracketImages
                let err = error ?? self.pendingPhotoError
                let cont = self.bracketContinuation
                self.pendingBracketImages = []
                self.pendingPhotoError = nil
                self.expectedBracketCount = 0
                self.bracketContinuation = nil
                if let err {
                    cont?.resume(throwing: err)
                } else if images.isEmpty {
                    cont?.resume(throwing: CameraError.captureFailed)
                } else {
                    cont?.resume(returning: PhotoEnhancerService.fuseExposureBracket(images))
                }
                return
            }

            defer {
                self.pendingProcessedImage = nil
                self.pendingRawDNGData = nil
                self.pendingPhotoError = nil
                self.photoContinuation = nil
            }
            if let err = error ?? self.pendingPhotoError {
                self.photoContinuation?.resume(throwing: err)
                return
            }
            guard let image = self.pendingProcessedImage else {
                self.photoContinuation?.resume(throwing: CameraError.captureFailed)
                return
            }
            self.photoContinuation?.resume(returning: (image, self.pendingRawDNGData))
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRecording = false
            if let error {
                self.videoContinuation?.resume(throwing: error)
            } else {
                self.videoContinuation?.resume(returning: outputFileURL)
            }
            self.videoContinuation = nil
        }
    }
}
