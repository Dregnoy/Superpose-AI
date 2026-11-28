import SwiftUI
import AVFoundation

// MARK: - UIKit AVCaptureVideoPreviewLayer Bridge

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.updatePreviewOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        uiView.updatePreviewOrientation()
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            updatePreviewOrientation()
        }

        func updatePreviewOrientation() {
            guard let connection = previewLayer.connection,
                  let scene = window?.windowScene ?? (UIApplication.shared.connectedScenes.first as? UIWindowScene) else {
                return
            }
            let angle: CGFloat = {
                switch scene.interfaceOrientation {
                case .portrait: return 90
                case .portraitUpsideDown: return 270
                case .landscapeLeft: return 180
                case .landscapeRight: return 0
                default: return 90
                }
            }()
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}

