import SwiftUI

/// Field calibration and thermal/AE telemetry sheet for physical iPhone testing.
struct FieldCalibrationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let visionService: PoseVisionService
    let cameraService: CameraService

    var body: some View {
        @Bindable var bindableState = appState
        NavigationStack {
            Form {
                Section("Termal & Performans Telemetrisi") {
                    LabeledContent("Termal Durum", value: visionService.thermalStateLabel)
                    LabeledContent("Canlı Vision FPS", value: String(format: "%.1f fps", visionService.currentAnalysisFPS))
                    LabeledContent("Düşük Güç / Pil Tasarrufu", value: visionService.isPowerSavingActive ? "Aktif" : "Normal")
                    let battery = UIDevice.current.batteryLevel
                    LabeledContent("Pil Seviyesi", value: battery >= 0 ? "%\(Int((battery * 100).rounded()))" : "Bilinmiyor")
                }

                Section("Kamera & AE/AF Durumu") {
                    LabeledContent("Aktif Kamera", value: cameraService.cameraPosition == .back ? "Arka Geniş" : "Ön Kamera")
                    LabeledContent("Sahne Parlaklığı (Luma)", value: String(format: "%.2f", visionService.guidance.lumaScore))
                    LabeledContent("Işık Durumu", value: visionService.guidance.lighting.message)
                    Toggle("Düşük Işık AE Desteği", isOn: $bindableState.lowLightBoostEnabled)
                }

                Section("Poz Eşleşme Eşiği Kalibrasyonu") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Otomatik Çekim / Hazır Eşiği")
                            Spacer()
                            Text("%\(appState.poseMatchThreshold)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.cyan)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(appState.poseMatchThreshold) },
                                set: { appState.poseMatchThreshold = Int($0.rounded()) }
                            ),
                            in: 65...95,
                            step: 1
                        )
                        .tint(.cyan)
                        Text("Sahada poz eşleşmesi çok zor tutuyorsa %75–%80 aralığına düşürebilir, stüdyoda %85–%90 kullanabilirsiniz.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Varsayılana Dön (%85)") {
                            appState.poseMatchThreshold = 85
                        }
                        .font(.caption.bold())
                    }
                }
            }
            .navigationTitle("Saha Kalibrasyonu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }
}
