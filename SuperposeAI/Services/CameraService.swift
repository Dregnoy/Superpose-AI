@preconcurrency import AVFoundation
import UIKit

@MainActor
@Observable
final class CameraService: NSObject, CameraServicing {
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
    var flashMode: AVCaptureDevice.FlashMode = .auto
    var zoomFactor: CGFloat = 1.0
    var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    var lastError: CameraError?
    var isSessionRunning = false
    var isRecording = false
    var isRAWEnabled = false
    var isRAWSupported = false
    var isAppleProRAWSupported = false
    var isHDRBracketingEnabled = false
    var is4KVideoEnabled: Bool = false

    final class SessionQueueState: @unchecked Sendable {
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

    @ObservationIgnored nonisolated let sessionQueue = DispatchQueue(label: "com.superposelabs.camera.session")
    @ObservationIgnored nonisolated private let videoQueue = DispatchQueue(label: "com.superposelabs.camera.video")
    @ObservationIgnored nonisolated let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored nonisolated let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored nonisolated let movieOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored nonisolated let sessionState = SessionQueueState()
    @ObservationIgnored var lastFaceFocusTime: CFAbsoluteTime = 0
    @ObservationIgnored var lastFaceFocusCenter: CGPoint = .zero
    @ObservationIgnored var photoContinuation: CheckedContinuation<(UIImage, Data?), Error>?
    @ObservationIgnored var pendingProcessedImage: UIImage?
    @ObservationIgnored var pendingRawDNGData: Data?
    @ObservationIgnored var pendingPhotoError: Error?
    @ObservationIgnored var bracketContinuation: CheckedContinuation<UIImage, Error>?
    @ObservationIgnored var pendingBracketImages: [UIImage] = []
    @ObservationIgnored var expectedBracketCount: Int = 0
    @ObservationIgnored var videoContinuation: CheckedContinuation<URL, Error>?

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

    nonisolated func configureSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.automaticallyConfiguresCaptureDeviceForWideColor = true

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
        photoOutput.maxPhotoQualityPrioritization = .quality
        if photoOutput.isAutoVirtualDeviceFusionSupported {
            photoOutput.isAutoVirtualDeviceFusionEnabled = true
        }
        if photoOutput.isResponsiveCaptureSupported {
            photoOutput.isResponsiveCaptureEnabled = true
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
