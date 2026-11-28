import SwiftUI
import AVFoundation
import PhotosUI
import AudioToolbox

struct CameraView: View {
    @Environment(AppState.self) var appState
    @Environment(LibraryStore.self) var libraryStore
    @Environment(ShotPackStore.self) var shotPackStore
    @Environment(\.verticalSizeClass) var verticalSizeClass

    var isLandscape: Bool { verticalSizeClass == .compact }

    @State var cameraService = CameraService()
    @State var visionService = PoseVisionService()
    @State var voiceCoach = VoiceCoachService()
    @State var voiceShutter = VoiceShutterService()
    @State var volumeShutter = VolumeShutterService()
    @State var horizonService = HorizonLevelService()
    @State var didVibrateForCurrentMatch = false
    @State var didShowHazeHint = false
    @State var isGeneratingPoses = false
    @State var toastMessage: String?
    @State var autoShutterCountdown: Int?
    @State var autoShutterTask: Task<Void, Never>?
    @State var lastAutoShotTime: CFAbsoluteTime = 0
    @State var selectedInspoItem: PhotosPickerItem?
    @State var timerSeconds: Int = 0 // 0, 3, or 10
    @State var intervalSeconds: Int = 0 // 0, 3, or 5 (Time-Lapse)
    @State var intervalTask: Task<Void, Never>?
    @State var intervalShotsCount: Int = 0
    @State var isBurstEnabled: Bool = false
    @State var isVideoMode: Bool = false
    @State var recordingSeconds: Int = 0
    @State var recordingTimerTask: Task<Void, Never>?
    @State var isProMode: Bool = false
    @State var isFocusPeakingEnabled: Bool = false
    @State var isMonochromePreview: Bool = false
    @State var isZenMode: Bool = false
    @State var showToolsDrawer: Bool = false
    @State var isFocusLocked: Bool = false
    @State var lockedJointLabel: String?
    @State var focusPoint: CGPoint?
    @State var exposureBias: Float = 0.0
    @State var manualFocus: Float = 0.5
    @State var manualISO: Float = 0.25
    @State var manualShutter: Double = 0.01 // 1/100s
    @State var manualWB: Float = 5500
    @State var previewingLatestItem: LibraryItem?
    @State var showPoseTemplates: Bool = false
    @State var selectedLook: PhotoLookPreset = .natural
    @State var isOneTapMagicEnabled: Bool = true
    @State var showCalibrationSheet: Bool = false
    @State var watchRemote = WatchRemoteService()

