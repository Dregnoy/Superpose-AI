@preconcurrency import AVFoundation
import UIKit

extension CameraService {
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
                    device.exposureMode = lock ? .locked : .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                // Ignore if device is busy
            }
        }
    }

    nonisolated func enableContinuousAutoFocus(on device: AVCaptureDevice) {
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
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
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

    func lockWhiteBalanceForVideo() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.sessionState.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                }
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
        switch flashMode {
        case .auto: flashMode = .on
        case .on: flashMode = .off
        case .off: flashMode = .auto
        @unknown default: flashMode = .auto
        }
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
}
