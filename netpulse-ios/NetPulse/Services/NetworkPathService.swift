import Darwin
import Foundation
import Network

enum LocalNetworkHelper {
    /// Genel iOS SDK (`Darwin.getifaddrs`) kullanarak en0 / yerel arayüzden IPv4 ve varsayılan ağ geçidini çıkarır.
    static func detectLocalIPv4AndGateway() -> (localIP: String?, gatewayIP: String?) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (nil, nil)
        }
        defer { freeifaddrs(ifaddr) }

        var candidateIP: String?
        var candidateGateway: String?
        var en0Found = false

        var ptr = Optional(firstAddr)
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let sa = current.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: current.pointee.ifa_name)
            let isUp = (Int32(current.pointee.ifa_flags) & IFF_UP) != 0
            let isLoopback = (Int32(current.pointee.ifa_flags) & IFF_LOOPBACK) != 0
            guard isUp, !isLoopback else { continue }

            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var addr = sin.sin_addr
            guard inet_ntop(AF_INET, &addr, &ipBuf, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }
            let ipStr = String(cString: ipBuf)
            guard (try? validatePrivateLANHost(ipStr)) != nil else { continue }

            let gwStr = inferGatewayIP(ip: addr.s_addr, netmaskPtr: current.pointee.ifa_netmask)
            if name == "en0" {
                en0Found = true
                candidateIP = ipStr
                candidateGateway = gwStr
                break
            } else if !en0Found && name.hasPrefix("en") && candidateIP == nil {
                candidateIP = ipStr
                candidateGateway = gwStr
            }
        }
        return (candidateIP, candidateGateway)
    }

    private static func inferGatewayIP(ip rawIP: UInt32, netmaskPtr: UnsafeMutablePointer<sockaddr>?) -> String {
        let hostIP = UInt32(bigEndian: rawIP)
        var maskHost: UInt32 = 0xFFFFFF00
        if let maskPtr = netmaskPtr, maskPtr.pointee.sa_family == UInt8(AF_INET) {
            let maskSin = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let m = UInt32(bigEndian: maskSin.sin_addr.s_addr)
            if m != 0 && m != 0xFFFFFFFF {
                maskHost = m
            }
        }
        let networkAddr = hostIP & maskHost
        let inferredHost = networkAddr | 1
        var outAddr = in_addr(s_addr: inferredHost.bigEndian)
        var outBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        if inet_ntop(AF_INET, &outAddr, &outBuf, socklen_t(INET_ADDRSTRLEN)) != nil {
            return String(cString: outBuf)
        }
        return "192.168.1.1"
    }
}

final class NetworkPathService: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.netpulse.ios.pathmonitor")
    private let lock = NSLock()
    private var latestSnapshot: NetworkPathSnapshot = .empty
    private var onUpdate: (@Sendable (NetworkPathSnapshot) -> Void)?

    func start(onUpdate: (@Sendable (NetworkPathSnapshot) -> Void)? = nil) {
        lock.lock()
        self.onUpdate = onUpdate
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let snapshot = Self.buildSnapshot(from: path)
            self.lock.lock()
            self.latestSnapshot = snapshot
            let cb = self.onUpdate
            self.lock.unlock()
            cb?(snapshot)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    func currentSnapshot() -> NetworkPathSnapshot {
        lock.lock()
        let current = latestSnapshot
        lock.unlock()
        let lan = LocalNetworkHelper.detectLocalIPv4AndGateway()
        return NetworkPathSnapshot(
            connectionType: current.connectionType,
            isConnected: current.isConnected,
            isExpensive: current.isExpensive,
            isConstrained: current.isConstrained,
            isVPNActive: current.isVPNActive,
            localIPv4: lan.localIP ?? current.localIPv4,
            inferredGatewayIP: lan.gatewayIP ?? current.inferredGatewayIP
        )
    }

    private static func buildSnapshot(from path: NWPath) -> NetworkPathSnapshot {
        let kind: ConnectionKind
        if path.status != .satisfied {
            kind = .unavailable
        } else if path.usesInterfaceType(.wifi) {
            kind = .wifi
        } else if path.usesInterfaceType(.cellular) {
            kind = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            kind = .wired
        } else {
            kind = .wifi
        }

        let isVPN = path.availableInterfaces.contains { iface in
            let lower = iface.name.lowercased()
            return lower.hasPrefix("utun") || lower.hasPrefix("ppp") || lower.hasPrefix("ipsec") || iface.type == .other
        }
               let lan: (localIP: String?, gatewayIP: String?) = (kind == .wifi || kind == .wired)
            ? LocalNetworkHelper.detectLocalIPv4AndGateway()
            : (localIP: nil, gatewayIP: nil)
        return NetworkPathSnapshot(
            connectionType: kind,
            isConnected: path.status == .satisfied,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            isVPNActive: isVPN,
            localIPv4: lan.localIP,
            inferredGatewayIP: lan.gatewayIP
        )
    }
}
