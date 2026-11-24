import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppTab: Hashable {
    case summary
    case tools
    case reports
}

enum ToolsSubTab: String, CaseIterable, Identifiable {
    case modem = "Modem"
    case dns = "DNS & DoH"
    case bloat = "Bufferbloat"
    case peering = "Peering"

    var id: String { rawValue }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedTab: AppTab = .summary
    @Published var selectedTool: ToolsSubTab = .modem

    @Published var pathSnapshot: NetworkPathSnapshot = .empty
    @Published var history: [TelemetrySample] = []
    @Published var diagnosis: DiagnosisReport?
    @Published var pinnedDeepDiagnosis: DiagnosisReport?
    @Published var upnpInfo: UpnpRouterInfo = UpnpRouterInfo()
    @Published var modemState: ModemState = ModemState()

    @Published var dnsBenchmark: DnsBenchmarkSummary?
    @Published var dohProfileURL: URL?
    @Published var dohProfileName: String?

    @Published var bufferbloat: BufferbloatResult?
    @Published var peeringProfile: PeeringProfile = .oyun
    @Published var peeringReport: PeeringReport?

    @Published var incidents: [IncidentRecord] = []
    @Published var heatmap24h: [HourlyBucket] = []
    @Published var summary7d: SevenDaySummary = SevenDaySummary()
    @Published var reportFileURL: URL?

    // Modem formu ve durumlar
    @Published var modemHostInput: String = ""
    @Published var modemUserInput: String = "admin"
    @Published var modemPassInput: String = ""
    @Published var modemSaveFeedback: String?
    @Published var modemSaveSuccess: Bool = false

    @Published var isDiagnosing: Bool = false
    @Published var isSavingModem: Bool = false
    @Published var isReadingDsl: Bool = false
    @Published var isRunningDns: Bool = false
    @Published var isRunningBloat: Bool = false
    @Published var isRunningPeering: Bool = false
    @Published var statusBanner: (text: String, isError: Bool)?

    @Published var pendingConfirm: RecommendedAction?

    private let pathService = NetworkPathService()
    private let upnpService = UpnpWanService()
    private let modemClient = AirTiesModemClient()
    private let vault = KeychainVault()
    private let storage = StorageService()

    private var monitorTask: Task<Void, Never>?
    private var tickCounter = 0
    private var hasAutoReadDsl = false

    var activeDiagnosis: DiagnosisReport? {
        pinnedDeepDiagnosis ?? diagnosis
    }

    var effectiveGatewayIP: String? {
        if let saved = modemState.savedHost, !saved.isEmpty {
            return saved
        }
        return pathSnapshot.inferredGatewayIP
    }

    func startMonitoring() {
        pathService.start { [weak self] snap in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pathSnapshot = snap
                if self.modemHostInput.isEmpty, let gw = snap.inferredGatewayIP {
                    self.modemHostInput = gw
                }
            }
        }

        loadModemMetadata()
        guard monitorTask == nil else { return }

        monitorTask = Task { [weak self] in
            guard let self else { return }
            self.history = await self.storage.recentSamples(limit: 120)
            await self.refreshReportsData()
            await self.collectTick(pingCount: 2, refreshUpnp: true, pinDeep: false)

            if !self.hasAutoReadDsl, self.vault.metadata().saved {
                self.hasAutoReadDsl = true
                await self.refreshDslStats(silent: true)
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2500))
                guard !Task.isCancelled else { break }
                self.tickCounter += 1
                let refreshUpnp = self.tickCounter % 6 == 0
                await self.collectTick(pingCount: 2, refreshUpnp: refreshUpnp, pinDeep: false)
                if self.tickCounter % 4 == 0 {
                    await self.refreshReportsData()
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        pathService.stop()
    }

    func loadModemMetadata() {
        let meta = vault.metadata()
        modemState = ModemState(
            credentialsSaved: meta.saved,
            savedHost: meta.host,
            savedUsername: meta.username,
            dslStats: modemState.dslStats
        )
        if let host = meta.host, !host.isEmpty {
            modemHostInput = host
        } else if modemHostInput.isEmpty, let gw = pathSnapshot.inferredGatewayIP {
            modemHostInput = gw
        }
        if let user = meta.username, !user.isEmpty {
            modemUserInput = user
        }
    }

    func runDeepDiagnose() async {
        guard !isDiagnosing else { return }
        isDiagnosing = true
        defer { isDiagnosing = false }
        await collectTick(pingCount: 5, refreshUpnp: true, pinDeep: true)
        await refreshReportsData()
        showToast("3 katman derin teşhis güncellendi.", isError: false)
    }

    func clearPinnedDiagnosis() {
        pinnedDeepDiagnosis = nil
    }

