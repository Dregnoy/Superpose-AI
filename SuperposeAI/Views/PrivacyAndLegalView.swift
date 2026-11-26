import SwiftUI

struct PrivacyAndLegalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Group {
                        Text("Güvenebileceğiniz Gizlilik")
                            .font(.title2.bold())

                        Text("• Cihaz İçi Rehberlik: Canlı ışık, kadraj ve poz eşleştirme tamamen telefonunuzda çalışır; buluta veri gönderilmez.")
                        Text("• Yerel Kütüphane: Çektiğiniz fotoğraflar yalnızca cihazınızdaki uygulama kütüphanesinde saklanır ve istediğiniz an silebilirsiniz.")
                        Text("• Sıfır Takip: Reklam amaçlı uygulama dışı takip yapılmaz ve verileriniz satılmaz.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Gizlilik ve Koşullar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }
}
