import SwiftUI

struct ShotPacksView: View {
    @Environment(AppState.self) private var appState
    @State private var showLegalSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI Poz Üretimi")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Sınırsız")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.cyan)
                        }
                        Spacer()
                        Label("Ücretsiz", systemImage: "infinity")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text("Tüm poz önerileri, ilham aktarımı ve canlı kamera rehberliği tamamen ücretsiz ve sınırsızdır.")
                }

                Section("Işık Zamanı Rehberi") {
                    HStack {
                        Image(systemName: "sun.horizon.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentLightWindowTitle())
                                .font(.subheadline.bold())
                            Text(currentLightWindowTip())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Kompozisyon Görevleri") {
                    missionButton(
                        title: "Çerçeveleme Dene",
                        subtitle: "Kapı, kemer veya yapraklarla kenarları çerçevele",
                        icon: "viewfinder",
                        grid: .framing
                    )
                    missionButton(
                        title: "1/3 Kuralı Portre",
                        subtitle: "Özneyi çizgi kesişimine, bakış yönüne boşluk bırak",
                        icon: "grid",
                        grid: .ruleOfThirds
                    )
                    missionButton(
                        title: "Simetri & Yansıma",
                        subtitle: "Su birikintisi veya camda yere eğilip simetri yakala",
                        icon: "square.split.2x2",
                        grid: .symmetry
                    )
                    missionButton(
                        title: "Köşegen / 3. Boyut",
                        subtitle: "Mimariyi tam karşıdan değil köşeden derinlikle çek",
                        icon: "line.diagonal",
                        grid: .diagonal
                    )
                }

                Section("Tercihler ve Yasal") {
                    Picker("Ana Odak", selection: Bindable(appState).preferredUseCase) {
                        ForEach(PoseUseCase.allCases) { useCase in
                            Text(useCase.rawValue).tag(useCase)
                        }
                    }

                    Toggle("Çekilenleri Apple Fotoğraflar'a da Kaydet", isOn: Bindable(appState).autoSaveToApplePhotos)
                    Toggle("Otomatik Doğallaştır ve Netleştir", isOn: Bindable(appState).autoEnhancePhotos)
                    Toggle("Gece Çekimi Arayüzü (Kırmızı HUD)", isOn: Bindable(appState).isNightHudEnabled)
                    Toggle("Poz Uyum Titreşimi", isOn: Bindable(appState).isHapticsEnabled)
                    Toggle("Hızlı Sesli Koç", isOn: Bindable(appState).voiceCoachFast)
                    Toggle("Gülümseyince Otomatik Çek", isOn: Bindable(appState).isSmileShutterEnabled)

                    Button {
                        showLegalSheet = true
                    } label: {
                        Label("Gizlilik Politikası ve Kullanım Koşulları", systemImage: "doc.text")
                    }
                }

                Section {
                    SecureField("Gemini API Anahtarı (İsteğe Bağlı)", text: Bindable(appState).geminiAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Text("Durum")
                        Spacer()
                        Text(appState.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Dahili Katalog" : "Anonim İskelet AI Aktif")
                            .font(.caption.bold())
                            .foregroundStyle(appState.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.green)
                    }
                } header: {
                    Text("Gizlilik Korumalı AI")
                } footer: {
                    Text("Fotoğrafınız ve yüzünüz asla sunucuya gönderilmez. Yalnızca cihazda çıkarılan anonim eklem sayıları (x, y) gönderilir.")
                }
            }
            .navigationTitle("Ayarlar")
            .sheet(isPresented: $showLegalSheet) {
                PrivacyAndLegalView()
            }
        }
    }

    private func missionButton(title: String, subtitle: String, icon: String, grid: GridMode) -> some View {
        Button {
            appState.gridMode = grid
            appState.pendingCameraTip = subtitle
            appState.selectedTab = .camera
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.cyan)
            }
        }
    }

    private func currentLightWindowTitle() -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5...7: return "Sabah Altın / Mavi Saat"
        case 8...10: return "Yumuşak Sabah Işığı"
        case 11...15: return "Sert Öğle Işığı"
        case 16...18: return "Akşam Altın Saat"
        case 19...20: return "Mavi Saat (Şehir Işıkları)"
        default: return "Gece / Düşük Işık"
        }
    }

    private func currentLightWindowTip() -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5...7, 16...18: return "Portre ve silüet için en yumuşak sıcak ışık zamanı."
        case 19...20: return "Mavi gökyüzü ve şehir ışıkları için Mavi Saat tonunu deneyin."
        case 11...15: return "Sert gölgelerden kaçınmak için gölge veya ters ışık kullanın."
        default: return "PRO modda Loş/Gölge hazır ayarını veya Gece HUD'u deneyin."
        }
    }
}