    func collectTick(pingCount: Int, refreshUpnp: Bool, pinDeep: Bool) async {
        let snap = pathService.currentSnapshot()
        pathSnapshot = snap
        if modemHostInput.isEmpty, let gw = snap.inferredGatewayIP {
            modemHostInput = gw
        }

        let gwTarget = effectiveGatewayIP
        async let gwProbeTask = probeGatewayIfNeeded(gwTarget: gwTarget, path: snap, count: pingCount)
        async let inetProbeTask = LatencyProbeService.measureTCPLatency(host: "1.1.1.1", port: 443, count: pingCount, timeoutSec: 2.0)
        async let dnsMsTask = DnsProbeService.queryDnsUDP(serverIP: "1.1.1.1", domain: "cloudflare.com", timeoutSec: 2.0)

        let gwProbe = await gwProbeTask
        let inetProbe = await inetProbeTask
        let dnsMs = await dnsMsTask

        if refreshUpnp && (snap.connectionType == .wifi || snap.connectionType == .wired), let gw = gwTarget {
            upnpInfo = await upnpService.sample(gatewayIP: gw)
        }

        let sample = TelemetrySample(
            timestamp: Date().timeIntervalSince1970,
            gateway: gwProbe,
            internet: inetProbe,
            dnsMs: dnsMs,
            pathType: snap.connectionType
        )

        let report = DiagnosisEngine.analyze(
            sample: sample,
            path: snap,
            history: history,
            bufferbloat: bufferbloat,
            upnpInfo: upnpInfo,
            modemState: modemState
        )

        history.append(sample)
        if history.count > 180 {
            history.removeFirst(history.count - 180)
        }
        diagnosis = report
        if pinDeep {
            pinnedDeepDiagnosis = report
        }

        await storage.recordTick(sample: sample, diagnosis: report)
    }

    func refreshUpnpNow() async {
        guard let gw = effectiveGatewayIP else {
            showToast("Yerel ağ geçidi bulunamadı (Wi-Fi bağlı mı?).", isError: true)
            return
        }
        upnpInfo = await upnpService.sample(gatewayIP: gw)
        showToast("Modem UPnP WAN bilgisi yenilendi.", isError: false)
    }

    func saveModemCredentials() async {
        guard !isSavingModem else { return }
        let candidateHost = modemHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (effectiveGatewayIP ?? "192.168.2.1")
            : modemHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        modemHostInput = candidateHost

        let cleanHost: String
        do {
            cleanHost = try validatePrivateLANHost(candidateHost)
        } catch {
            modemSaveFeedback = error.localizedDescription
            modemSaveSuccess = false
            return
        }

        let user = modemUserInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "admin"
            : modemUserInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let pwd = modemPassInput

        isSavingModem = true
        modemSaveFeedback = nil
        defer { isSavingModem = false }

        let stats = await modemClient.readDslStats(host: cleanHost, username: user, password: pwd)
        guard stats.connected else {
            modemSaveFeedback = stats.error ?? "Modem girişi doğrulanamadı."
            modemSaveSuccess = false
            showToast(modemSaveFeedback ?? "Modem hatası", isError: true)
            return
        }

        do {
            try vault.save(host: cleanHost, username: user, password: pwd)
        } catch {
            modemSaveFeedback = error.localizedDescription
            modemSaveSuccess = false
            return
        }

        modemPassInput = ""
        modemSaveFeedback = nil
        modemSaveSuccess = true
        modemState = ModemState(
            credentialsSaved: true,
            savedHost: cleanHost,
            savedUsername: user,
            dslStats: stats
        )
        recomputeDiagnosisWithCurrentState()
        showToast("Modem bilgisi iOS Keychain'e kaydedildi ve DSL okundu.", isError: false)
    }

    func deleteModemCredentials() {
        _ = vault.delete()
        modemSaveFeedback = nil
        modemSaveSuccess = false
        modemState = ModemState(credentialsSaved: false, savedHost: nil, savedUsername: nil, dslStats: nil)
        recomputeDiagnosisWithCurrentState()
        showToast("Kayıtlı modem şifresi Keychain'den silindi.", isError: false)
    }

    func refreshDslStats(silent: Bool = false) async {
        guard !isReadingDsl else { return }
        guard let creds = vault.load() else {
            if !silent {
                modemSaveFeedback = "Önce modem giriş bilgilerini kaydedin."
                modemSaveSuccess = false
            }
            return
        }
        isReadingDsl = true
        defer { isReadingDsl = false }

        let stats = await modemClient.readDslStats(host: creds.host, username: creds.username, password: creds.password)
        modemState = ModemState(
            credentialsSaved: true,
            savedHost: creds.host,
            savedUsername: creds.username,
            dslStats: stats
        )
        recomputeDiagnosisWithCurrentState()

        if !silent {
            if stats.connected {
                modemSaveFeedback = nil
                showToast("Fiziksel DSL değerleri güncellendi.", isError: false)
            } else {
                modemSaveFeedback = stats.error
                modemSaveSuccess = false
                showToast(stats.error ?? "DSL okunamadı.", isError: true)
            }
        }
    }

