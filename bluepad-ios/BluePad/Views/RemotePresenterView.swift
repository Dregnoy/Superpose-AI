import SwiftUI

struct RemotePresenterView: View {
    @ObservedObject var viewModel: AppViewModel

    enum RemoteMode: String, CaseIterable, Identifiable {
        case mediaTV = "Medya & TV"
        case presenter = "Sunum"
        case gamepad = "Gamepad"

        var id: String { rawValue }
    }

    @State private var mode: RemoteMode = .mediaTV
    @State private var presenterSeconds: Int = 0
    @State private var isTimerRunning: Bool = false
    @State private var showPowerConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Kumanda Modu", selection: $mode) {
                    ForEach(RemoteMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .mediaTV:
                    mediaAndTVSection
                case .presenter:
                    presenterSection
                case .gamepad:
                    GamepadView(viewModel: viewModel)
                }
            }
            .padding(14)
        }
        .background(BluePadTheme.bgPrimary)
        .task(id: isTimerRunning) {
            while isTimerRunning && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled || !isTimerRunning { break }
                presenterSeconds += 1
            }
        }
        .alert("Bilgisayarı Kapat / Uyku", isPresented: $showPowerConfirm) {
            Button("Güç Komutu Gönder", role: .destructive) {
                viewModel.tapSystem(.powerDown)
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("Bağlı cihaza HID Sistem Güç (Power Down) sinyali gönderilecek. Emin misiniz?")
        }
    }

    // MARK: Media & TV Section

    private var mediaAndTVSection: some View {
        VStack(spacing: 14) {
            // Playback controls card
            VStack(spacing: 12) {
                Text("MEDYA OYNATMA")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    consumerKeyButton(icon: "backward.end.fill", usage: .scanPreviousTrack)
                    consumerKeyButton(icon: "backward.fill", usage: .rewind)
                    Button {
                        viewModel.tapConsumer(.playPause)
                    } label: {
                        Image(systemName: "playpause.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BluePadTheme.bgPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                    }
                    .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.accentCyan, border: BluePadTheme.accentCyan, cornerRadius: 16))
                    consumerKeyButton(icon: "forward.fill", usage: .fastForward)
                    consumerKeyButton(icon: "forward.end.fill", usage: .scanNextTrack)
                }

                HStack(spacing: 10) {
                    consumerTile(title: "Ses Kıs", icon: "speaker.wave.1.fill", usage: .volumeDecrement)
                    consumerTile(title: "Sessiz", icon: "speaker.slash.fill", usage: .mute, tint: BluePadTheme.accentRose)
                    consumerTile(title: "Ses Aç", icon: "speaker.wave.3.fill", usage: .volumeIncrement)
                }

                HStack(spacing: 10) {
                    consumerTile(title: "Parlaklık -", icon: "sun.min.fill", usage: .brightnessDecrement)
                    consumerTile(title: "Durdur", icon: "stop.fill", usage: .stop)
                    consumerTile(title: "Parlaklık +", icon: "sun.max.fill", usage: .brightnessIncrement)
                }
            }
            .glassCard()

            // Circular TV / Navigation D-Pad
            VStack(spacing: 14) {
                Text("TV & GEZİNTİ KUMANDASI")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    dpadButton(icon: "chevron.up", code: .upArrow)
                    HStack(spacing: 10) {
                        dpadButton(icon: "chevron.left", code: .leftArrow)
                        Button {
                            viewModel.sendKey(.enter)
                        } label: {
                            Text("OK")
                                .font(.headline.weight(.black))
                                .foregroundStyle(BluePadTheme.bgPrimary)
                                .frame(width: 78, height: 78)
                                .background(Circle().fill(BluePadTheme.accentCyan))
                        }
                        .buttonStyle(.plain)
                        dpadButton(icon: "chevron.right", code: .rightArrow)
                    }
                    dpadButton(icon: "chevron.down", code: .downArrow)
                }
                .padding(.vertical, 4)

                HStack(spacing: 10) {
                    consumerTile(title: "Geri", icon: "arrow.uturn.backward", usage: .acBack)
                    consumerTile(title: "Ana Sayfa", icon: "house.fill", usage: .acHome)
                    consumerTile(title: "Menü", icon: "line.3.horizontal", usage: .menu)
                    consumerTile(title: "Ara", icon: "magnifyingglass", usage: .acSearch)
                }
            }
            .glassCard()

            // Smart TV Shortcuts & App Launcher (shown when TV is connected over Wi-Fi)
            if viewModel.tvState.isConnected {
                VStack(alignment: .leading, spacing: 10) {
                    Text("TV KISAYOLLARI (\(viewModel.tvState.statusText))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BluePadTheme.accentMint)

                    HStack(spacing: 10) {
                        Button {
                            viewModel.sendKey(.pageDown)
                        } label: {
                            presenterToolLabel("CH -", icon: "chevron.down.square")
                        }
                        .buttonStyle(KeycapButtonStyle())

                        Button {
                            viewModel.sendKey(.pageUp)
                        } label: {
                            presenterToolLabel("CH +", icon: "chevron.up.square")
                        }
                        .buttonStyle(KeycapButtonStyle())

                        Button {
                            viewModel.sendTVInputSource()
                        } label: {
                            presenterToolLabel("Kaynak", icon: "rectangle.connected.to.line.below")
                        }
                        .buttonStyle(KeycapButtonStyle())
                    }

                    if viewModel.tvState.connectedKind == .androidTV {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                tvAppButton("YouTube", url: "https://www.youtube.com")
                                tvAppButton("Netflix", url: "https://www.netflix.com")
                                tvAppButton("Spotify", url: "https://open.spotify.com")
                                tvAppButton("Prime", url: "https://www.primevideo.com")
                                tvAppButton("Disney+", url: "https://www.disneyplus.com")
                            }
                        }
                    }
                }
                .glassCard()
            }

            // System Power Controls
            VStack(spacing: 10) {
                Text("SİSTEM GÜÇ KONTROLÜ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button {
                        viewModel.tapSystem(.wakeUp)
                    } label: {
                        Label("Uyandır", systemImage: "sun.horizon.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BluePadTheme.accentMint)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(KeycapButtonStyle())

                    Button {
                        viewModel.tapSystem(.sleep)
                    } label: {
                        Label("Uyku", systemImage: "moon.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BluePadTheme.accentAmber)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(KeycapButtonStyle())

                    Button {
                        showPowerConfirm = true
                    } label: {
                        Label("Güç", systemImage: "power")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BluePadTheme.accentRose)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(KeycapButtonStyle())
                }
            }
            .glassCard()
        }
    }

    // MARK: Presenter Section

    private var presenterSection: some View {
        VStack(spacing: 14) {
            // Presentation Timer
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SUNUM ZAMANLAYICI")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BluePadTheme.textSecondary)
                    Text(formattedTimer)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(isTimerRunning ? BluePadTheme.accentMint : BluePadTheme.textPrimary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        isTimerRunning.toggle()
                        viewModel.triggerHaptic(.light)
                    } label: {
                        Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                            .font(.headline)
                            .foregroundStyle(BluePadTheme.bgPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(isTimerRunning ? BluePadTheme.accentAmber : BluePadTheme.accentCyan))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isTimerRunning = false
                        presenterSeconds = 0
                        viewModel.triggerHaptic(.light)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.headline)
                            .foregroundStyle(BluePadTheme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(BluePadTheme.bgKeycap))
                    }
                    .buttonStyle(.plain)
                }
            }
            .glassCard()

            // Hero Next / Previous Slide buttons
            VStack(spacing: 12) {
                Button {
                    viewModel.sendKey(.rightArrow)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 46))
                        Text("SONRAKİ SLAYT")
                            .font(.title3.weight(.heavy))
                    }
                    .foregroundStyle(BluePadTheme.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 158)
                }
                .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.accentCyan, border: BluePadTheme.accentCyan, cornerRadius: 22))

                Button {
                    viewModel.sendKey(.leftArrow)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.title2)
                        Text("ÖNCEKİ SLAYT")
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(BluePadTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                }
                .buttonStyle(KeycapButtonStyle(cornerRadius: 18))
            }

            // Slide Utilities & Air Pointer
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        if viewModel.settings.hostOS == .macOS {
                            viewModel.sendKey(.enter, extraModifiers: .leftGUI)
                        } else {
                            viewModel.sendKey(.f5)
                        }
                    } label: {
                        presenterToolLabel("Başlat", icon: "play.rectangle.fill")
                    }
                    .buttonStyle(KeycapButtonStyle())

                    Button {
                        viewModel.sendKey(.f5, extraModifiers: .leftShift)
                    } label: {
                        presenterToolLabel("Bu Slayt", icon: "play.display")
                    }
                    .buttonStyle(KeycapButtonStyle())

                    Button {
                        viewModel.sendKey(.escape)
                    } label: {
                        presenterToolLabel("Çıkış", icon: "xmark.rectangle.fill")
                    }
                    .buttonStyle(KeycapButtonStyle())
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.sendKey(.b)
                    } label: {
                        presenterToolLabel("Siyah Ekran (B)", icon: "rectangle.fill")
                    }
                    .buttonStyle(KeycapButtonStyle())

                    Button {
                        viewModel.sendKey(.w)
                    } label: {
                        presenterToolLabel("Beyaz Ekran (W)", icon: "rectangle")
                    }
                    .buttonStyle(KeycapButtonStyle())
                }

                Button {
                    viewModel.toggleAirMouse()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gyroscope")
                        Text(viewModel.isAirMouseActive ? "Hava İşaretçisi Açık (Kapat)" : "Hava İşaretçisi (Jiroskop)")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(viewModel.isAirMouseActive ? BluePadTheme.bgPrimary : BluePadTheme.accentMint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(
                    KeycapButtonStyle(
                        fill: viewModel.isAirMouseActive ? BluePadTheme.accentMint : BluePadTheme.bgKeycap,
                        border: BluePadTheme.accentMint.opacity(0.6)
                    )
                )
            }
            .glassCard()
        }
    }

    private var formattedTimer: String {
        let mins = presenterSeconds / 60
        let secs = presenterSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: Button Helpers

    private func consumerKeyButton(icon: String, usage: HIDConsumerUsage) -> some View {
        Button {
            viewModel.tapConsumer(usage)
        } label: {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(BluePadTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(KeycapButtonStyle())
    }

    private func consumerTile(
        title: String,
        icon: String,
        usage: HIDConsumerUsage,
        tint: Color = BluePadTheme.textPrimary
    ) -> some View {
        Button {
            viewModel.tapConsumer(usage)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BluePadTheme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(KeycapButtonStyle())
    }

    private func dpadButton(icon: String, code: HIDKeyCode) -> some View {
        Button {
            viewModel.sendKey(code)
        } label: {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(BluePadTheme.textPrimary)
                .frame(width: 72, height: 56)
        }
        .buttonStyle(KeycapButtonStyle(cornerRadius: 16))
    }

    private func presenterToolLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(BluePadTheme.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    private func tvAppButton(_ title: String, url: String) -> some View {
        Button {
            viewModel.launchTVApp(url: url, title: title)
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(BluePadTheme.bgPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(BluePadTheme.accentCyan))
        }
        .buttonStyle(.plain)
    }
}
