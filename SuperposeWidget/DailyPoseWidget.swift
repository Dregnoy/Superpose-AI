import WidgetKit
import SwiftUI

struct DailyPoseEntry: TimelineEntry {
    let date: Date
    let title: String
    let subtitle: String
    let tip: String
    let icon: String
}

struct DailyPoseProvider: TimelineProvider {
    private static let dailyPoses: [(title: String, subtitle: String, tip: String, icon: String)] = [
        ("Altın Oran Yürüyüşü", "Tam Boy · 2x Lens", "Kameraya doğru yürürken hafifçe omuz üzerinden bak.", "figure.walk"),
        ("Kafe Pencere Işığı", "Bel Üstü · Yan 45°", "Yumuşak pencere ışığına doğru çeneni hafif yukarı kaldır.", "sun.max.fill"),
        ("Çift Dengeli Portre", "İki Kişi · 1/3 Hiza", "İki kişinin baş yüksekliğini farklı tutarak derinlik oluştur.", "person.2.fill"),
        ("Doğal Sokak Duruşu", "Tam Boy · Alçak Açı", "Ağırlığını tek ayağa verip ellerini cepte veya çantada rahat bırak.", "figure.stand"),
        ("Portre Bakış Kaçışı", "Yakın Plan · 2x", "Kameranın biraz yanına bakarak daha doğal ve samimi ifade yakala.", "camera.aperture")
    ]

    func placeholder(in context: Context) -> DailyPoseEntry {
        DailyPoseEntry(
            date: .now,
            title: "Altın Oran Yürüyüşü",
            subtitle: "Tam Boy · 2x Lens",
            tip: "Kameraya doğru yürürken hafifçe omuz üzerinden bak.",
            icon: "figure.walk"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyPoseEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyPoseEntry>) -> Void) {
        let now = Date()
        let entry = entry(for: now)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now.addingTimeInterval(21600)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func entry(for date: Date) -> DailyPoseEntry {
        let dayIndex = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        let item = Self.dailyPoses[dayIndex % Self.dailyPoses.count]
        return DailyPoseEntry(
            date: date,
            title: item.title,
            subtitle: item.subtitle,
            tip: item.tip,
            icon: item.icon
        )
    }
}

struct DailyPoseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyPoseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: entry.icon)
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                Text("Günün Pozu")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(entry.title)
                .font(family == .systemSmall ? .subheadline.bold() : .headline)
                .lineLimit(2)

            Text(entry.subtitle)
                .font(.caption2)
                .foregroundStyle(.cyan)

            if family != .systemSmall {
                Text(entry.tip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.black, Color(white: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct DailyPoseWidget: Widget {
    let kind: String = "com.superposelabs.superpose.dailyPose"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyPoseProvider()) { entry in
            DailyPoseWidgetView(entry: entry)
        }
        .configurationDisplayName("Günün Pozu")
        .description("Her gün yeni bir poz fikri ve kadraj ipucu gösterir.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
