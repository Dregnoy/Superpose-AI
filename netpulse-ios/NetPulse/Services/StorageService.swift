import Foundation

struct PersistedStoreData: Codable, Sendable {
    var samples: [TelemetrySample] = []
    var incidents: [IncidentRecord] = []
    var settings: AppSettings = AppSettings()
}

actor StorageService {
    private let fileURL: URL
    private var store: PersistedStoreData
    private var openIncidentID: UUID?
    private var badStreak: Int = 0
    private var goodStreak: Int = 0

    private let maxSamplesAgeSec: TimeInterval = 7 * 24 * 3600
    private let maxSamplesCount: Int = 2500

    init(fileURL: URL? = nil) {
        if let customURL = fileURL {
            self.fileURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = appSupport.appendingPathComponent("NetPulse", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("netpulse_store.json")
        }

        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode(PersistedStoreData.self, from: data) {
            self.store = decoded
            self.openIncidentID = decoded.incidents.first(where: { $0.endedAt == nil })?.id
        } else {
            self.store = PersistedStoreData()
        }
    }

    func loadSettings() -> AppSettings {
        store.settings
    }

    func saveSettings(_ settings: AppSettings) {
        store.settings = settings
        persist()
    }

    func recentSamples(limit: Int = 180) -> [TelemetrySample] {
        Array(store.samples.suffix(limit))
    }

    func recordTick(sample: TelemetrySample, diagnosis: DiagnosisReport) {
        store.samples.append(sample)
        let cutoff = sample.timestamp - maxSamplesAgeSec
        if store.samples.count > maxSamplesCount {
            store.samples.removeFirst(store.samples.count - maxSamplesCount)
        }
        store.samples.removeAll { $0.timestamp < cutoff }

        let isBad = diagnosis.status != .healthy
        if isBad {
            badStreak += 1
            goodStreak = 0
            if let openID = openIncidentID,
               let idx = store.incidents.firstIndex(where: { $0.id == openID }) {
                let curPing = sample.internet.avgMs ?? sample.gateway.avgMs ?? 0
                let curLoss = max(sample.internet.lossPct, sample.gateway.lossPct)
                store.incidents[idx].peakPingMs = max(store.incidents[idx].peakPingMs, curPing)
                store.incidents[idx].peakLossPct = max(store.incidents[idx].peakLossPct, curLoss)
                if diagnosis.status == .critical {
                    store.incidents[idx].severity = .critical
                }
            } else if badStreak >= 2 {
                let inc = IncidentRecord(
                    startedAt: sample.timestamp,
                    endedAt: nil,
                    severity: diagnosis.status == .critical ? .critical : .warning,
                    title: diagnosis.headline,
                    peakPingMs: sample.internet.avgMs ?? sample.gateway.avgMs ?? 0,
                    peakLossPct: max(sample.internet.lossPct, sample.gateway.lossPct),
                    note: diagnosis.summary
                )
                store.incidents.insert(inc, at: 0)
                if store.incidents.count > 120 {
                    store.incidents = Array(store.incidents.prefix(120))
                }
                openIncidentID = inc.id
            }
        } else {
            badStreak = 0
            if openIncidentID != nil {
                goodStreak += 1
                if goodStreak >= 3 {
                    if let idx = store.incidents.firstIndex(where: { $0.id == openIncidentID }) {
                        store.incidents[idx].endedAt = sample.timestamp
                    }
                    openIncidentID = nil
                    goodStreak = 0
                }
            }
        }

        persist()
    }

    func recentIncidents(limit: Int = 25, days: Int = 7, nowTs: TimeInterval = Date().timeIntervalSince1970) -> [IncidentRecord] {
        let cutoff = nowTs - Double(days) * 86400.0
        return Array(store.incidents.filter { $0.startedAt >= cutoff }.prefix(limit))
    }

    func hourlyHeatmap(hours: Int = 24, nowTs: TimeInterval = Date().timeIntervalSince1970) -> [HourlyBucket] {
        let cal = Calendar.current
        let nowDate = Date(timeIntervalSince1970: nowTs)
        let currentHourStart = cal.dateInterval(of: .hour, for: nowDate)?.start ?? nowDate
        var buckets: [HourlyBucket] = []

        for offset in stride(from: -(hours - 1), through: 0, by: 1) {
            guard let start = cal.date(byAdding: .hour, value: offset, to: currentHourStart),
                  let end = cal.date(byAdding: .hour, value: 1, to: start) else { continue }
            let startTs = start.timeIntervalSince1970
            let endTs = end.timeIntervalSince1970
            let hourSamples = store.samples.filter { $0.timestamp >= startTs && $0.timestamp < endTs }
            let validPings = hourSamples.compactMap { $0.internet.avgMs }
            let avgPing = validPings.isEmpty ? nil : validPings.reduce(0, +) / Double(validPings.count)
            let maxPing = hourSamples.compactMap { $0.internet.maxMs ?? $0.internet.avgMs }.max()
            let avgLoss = hourSamples.isEmpty
                ? 0.0
                : hourSamples.map(\.internet.lossPct).reduce(0, +) / Double(hourSamples.count)
            let incCount = store.incidents.filter { $0.startedAt >= startTs && $0.startedAt < endTs }.count

            let comp = cal.component(.hour, from: start)
            buckets.append(
                HourlyBucket(
                    hourLabel: String(format: "%02d:00", comp),
                    samples: hourSamples.count,
                    avgInetMs: avgPing,
                    maxInetMs: maxPing,
                    lossPct: (avgLoss * 10).rounded() / 10,
                    incidentCount: incCount
                )
            )
        }
        return buckets
    }

    func sevenDaySummary(nowTs: TimeInterval = Date().timeIntervalSince1970) -> SevenDaySummary {
        let cutoff = nowTs - 7 * 86400.0
        let samples = store.samples.filter { $0.timestamp >= cutoff }
        let incidents = store.incidents.filter { $0.startedAt >= cutoff }
        let pings = samples.compactMap { $0.internet.avgMs }
        let avgPing = pings.isEmpty ? nil : pings.reduce(0, +) / Double(pings.count)
        let maxPing = samples.compactMap { $0.internet.maxMs ?? $0.internet.avgMs }.max()

        let cal = Calendar.current
        var hourScores: [Int: Double] = [:]
        for s in samples {
            let h = cal.component(.hour, from: Date(timeIntervalSince1970: s.timestamp))
            let penalty = (s.internet.lossPct * 20.0) + max(0, (s.internet.avgMs ?? 0) - 55.0)
            hourScores[h, default: 0] += penalty
        }
        let worstHour = hourScores.max(by: { $0.value < $1.value })
        let worstLabel: String? = worstHour.flatMap { pair in
            pair.value > 0 ? String(format: "%02d:00–%02d:00", pair.key, (pair.key + 1) % 24) : nil
        }

        return SevenDaySummary(
            totalSamples: samples.count,
            totalIncidents: incidents.count,
            avgInetMs: avgPing,
            maxInetMs: maxPing,
            worstHourRange: worstLabel
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
