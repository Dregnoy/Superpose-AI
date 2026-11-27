import SwiftUI
import AVFoundation
import PhotosUI
import AudioToolbox

struct CameraView: View {
    @Environment(AppState.self) private var appState
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ShotPackStore.self) private var shotPackStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    @State private var cameraService = CameraService()
    @State private var visionService = PoseVisionService()
    @State private var voiceCoach = VoiceCoachService()
    @State private var voiceShutter = VoiceShutterService()
    @State private var volumeShutter = VolumeShutterService()
    @State private var horizonService = HorizonLevelService()
    @State private var didVibrateForCurrentMatch = false
    @State private var didShowHazeHint = false
    @State private var isGeneratingPoses = false
    @State private var toastMessage: String?
    @State private var autoShutterCountdown: Int?
    @State private var autoShutterTask: Task<Void, Never>?
    @State private var lastAutoShotTime: CFAbsoluteTime = 0
    @State private var selectedInspoItem: PhotosPickerItem?
    @State private var timerSeconds: Int = 0 // 0, 3, or 10
    @State private var intervalSeconds: Int = 0 // 0, 3, or 5 (Time-Lapse)
    @State private var intervalTask: Task<Void, Never>?
    @State private var intervalShotsCount: Int = 0
    @State private var isBurstEnabled: Bool = false
    @State private var isVideoMode: Bool = false
    @State private var recordingSeconds: Int = 0
    @State private var recordingTimerTask: Task<Void, Never>?
    @State private var isProMode: Bool = false
    @State private var showToolsDrawer: Bool = false
    @State private var isFocusLocked: Bool = false
    @State private var focusPoint: CGPoint?
    @State private var exposureBias: Float = 0.0
    @State private var manualFocus: Float = 0.5
    @State private var manualISO: Float = 0.25
    @State private var manualShutter: Double = 0.01 // 1/100s
    @State private var manualWB: Float = 5500
    @State private var previewingLatestItem: LibraryItem?

    private let poseGenerator = AIPoseGeneratorService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HiddenVolumeViewRepresentable(service: volumeShutter)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)

            if cameraService.authorizationStatus == .authorized {
                GeometryReader { geo in
                    CameraPreviewRepresentable(session: cameraService.session)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let normalized = CGPoint(
                                x: max(0, min(1, location.y / geo.size.height)),
                                y: max(0, min(1, 1.0 - (location.x / geo.size.width)))
                            )
                            isFocusLocked = false
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

            // Focus Reticle + Visible Sun Exposure Track
            if let focusPoint {
                VStack(spacing: 4) {
                    if isFocusLocked {
                        Text("AE/AF KİLİT")
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
                    CompositionGridView(mode: appState.gridMode)
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
            if visionService.guidance.eyesClosed || visionService.guidance.backgroundPoleWarning || visionService.guidance.couplesBalanceHint != nil || visionService.guidance.faceAngleHint != nil || visionService.guidance.subjectContrastHint != nil || showShakeAlert {
                VStack(spacing: 6) {
                    Spacer().frame(height: 96)
                    if showShakeAlert {
                        Label("Telefonu sabit tut", systemImage: "hand.raised.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    if visionService.guidance.eyesClosed {
                        Label("Gözler Kapalı", systemImage: "eye.slash")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.85), in: Capsule())
                            .foregroundStyle(.black)
                    }
                    if visionService.guidance.backgroundPoleWarning {
                        Label("Baş arkasında çizgi var", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.yellow.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                    }
                    if let contrastHint = visionService.guidance.subjectContrastHint {
                        Label(contrastHint, systemImage: "circle.lefthalf.filled")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.purple.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    if let faceHint = visionService.guidance.faceAngleHint {
                        Label(faceHint, systemImage: "face.smiling")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.mint.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                    }
                    if let hint = visionService.guidance.couplesBalanceHint {
                        Label(hint, systemImage: "person.2.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.cyan.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // Top & Bottom (or Trailing in Landscape) HUD
            if isLandscape {
                HStack(spacing: 0) {
                    VStack {
                        topGuidanceHUD
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
                    topGuidanceHUD
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
            let granted = await cameraService.checkAndRequestPermission()
            if granted {
                cameraService.onVideoFrame = { buffer in
                    visionService.analyzeFrame(buffer, targetPose: appState.pinnedPose)
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
            evaluateAutoShutter(with: newGuidance)
            evaluateMatchHaptic(with: newGuidance)
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
        .sheet(item: $previewingLatestItem) { item in
            ResultViewerSheet(item: item)
        }
        .onChange(of: appState.pendingCameraTip) { _, tip in
            if let tip {
                showToast(tip)
                appState.pendingCameraTip = nil
            }
        }
    }

    // MARK: - Top Real-Time Guidance HUD (Compact & Responsive)

    private var topGuidanceHUD: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label(visionService.guidance.lighting.message, systemImage: visionService.guidance.lighting.icon)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(visionService.guidance.lighting.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                if visionService.isPowerSavingActive {
                    Image(systemName: "leaf.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }

                if cameraService.isRecording {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(String(format: "%02d:%02d", recordingSeconds / 60, recordingSeconds % 60))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.35), in: Capsule())
                }

                if intervalTask != nil {
                    Text("Aralıklı: \(intervalShotsCount)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan, in: Capsule())
                }

                Spacer(minLength: 4)

                Text(visionService.guidance.framing.message)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(visionService.guidance.framing.isOptimal ? .green : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            if !appState.isOneHandedMode {
                quickPoseAndGuideRow
            }
        }
    }

    private var quickPoseAndGuideRow: some View {
        HStack(spacing: 8) {
            if let pinned = appState.pinnedPose {
                    HStack(spacing: 6) {
                        Button {
                            appState.cyclePinnedPose(step: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                        Text(pinned.title)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Button {
                            appState.cyclePinnedPose(step: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            appState.toggleSavePose(pinned)
                            showToast(appState.isPoseSaved(pinned) ? "Poz kaydedildi" : "Kayıttan çıkarıldı")
                        } label: {
                            Image(systemName: appState.isPoseSaved(pinned) ? "bookmark.fill" : "bookmark")
                                .font(.caption)
                                .foregroundStyle(appState.isPoseSaved(pinned) ? .yellow : .white)
                        }
                        Button {
                            appState.coachingPose = pinned
                        } label: {
                            Text("Koç")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.cyan, in: Capsule())
                                .foregroundStyle(.black)
                        }
                        if pinned.secondarySkeleton != nil {
                            Button {
                                appState.swapCouplesPose()
                                showToast("Pozlar yer değiştirildi")
                            } label: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.cyan)
                            }
                        }
                        Button {
                            appState.isOverlayMirrored.toggle()
                        } label: {
                            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                                .font(.caption)
                                .foregroundStyle(appState.isOverlayMirrored ? .cyan : .white)
                        }
                        Button {
                            appState.pinnedPose = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                } else if appState.pinnedReferencePhoto != nil {
                    HStack(spacing: 8) {
                        Button {
                            appState.isOverlayMirrored.toggle()
                        } label: {
                            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                                .font(.caption)
                                .foregroundStyle(appState.isOverlayMirrored ? .cyan : .white)
                        }
                        Slider(value: Bindable(appState).ghostOpacity, in: 0.15...0.65)
                            .frame(width: 64)
                            .tint(.cyan)
                        Button {
                            appState.pinnedReferencePhoto = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.cyan)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                } else {
                    HStack(spacing: 6) {
                        Button {
                            appState.latestGeneratedPoses = appState.savedCustomPoses + MockPoseCatalog.quickOfflinePoses
                            appState.isResultsSheetPresented = true
                        } label: {
                            Label("Hızlı Poz", systemImage: "figure.stand")
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }

                        PhotosPicker(selection: $selectedInspoItem, matching: .images) {
                            Label("İlham", systemImage: "photo.badge.plus")
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Button {
                        cycleAspectGuide()
                    } label: {
                        Text(appState.aspectGuideMode.rawValue)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(
                                appState.aspectGuideMode == .full
                                    ? AnyShapeStyle(.ultraThinMaterial)
                                    : AnyShapeStyle(Color.cyan.opacity(0.28)),
                                in: Capsule()
                            )
                    }

                    Button {
                        cycleOverlayMode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: appState.overlayMode.icon)
                            Text(appState.overlayMode.rawValue)
                                .lineLimit(1)
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Bottom Camera Controls (Fits Every iPhone Width)

    private var isShotReady: Bool {
        let g = visionService.guidance
        guard g.lighting == .good, g.framing == .great, !g.eyesClosed else { return false }
        if appState.pinnedPose != nil, (g.poseMatchScore ?? 0) < 85 {
            return false
        }
        return true
    }

    private var hasActiveDrawerTools: Bool {
        cameraService.flashMode == .on ||
        appState.isVoiceCoachEnabled ||
        appState.isAutoShutterEnabled ||
        appState.gridMode != .off ||
        timerSeconds > 0 ||
        intervalSeconds > 0 ||
        isBurstEnabled ||
        voiceShutter.isListening ||
        isProMode
    }

    private var bottomControlsHUD: some View {
        VStack(spacing: 10) {
            if appState.isOneHandedMode {
                quickPoseAndGuideRow
            }

            if showToolsDrawer {
                // Compact Tools Strip (scrollable so OTO / PRO never truncate to "...")
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                Button {
                    cameraService.toggleFlash()
                } label: {
                    Image(systemName: cameraService.flashMode == .on ? "bolt.fill" : "bolt.slash")
                        .font(.subheadline)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Button {
                    appState.isVoiceCoachEnabled.toggle()
                    if appState.isVoiceCoachEnabled {
                        voiceCoach.speak("Sesli koç açık")
                        showToast("Sesli koç açık")
                    } else {
                        voiceCoach.stop()
                        showToast("Sesli koç kapalı")
                    }
                } label: {
                    Image(systemName: appState.isVoiceCoachEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.subheadline)
                        .foregroundStyle(appState.isVoiceCoachEnabled ? .cyan : .white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Button {
                    appState.isAutoShutterEnabled.toggle()
                    if !appState.isAutoShutterEnabled {
                        autoShutterTask?.cancel()
                        autoShutterCountdown = nil
                    }
                } label: {
                    Text("OTO")
                        .font(.caption2.bold())
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(appState.isAutoShutterEnabled ? .black : .white)
                        .padding(.horizontal, 9)
                        .frame(height: 34)
                        .background(appState.isAutoShutterEnabled ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                }

                Button {
                    cycleGridMode()
                    showToast("Izgara: \(appState.gridMode.rawValue)")
                } label: {
                    Image(systemName: "grid")
                        .font(.subheadline)
                        .foregroundStyle(appState.gridMode != .off ? .cyan : .white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Button {
                    timerSeconds = (timerSeconds == 0) ? 3 : (timerSeconds == 3 ? 10 : 0)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "timer")
                        if timerSeconds > 0 {
                            Text("\(timerSeconds)sn")
                        }
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(timerSeconds > 0 ? .black : .white)
                    .padding(.horizontal, timerSeconds > 0 ? 8 : 0)
                    .frame(minWidth: 34, minHeight: 34)
                    .background(timerSeconds > 0 ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                }

                Button {
                    isBurstEnabled.toggle()
                } label: {
                    Image(systemName: "square.stack.3d.down.right")
                        .font(.subheadline)
                        .foregroundStyle(isBurstEnabled ? .black : .white)
                        .frame(width: 34, height: 34)
                        .background(isBurstEnabled ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                }

                Button {
                    intervalSeconds = (intervalSeconds == 0) ? 3 : (intervalSeconds == 3 ? 5 : 0)
                    showToast(intervalSeconds > 0 ? "Aralıklı çekim: Her \(intervalSeconds) sn" : "Aralıklı çekim kapalı")
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "repeat")
                        if intervalSeconds > 0 {
                            Text("\(intervalSeconds)sn")
                        }
                    }
                    .font(.caption2.bold())
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(intervalSeconds > 0 ? .black : .white)
                    .padding(.horizontal, intervalSeconds > 0 ? 8 : 0)
                    .frame(minWidth: 34, minHeight: 34)
                    .background(intervalSeconds > 0 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                }

                Button {
                    Task {
                        let active = await voiceShutter.toggle()
                        showToast(active ? "\"Çek\" diyerek fotoğraf çekin" : "Sesli deklanşör kapalı")
                    }
                } label: {
                    Image(systemName: voiceShutter.isListening ? "mic.fill" : "mic.slash")
                        .font(.subheadline)
                        .foregroundStyle(voiceShutter.isListening ? .black : .white)
                        .frame(width: 34, height: 34)
                        .background(voiceShutter.isListening ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                }

                if cameraService.cameraPosition == .back {
                    Button {
                        isProMode.toggle()
                        if !isProMode { cameraService.resetProControls() }
                    } label: {
                        Text("PRO")
                            .font(.caption2.bold())
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(isProMode ? .black : .white)
                            .padding(.horizontal, 8)
                            .frame(height: 34)
                            .background(isProMode ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    }
                }
                }
                .padding(.horizontal, 2)
            }
            }

            if isProMode && cameraService.cameraPosition == .back {
                proControlsBar
            }

            if cameraService.cameraPosition == .back {
                HStack(spacing: 8) {
                    ForEach([CGFloat(1.0), CGFloat(2.0), CGFloat(3.0)], id: \.self) { factor in
                        Button {
                            cameraService.setZoom(factor)
                        } label: {
                            Text("\(Int(factor))x")
                                .font(.caption2.bold())
                                .frame(width: 32, height: 32)
                                .background(
                                    cameraService.zoomFactor == factor
                                        ? AnyShapeStyle(Color.cyan)
                                        : AnyShapeStyle(.ultraThinMaterial),
                                    in: Circle()
                                )
                                .foregroundStyle(cameraService.zoomFactor == factor ? .black : .white)
                        }
                    }
                }
            }

            // Compact Tools Drawer Toggle + Foto / Video (Reels) switch + 4K Video Quality Pill
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        showToolsDrawer.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showToolsDrawer ? "chevron.down" : "chevron.up")
                        Text("Araçlar")
                        if hasActiveDrawerTools && !showToolsDrawer {
                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(showToolsDrawer ? .black : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(showToolsDrawer ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Button {
                        isVideoMode = false
                    } label: {
                        Text("FOTO")
                            .font(.caption.bold())
                            .foregroundStyle(!isVideoMode ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(!isVideoMode ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(Color.clear), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        isVideoMode = true
                    } label: {
                        Text("VİDEO")
                            .font(.caption.bold())
                            .foregroundStyle(isVideoMode ? .white : .white.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isVideoMode ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.clear), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(3)
                .background(.ultraThinMaterial, in: Capsule())

                if isVideoMode {
                    Button {
                        cameraService.configureCaptureMode(isVideo: true, is4K: !cameraService.is4KVideoEnabled)
                    } label: {
                        Text(cameraService.is4KVideoEnabled ? "4K" : "HD")
                            .font(.caption2.bold())
                            .foregroundStyle(cameraService.is4KVideoEnabled ? .black : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(cameraService.is4KVideoEnabled ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onChange(of: isVideoMode) { _, video in
                cameraService.configureCaptureMode(isVideo: video, is4K: cameraService.is4KVideoEnabled)
            }

            HStack(spacing: 22) {
                // Unlimited AI Poses Button
                Button {
                    Task { await captureAndGeneratePoses() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .background(Color.cyan.opacity(0.22), in: Circle())
                            .overlay(Circle().stroke(Color.cyan, lineWidth: 1.5))
                        Text("AI Poz")
                            .font(.caption2.bold())
                    }
                }
                .foregroundStyle(.white)

                // Standard Shutter / Video Record Button
                Button {
                    if isVideoMode {
                        if cameraService.isRecording {
                            cameraService.stopVideoRecording()
                        } else {
                            Task { await recordVideoClip() }
                        }
                    } else if intervalSeconds > 0 {
                        toggleIntervalShooting()
                    } else if autoShutterTask != nil {
                        autoShutterTask?.cancel()
                        autoShutterTask = nil
                        autoShutterCountdown = nil
                    } else if timerSeconds > 0 {
                        startManualTimerCapture(seconds: timerSeconds)
                    } else {
                        Task { await captureAndSavePhoto() }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(autoShutterCountdown != nil ? Color.cyan : (isShotReady ? Color.green : Color.white), lineWidth: isShotReady ? 5 : 4)
                            .frame(width: 72, height: 72)
                        if isVideoMode {
                            RoundedRectangle(cornerRadius: cameraService.isRecording ? 8 : 29)
                                .fill(Color.red)
                                .frame(width: cameraService.isRecording ? 28 : 58, height: cameraService.isRecording ? 28 : 58)
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 58, height: 58)
                        }
                        if let count = autoShutterCountdown {
                            Text("\(count)")
                                .font(.title2.bold())
                                .foregroundStyle(.black)
                        }
                    }
                }

                // Flip Camera & Last Shot Pill
                HStack(spacing: 10) {
                    Button {
                        cameraService.toggleCamera()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.title3)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: Circle())
                            Text("Çevir")
                                .font(.caption2.bold())
                        }
                    }
                    .foregroundStyle(.white)

                    if let latest = libraryStore.items.first,
                       let thumb = libraryStore.image(for: latest) {
                        Button {
                            previewingLatestItem = latest
                        } label: {
                            VStack(spacing: 4) {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 46, height: 46)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
                                Text("Son")
                                    .font(.caption2.bold())
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    private var proControlsBar: some View {
        let ev = max(-3.0, min(3.0, (visionService.guidance.lumaScore - 0.5) * 8.0))
        let evBalanced = abs(ev) <= 0.6

        return VStack(spacing: 6) {
            // Live Exposure Meter (-3 .. 0 .. +3) + Overexposure Warning
            HStack(spacing: 6) {
                Text("Pozometre")
                    .font(.caption2.bold())
                    .foregroundStyle(evBalanced ? .green : .yellow)
                if visionService.guidance.lumaScore > 0.88 {
                    Text("Aşırı Parlak")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(-3...3, id: \.self) { tick in
                        let isNear = Int(ev.rounded()) == tick
                        Text(tick > 0 ? "+\(tick)" : "\(tick)")
                            .font(.system(size: 9, weight: isNear ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(isNear ? (evBalanced ? .green : .yellow) : .secondary)
                            .padding(.horizontal, isNear ? 4 : 1)
                            .background(isNear ? Color.white.opacity(0.15) : Color.clear, in: Capsule())
                    }
                }
            }

            // Quick Pro Presets (Portre / Hareket / Loş / Silüet / Uzun Poz)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button("Portre") {
                        manualISO = 0.18
                        manualShutter = 0.008
                        manualWB = 5600
                        cameraService.setManualExposure(isoNormalized: 0.18, shutterSeconds: 0.008)
                        cameraService.setWhiteBalanceKelvin(5600)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)

                    Button("Hareket 1/1000") {
                        manualISO = 0.40
                        manualShutter = 0.001
                        cameraService.setManualExposure(isoNormalized: 0.40, shutterSeconds: 0.001)
                    }
                    .buttonStyle(.bordered)
                    .tint(.yellow)

                    Button("Loş / Gölge") {
                        manualISO = 0.72
                        manualShutter = 0.02
                        cameraService.setManualExposure(isoNormalized: 0.72, shutterSeconds: 0.02)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button("Silüet") {
                        manualISO = 0.05
                        manualShutter = 0.002
                        cameraService.setManualExposure(isoNormalized: 0.05, shutterSeconds: 0.002)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)

                    Button("Uzun Poz") {
                        manualISO = 0.05
                        manualShutter = 0.25
                        cameraService.setManualExposure(isoNormalized: 0.05, shutterSeconds: 0.25)
                    }
                    .buttonStyle(.bordered)
                    .tint(.mint)

                    if cameraService.isRAWSupported {
                        Button("RAW") {
                            cameraService.isRAWEnabled.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(cameraService.isRAWEnabled ? .yellow : .gray.opacity(0.4))
                        .foregroundStyle(cameraService.isRAWEnabled ? .black : .white)
                    }
                }
                .font(.caption2.bold())
            }

            HStack(spacing: 10) {
                Text("Odak")
                    .font(.caption2.bold())
                    .frame(width: 36, alignment: .leading)
                Slider(value: $manualFocus, in: 0...1)
                    .tint(.yellow)
                    .onChange(of: manualFocus) { _, v in cameraService.setManualFocus(v) }
            }
            HStack(spacing: 10) {
                Text("ISO")
                    .font(.caption2.bold())
                    .frame(width: 36, alignment: .leading)
                Slider(value: $manualISO, in: 0...1)
                    .tint(.yellow)
                    .onChange(of: manualISO) { _, v in cameraService.setManualISO(v) }
            }
            HStack(spacing: 10) {
                Text("Sec")
                    .font(.caption2.bold())
                    .frame(width: 36, alignment: .leading)
                Slider(value: $manualShutter, in: 0.001...0.25)
                    .tint(.yellow)
                    .onChange(of: manualShutter) { _, v in cameraService.setManualShutter(seconds: v) }
                Text("1/\(max(1, Int((1.0 / manualShutter).rounded())))")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Text("WB")
                    .font(.caption2.bold())
                    .frame(width: 36, alignment: .leading)
                Slider(value: $manualWB, in: 3000...7500)
                    .tint(.yellow)
                    .onChange(of: manualWB) { _, v in cameraService.setWhiteBalanceKelvin(v) }
                Button("Sıfırla") {
                    manualFocus = 0.5
                    manualISO = 0.25
                    manualShutter = 0.01
                    manualWB = 5500
                    cameraService.resetProControls()
                }
                .font(.caption2.bold())
                .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Landscape Trailing HUD (Apple Camera Style)

    private var landscapeTrailingHUD: some View {
        HStack(spacing: 12) {
            VStack(spacing: 8) {
                Button {
                    cameraService.toggleFlash()
                } label: {
                    Image(systemName: cameraService.flashMode == .on ? "bolt.fill" : "bolt.slash")
                        .font(.caption)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Button {
                    appState.isVoiceCoachEnabled.toggle()
                    if appState.isVoiceCoachEnabled {
                        voiceCoach.speak("Sesli koç açık")
                        showToast("Sesli koç açık")
                    } else {
                        voiceCoach.stop()
                        showToast("Sesli koç kapalı")
                    }
                } label: {
                    Image(systemName: appState.isVoiceCoachEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.caption)
                        .foregroundStyle(appState.isVoiceCoachEnabled ? .cyan : .white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Button {
                    appState.isAutoShutterEnabled.toggle()
                    if !appState.isAutoShutterEnabled {
                        autoShutterTask?.cancel()
                        autoShutterCountdown = nil
                    }
                } label: {
                    Text("OTO")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(appState.isAutoShutterEnabled ? .black : .white)
                        .frame(width: 34, height: 30)
                        .background(appState.isAutoShutterEnabled ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                }

                Button {
                    cycleGridMode()
                } label: {
                    Image(systemName: "grid")
                        .font(.caption)
                        .foregroundStyle(appState.gridMode != .off ? .cyan : .white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Button {
                    timerSeconds = (timerSeconds == 0) ? 3 : (timerSeconds == 3 ? 10 : 0)
                } label: {
                    Text(timerSeconds > 0 ? "\(timerSeconds)s" : "⏱")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(timerSeconds > 0 ? .black : .white)
                        .frame(width: 30, height: 30)
                        .background(timerSeconds > 0 ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                }

                Button {
                    isBurstEnabled.toggle()
                } label: {
                    Image(systemName: "square.stack.3d.down.right")
                        .font(.caption)
                        .foregroundStyle(isBurstEnabled ? .black : .white)
                        .frame(width: 30, height: 30)
                        .background(isBurstEnabled ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                }
            }

            VStack(spacing: 12) {
                Button {
                    isVideoMode.toggle()
                } label: {
                    Text(isVideoMode ? "VİDEO" : "FOTO")
                        .font(.caption2.bold())
                        .foregroundStyle(isVideoMode ? .white : .black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isVideoMode ? Color.red : Color.cyan, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await captureAndGeneratePoses() }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Color.cyan.opacity(0.22), in: Circle())
                        .overlay(Circle().stroke(Color.cyan, lineWidth: 1.5))
                }
                .foregroundStyle(.white)

                Button {
                    if isVideoMode {
                        if cameraService.isRecording {
                            cameraService.stopVideoRecording()
                        } else {
                            Task { await recordVideoClip() }
                        }
                    } else if intervalSeconds > 0 {
                        toggleIntervalShooting()
                    } else if autoShutterTask != nil {
                        autoShutterTask?.cancel()
                        autoShutterTask = nil
                        autoShutterCountdown = nil
                    } else if timerSeconds > 0 {
                        startManualTimerCapture(seconds: timerSeconds)
                    } else {
                        Task { await captureAndSavePhoto() }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(autoShutterCountdown != nil ? Color.cyan : (isShotReady ? Color.green : Color.white), lineWidth: isShotReady ? 5 : 4)
                            .frame(width: 66, height: 66)
                        if isVideoMode {
                            RoundedRectangle(cornerRadius: cameraService.isRecording ? 8 : 27)
                                .fill(Color.red)
                                .frame(width: cameraService.isRecording ? 26 : 54, height: cameraService.isRecording ? 26 : 54)
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 54, height: 54)
                        }
                        if let count = autoShutterCountdown {
                            Text("\(count)")
                                .font(.title3.bold())
                                .foregroundStyle(.black)
                        }
                    }
                }

                Button {
                    cameraService.toggleCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 8)
    }

    private var cameraPermissionPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Kamera İzni Gerekli")
                .font(.headline)
            Text("Canlı ışık, kadraj ve poz rehberliği için Ayarlar'dan kamera iznini açın.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.cyan)
                Text("4 Poz Önerisi Hazırlanıyor…")
                    .font(.headline)
                Text("Duruş, açı ve kadraj analiz ediliyor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Actions

    private func cycleOverlayMode() {
        let all = OverlayMode.allCases
        if let idx = all.firstIndex(of: appState.overlayMode) {
            appState.overlayMode = all[(idx + 1) % all.count]
        }
    }

    private func cycleAspectGuide() {
        let all = AspectGuideMode.allCases
        if let idx = all.firstIndex(of: appState.aspectGuideMode) {
            appState.aspectGuideMode = all[(idx + 1) % all.count]
        }
    }

    private func cycleGridMode() {
        let all = GridMode.allCases
        if let idx = all.firstIndex(of: appState.gridMode) {
            appState.gridMode = all[(idx + 1) % all.count]
        }
    }

    private func captureAndSavePhoto() async {
        do {
            if isBurstEnabled {
                var burstFrames: [UIImage] = []
                for idx in 0..<3 {
                    let frame = try await cameraService.capturePhoto()
                    burstFrames.append(frame)
                    if idx < 2 {
                        try? await Task.sleep(for: .milliseconds(160))
                    }
                }
                if let best = await visionService.pickBestShot(from: burstFrames) {
                    let finalBest = appState.autoEnhancePhotos ? PhotoEnhancerService.naturalizeAndSharpen(best) : best
                    libraryStore.saveCapturedPhoto(
                        finalBest,
                        isGeneratedReference: false,
                        poseIdea: appState.pinnedPose,
                        zoomFactor: Double(cameraService.zoomFactor),
                        overlayModeRaw: appState.overlayMode.rawValue,
                        rollDegrees: horizonService.rollDegrees
                    )
                    if appState.autoSaveToApplePhotos, let latest = libraryStore.items.first {
                        _ = await libraryStore.saveToApplePhotos(latest)
                    }
                    showToast("En net kare (3'ten) kaydedildi")
                }
            } else {
                let (image, rawDNGData) = try await cameraService.capturePhotoWithRAW(preferRAW: isProMode)
                let finalImage = appState.autoEnhancePhotos ? PhotoEnhancerService.naturalizeAndSharpen(image) : image
                libraryStore.saveCapturedPhoto(
                    finalImage,
                    isGeneratedReference: false,
                    poseIdea: appState.pinnedPose,
                    zoomFactor: Double(cameraService.zoomFactor),
                    overlayModeRaw: appState.overlayMode.rawValue,
                    rollDegrees: horizonService.rollDegrees
                )
                var rawSaved = false
                if let rawDNGData {
                    rawSaved = await libraryStore.saveRAWToApplePhotos(rawDNGData)
                }
                if appState.autoSaveToApplePhotos, let latest = libraryStore.items.first {
                    _ = await libraryStore.saveToApplePhotos(latest)
                }
                showToast(rawSaved ? "RAW (DNG) + Fotoğraf kaydedildi" : "Kütüphaneye kaydedildi")
            }
        } catch {
            showToast("Çekim başarısız")
        }
    }

    private func captureAndGeneratePoses() async {
        _ = shotPackStore.consumeOnePack()
        isGeneratingPoses = true
        defer { isGeneratingPoses = false }

        do {
            let testImage = try await cameraService.capturePhoto()
            libraryStore.saveCapturedPhoto(testImage, isGeneratedReference: false)
            // Extract anonymous skeleton & scene tags on-device so zero pixels or biometric photos leave the phone
            async let extractedTask = visionService.extractPose(from: testImage)
            async let sceneTagsTask = visionService.classifySceneTags(from: testImage)
            let (extracted, sceneTags) = await (extractedTask, sceneTagsTask)
            let poses = try await poseGenerator.generatePosePack(
                from: extracted?.skeleton ?? visionService.guidance.detectedSkeleton,
                sceneTags: sceneTags,
                lighting: visionService.guidance.lighting,
                useCase: appState.preferredUseCase,
                apiKey: appState.geminiAPIKey
            )
            appState.latestGeneratedPoses = poses
            appState.isResultsSheetPresented = true
        } catch {
            showToast("Pozlar üretilemedi")
        }
    }

    private func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toastMessage == text { toastMessage = nil }
        }
    }

    private func evaluateAutoShutter(with guidance: LiveGuidanceState) {
        guard !isGeneratingPoses, !isVideoMode else { return }

        let poseReady = appState.isAutoShutterEnabled
            && appState.pinnedPose != nil
            && guidance.lighting == .good
            && guidance.framing == .great
            && !guidance.eyesClosed
            && (guidance.poseMatchScore ?? 0) >= 85

        let smileReady = appState.isSmileShutterEnabled
            && guidance.isGoodSmile
            && !guidance.eyesClosed
            && guidance.framing != .noSubject

        let isReady = poseReady || smileReady
        let cooledDown = (CFAbsoluteTimeGetCurrent() - lastAutoShotTime) >= 5.0

        if isReady && cooledDown && autoShutterTask == nil {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()

            autoShutterTask = Task {
                for count in [3, 2, 1] {
                    guard !Task.isCancelled else { return }
                    autoShutterCountdown = count
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
                autoShutterCountdown = nil
                autoShutterTask = nil
                lastAutoShotTime = CFAbsoluteTimeGetCurrent()
                await captureAndSavePhoto()
            }
        } else if !isReady, autoShutterTask != nil {
            autoShutterTask?.cancel()
            autoShutterTask = nil
            autoShutterCountdown = nil
        }
    }

    private func evaluateMatchHaptic(with guidance: LiveGuidanceState) {
        guard appState.isHapticsEnabled,
              appState.pinnedPose != nil,
              let score = guidance.poseMatchScore else {
            didVibrateForCurrentMatch = false
            return
        }
        if score >= 85 && !didVibrateForCurrentMatch {
            didVibrateForCurrentMatch = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if !appState.isSilentModeEnabled {
                AudioServicesPlaySystemSound(1057)
            }
        } else if score < 75 {
            didVibrateForCurrentMatch = false
        }
    }

    private func importInspoPose(from item: PhotosPickerItem) async {
        defer { selectedInspoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let extracted = await visionService.extractPose(from: uiImage) else {
            showToast("Fotoğrafta kişi algılanamadı")
            return
        }
        let mask = await visionService.extractPersonSilhouette(from: uiImage)
        appState.pinPoseAndSwitchToCamera(extracted)
        appState.pinnedGhostMask = mask
        if mask != nil { appState.overlayMode = .ghost }
        showToast("İlham pozu sabitlendi!")
    }

    private func startManualTimerCapture(seconds: Int) {
        autoShutterTask?.cancel()
        autoShutterTask = Task {
            for remaining in stride(from: seconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                autoShutterCountdown = remaining
                if remaining <= 3 && !appState.isSilentModeEnabled {
                    voiceCoach.speak("\(remaining)", fast: appState.voiceCoachFast)
                }
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            autoShutterCountdown = nil
            autoShutterTask = nil
            await captureAndSavePhoto()
        }
    }

    private func toggleIntervalShooting() {
        if let existing = intervalTask {
            existing.cancel()
            intervalTask = nil
            showToast("Aralıklı çekim durduruldu (\(intervalShotsCount) kare)")
            return
        }
        intervalShotsCount = 0
        let step = intervalSeconds
        showToast("Aralıklı çekim başladı (Her \(step) sn)")
        intervalTask = Task {
            while !Task.isCancelled {
                await captureAndSavePhoto()
                intervalShotsCount += 1
                try? await Task.sleep(for: .seconds(step))
            }
        }
    }

    private func recordVideoClip() async {
        recordingSeconds = 0
        recordingTimerTask?.cancel()
        recordingTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                recordingSeconds += 1
            }
        }
        defer {
            recordingTimerTask?.cancel()
            recordingTimerTask = nil
            recordingSeconds = 0
        }
        do {
            let videoURL = try await cameraService.startVideoRecording()
            let saved = await libraryStore.saveVideoToApplePhotos(videoURL)
            showToast(saved ? "Video Fotoğraflar'a kaydedildi" : "Video kaydedilemedi")
        } catch {
            showToast("Video kaydı başarısız")
        }
    }
}

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

// MARK: - Subtle Rule of Thirds Grid & Horizon Level

struct CompositionGridView: View {
    let mode: GridMode

    var body: some View {
        Canvas { context, size in
            let lineColor = Color.white.opacity(0.30)
            switch mode {
            case .off:
                break
            case .ruleOfThirds:
                for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                    var vLine = Path()
                    vLine.move(to: CGPoint(x: size.width * fraction, y: 0))
                    vLine.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                    context.stroke(vLine, with: .color(lineColor), lineWidth: 0.75)

                    var hLine = Path()
                    hLine.move(to: CGPoint(x: 0, y: size.height * fraction))
                    hLine.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    context.stroke(hLine, with: .color(lineColor), lineWidth: 0.75)
                }
            case .symmetry:
                var vMid = Path()
                vMid.move(to: CGPoint(x: size.width * 0.5, y: 0))
                vMid.addLine(to: CGPoint(x: size.width * 0.5, y: size.height))
                context.stroke(vMid, with: .color(Color.cyan.opacity(0.45)), lineWidth: 1.0)

                var hMid = Path()
                hMid.move(to: CGPoint(x: 0, y: size.height * 0.5))
                hMid.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                context.stroke(hMid, with: .color(Color.cyan.opacity(0.45)), lineWidth: 1.0)
            case .diagonal:
                var d1 = Path()
                d1.move(to: .zero)
                d1.addLine(to: CGPoint(x: size.width, y: size.height))
                context.stroke(d1, with: .color(lineColor), lineWidth: 0.85)

                var d2 = Path()
                d2.move(to: CGPoint(x: size.width, y: 0))
                d2.addLine(to: CGPoint(x: 0, y: size.height))
                context.stroke(d2, with: .color(lineColor), lineWidth: 0.85)
            case .framing:
                let insetX = size.width * 0.14
                let insetY = size.height * 0.16
                let innerRect = CGRect(
                    x: insetX,
                    y: insetY,
                    width: size.width - insetX * 2,
                    height: size.height - insetY * 2
                )
                context.stroke(
                    Path(roundedRect: innerRect, cornerRadius: 14),
                    with: .color(Color.cyan.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [6, 5])
                )
            }
        }
    }
}

struct HorizonLevelIndicatorView: View {
    let rollDegrees: Double
    let isLevel: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 72, height: 1)

            Rectangle()
                .fill(isLevel ? Color.green : Color.yellow)
                .frame(width: 48, height: isLevel ? 2 : 1.5)
                .rotationEffect(.degrees(-rollDegrees))
        }
    }
}

struct FaceTrackingBoxView: View {
    let normalizedBox: CGRect
    let isMirrored: Bool
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = normalizedBox.width * geo.size.width
            let h = normalizedBox.height * geo.size.height
            let rawX = normalizedBox.minX * geo.size.width
            let x = isMirrored ? (geo.size.width - rawX - w) : rawX
            let y = normalizedBox.minY * geo.size.height

            RoundedRectangle(cornerRadius: 8)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                .frame(width: w, height: h)
                .position(x: x + w / 2, y: y + h / 2)
                .animation(.easeOut(duration: 0.12), value: normalizedBox)
        }
    }
}

struct AspectRatioMaskView: View {
    let mode: AspectGuideMode

    var body: some View {
        GeometryReader { geo in
            let ratio: CGFloat = (mode == .feed4x5) ? (4.0 / 5.0) : (9.0 / 16.0)
            let boxWidth = min(geo.size.width, geo.size.height * ratio)
            let boxHeight = boxWidth / ratio

            ZStack {
                Color.black.opacity(0.45)
                    .mask(
                        Rectangle()
                            .overlay(
                                Rectangle()
                                    .frame(width: boxWidth, height: boxHeight)
                                    .blendMode(.destinationOut)
                            )
                    )
                    .compositingGroup()

                Rectangle()
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
                    .frame(width: boxWidth, height: boxHeight)
            }
        }
    }
}

/// Dual '+' overhead flat-lay crosshair: turns green when phone is parallel to table/floor.
struct FlatLayCrosshairView: View {
    let offsetX: Double
    let offsetY: Double
    let isAligned: Bool

    var body: some View {
        ZStack {
            Image(systemName: "plus")
                .font(.title3.weight(.light))
                .foregroundStyle(isAligned ? Color.green : Color.white.opacity(0.7))

            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isAligned ? Color.green : Color.yellow)
                .offset(x: CGFloat(offsetX * 140), y: CGFloat(-offsetY * 140))
        }
    }
}
