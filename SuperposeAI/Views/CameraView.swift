import SwiftUI
import AVFoundation
import PhotosUI

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
    @State private var isGeneratingPoses = false
    @State private var toastMessage: String?
    @State private var autoShutterCountdown: Int?
    @State private var autoShutterTask: Task<Void, Never>?
    @State private var selectedInspoItem: PhotosPickerItem?
    @State private var timerSeconds: Int = 0 // 0, 3, or 10
    @State private var isBurstEnabled: Bool = false
    @State private var isVideoMode: Bool = false
    @State private var focusPoint: CGPoint?
    @State private var exposureBias: Float = 0.0
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
                            cameraService.focusAndExpose(at: normalized)
                            focusPoint = location
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                if focusPoint == location { focusPoint = nil }
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { value in
                                    guard focusPoint != nil else { return }
                                    let delta = Float(-value.translation.height / 120.0)
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

            // Focus Reticle
            if let focusPoint {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow, lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
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

            // Optional Rule of Thirds Grid + Subtle Horizon Level
            if appState.isGridEnabled {
                ZStack {
                    RuleOfThirdsGridView()
                    HorizonLevelIndicatorView(
                        rollDegrees: horizonService.rollDegrees,
                        isLevel: horizonService.isLevel
                    )
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
            }

            // Subtle Eye Blink, Background Line & Couples Balance Alerts
            if visionService.guidance.eyesClosed || visionService.guidance.backgroundPoleWarning || visionService.guidance.couplesBalanceHint != nil {
                VStack(spacing: 6) {
                    Spacer().frame(height: 96)
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
                isEnabled: appState.isVoiceCoachEnabled,
                hasPinnedPose: appState.pinnedPose != nil
            )
            evaluateAutoShutter(with: newGuidance)
            evaluateMatchHaptic(with: newGuidance)
        }
        .onDisappear {
            autoShutterTask?.cancel()
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

            HStack(spacing: 8) {
                if let pinned = appState.pinnedPose {
                    HStack(spacing: 6) {
                        Text(pinned.title)
                            .font(.caption.bold())
                            .lineLimit(1)
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
                } else {
                    HStack(spacing: 6) {
                        Button {
                            appState.latestGeneratedPoses = appState.savedCustomPoses + MockPoseCatalog.quickOfflinePoses
                            appState.isResultsSheetPresented = true
                        } label: {
                            Label("Hızlı Poz", systemImage: "figure.stand")
                                .font(.caption.bold())
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }

                        PhotosPicker(selection: $selectedInspoItem, matching: .images) {
                            Label("İlham", systemImage: "photo.badge.plus")
                                .font(.caption.bold())
                                .lineLimit(1)
                                .padding(.horizontal, 10)
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

    private var bottomControlsHUD: some View {
        VStack(spacing: 10) {
            // Compact Tools Strip
            HStack(spacing: 10) {
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
                    if !appState.isVoiceCoachEnabled { voiceCoach.stop() }
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
                        .foregroundStyle(appState.isAutoShutterEnabled ? .black : .white)
                        .padding(.horizontal, 9)
                        .frame(height: 34)
                        .background(appState.isAutoShutterEnabled ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                }

                Button {
                    appState.isGridEnabled.toggle()
                } label: {
                    Image(systemName: "grid")
                        .font(.subheadline)
                        .foregroundStyle(appState.isGridEnabled ? .cyan : .white)
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
            }

            if cameraService.cameraPosition == .back {
                HStack(spacing: 8) {
                    ForEach([CGFloat(1.0), CGFloat(2.0)], id: \.self) { factor in
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

            // Compact Foto / Video (Reels) switch
            HStack(spacing: 14) {
                Button("FOTO") { isVideoMode = false }
                    .font(.caption2.bold())
                    .foregroundStyle(!isVideoMode ? .cyan : .secondary)
                Button("VİDEO") { isVideoMode = true }
                    .font(.caption2.bold())
                    .foregroundStyle(isVideoMode ? .red : .secondary)
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
                            .stroke(autoShutterCountdown != nil ? Color.cyan : Color.white, lineWidth: 4)
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
                    if !appState.isVoiceCoachEnabled { voiceCoach.stop() }
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
                    appState.isGridEnabled.toggle()
                } label: {
                    Image(systemName: "grid")
                        .font(.caption)
                        .foregroundStyle(appState.isGridEnabled ? .cyan : .white)
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

            VStack(spacing: 16) {
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
                    if autoShutterTask != nil {
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
                            .stroke(autoShutterCountdown != nil ? Color.cyan : Color.white, lineWidth: 4)
                            .frame(width: 66, height: 66)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 54, height: 54)
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
                    libraryStore.saveCapturedPhoto(
                        best,
                        isGeneratedReference: false,
                        poseIdea: appState.pinnedPose,
                        zoomFactor: Double(cameraService.zoomFactor),
                        overlayModeRaw: appState.overlayMode.rawValue
                    )
                    if appState.autoSaveToApplePhotos, let latest = libraryStore.items.first {
                        _ = await libraryStore.saveToApplePhotos(latest)
                    }
                    showToast("En net kare (3'ten) kaydedildi")
                }
            } else {
                let image = try await cameraService.capturePhoto()
                libraryStore.saveCapturedPhoto(
                    image,
                    isGeneratedReference: false,
                    poseIdea: appState.pinnedPose,
                    zoomFactor: Double(cameraService.zoomFactor),
                    overlayModeRaw: appState.overlayMode.rawValue
                )
                if appState.autoSaveToApplePhotos, let latest = libraryStore.items.first {
                    _ = await libraryStore.saveToApplePhotos(latest)
                }
                showToast("Kütüphaneye kaydedildi")
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
        guard appState.isAutoShutterEnabled,
              appState.pinnedPose != nil,
              !isGeneratingPoses else { return }

        let isReady = guidance.lighting == .good
            && guidance.framing == .great
            && !guidance.eyesClosed
            && (guidance.poseMatchScore ?? 0) >= 85

        if isReady && autoShutterTask == nil {
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
                await captureAndSavePhoto()
            }
        } else if !isReady, autoShutterTask != nil {
            autoShutterTask?.cancel()
            autoShutterTask = nil
            autoShutterCountdown = nil
        }
    }

    private func evaluateMatchHaptic(with guidance: LiveGuidanceState) {
        guard appState.pinnedPose != nil,
              let score = guidance.poseMatchScore else {
            didVibrateForCurrentMatch = false
            return
        }
        if score >= 85 && !didVibrateForCurrentMatch {
            didVibrateForCurrentMatch = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            autoShutterCountdown = nil
            autoShutterTask = nil
            await captureAndSavePhoto()
        }
    }

    private func recordVideoClip() async {
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

struct RuleOfThirdsGridView: View {
    var body: some View {
        Canvas { context, size in
            let lineColor = Color.white.opacity(0.28)
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
