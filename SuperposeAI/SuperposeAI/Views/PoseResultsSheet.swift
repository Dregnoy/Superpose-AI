import SwiftUI

struct PoseResultsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let poses: [PoseIdea]
    @State private var selectedCategory: PoseCategory = .all

    private var filteredPoses: [PoseIdea] {
        guard selectedCategory != .all else { return poses }
        let matched = poses.filter { $0.category == selectedCategory }
        return matched.isEmpty ? poses : matched
    }

    private var availableCategories: [PoseCategory] {
        let present = Set(poses.map(\.category))
        return [.all] + PoseCategory.allCases.filter { $0 != .all && present.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if availableCategories.count > 2 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableCategories) { category in
                                    Button {
                                        selectedCategory = category
                                    } label: {
                                        Text(category.rawValue)
                                            .font(.caption.bold())
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(
                                                selectedCategory == category
                                                    ? Color.cyan
                                                    : Color.white.opacity(0.1),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(selectedCategory == category ? .black : .white)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Text("Pozu kameraya yansıtmak için Sabitle'ye bas ya da poz veren ve fotoğrafçı ipuçları için Koç'u aç.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(filteredPoses) { pose in
                            poseCard(pose)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Poz Önerileri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
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
                        Button {
                            appState.toggleSavePose(pose)
                        } label: {
                            Image(systemName: appState.isPoseSaved(pose) ? "bookmark.fill" : "bookmark")
                                .font(.caption)
                                .foregroundStyle(appState.isPoseSaved(pose) ? .yellow : .secondary)
                        }
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
                    Label("Sabitle", systemImage: "pin.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.black)
                }

                Button {
                    appState.coachingPose = pose
                } label: {
                    Text("Koç")
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
