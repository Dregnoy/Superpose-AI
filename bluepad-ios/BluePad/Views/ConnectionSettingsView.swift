import SwiftUI
import UIKit

struct ConnectionSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var nameDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 1. Bluetooth Broadcast & Identity Card
                bluetoothControlCard

                // 2. Step-by-Step Pairing Guides
                pairingGuidesCard

                // 3. Trackpad, Keyboard & Haptics Preferences
                preferencesCard

                // 4. Live HID Protocol Diagnostic Log
                diagnosticsCard
            }
            .padding(14)
        }
        .background(BluePadTheme.bgPrimary)
        .onAppear {
            nameDraft = viewModel.settings.advertisedName
        }
    }

    // MARK: Bluetooth Control Card

    private var bluetoothControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bluetooth HID Yayını", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentCyan)
                Spacer()
                Text(viewModel.connectionState.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(viewModel.connectionState.isConnected ? BluePadTheme.accentMint : BluePadTheme.textSecondary)
            }

            HStack(spacing: 8) {
                TextField("Yayın Adı", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BluePadTheme.bgPrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(BluePadTheme.borderSubtle, lineWidth: 1)
                            )
                    )
                    .foregroundStyle(.white)

                Button("Uygula") {
                    viewModel.applyAdvertisedName(nameDraft)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(BluePadTheme.bgPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BluePadTheme.accentCyan))
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                statPill(title: "Protokol", value: viewModel.protocolMode.displayName)
                statPill(title: "Gönderilen Paket", value: "\(viewModel.packetsSentCount)")
            }

            Button {
                viewModel.toggleBluetoothAdvertising()
            } label: {
                Label(
                    viewModel.connectionState.isActiveRadio ? "Yayını Durdur" : "Yayını Başlat",
                    systemImage: viewModel.connectionState.isActiveRadio ? "stop.fill" : "play.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(viewModel.connectionState.isActiveRadio ? .white : BluePadTheme.bgPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(
                KeycapButtonStyle(
                    fill: viewModel.connectionState.isActiveRadio ? BluePadTheme.accentRose.opacity(0.85) : BluePadTheme.accentMint,
                    border: BluePadTheme.borderSubtle
                )
            )

            if !viewModel.connectionState.isActiveRadio {
                Button {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                } label: {
                    Label("iOS Bluetooth Ayarlarını Aç", systemImage: "gearshape.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.accentCyan)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.bgPrimary, border: BluePadTheme.accentCyan.opacity(0.35)))
            }
        }
        .glassCard()
    }

    // MARK: Pairing Guides

    private var pairingGuidesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Eşleştirme Rehberi (Sunucusuz)", systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BluePadTheme.accentMint)

            DisclosureGroup("Windows 10 / 11 ile Eşleştirme") {
                Text("1. Bilgisayarda Ayarlar → Bluetooth ve cihazlar → Cihaz ekle → Bluetooth'u seçin.\n2. Listede \"\(viewModel.settings.advertisedName)\" (veya iPhone adınızı) seçin.\n3. Bağlanınca hem iPhone'da hem Windows'ta çıkan eşleştirme onayını kabul edin.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.top, 4)
            }
            .tint(BluePadTheme.accentCyan)

            DisclosureGroup("macOS & iPadOS ile Eşleştirme") {
                Text("1. Mac veya iPad'de Sistem Ayarları → Bluetooth menüsünü açın.\n2. \"Yakındaki Cihazlar\" altında \"\(viewModel.settings.advertisedName)\" göründüğünde Bağlan'a tıklayın.\n3. Eşleşme sonrası hiçbir ek uygulama olmadan klavye ve trackpad çalışır.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.top, 4)
            }
            .tint(BluePadTheme.accentCyan)

            DisclosureGroup("Android / Google TV / Linux") {
                Text("1. TV veya cihazınızın Bluetooth Ayarları → Aksesuar Ekle bölümüne girin.\n2. \"\(viewModel.settings.advertisedName)\" cihazını seçip eşleştirin.\n3. Kumanda sekmesindeki D-Pad ve Medya tuşlarıyla TV'yi yönetin.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.top, 4)
            }
            .tint(BluePadTheme.accentCyan)

            DisclosureGroup("Bağlantı Kopuyorsa / Eşleşmiyorsa") {
                Text("HOGP protokolü şifreli bağlama (bonding) gerektirir. Eğer bir tarafta eski eşleştirme anahtarı kaldıysa bağlantı hemen düşebilir:\n• Hedef cihazda Bluetooth listesinden iPhone'u 'Cihazı Unut' yapın.\n• iPhone Ayarlar → Bluetooth altından hedef cihazı 'Bu Aygıtı Unut' yapın.\n• Ardından yeniden eşleştirin.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.top, 4)
            }
            .tint(BluePadTheme.accentAmber)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(BluePadTheme.textPrimary)
        .glassCard()
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Trackpad, Klavye & Haptik Ayarları", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BluePadTheme.accentCyan)

            Picker("Varsayılan Klavye Düzeni", selection: $viewModel.settings.keyboardLayout) {
                ForEach(KeyboardLayoutKind.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }

            Picker("Hedef İşletim Sistemi", selection: $viewModel.settings.hostOS) {
                ForEach(HostOSProfile.allCases) { os in
                    Text(os.displayName).tag(os)
                }
            }

            Divider().overlay(BluePadTheme.borderSubtle)

            sliderRow(
                title: "İmleç Hassasiyeti",
                valueText: String(format: "%.2fx", viewModel.settings.pointerSensitivity),
                value: $viewModel.settings.pointerSensitivity,
                range: 0.3...3.5,
                step: 0.05
            )

            sliderRow(
                title: "Kaydırma Hızı",
                valueText: String(format: "%.2fx", viewModel.settings.scrollSensitivity),
                value: $viewModel.settings.scrollSensitivity,
                range: 0.3...3.0,
                step: 0.05
            )

            sliderRow(
                title: "Hava Faresi Hassasiyeti",
                valueText: String(format: "%.2fx", viewModel.settings.airMouseSensitivity),
                value: $viewModel.settings.airMouseSensitivity,
                range: 0.4...3.0,
                step: 0.05
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Toplu Yazma Gecikmesi")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(viewModel.settings.typingDelayMs) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BluePadTheme.accentCyan)
                }
                Slider(
                    value: Binding(
                        get: { Double(viewModel.settings.typingDelayMs) },
                        set: { viewModel.settings.typingDelayMs = Int($0.rounded()) }
                    ),
                    in: 5...80,
                    step: 1
                )
                .tint(BluePadTheme.accentCyan)
            }

            Divider().overlay(BluePadTheme.borderSubtle)

            Toggle("İmleç İvmelenmesi", isOn: $viewModel.settings.pointerAcceleration)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
            Toggle("Doğal Kaydırma (Natural Scroll)", isOn: $viewModel.settings.naturalScrolling)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
            Toggle("Dokunarak Tıklama (Tap-to-Click)", isOn: $viewModel.settings.tapToClick)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
            Toggle("Dokunsal Geri Bildirim (Haptik)", isOn: $viewModel.settings.hapticsEnabled)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
        }
        .glassCard()
    }

    // MARK: Live HID Diagnostics

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("HID Protokol Tanı Günlüğü", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentViolet)
                Spacer()
                Button("Kopyala") {
                    UIPasteboard.general.string = viewModel.diagnosticsLogText()
                    viewModel.showToast("Tanı günlüğü panoya kopyalandı")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BluePadTheme.accentCyan)

                Button("Temizle") {
                    viewModel.clearDiagnostics()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BluePadTheme.accentRose)
            }

            if viewModel.diagnosticEvents.isEmpty {
                Text("Henüz HID / GATT olayı kaydedilmedi.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.diagnosticEvents.prefix(40)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(event.category.rawValue)
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(categoryColor(event.category))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(categoryColor(event.category).opacity(0.16)))
                                Text(event.message)
                                    .font(.caption2)
                                    .foregroundStyle(BluePadTheme.textPrimary)
                                    .lineLimit(2)
                            }
                            if let hex = event.hexPayload {
                                Text(hex)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(BluePadTheme.accentCyan)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BluePadTheme.bgPrimary)
                )
            }
        }
        .glassCard()
    }

    // MARK: Helpers

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BluePadTheme.textSecondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(BluePadTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BluePadTheme.bgPrimary)
        )
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BluePadTheme.accentCyan)
            }
            Slider(value: value, in: range, step: step)
                .tint(BluePadTheme.accentCyan)
        }
    }

    private func categoryColor(_ category: HIDDiagnosticEvent.Category) -> Color {
        switch category {
        case .ble: return BluePadTheme.accentCyan
        case .gatt: return BluePadTheme.accentMint
        case .tx: return BluePadTheme.accentBlue
        case .rx: return BluePadTheme.accentAmber
        case .error: return BluePadTheme.accentRose
        }
    }
}
