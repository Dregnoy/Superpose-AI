import SwiftUI

struct PrivacyAndLegalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Group {
                        Text("Privacy You Can Trust")
                            .font(.title2.bold())

                        Text("• On-Device Guidance: Real-time lighting, framing, and pose-matching run entirely on your iPhone with zero cloud delay.")
                        Text("• Cloud Pose Generation: When generating AI pose references, your photo is transmitted securely for processing and is never used to train AI models.")
                        Text("• Zero Ad Tracking: We do not sell your data or track you across third-party apps.")
                        Text("• Full Control: Your photos and generated references stay in your local in-app library and can be deleted anytime.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Legal")
                            .font(.headline)
                        Text("Terms of Use follow Apple's Standard EULA.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Privacy & Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
