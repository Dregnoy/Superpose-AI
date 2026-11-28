@preconcurrency import AVFoundation
import UIKit

@MainActor
@Observable
final class CameraService: NSObject {
    enum CameraError: LocalizedError {
        case unauthorized
        case configurationFailed
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Camera access is required for real-time pose coaching."
            case .configurationFailed:
                return "Unable to configure the camera session."
            case .captureFailed:
                return "Failed to capture photo."
            }
        }
    }

    nonisolated let session = AVCaptureSession()
    var cameraPosition: AVCaptureDevice.Position = .back
    var flashMode: AVCaptureDevice.FlashMode = .off
    var zoomFactor: CGFloat = 1.0
    var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    var lastError: CameraError?
    var isSessionRunning = false
    var isRecording = false
    var isRAWEnabled = false
    var isRAWSupported = false
    var isAppleProRAWSupported = false
    var isHDRBracketingEnabled = false

    private final class SessionQueueState: @unchecked Sendable {
        private let lock = NSLock()
        private var _currentInput: AVCaptureDeviceInput?
        private var _isFocusLockedByUser = false
        private var _subjectAreaObserver: NSObjectProtocol?

        var currentInput: AVCaptureDeviceInput? {
            get { lock.withLock { _currentInput } }
            set { lock.withLock { _currentInput = newValue } }
        }

        var isFocusLockedByUser: Bool {
            get { lock.withLock { _isFocusLockedByUser } }
            set { lock.withLock { _isFocusLockedByUser = newValue } }
        }

        var subjectAreaObserver: NSObjectProtocol? {
            get { lock.withLock { _subjectAreaObserver } }
            set { lock.withLock { _subjectAreaObserver = newValue } }
        }
    }

    @ObservationIgnored nonisolated private let sessionQueue = DispatchQueue(label: "com.superposelabs.camera.session")
    @ObservationIgnored nonisolated private let videoQueue = DispatchQueue(label: "com.superposelabs.camera.video")
    @ObservationIgnored nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored nonisolated private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored nonisolated private let movieOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored nonisolated private let sessionState = SessionQueueState()
    @ObservationIgnored private var lastFaceFocusTime: CFAbsoluteTime = 0
    @ObservationIgnored private var lastFaceFocusCenter: CGPoint = .zero
    @ObservationIgnored private var photoContinuation: CheckedContinuation<(UIImage, Data?), Error>?
    @ObservationIgnored private var pendingProcessedImage: UIImage?
    @ObservationIgnored private var pendingRawDNGData: Data?
    @ObservationIgnored private var pendingPhotoError: Error?
    @ObservationIgnored private var bracketContinuation: CheckedContinuation<UIImage, Error>?
    @ObservationIgnored private var pendingBracketImages: [UIImage] = []
    @ObservationIgnored private var expectedBracketCount: Int = 0
    @ObservationIgnored private var videoContinuation: CheckedContinuation<URL, Error>?

    var onVideoFrame: ((CVPixelBuffer) -> Void)?

    func checkAndRequestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            return granted
        default:
            lastError = .unauthorized
            return false
        }
    }

    func startSession() {
        let position = cameraPosition
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.inputs.isEmpty {
                if !self.session.isRunning {
                    self.session.startRunning()
                    Task { @MainActor [weak self] in self?.isSessionRunning = true }
                }
                return
            }

            self.configureSession(position: position)
            self.session.startRunning()
            Task { @MainActor [weak self] in self?.isSessionRunning = true }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor [weak self] in self?.isSessionRunning = false }
        }
    }

    func toggleCamera() {
        let nextPosition: AVCaptureDevice.Position = (cameraPosition == .back) ? .front : .back
        cameraPosition = nextPosition
        zoomFactor = 1.0
        sessionQueue.async { [weak self] in
            self?.configureSession(position: nextPosition)
        }
    }

    func setZoom(_ factor: CGFloat) {
        zoomFactor = factor
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minAvailableVideoZoomFactor, min(factor, min(device.maxAvailableVideoZoomFactor, 5.0)))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                // Ignore if device is busy
            }
        }
    }

    func focusAndExpose(at normalizedPoint: CGPoint, lock: Bool = false) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device else { return }
            self.sessionState.isFocusLockedByUser = lock
            do {
                try device.lockForConfiguration()
                device.isSubjectAreaChangeMonitoringEnabled = !lock
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = normalizedPoint
                    device.focusMode = lock ? .locked : .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = normalizedPoint
                    device.exposureMode = lock ? .locked : .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                // Ignore if device is busy
            }
        }
    }

    nonisolated private func enableContinuousAutoFocus(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.isSubjectAreaChangeMonitoringEnabled = true
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            // Ignore if device is busy
        }
    }

    func trackFaceFocusIfUnlocked(normalizedFaceBox: CGRect, isProMode: Bool) {
        guard !isProMode, !sessionState.isFocusLockedByUser else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFaceFocusTime >= 0.8 else { return }

        let center = CGPoint(x: normalizedFaceBox.midX, y: normalizedFaceBox.midY)
        guard hypot(center.x - lastFaceFocusCenter.x, center.y - lastFaceFocusCenter.y) >= 0.06 else { return }

        lastFaceFocusTime = now
        lastFaceFocusCenter = center
        let devicePoint = CGPoint(
            x: max(0.0, min(1.0, center.y)),
            y: max(0.0, min(1.0, cameraPosition == .front ? center.x : (1.0 - center.x)))
        )

        sessionQueue.async { [weak self] in
            guard let self, !self.sessionState.isFocusLockedByUser, let device = self.sessionState.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setManualFocus(_ lensPosition: Float) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device,
                  device.isLockingFocusWithCustomLensPositionSupported else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(0.0, min(1.0, lensPosition))
                device.setFocusModeLocked(lensPosition: clamped)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setManualISO(_ isoNormalized: Float) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let minISO = device.activeFormat.minISO
                let maxISO = min(device.activeFormat.maxISO, 1600)
                let targetISO = minISO + (maxISO - minISO) * max(0.0, min(1.0, isoNormalized))
                device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: targetISO)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setManualShutter(seconds: Double) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let minDur = device.activeFormat.minExposureDuration
                let maxDur = min(device.activeFormat.maxExposureDuration, CMTimeMakeWithSeconds(0.5, preferredTimescale: 1000))
                let target = CMTimeMakeWithSeconds(seconds, preferredTimescale: 1000)
                let clamped = max(minDur, min(target, maxDur))
                device.setExposureModeCustom(duration: clamped, iso: AVCaptureDevice.currentISO)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setManualExposure(isoNormalized: Float, shutterSeconds: Double) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let minISO = device.activeFormat.minISO
                let maxISO = min(device.activeFormat.maxISO, 1600)
                let targetISO = minISO + (maxISO - minISO) * max(0.0, min(1.0, isoNormalized))
                let minDur = device.activeFormat.minExposureDuration
                let maxDur = min(device.activeFormat.maxExposureDuration, CMTimeMakeWithSeconds(0.5, preferredTimescale: 1000))
                let target = CMTimeMakeWithSeconds(shutterSeconds, preferredTimescale: 1000)
                let clampedDur = max(minDur, min(target, maxDur))
                device.setExposureModeCustom(duration: clampedDur, iso: targetISO)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setWhiteBalanceKelvin(_ kelvin: Float) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device,
                  device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
            do {
                try device.lockForConfiguration()
                let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: kelvin, tint: 0)
                var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                let maxGain = device.maxWhiteBalanceGain
                gains.redGain = max(1.0, min(gains.redGain, maxGain))
                gains.greenGain = max(1.0, min(gains.greenGain, maxGain))
                gains.blueGain = max(1.0, min(gains.blueGain, maxGain))
                device.setWhiteBalanceModeLocked(with: gains)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func resetProControls() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
                device.setExposureTargetBias(0.0)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setExposureBias(_ bias: Float) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minExposureTargetBias, min(bias, device.maxExposureTargetBias))
                device.setExposureTargetBias(clamped)
                device.unlockForConfiguration()
            } catch {
                // Ignore if device is busy
            }
        }
    }

    func toggleFlash() {
        flashMode = (flashMode == .off) ? .on : .off
    }

    func updateOrientation(to interfaceOrientation: UIInterfaceOrientation) {
        let angle: CGFloat = {
            switch interfaceOrientation {
            case .portrait: return 90
            case .portraitUpsideDown: return 270
            case .landscapeLeft: return 180
            case .landscapeRight: return 0
            default: return 90
            }
        }()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let videoConn = self.videoOutput.connection(with: .video),
               videoConn.isVideoRotationAngleSupported(angle) {
                videoConn.videoRotationAngle = angle
            }
            if let photoConn = self.photoOutput.connection(with: .video),
               photoConn.isVideoRotationAngleSupported(angle) {
                photoConn.videoRotationAngle = angle
            }
            if let movieConn = self.movieOutput.connection(with: .video),
               movieConn.isVideoRotationAngleSupported(angle) {
                movieConn.videoRotationAngle = angle
            }
        }
    }

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

    var is4KVideoEnabled: Bool = false

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
                    settings = AVCapturePhotoSettings()
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

    nonisolated private func configureSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let currentInput = sessionState.currentInput {
            session.removeInput(currentInput)
            sessionState.currentInput = nil
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            Task { @MainActor [weak self] in self?.lastError = .configurationFailed }
            return
        }

        session.addInput(input)
        sessionState.currentInput = input
        sessionState.isFocusLockedByUser = false
        enableContinuousAutoFocus(on: device)

        if sessionState.subjectAreaObserver == nil {
            sessionState.subjectAreaObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.sessionQueue.async { [weak self] in
                    guard let self, !self.sessionState.isFocusLockedByUser, let activeDevice = self.sessionState.currentInput?.device else { return }
                    self.enableContinuousAutoFocus(on: activeDevice)
                }
            }
        }

        if !session.outputs.contains(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (position == .front)
            }
        }

        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        if photoOutput.isAppleProRAWSupported {
            photoOutput.isAppleProRAWEnabled = true
        }
        session.commitConfiguration()
        let proRAWSupported = photoOutput.isAppleProRAWSupported
        let rawSupported = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        Task { @MainActor [weak self] in
            self?.isAppleProRAWSupported = proRAWSupported
            self?.isRAWSupported = rawSupported
            if !rawSupported { self?.isRAWEnabled = false }
        }
    }
}

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
