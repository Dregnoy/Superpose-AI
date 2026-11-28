import SwiftUI

/// Pre-shot pose template picker allowing ordinary users to browse curated
/// poses by category and pin one onto the live camera before shooting.
struct PoseTemplatePickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: PoseCategory? = nil

    private var templates: [PoseIdea] {
        let all = MockPoseCatalog.quickOfflinePoses
        guard let selectedCategory else { return all }
        return all.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                categoryBar
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(templates) { pose in
                            templateRow(pose)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Hazır Poz Şablonları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: "Tümü", category: nil)
                ForEach(PoseCategory.allCases.filter { $0 != .all }) { category in
                    categoryChip(title: category.rawValue, category: category)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 6)
    }

    private func templateRow(_ pose: PoseIdea) -> some View {
        let isPinned = appState.pinnedPose?.id == pose.id
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.85))
                PoseOverlayView(
                    targetSkeleton: pose.skeleton,
                    secondaryTargetSkeleton: pose.secondarySkeleton,
                    liveSkeleton: nil,
                    mode: .fastSilhouette,
                    matchScore: nil
                )
                .padding(6)
            }
            .frame(width: 72, height: 96)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pose.category.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.2), in: Capsule())
                        .foregroundStyle(.cyan)
                    Spacer()
                    Text(pose.angleLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(pose.title)
                    .font(.subheadline.bold())
                Text(pose.coaching.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                appState.pinnedPose = pose
                appState.pendingCameraTip = "Poz sabitlendi: \(pose.title)"
                dismiss()
            } label: {
                Text(isPinned ? "Aktif" : "Seç")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isPinned ? Color.green : Color.cyan, in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func categoryChip(title: String, category: PoseCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.cyan : Color.secondary.opacity(0.18), in: Capsule())
                .foregroundStyle(isSelected ? .black : .primary)
        }
        .buttonStyle(.plain)
    }
}
