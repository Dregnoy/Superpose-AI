# NetPulse iOS — Proje Mimarisi ve Kurallar

## 1. Proje Amacı
**NetPulse iOS**, Windows için geliştirilen NetPulse Ağ Doktoru ve Modem Kontrol uygulamasının iOS 17+ için sıfır dış bağımlılıklı, saf native **SwiftUI** sürümüdür. Ev ağınızdaki yavaşlamaları ve kopmaları modem (`Air5650TT` vb.), ISS/internet omurgası, DNS ve Bufferbloat katmanlarında teşhis eder, fiziksel DSL değerlerini (SNR, CRC, hız, hat zayıflaması) okur ve UPnP/Keychain destekli güvenli kurtarma sağlar.

## 2. Teknoloji Yığını
- **Dil / Arayüz:** Swift 5.9+, SwiftUI (iOS 17.0+), Swift Charts (`Charts.framework`)
- **Ağ & Ölçüm:** `Network.framework` (`NWPathMonitor`, `NWConnection`), `URLSession`, public `Darwin.getifaddrs`
- **Güvenlik & Depolama:** `Security.framework` (iOS Keychain), `FileManager` JSON kalıcılığı (`Application Support`)
- **Derleme:** `project.yml` (XcodeGen), önceden üretilmiş `NetPulse.xcodeproj` ve GitHub Actions macOS CI (`.github/workflows/build-ios.yml`)

## 3. Dizin Haritası
- `NetPulse/App/` — `NetPulseApp.swift`, `AppViewModel.swift`
- `NetPulse/Models/` — `NetworkModels.swift` (`Sendable` + `Codable` modeller)
- `NetPulse/Services/` — Ağ yolu, gecikme/Peering, UDP DNS + DoH `.mobileconfig`, Bufferbloat, iOS Keychain kasası, UPnP WAN unicast istemcisi, AirTies (`Air5650TT`) DSL/Reboot istemcisi, teşhis motoru, kalıcı depolama ve HTML/metin ISS kanıt raporu üreteci
- `NetPulse/Views/` — `Theme.swift`, `SummaryView.swift`, `ModemControlView.swift`, `ToolsView.swift`, `ReportsView.swift`
- `NetPulse/Resources/` — `Info.plist`, `Assets.xcassets`
- `NetPulseTests/` — `NetPulseCoreTests.swift` (`XCTest`)

## 4. Yasaklı Eylemler (Do NOT Do)
- **Özel / macOS API Yasak:** `net/route.h`, `RTM_GET`, `AppKit` veya özel Apple API'leri asla kullanılmaz.
- **Ücretli Entitlement Yasak:** `com.apple.developer.networking.multicast` entitlement eklenmez (ücretsiz Apple ID ile SideStore/AltStore/Sideloadly kurulumunu bozmamak için UPnP unicast HTTP/UDP kullanılır).
- **Şifre Güvenliği:** Modem şifresi yalnızca iOS Keychain içinde tutulur; hiçbir log, durum nesnesi veya ISS raporuna yazılmaz.
- **SSRF Koruması:** Modem ve UPnP istekleri `validatePrivateLANHost` üzerinden yalnızca RFC1918 özel LAN IPv4 adresleriyle (`10/8`, `172.16/12`, `192.168/16`) sınırlandırılır.
- **Onaysız Kesinti Yasak:** `modem_reconnect_wan` ve `modem_reboot` mutlaka açık kullanıcı onayı (`confirmed: true`) gerektirir; `factory_default` kesinlikle kapsam dışıdır.
- **Süreklilik Güvenliği:** Tüm `CheckedContinuation` çağrıları çift devam çökmesini önlemek için `LockedOnce` ile korunur; `AirTiesModemClient` daima çift tırnaklı `<?xml version="1.0" encoding="UTF-8"?>` ve `<xmlrequest version="1.0.1">` kullanır.
