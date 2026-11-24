import SwiftUI

struct ToolsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Araç", selection: $vm.selectedTool) {
                        ForEach(ToolsSubTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch vm.selectedTool {
                    case .modem:
                        ModemControlView(vm: vm)
                    case .dns:
                        dnsSection
                    case .bloat:
                        bufferbloatSection
                    case .peering:
                        peeringSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.npBg.ignoresSafeArea())
            .navigationTitle("Araçlar")
        }
    }

    private var dnsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DNS Hız Testi & iOS DoH Profili")
                        .font(.subheadline.weight(.bold))
                    Text("Gerçek UDP DNS sorgusu yapar ve iOS Ayarlar için .mobileconfig üretir.")
                        .font(.caption)
                        .foregroundStyle(Color.npMuted)
                }
                Spacer()
                Button {
                    Task { await vm.runDnsBenchmark() }
                } label: {
                    HStack(spacing: 5) {
                        if vm.isRunningDns { ProgressView().scaleEffect(0.75) }
                        Text(vm.isRunningDns ? "Test Ediliyor" : "Test Et")
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.npBlue)
                .disabled(vm.isRunningDns)
            }

            if let dohURL = vm.dohProfileURL {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(vm.dohProfileName ?? "DNS") DoH Profili Hazır")
                            .font(.caption.weight(.semibold))
                        Text("Paylaş → Dosyalara Kaydet veya Safari ile açıp Ayarlar → İndirilen Profil'den yükleyin.")
                            .font(.caption2)
                            .foregroundStyle(Color.npMuted)
                    }
                    Spacer()
                    ShareLink(item: dohURL) {
                        Label("Profili Paylaş", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.npGreen)
                }
                .padding(10)
                .background(Color.npGreen.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let bench = vm.dnsBenchmark {
                let maxMs = max(60.0, bench.results.compactMap(\.avgMs).max() ?? 100.0)
                ForEach(bench.results) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                            if bench.fastestProvider?.id == item.id {
                                StatusPill(text: "En Hızlı", tone: .safe)
                            }
                            Spacer()
                            Text(item.reachable ? String(format: "%.1f ms", item.avgMs ?? 0) : "Başarısız")
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        }
                        HStack {
                            Text(item.primaryIP)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color.npMuted)
                            Spacer()
                            if item.reachable, item.dohURL != nil {
                                Button("DoH Profili Seç") {
                                    vm.prepareDoHProfile(for: item)
                                }
                                .font(.caption2.weight(.semibold))
                            }
                        }
                        GeometryReader { geo in
                            let ratio = item.reachable ? min(1.0, max(0.08, (item.avgMs ?? maxMs) / maxMs)) : 1.0
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule()
                                    .fill(!item.reachable ? Color.npRed : ((item.avgMs ?? 0) >= 80 ? Color.npAmber : Color.npGreen))
                                    .frame(width: geo.size.width * ratio)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(10)
                    .background(Color.npBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } else {
                Text("Sağlayıcı hızlarını görmek için \"Test Et\" butonuna dokunun.")
                    .font(.caption)
                    .foregroundStyle(Color.npMuted)
            }
        }
        .npCard()
    }

    private var bufferbloatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bufferbloat (Yük Altında Gecikme)")
                        .font(.subheadline.weight(.bold))
                    Text("İndirme ve yükleme trafiği altında modem kuyruk şişmesini ölçer.")
                        .font(.caption)
                        .foregroundStyle(Color.npMuted)
                }
                Spacer()
                Button {
                    Task { await vm.runBufferbloat() }
                } label: {
                    HStack(spacing: 5) {
                        if vm.isRunningBloat { ProgressView().scaleEffect(0.75) }
                        Text(vm.isRunningBloat ? "Ölçülüyor..." : "Testi Başlat")
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.npBlue)
                .disabled(vm.isRunningBloat)
            }

            if let b = vm.bufferbloat {
                if let err = b.error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.npAmber)
                } else {
                    HStack(spacing: 12) {
                        Text(b.grade)
                            .font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                            .frame(width: 72, height: 72)
                            .background(Color.npBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(["A+", "A"].contains(b.grade) ? Color.npGreen : (["B", "C"].contains(b.grade) ? Color.npAmber : Color.npRed), lineWidth: 2)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Boşta Ping: \(b.idlePingMs.map { String(format: "%.1f ms", $0) } ?? "—")")
                                .font(.caption.monospaced())
                            Text("İndirme: \(b.downloadMbps.map { String(format: "%.1f Mbps", $0) } ?? "—") (+\(b.downloadBloatMs.map { String(format: "%.1f ms", $0) } ?? "—"))")
                                .font(.caption.monospaced())
                            Text("Yükleme: \(b.uploadMbps.map { String(format: "%.1f Mbps", $0) } ?? "—") (+\(b.uploadBloatMs.map { String(format: "%.1f ms", $0) } ?? "—"))")
                                .font(.caption.monospaced())
                        }
                    }
                    Text(b.summary)
                        .font(.caption)
                        .foregroundStyle(Color.npMuted)
                }
            } else {
                Text("Henüz Bufferbloat testi çalıştırılmadı (~10 saniye sürer).")
                    .font(.caption)
                    .foregroundStyle(Color.npMuted)
            }
        }
        .npCard()
    }

    private var peeringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Oyun, Toplantı & Yayın Peering Testi")
                .font(.subheadline.weight(.bold))

            Picker("Profil", selection: $vm.peeringProfile) {
                ForEach(PeeringProfile.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await vm.runPeering() }
            } label: {
                HStack(spacing: 6) {
                    if vm.isRunningPeering { ProgressView().scaleEffect(0.8) }
                    Text(vm.isRunningPeering ? "Ölçülüyor..." : "Bağlantıyı Test Et")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.npBlue)
            .disabled(vm.isRunningPeering)

            if let rep = vm.peeringReport {
                Text(rep.summary)
                    .font(.caption)
                    .foregroundStyle(Color.npMuted)

                ForEach(rep.results) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.subheadline.weight(.semibold))
                            Text("\(r.host) • \(r.protocolName)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color.npMuted)
                        }
                        Spacer()
                        Text(r.reachable ? String(format: "%.1f ms", r.rttMs ?? 0) : "Ulaşılamadı")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(r.reachable ? ((r.rttMs ?? 0) >= 90 ? Color.npAmber : Color.npGreen) : Color.npRed)
                    }
                    .padding(10)
                    .background(Color.npBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .npCard()
    }
}