    let poseGenerator = AIPoseGeneratorService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HiddenVolumeViewRepresentable(service: volumeShutter)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)

            if cameraService.authorizationStatus == .authorized {
                GeometryReader { geo in
                    CameraPreviewRepresentable(session: cameraService.session)
                        .saturation(isMonochromePreview ? 0 : 1)
                        .contrast(isMonochromePreview ? 1.08 : 1.0)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            if let (joint, jointLoc) = nearestDetectedJoint(to: location, in: geo.size) {
                                let normalized = CGPoint(
                                    x: max(0, min(1, jointLoc.y / geo.size.height)),
                                    y: max(0, min(1, 1.0 - (jointLoc.x / geo.size.width)))
                                )
                                let label = Self.jointDisplayLabel(joint)
                                isFocusLocked = true
                                lockedJointLabel = label
                                focusPoint = jointLoc
                                cameraService.focusAndExpose(at: normalized, lock: true)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                showToast("Odak kilitlendi: \(label)")
                                return
                            }
                            let normalized = CGPoint(
                                x: max(0, min(1, location.y / geo.size.height)),
                                y: max(0, min(1, 1.0 - (location.x / geo.size.width)))
                            )
                            isFocusLocked = false
                            lockedJointLabel = nil
                            cameraService.focusAndExpose(at: normalized, lock: false)
                            focusPoint = location
                            Task {
                                try? await Task.sleep(for: .seconds(2.2))
                                if focusPoint == location && !isFocusLocked { focusPoint = nil }
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.45) {
                            let center = focusPoint ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let normalized = CGPoint(
                                x: max(0, min(1, center.y / geo.size.height)),
                                y: max(0, min(1, 1.0 - (center.x / geo.size.width)))
                            )
                            isFocusLocked = true
                            focusPoint = center
                            cameraService.focusAndExpose(at: normalized, lock: true)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            showToast("AE/AF Kilitlendi")
                        }
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { value in
                                    guard focusPoint != nil else { return }
                                    let delta = Float(-value.translation.height / 110.0)
                                    let clamped = max(-2.0, min(2.0, delta))
                                    exposureBias = clamped
                                    cameraService.setExposureBias(clamped)
                                }
                        )
                }
                .ignoresSafeArea()
            } else {
                cameraPermissionPlaceholder
            }

            // PRO Focus Peaking Overlay
            if isProMode && isFocusPeakingEnabled && cameraService.cameraPosition == .back,
               let peakingImage = visionService.focusPeakingImage {
                Image(uiImage: peakingImage)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.yellow)
                    .scaledToFill()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(0.80)
            }

            // Focus Reticle + Visible Sun Exposure Track
            if let focusPoint {
                VStack(spacing: 4) {
                    if isFocusLocked {
                        Text(lockedJointLabel ?? "AE/AF KİLİT")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.yellow, lineWidth: isFocusLocked ? 2.2 : 1.5)
                            .frame(width: 64, height: 64)

                        // Visible vertical exposure track
                        ZStack {
                            Capsule()
                                .fill(Color.yellow.opacity(0.45))
                                .frame(width: 2, height: 64)
                            Image(systemName: "sun.max.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .offset(y: CGFloat(-exposureBias / 2.0) * 26.0)
                        }
                    }
                }
                .position(focusPoint)
                .allowsHitTesting(false)
            }

            // Optional 4:5 / 9:16 Social Aspect Guide Mask
            if appState.aspectGuideMode != .full {
                AspectRatioMaskView(mode: appState.aspectGuideMode)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Optional Composition Grid (1/3, Symmetry, Diagonal) + Horizon / Flat-Lay Level
            if appState.gridMode != .off {
                ZStack {
                    CompositionGridView(
                        mode: appState.gridMode,
                        detectedSkeleton: visionService.guidance.detectedSkeleton,
                        isMirrored: cameraService.cameraPosition == .front
                    )
                    if horizonService.isFlatLayOrientation {
                        FlatLayCrosshairView(
                            offsetX: horizonService.flatLayOffsetX,
                            offsetY: horizonService.flatLayOffsetY,
                            isAligned: horizonService.isFlatLayAligned
                        )
                    } else {
                        HorizonLevelIndicatorView(
                            rollDegrees: horizonService.rollDegrees,
                            isLevel: horizonService.isLevel
                        )
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Front Camera Soft Ring Light (when Flash is ON in front camera)
            if cameraService.cameraPosition == .front && cameraService.flashMode == .on {
                RoundedRectangle(cornerRadius: 36)
                    .strokeBorder(Color(red: 1.0, green: 0.96, blue: 0.90).opacity(0.85), lineWidth: 22)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Chronological / Ghost Reference Photo Overlay
            if let refPhoto = appState.pinnedReferencePhoto {
                Image(uiImage: refPhoto)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(x: appState.isOverlayMirrored ? -1 : 1, y: 1)
                    .ignoresSafeArea()
                    .opacity(appState.ghostOpacity)
                    .allowsHitTesting(false)
            }

            // Eye-AF / Face Tracking Bracket
            if let faceBox = visionService.guidance.detectedFaceBox {
                FaceTrackingBoxView(
                    normalizedBox: faceBox,
                    isMirrored: cameraService.cameraPosition == .front,
                    color: visionService.guidance.eyesClosed
                        ? .orange
                        : (visionService.guidance.isGoodSmile ? .green : .cyan.opacity(0.85))
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Pose Outline Overlay
            if let pinned = appState.pinnedPose {
                PoseOverlayView(
                    targetSkeleton: pinned.skeleton,
                    secondaryTargetSkeleton: pinned.secondarySkeleton,
                    liveSkeleton: visionService.guidance.detectedSkeleton,
                    liveSecondarySkeleton: visionService.guidance.detectedSecondarySkeleton,
                    ghostMaskImage: appState.pinnedGhostMask,
                    mode: appState.overlayMode,
                    matchScore: visionService.guidance.poseMatchScore,
                    isNightHud: appState.isNightHudEnabled
                )
                .scaleEffect(x: appState.isOverlayMirrored ? -1 : 1, y: 1)
            }

            // Subtle Eye Blink, Background Line, Face Angle, Contrast, Shake & Couples Balance Alerts
            let showShakeAlert = horizonService.isShaking && (isProMode && manualShutter >= 0.04)
            let showContrastEVButton = (visionService.guidance.lighting == .backlitOrHarsh || visionService.guidance.hazeOrFlareWarning) && exposureBias > -0.4
            if visionService.guidance.eyesClosed || visionService.guidance.backgroundPoleWarning || visionService.guidance.hazeOrFlareWarning || visionService.guidance.couplesBalanceHint != nil || visionService.guidance.faceAngleHint != nil || visionService.guidance.leadRoomHint != nil || visionService.guidance.subjectContrastHint != nil || showShakeAlert || showContrastEVButton {
                VStack(spacing: 6) {
                    Spacer().frame(height: 96)
                    if showShakeAlert {
                        Label("Telefonu sabit tut", systemImage: "hand.raised.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                            .allowsHitTesting(false)
                    }
                    if visionService.guidance.hazeOrFlareWarning {
                        Label("Pus / Flare — Açıyı 10° değiştir", systemImage: "sun.haze.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                            .allowsHitTesting(false)
                    }
                    if showContrastEVButton {
                        Button {
                            exposureBias = -0.7
                            cameraService.setExposureBias(-0.7)
                            showToast("-0.7 EV kontrast koruması uygulandı")
                        } label: {
                            Label("-0.7 EV Kontrast Koru", systemImage: "minus.circle.fill")
                                .font(.caption2.bold())
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Color.yellow, in: Capsule())
                                .foregroundStyle(.black)
                        }
                    }
                    if visionService.guidance.eyesClosed {
                        Label("Gözler Kapalı", systemImage: "eye.slash")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.85), in: Capsule())
                            .foregroundStyle(.black)
                            .allowsHitTesting(false)
                    }
                    if visionService.guidance.backgroundPoleWarning {
                        Label("Baş arkasında çizgi var", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.yellow.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                            .allowsHitTesting(false)
                    }
                    if let contrastHint = visionService.guidance.subjectContrastHint {
                        Label(contrastHint, systemImage: "circle.lefthalf.filled")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.purple.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                            .allowsHitTesting(false)
                    }
                    if let leadHint = visionService.guidance.leadRoomHint {
                        Label(leadHint, systemImage: "arrow.left.and.right")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.cyan.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                            .allowsHitTesting(false)
                    }
                    if let faceHint = visionService.guidance.faceAngleHint {
                        Label(faceHint, systemImage: "face.smiling")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.mint.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                            .allowsHitTesting(false)
                    }
                    if let hint = visionService.guidance.couplesBalanceHint {
                        Label(hint, systemImage: "person.2.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.cyan.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                            .allowsHitTesting(false)
                    }
                    Spacer()
                }
            }

            // Top & Bottom (or Trailing in Landscape) HUD
            if isLandscape {
                HStack(spacing: 0) {
                    VStack {
                        if !isZenMode {
                            topGuidanceHUD
                        } else {
                            HStack {
                                Spacer()
                                zenToggleButton
                            }
                        }
                        Spacer()
                        if let toastMessage {
                            Text(toastMessage)
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.bottom, 6)
                        }
                    }
                    Spacer(minLength: 8)
                    landscapeTrailingHUD
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else {
                VStack {
                    if !isZenMode {
                        topGuidanceHUD
                    } else {
                        HStack {
                            Spacer()
                            zenToggleButton
                        }
                    }
                    Spacer()
                    if let toastMessage {
                        Text(toastMessage)
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 6)
                    }
                    bottomControlsHUD
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            if isGeneratingPoses {
                generatingOverlay
            }

            if intervalTask != nil {
                ZStack {
                    Color.black.opacity(0.86)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "repeat.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.cyan)
                        Text("Aralıklı Çekim • \(intervalShotsCount) kare")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                        Text("Pil tasarrufu için ekran karartıldı")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Durdur") {
                            toggleIntervalShooting()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
        }
        .tint(appState.isNightHudEnabled ? Color(red: 0.95, green: 0.35, blue: 0.25) : .cyan)
        .task {
            UIDevice.current.isBatteryMonitoringEnabled = true
            horizonService.start()
            voiceShutter.onTriggerShutter = {
                Task { await captureAndSavePhoto() }
            }
            volumeShutter.onVolumePressed = {
                guard !isGeneratingPoses else { return }
                if isVideoMode {
                    if cameraService.isRecording {
                        cameraService.stopVideoRecording()
                    } else {
                        Task { await recordVideoClip() }
                    }
                } else {
                    Task { await captureAndSavePhoto() }
                }
            }
            volumeShutter.start()
            watchRemote.start { timer in
                guard !isGeneratingPoses else { return }
                if timer > 0 {
                    startManualTimerCapture(seconds: timer)
                } else {
                    Task { await captureAndSavePhoto() }
                }
            }
            let granted = await cameraService.checkAndRequestPermission()
            if granted {
                cameraService.onVideoFrame = { buffer in
                    visionService.analyzeFrame(
                        buffer,
                        targetPose: appState.pinnedPose,
                        enableFocusPeaking: isProMode && isFocusPeakingEnabled && cameraService.cameraPosition == .back
                    )
                }
                cameraService.startSession()
                if let requestedZoom = appState.requestedZoomFactor {
                    cameraService.setZoom(CGFloat(requestedZoom))
                    appState.requestedZoomFactor = nil
                }
            }
        }
        .onChange(of: visionService.guidance) { _, newGuidance in
            voiceCoach.announceIfNeeded(
                newGuidance,
                isEnabled: appState.isVoiceCoachEnabled && !appState.isSilentModeEnabled,
                hasPinnedPose: appState.pinnedPose != nil,
                fast: appState.voiceCoachFast
            )
            if newGuidance.lighting == .lowContrast && !didShowHazeHint {
                didShowHazeHint = true
                showToast("Görüntü puslu görünüyor — lensi kontrol edin")
            }
            if let faceBox = newGuidance.detectedFaceBox {
                cameraService.trackFaceFocusIfUnlocked(normalizedFaceBox: faceBox, isProMode: isProMode)
            }
            evaluateAutoShutter(with: newGuidance)
            evaluateMatchHaptic(with: newGuidance)
            watchRemote.sendLiveStatus(
                matchScore: newGuidance.poseMatchScore,
                lightingMessage: newGuidance.lighting.message,
                isShotReady: isShotReady,
                isRecording: cameraService.isRecording,
                threshold: appState.poseMatchThreshold
            )
        }
        .onChange(of: appState.isSilentModeEnabled) { _, silent in
            if silent {
                voiceCoach.stop()
                if cameraService.flashMode == .on {
                    cameraService.toggleFlash()
                }
            }
        }
        .onDisappear {
            autoShutterTask?.cancel()
            intervalTask?.cancel()
            intervalTask = nil
            voiceCoach.stop()
            voiceShutter.stop()
            volumeShutter.stop()
            horizonService.stop()
            cameraService.stopSession()
        }
        .onChange(of: selectedInspoItem) { _, newItem in
            guard let newItem else { return }
            Task { await importInspoPose(from: newItem) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                cameraService.updateOrientation(to: scene.interfaceOrientation)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            visionService.focusPeakingImage = nil
        }
        .sheet(item: $previewingLatestItem) { item in
            ResultViewerSheet(item: item)
        }
        .sheet(isPresented: $showPoseTemplates) {
            PoseTemplatePickerSheet()
        }
        .sheet(isPresented: $showCalibrationSheet) {
            FieldCalibrationSheet(visionService: visionService, cameraService: cameraService)
        }
        .onChange(of: appState.pendingCameraTip) { _, tip in
            if let tip {
                showToast(tip)
                appState.pendingCameraTip = nil
            }
        }
    }
}
