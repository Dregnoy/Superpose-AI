@preconcurrency import AVFoundation
import UIKit

extension CameraService {
    func startVideoRecording() async throws -> URL {
        isRecording = true
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("superpose_\(UUID().uuidString).mov")
        return try await withCheckedThrowingContinuation { continuation in
            self.videoContinuation = continuation
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if let conn = self.movieOutput.connection(with: .video),
                   conn.isVideoStabilizationSupported {
                    conn.preferredVideoStabilizationMode = .cinematic
                }
                self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            }
        }
    }

    func configureCaptureMode(isVideo: Bool, is4K: Bool) {
        is4KVideoEnabled = is4K
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let targetPreset: AVCaptureSession.Preset
            if isVideo {
                if is4K && self.session.canSetSessionPreset(.hd4K3840x2160) {
                    targetPreset = .hd4K3840x2160
                } else if self.session.canSetSessionPreset(.hd1920x1080) {
                    targetPreset = .hd1920x1080
                } else {
                    targetPreset = .high
                }
            } else {
                targetPreset = .photo
            }
            guard self.session.sessionPreset != targetPreset else { return }
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(targetPreset) {
                self.session.sessionPreset = targetPreset
            }
            self.session.commitConfiguration()
        }
    }

    func stopVideoRecording() {
        isRecording = false
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    func capturePhoto() async throws -> UIImage {
        try await capturePhotoWithRAW(preferRAW: false).0
    }

    func capturePhotoWithRAW(preferRAW: Bool) async throws -> (UIImage, Data?) {
        let flash = flashMode
        let wantRAW = preferRAW && isRAWEnabled
        pendingProcessedImage = nil
        pendingRawDNGData = nil
        pendingPhotoError = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            sessionQueue.async { [weak self] in
                guard let self else { return }
                let settings: AVCapturePhotoSettings
                if wantRAW {
                    let rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
                        AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
                    }) ?? self.photoOutput.availableRawPhotoPixelFormatTypes.first
                    if let rawFormat {
                        settings = AVCapturePhotoSettings(
                            rawPixelFormatType: rawFormat,
                            processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg]
                        )
                    } else {
                        settings = AVCapturePhotoSettings()
                    }
                } else {
                    if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                        settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    } else {
                        settings = AVCapturePhotoSettings()
                    }
                    settings.photoQualityPrioritization = .quality
                }
                if self.photoOutput.isAutoRedEyeReductionSupported {
                    settings.isAutoRedEyeReductionEnabled = true
                }
                if self.photoOutput.supportedFlashModes.contains(flash) {
                    settings.flashMode = flash
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    /// Captures a 3-frame exposure bracket (-1 EV, 0 EV, +1 EV) and fuses them
    /// on-device for high dynamic range on devices without Apple ProRAW.
    func captureBracketedHDR() async throws -> UIImage {
        pendingBracketImages = []
        pendingPhotoError = nil
        expectedBracketCount = min(3, max(1, photoOutput.maxBracketedCapturePhotoCount))
        guard expectedBracketCount >= 2 else {
            return try await capturePhoto()
        }

        let bracketCount = expectedBracketCount
        return try await withCheckedThrowingContinuation { continuation in
            self.bracketContinuation = continuation
            sessionQueue.async { [weak self] in
                guard let self else { return }
                let biases: [Float] = [-1.0, 0.0, 1.0].prefix(bracketCount).map { $0 }
                let bracketSettings = biases.map {
                    AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: $0)
                }
                let settings = AVCapturePhotoBracketSettings(
                    rawPixelFormatType: 0,
                    processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg],
                    bracketedSettings: bracketSettings
                )
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}
