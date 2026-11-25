import AVFoundation
import SwiftUI
import UIKit

struct BarcodeScannerSheet: View {
    let onScanned: (String) -> Void
    let onDismiss: () -> Void

    @State private var torchEnabled = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScannerCameraRepresentable(
                    torchEnabled: torchEnabled,
                    onCodeDetected: onScanned,
                    onStatusMessage: { msg in
                        statusMessage = msg
                    }
                )
                .ignoresSafeArea()

                // Targeting reticle overlay
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(BluePadTheme.accentCyan, lineWidth: 2.5)
                        .frame(width: 250, height: 250)
                        .background(Color.clear)
                    Spacer()

                    Text(statusMessage ?? "QR kodu veya barkodu çerçevenin içine hizalayın")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .padding(.bottom, 30)
                }
            }
            .navigationTitle("QR & Barkod Tarayıcı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat", action: onDismiss)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        torchEnabled.toggle()
                    } label: {
                        Image(systemName: torchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                }
            }
        }
    }
}

private struct ScannerCameraRepresentable: UIViewControllerRepresentable {
    var torchEnabled: Bool
    var onCodeDetected: (String) -> Void
    var onStatusMessage: (String?) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onCodeDetected = onCodeDetected
        vc.onStatusMessage = onStatusMessage
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        uiViewController.onCodeDetected = onCodeDetected
        uiViewController.onStatusMessage = onStatusMessage
        uiViewController.setTorch(enabled: torchEnabled)
    }
}

final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeDetected: ((String) -> Void)?
    var onStatusMessage: ((String?) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.bluepad.scanner.session")
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastEmitTime: Date = .distantPast
    private var isConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkPermissionAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    func setTorch(enabled: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Ignore torch errors on devices where unavailable.
        }
    }

    private func checkPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.onStatusMessage?("Kamera izni verilmedi. Ayarlar'dan izin verin.")
                    }
                }
            }
        default:
            DispatchQueue.main.async { [weak self] in
                self?.onStatusMessage?("Kamera erişimi kısıtlı veya reddedilmiş.")
            }
        }
    }

    private func configureSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async { [weak self] in
                self?.onStatusMessage?("Bu cihazda veya Simülatörde kamera bulunamadı.")
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                let wanted: [AVMetadataObject.ObjectType] = [
                    .qr, .ean13, .ean8, .code128, .code39, .pdf417, .dataMatrix, .aztec
                ]
                metadataOutput.metadataObjectTypes = wanted.filter {
                    metadataOutput.availableMetadataObjectTypes.contains($0)
                }
            }

            let layer = AVCaptureVideoPreviewLayer(session: captureSession)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            self.previewLayer = layer
            self.isConfigured = true

            sessionQueue.async { [weak self] in
                self?.captureSession.startRunning()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onStatusMessage?("Kamera başlatılamadı: \(error.localizedDescription)")
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard Date().timeIntervalSince(lastEmitTime) > 1.5,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = readable.stringValue,
              !code.isEmpty else {
            return
        }
        lastEmitTime = Date()
        onCodeDetected?(code)
    }
}
