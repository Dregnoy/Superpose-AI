import SwiftUI

struct PoseResultsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let poses: [PoseIdea]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pin a pose to project its outline onto your camera, or tap Coach for split subject & photographer tips.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(poses) { pose in
                            poseCard(pose)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Your 4 Pose Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func poseCard(_ pose: PoseIdea) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 180)

                PoseOverlayView(
                    targetSkeleton: pose.skeleton,
                    secondaryTargetSkeleton: pose.secondarySkeleton,
                    liveSkeleton: nil,
                    mode: .detailedContour,
                    matchScore: nil
                )
                .frame(height: 170)

                VStack {
                    HStack {
                        Text(pose.confidenceTag)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.2), in: Capsule())
                            .foregroundStyle(.cyan)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pose.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(pose.angleLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    appState.pinPoseAndSwitchToCamera(pose)
                } label: {
                    Label("Pin", systemImage: "pin.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.black)
                }

                Button {
                    appState.coachingPose = pose
                } label: {
                    Text("Coach")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }
}
