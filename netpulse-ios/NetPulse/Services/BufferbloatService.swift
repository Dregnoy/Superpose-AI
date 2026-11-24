import Foundation

enum BufferbloatService {
    static func runTest() async -> BufferbloatResult {
        let now = Date().timeIntervalSince1970
        let idle = await LatencyProbeService.measureTCPLatency(host: "1.1.1.1", port: 443, count: 4, timeoutSec: 2.0)
        guard idle.reachable, let idleMs = idle.avgMs else {
            return BufferbloatResult(
                timestamp: now,
                idlePingMs: nil,
                downloadMbps: nil,
                uploadMbps: nil,
                downloadLoadedPingMs: nil,
                uploadLoadedPingMs: nil,
                downloadBloatMs: nil,
                uploadBloatMs: nil,
                grade: "—",
                summary: "Boşta internet ping ölçülemedi; Bufferbloat testi başlatılamadı.",
                error: "1.1.1.1 adresine ulaşılamadı."
            )
        }

        let sessionCfg = URLSessionConfiguration.ephemeral
        sessionCfg.timeoutIntervalForRequest = 8.0
        sessionCfg.timeoutIntervalForResource = 9.0
        let session = URLSession(configuration: sessionCfg)
        defer { session.finishTasksAndInvalidate() }

        // 1. İndirme yükü + yüklü ping
        let (dlMbps, dlLoadedMs) = await measureDownloadWithLoadedPing(session: session)
        // 2. Yükleme yükü + yüklü ping
        let (ulMbps, ulLoadedMs) = await measureUploadWithLoadedPing(session: session)

        let dlBloat = dlLoadedMs.map { max(0.0, (($0 - idleMs) * 10).rounded() / 10) }
        let ulBloat = ulLoadedMs.map { max(0.0, (($0 - idleMs) * 10).rounded() / 10) }
        let maxBloat = max(dlBloat ?? 0.0, ulBloat ?? 0.0)

        let grade: String
        let summary: String
        if dlMbps == nil && ulMbps == nil {
            return BufferbloatResult(
                timestamp: now,
                idlePingMs: idleMs,
                downloadMbps: nil,
                uploadMbps: nil,
                downloadLoadedPingMs: dlLoadedMs,
                uploadLoadedPingMs: ulLoadedMs,
                downloadBloatMs: dlBloat,
                uploadBloatMs: ulBloat,
                grade: "—",
                summary: "Hız yükleme/indirme uçlarına erişilemedi.",
                error: "speed.cloudflare.com test uçlarına ulaşılamadı."
            )
        } else if maxBloat <= 10.0 {
            grade = "A+"
            summary = "Yük altında gecikme artışı çok düşük; modem/hat kuyruk yönetimi mükemmel."
        } else if maxBloat <= 30.0 {
            grade = "A"
            summary = "Yük altında gecikme hafif artıyor; oyun ve görüntülü görüşmeler için gayet iyi."
        } else if maxBloat <= 65.0 {
            grade = "B"
            summary = "Orta düzey Bufferbloat tespit edildi; büyük indirmelerde ping yükselmesi hissedilebilir."
        } else if maxBloat <= 140.0 {
            grade = "C"
            summary = "Belirgin Bufferbloat var; indirme/yükleme sırasında diğer cihazlar donma yaşayabilir."
        } else if maxBloat <= 260.0 {
            grade = "D"
            summary = "Yüksek Bufferbloat; modemde SQM / QoS yoksa yoğun trafik pingi ciddi şişiriyor."
        } else {
            grade = "F"
            summary = "Kritik Bufferbloat; yük altında gecikme aşırı yükseliyor."
        }

        return BufferbloatResult(
            timestamp: now,
            idlePingMs: idleMs,
            downloadMbps: dlMbps,
            uploadMbps: ulMbps,
            downloadLoadedPingMs: dlLoadedMs,
            uploadLoadedPingMs: ulLoadedMs,
            downloadBloatMs: dlBloat,
            uploadBloatMs: ulBloat,
            grade: grade,
            summary: summary,
            error: nil
        )
    }

    private static func measureDownloadWithLoadedPing(session: URLSession) async -> (Double?, Double?) {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=8000000") else {
            return (nil, nil)
        }
        async let loadedPing = samplePingUnderLoad(samples: 4)
        let started = DispatchTime.now().uptimeNanoseconds
        var mbps: Double?
        do {
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await session.data(for: req)
            let sec = max(0.2, Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000.0)
            let bitsPerSec = (Double(data.count) * 8.0) / sec
            mbps = ((bitsPerSec / 1_000_000.0) * 10).rounded() / 10
        } catch {
            mbps = nil
        }
        let ping = await loadedPing
        return (mbps, ping)
    }

    private static func measureUploadWithLoadedPing(session: URLSession) async -> (Double?, Double?) {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else {
            return (nil, nil)
        }
        let payload = Data(repeating: 0x41, count: 1_500_000)
        async let loadedPing = samplePingUnderLoad(samples: 4)
        let started = DispatchTime.now().uptimeNanoseconds
        var mbps: Double?
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            _ = try await session.upload(for: req, from: payload)
            let sec = max(0.2, Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000.0)
            let bitsPerSec = (Double(payload.count) * 8.0) / sec
            mbps = ((bitsPerSec / 1_000_000.0) * 10).rounded() / 10
        } catch {
            mbps = nil
        }
        let ping = await loadedPing
        return (mbps, ping)
    }

    private static func samplePingUnderLoad(samples: Int) async -> Double? {
        try? await Task.sleep(for: .milliseconds(250))
        let res = await LatencyProbeService.measureTCPLatency(host: "1.1.1.1", port: 443, count: samples, timeoutSec: 1.5)
        return res.avgMs
    }
}
