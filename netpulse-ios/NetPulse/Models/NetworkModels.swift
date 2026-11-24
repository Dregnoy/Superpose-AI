import Foundation

enum ConnectionKind: String, Codable, Sendable {
    case wifi = "Wi-Fi"
    case cellular = "Hücresel"
    case wired = "Ethernet"
    case unavailable = "Bağlı Değil"
}

struct NetworkPathSnapshot: Codable, Equatable, Sendable {
    var connectionType: ConnectionKind
    var isConnected: Bool
    var isExpensive: Bool
    var isConstrained: Bool
    var isVPNActive: Bool
    var localIPv4: String?
    var inferredGatewayIP: String?

    static let empty = NetworkPathSnapshot(
        connectionType: .unavailable,
        isConnected: false,
        isExpensive: false,
        isConstrained: false,
        isVPNActive: false,
        localIPv4: nil,
        inferredGatewayIP: nil
    )
}

struct ProbeMetrics: Codable, Equatable, Sendable {
    var target: String
    var sent: Int
    var received: Int
    var lossPct: Double
    var avgMs: Double?
    var maxMs: Double?
    var jitterMs: Double?
    var reachable: Bool

    static func unreachable(_ target: String, sent: Int = 0) -> ProbeMetrics {
        ProbeMetrics(
            target: target,
            sent: sent,
            received: 0,
            lossPct: sent > 0 ? 100.0 : 0.0,
            avgMs: nil,
            maxMs: nil,
            jitterMs: nil,
            reachable: false
        )
    }
}

struct TelemetrySample: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var timestamp: TimeInterval
    var gateway: ProbeMetrics
    var internet: ProbeMetrics
    var dnsMs: Double?
    var pathType: ConnectionKind
}

struct UpnpRouterInfo: Codable, Equatable, Sendable {
    var available: Bool = false
    var routerName: String?
    var accessType: String?
    var maxDownMbps: Double?
    var maxUpMbps: Double?
    var routerDownMbps: Double = 0.0
    var routerUpMbps: Double = 0.0
    var wanStatus: String?
    var wanLastError: String?
    var wanUptimeSec: Int?
    var wanExternalIP: String?
    var wanControlAvailable: Bool = false
    var note: String?
}

enum DslLineHealth: String, Codable, Sendable {
    case unknown
    case good
    case warn
    case bad

    var label: String {
        switch self {
        case .unknown: return "KISMİ"
        case .good: return "SAĞLIKLI"
        case .warn: return "ORTA"
        case .bad: return "SORUNLU"
        }
    }
}

struct ModemDslStats: Codable, Equatable, Sendable {
    var connected: Bool = false
    var routerModel: String?
    var firmware: String?
    var dslStatus: String?
    var physLinkStatus: String?
    var downlinkKbps: Int?
    var uplinkKbps: Int?
    var crcErrors: Int?
    var atucCrcErrors: Int?
    var snrDownDb: Double?
    var snrUpDb: Double?
    var attenDownDb: Double?
    var attenUpDb: Double?
    var lineHealth: DslLineHealth = .unknown
    var healthNote: String = "Henüz okunmadı."
    var readAt: TimeInterval = 0
    var error: String?
}

struct ModemState: Codable, Equatable, Sendable {
    var credentialsSaved: Bool = false
    var savedHost: String?
    var savedUsername: String?
    var dslStats: ModemDslStats?
}

enum ActionSafety: String, Codable, Sendable {
    case safe
    case disruptive
}

enum DiagnosisSeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

enum HealthStatus: String, Codable, Sendable {
    case healthy
    case degraded
    case critical

    var titleTR: String {
        switch self {
        case .healthy: return "Sağlıklı"
        case .degraded: return "Yavaşlama"
        case .critical: return "Kritik"
        }
    }
}

enum DiagnosisLayer: String, Codable, Sendable {
    case healthy
    case modemWan = "modem_wan"
    case wifiLan = "wifi_lan"
    case ispLine = "isp_line"
    case dns
    case vpn
    case bufferbloat
}

struct RootCause: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(layer.rawValue)-\(title)" }
    var layer: DiagnosisLayer
    var severity: DiagnosisSeverity
    var title: String
    var evidence: String
}

enum ModemActionKind: String, Codable, Sendable {
    case modemReconnectWAN = "modem_reconnect_wan"
    case modemReboot = "modem_reboot"
    case runDnsTest = "run_dns_test"
    case runBufferbloat = "run_bufferbloat"
}

struct RecommendedAction: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID.rawValue }
    var actionID: ModemActionKind
    var label: String
    var description: String
    var safety: ActionSafety
    var requiresConfirmation: Bool
}

struct DiagnosisReport: Codable, Equatable, Sendable {
    var timestamp: TimeInterval
    var healthScore: Int
    var status: HealthStatus
    var headline: String
    var summary: String
    var rootCauses: [RootCause]
    var actions: [RecommendedAction]
}

struct DnsProviderResult: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var primaryIP: String
    var secondaryIP: String?
    var dohURL: String?
    var reachable: Bool
    var avgMs: Double?
    var minMs: Double?
    var maxMs: Double?
}

struct DnsBenchmarkSummary: Codable, Equatable, Sendable {
    var timestamp: TimeInterval
    var fastestProvider: DnsProviderResult?
    var results: [DnsProviderResult]
}

struct BufferbloatResult: Codable, Equatable, Sendable {
    var timestamp: TimeInterval
    var idlePingMs: Double?
    var downloadMbps: Double?
    var uploadMbps: Double?
    var downloadLoadedPingMs: Double?
    var uploadLoadedPingMs: Double?
    var downloadBloatMs: Double?
    var uploadBloatMs: Double?
    var grade: String
    var summary: String
    var error: String?
}

enum PeeringProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case oyun
    case toplanti
    case yayin

    var id: String { rawValue }
    var title: String {
        switch self {
        case .oyun: return "Oyun (EU)"
        case .toplanti: return "Toplantı"
        case .yayin: return "Yayın"
        }
    }
}

struct PeeringTargetResult: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(name)-\(host)" }
    var name: String
    var host: String
    var port: UInt16
    var reachable: Bool
    var rttMs: Double?
    var protocolName: String
}

struct PeeringReport: Codable, Equatable, Sendable {
    var timestamp: TimeInterval
    var profile: PeeringProfile
    var results: [PeeringTargetResult]
    var summary: String
}

struct IncidentRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var startedAt: TimeInterval
    var endedAt: TimeInterval?
    var severity: DiagnosisSeverity
    var title: String
    var peakPingMs: Double
    var peakLossPct: Double
    var note: String?
}

struct HourlyBucket: Codable, Equatable, Identifiable, Sendable {
    var id: String { hourLabel }
    var hourLabel: String
    var samples: Int
    var avgInetMs: Double?
    var maxInetMs: Double?
    var lossPct: Double
    var incidentCount: Int
}

struct SevenDaySummary: Codable, Equatable, Sendable {
    var totalSamples: Int = 0
    var totalIncidents: Int = 0
    var avgInetMs: Double?
    var maxInetMs: Double?
    var worstHourRange: String?
}

struct AppSettings: Codable, Equatable, Sendable {
    var autoReadDslOnLaunch: Bool = true
    var pollingIntervalSec: Double = 2.5
    var customGatewayIP: String = ""
}
