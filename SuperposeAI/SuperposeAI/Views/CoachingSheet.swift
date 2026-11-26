import SwiftUI

struct CoachingSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let pose: PoseIdea

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pose.angleLabel)
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                        Text(pose.coaching.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // For the Subject
                    tipSection(
                        title: "For Subject (Posing)",
                        icon: "person.fill",
                        accent: .cyan,
                        tips: pose.coaching.subjectTips
                    )

                    // For the Photographer
                    tipSection(
                        title: "For Photographer (Framing)",
                        icon: "camera.fill",
                        accent: .orange,
                        tips: pose.coaching.photographerTips
                    )

                    Button {
                        dismiss()
                        appState.pinPoseAndSwitchToCamera(pose)
                    } label: {
                        Label("Pin Pose & Open Camera", systemImage: "pin.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)
                    }
                }
                .padding(20)
            }
            .navigationTitle(pose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func tipSection(title: String, icon: String, accent: Color, tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(accent)

            ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .frame(width: 22, height: 22)
                        .background(accent.opacity(0.2), in: Circle())
                        .foregroundStyle(accent)

                    Text(tip)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
