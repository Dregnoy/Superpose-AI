import SwiftUI

struct ReportsView: View {
    @ObservedObject var vm: AppViewModel
    @State private var reportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    heatmapCard
                    evidenceReportCard
                    incidentsCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.npBg.ignoresSafeArea())
            .navigationTitle("Kayıtlar & Rapor")
            .onAppear {
                Task {
                    await vm.refreshReportsData()
                    reportURL = vm.prepareEvidenceReportFile()
                }
            }
        }
    }

    private var summaryCard: some View {
        let s = vm.summary7d
        return VStack(alignment: .leading, spacing: 10) {
            Text("7 Günlük Ağ Hafızası")
                .font(.subheadline.weight(.bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                statTile("7 Günlük Olay", "\(s.totalIncidents)")
                statTile("Ort. İnternet Ping", s.avgInetMs.map { String(format: "%.1f ms", $0) } ?? "—")
                statTile("Tepe Ping", s.maxInetMs.map { String(format: "%.1f ms", $0) } ?? "—")
                statTile("En Sorunlu Saat", s.worstHourRange ?? "Yok")
            }
        }
        .npCard()
    }

    private func statTile(_ label: String, _ val: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.npMuted)
            Text(val)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.npBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("24 Saatlik Kalite Isı Haritası")
                .font(.subheadline.weight(.bold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                ForEach(vm.heatmap24h) { bucket in
                    let color: Color = {
                        guard bucket.samples > 0 else { return Color.white.opacity(0.08) }
                        if bucket.incidentCount > 1 || bucket.lossPct >= 5 || (bucket.avgInetMs ?? 0) >= 120 {
                            return Color.npRed.opacity(0.45)
                        }
                        if bucket.incidentCount > 0 || bucket.lossPct > 0 || (bucket.avgInetMs ?? 0) >= 70 {
                            return Color.npAmber.opacity(0.42)
                        }
                        return Color.npGreen.opacity(0.35)
                    }()

                    Text(String(bucket.hourLabel.prefix(2)))
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(color)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .npCard()
    }

    private var evidenceReportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ISS Teknik Kanıt Raporu")
                .font(.subheadline.weight(.bold))
            Text("Modem UPnP WAN durumu, fiziksel DSL SNR/CRC verileri ve 7 günlük olay özetini tek raporda paylaşır.")
                .font(.caption)
                .foregroundStyle(Color.npMuted)

            HStack(spacing: 10) {
                Button {
                    vm.copySupportSummary()
                } label: {
                    Label("Özeti Kopyala", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                if let url = reportURL {
                    ShareLink(item: url) {
                        Label("HTML Raporu Paylaş", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.npGreen)
                }

                Button("Yenile") {
                    reportURL = vm.prepareEvidenceReportFile()
                    vm.showToast("ISS kanıt raporu güncellendi.", isError: false)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .npCard()
    }

    private var incidentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Son Yavaşlama Olayları")
                .font(.subheadline.weight(.bold))

            if vm.incidents.isEmpty {
                Text("Henüz kaydedilmiş yavaşlama olayı yok.")
                    .font(.caption)
                    .foregroundStyle(Color.npMuted)
            } else {
                ForEach(vm.incidents) { inc in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(inc.title)
                                .font(.caption.weight(.semibold))
                            Text("\(fmtClock(inc.startedAt)) → \(inc.endedAt.map(fmtClock) ?? "Sürüyor")")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color.npMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            StatusPill(
                                text: inc.severity == .critical ? "Kritik" : "Uyarı",
                                tone: inc.severity == .critical ? .bad : .warn
                            )
                            Text("\(Int(inc.peakPingMs)) ms / %\(String(format: "%.1f", inc.peakLossPct))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color.npMuted)
                        }
                    }
                    .padding(10)
                    .background(Color.npBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .npCard()
    }

    private func fmtClock(_ ts: TimeInterval) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd.MM HH:mm"
        return fmt.string(from: Date(timeIntervalSince1970: ts))
    }
}