    func triggerAction(_ action: RecommendedAction, confirmed: Bool = false) {
        if action.requiresConfirmation && !confirmed {
            pendingConfirm = action
            return
        }

        Task {
            switch action.actionID {
            case .modemReconnectWAN:
                let gw = effectiveGatewayIP
                let res = await upnpService.reconnectWAN(gatewayIP: gw, confirmed: confirmed)
                showToast(res.message, isError: !res.ok)
                if res.ok {
                    upnpInfo = await upnpService.sample(gatewayIP: gw)
                }
            case .modemReboot:
                guard let creds = vault.load() else {
                    selectedTab = .tools
                    selectedTool = .modem
                    showToast("Modemi yeniden başlatmak için önce giriş bilgilerini kaydedin.", isError: true)
                    return
                }
                let res = await modemClient.rebootModem(
                    host: creds.host,
                    username: creds.username,
                    password: creds.password,
                    confirmed: confirmed
                )
                showToast(res.message, isError: !res.ok)
            case .runDnsTest:
                selectedTab = .tools
                selectedTool = .dns
                await runDnsBenchmark()
            case .runBufferbloat:
                selectedTab = .tools
                selectedTool = .bloat
                await runBufferbloat()
            }
        }
    }

    func runDnsBenchmark() async {
        guard !isRunningDns else { return }
        isRunningDns = true
        defer { isRunningDns = false }
        let res = await DnsProbeService.benchmarkAll()
        dnsBenchmark = res
        if let best = res.fastestProvider {
            prepareDoHProfile(for: best)
            showToast("En hızlı DNS: \(best.name) (\(String(format: "%.1f", best.avgMs ?? 0)) ms)", isError: false)
        } else {
            showToast("DNS testi tamamlandı.", isError: false)
        }
    }

    func prepareDoHProfile(for provider: DnsProviderResult) {
        guard let doh = provider.dohURL else { return }
        let xml = DnsProbeService.generateDoHMobileConfig(
            providerName: provider.name,
            primaryIP: provider.primaryIP,
            secondaryIP: provider.secondaryIP,
            dohURL: doh
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NetPulse_\(provider.id)_DoH.mobileconfig")
        if (try? xml.write(to: url, atomically: true, encoding: .utf8)) != nil {
            dohProfileURL = url
            dohProfileName = provider.name
        }
    }

    func runBufferbloat() async {
        guard !isRunningBloat else { return }
        isRunningBloat = true
        defer { isRunningBloat = false }
        let res = await BufferbloatService.runTest()
        bufferbloat = res
        recomputeDiagnosisWithCurrentState()
        showToast("Bufferbloat testi tamamlandı (Not: \(res.grade)).", isError: res.error != nil)
    }

    func runPeering() async {
        guard !isRunningPeering else { return }
        isRunningPeering = true
        defer { isRunningPeering = false }
        let res = await LatencyProbeService.runPeeringTest(profile: peeringProfile)
        peeringReport = res
        showToast("Peering testi tamamlandı.", isError: false)
    }

    func refreshReportsData() async {
        incidents = await storage.recentIncidents(limit: 25, days: 7)
        heatmap24h = await storage.hourlyHeatmap(hours: 24)
        summary7d = await storage.sevenDaySummary()
    }

    func prepareEvidenceReportFile() -> URL? {
        let generated = ReportGenerator.generateHTMLReport(
            path: pathSnapshot,
            sample: history.last,
            diagnosis: activeDiagnosis,
            upnpInfo: upnpInfo,
            modemState: modemState,
            bufferbloat: bufferbloat,
            sevenDay: summary7d,
            incidents: incidents
        )
        reportFileURL = generated.fileURL
        return generated.fileURL
    }

    func copySupportSummary() {
        let txt = ReportGenerator.buildSupportSummaryText(
            path: pathSnapshot,
            sample: history.last,
            diagnosis: activeDiagnosis,
            upnpInfo: upnpInfo,
            modemState: modemState,
            sevenDay: summary7d
        )
        #if canImport(UIKit)
        UIPasteboard.general.string = txt
        #endif
        showToast("ISS destek özet metni panoya kopyalandı.", isError: false)
    }

    private func probeGatewayIfNeeded(gwTarget: String?, path: NetworkPathSnapshot, count: Int) async -> ProbeMetrics {
        guard let gw = gwTarget, path.connectionType == .wifi || path.connectionType == .wired else {
            return ProbeMetrics.unreachable(gwTarget ?? "—", sent: 0)
        }
        return await LatencyProbeService.measureTCPLatency(host: gw, port: 80, count: count, timeoutSec: 1.5)
    }

    private func recomputeDiagnosisWithCurrentState() {
        guard let last = history.last else { return }
        let updated = DiagnosisEngine.analyze(
            sample: last,
            path: pathSnapshot,
            history: Array(history.dropLast()),
            bufferbloat: bufferbloat,
            upnpInfo: upnpInfo,
            modemState: modemState
        )
        diagnosis = updated
        if pinnedDeepDiagnosis != nil {
            pinnedDeepDiagnosis = updated
        }
    }

    func showToast(_ text: String, isError: Bool) {
        statusBanner = (text, isError)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                if self?.statusBanner?.text == text {
                    self?.statusBanner = nil
                }
            }
        }
    }
}
