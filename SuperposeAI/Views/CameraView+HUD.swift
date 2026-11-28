import SwiftUI
import AVFoundation
import PhotosUI
import AudioToolbox

extension CameraView {
    // MARK: - Top Real-Time Guidance HUD (Compact & Responsive)

    var topGuidanceHUD: some View {
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

                monochromeToggleButton
                zenToggleButton
            }

            if !appState.isOneHandedMode {
                quickPoseAndGuideRow
            }
        }
    }

    var monochromeToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isMonochromePreview.toggle()
            }
            showToast(isMonochromePreview ? "Siyah-Beyaz Önizleme Açık" : "Renkli Önizleme")
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(isMonochromePreview ? .yellow : .white)
                .padding(7)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(isMonochromePreview ? "Renkli Önizleme" : "Siyah-Beyaz Önizleme")
    }

    var zenToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isZenMode.toggle()
            }
        } label: {
            Image(systemName: isZenMode ? "eye.slash.fill" : "eye")
                .font(.caption)
                .foregroundStyle(isZenMode ? .cyan : .white)
                .padding(7)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(isZenMode ? "Arayüzü Göster" : "Temiz Vizör")
    }

    func nearestDetectedJoint(to location: CGPoint, in size: CGSize) -> (BodyJoint, CGPoint)? {
        guard let skeleton = visionService.guidance.detectedSkeleton else { return nil }
        let isFront = cameraService.cameraPosition == .front
        var best: (BodyJoint, CGPoint, CGFloat)?
        for (joint, pt) in skeleton.joints {
            let x = CGFloat(isFront ? (1.0 - pt.x) : pt.x) * size.width
            let y = CGFloat(pt.y) * size.height
            let dist = hypot(location.x - x, location.y - y)
            if dist <= 44, best == nil || dist < best!.2 {
                best = (joint, CGPoint(x: x, y: y), dist)
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    static func jointDisplayLabel(_ joint: BodyJoint) -> String {
        switch joint {
        case .nose: return "Yüz / Göz"
        case .neck: return "Boyun"
        case .leftShoulder: return "Sol Omuz"
        case .rightShoulder: return "Sağ Omuz"
        case .leftElbow: return "Sol Dirsek"
        case .rightElbow: return "Sağ Dirsek"
        case .leftWrist: return "Sol El"
        case .rightWrist: return "Sağ El"
        case .root: return "Gövde"
        case .leftHip: return "Sol Kalça"
        case .rightHip: return "Sağ Kalça"
        case .leftKnee: return "Sol Diz"
        case .rightKnee: return "Sağ Diz"
        case .leftAnkle: return "Sol Ayak"
        case .rightAnkle: return "Sağ Ayak"
        }
    }

    var quickPoseAndGuideRow: some View {
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

                        Button {
                            appState.pickRandomPose()
                            if let title = appState.pinnedPose?.title {
                                showToast("Rastgele poz: \(title)")
                            }
                        } label: {
                            Image(systemName: "die.face.5")
                                .font(.caption.bold())
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
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

    // MARK: - Bottom Camera Controls (Fits Every iPhone Width)

    var isShotReady: Bool {
        let g = visionService.guidance
        guard g.lighting == .good, g.framing == .great, !g.eyesClosed else { return false }
        if appState.pinnedPose != nil, (g.poseMatchScore ?? 0) < 85 {
            return false
        }
        return true
    }

    var hasActiveDrawerTools: Bool {
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

    var bottomControlsHUD: some View {
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
                        if !isProMode {
                            isFocusPeakingEnabled = false
                            cameraService.resetProControls()
                        }
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
                            .stroke(autoShutterCountdown != nil ? Color.cyan : (isShotReady ? Color.green : Color.white.opacity(0.45)), lineWidth: isShotReady ? 5 : 4)
                            .frame(width: 72, height: 72)
                        if appState.pinnedPose != nil, let matchScore = visionService.guidance.poseMatchScore, !isVideoMode {
                            Circle()
                                .trim(from: 0, to: CGFloat(min(100, max(0, matchScore))) / 100.0)
                                .stroke(matchScore >= 85 ? Color.green : Color.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 72, height: 72)
                                .animation(.easeOut(duration: 0.18), value: matchScore)
                        }
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

    var proControlsBar: some View {
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
                        Button(cameraService.isAppleProRAWSupported ? "ProRAW" : "RAW") {
                            cameraService.isRAWEnabled.toggle()
                            if cameraService.isRAWEnabled {
                                cameraService.isHDRBracketingEnabled = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(cameraService.isRAWEnabled ? .yellow : .gray.opacity(0.4))
                        .foregroundStyle(cameraService.isRAWEnabled ? .black : .white)
                    }

                    Button("HDR+") {
                        cameraService.isHDRBracketingEnabled.toggle()
                        if cameraService.isHDRBracketingEnabled {
                            cameraService.isRAWEnabled = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(cameraService.isHDRBracketingEnabled ? .cyan : .gray.opacity(0.4))
                    .foregroundStyle(cameraService.isHDRBracketingEnabled ? .black : .white)
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
                Button("Peak") {
                    isFocusPeakingEnabled.toggle()
                }
                .font(.caption2.bold())
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isFocusPeakingEnabled ? Color.yellow : Color.white.opacity(0.15), in: Capsule())
                .foregroundStyle(isFocusPeakingEnabled ? .black : .white)
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

    var landscapeTrailingHUD: some View {
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

    var cameraPermissionPlaceholder: some View {
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

    var generatingOverlay: some View {
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
}
