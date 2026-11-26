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

                Section("Tercihler ve Yasal") {
                    Picker("Ana Odak", selection: Bindable(appState).preferredUseCase) {
                        ForEach(PoseUseCase.allCases) { useCase in
                            Text(useCase.rawValue).tag(useCase)
                        }
                    }

                    Toggle("Çekilenleri Apple Fotoğraflar'a da Kaydet", isOn: Bindable(appState).autoSaveToApplePhotos)
                    Toggle("Gece Çekimi Arayüzü (Kırmızı HUD)", isOn: Bindable(appState).isNightHudEnabled)

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
                            .foregroundStyle(appState.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .green)
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
}
