# BluePad iOS — Proje Mimarisi ve Kurallar

## 1. Proje Amacı
**BluePad**, Android'deki `io.appground.blek` (*Bluetooth Keyboard & Mouse*) uygulamasının iOS 17+ için geliştirilmiş sıfır dış bağımlılıklı, saf native **SwiftUI** karşılığıdır. iPhone ve iPad'i karşı bilgisayara/TV'ye hiçbir sunucu yazılımı veya sürücü kurmadan doğrudan standart bir Bluetooth Klavye, Çoklu Dokunmatik Trackpad, Medya/TV Kumandası, Sunum Kumandası, Barkod/QR Tarayıcı, Sesli Dikte ve Makro Paneline dönüştürür.

## 2. Teknoloji Yığını
- **Dil / Arayüz:** Swift 5.9+, SwiftUI (iOS 17.0+), UIKit dokunma ve `UIKeyInput` köprüleri
- **Bluetooth HID:** `CoreBluetooth` (`CBPeripheralManager`) üzerinden sunucusuz **HID over GATT Profile (HOGP)**
- **Hareket & Sensörler:** `CoreMotion` (`CMMotionManager` ile jiroskop tabanlı Hava Faresi)
- **Tarama & Dikte:** `AVFoundation` (Canlı QR/Barkod kamera tarayıcısı), `Speech` + `AVAudioEngine` (Türkçe/İngilizce sesle yazma)
- **Kalıcılık & Derleme:** `FileManager` JSON depolama (`Application Support/BluePad`), `project.yml` (XcodeGen), önceden üretilmiş `BluePad.xcodeproj` ve GitHub Actions `macos-15` imzasız `.ipa` hattı (`.github/workflows/build-ios.yml`)

## 3. Dizin Haritası
- `BluePad/App/` — `BluePadApp.swift`, `AppViewModel.swift`
- `BluePad/Models/` — `HIDModels.swift`, `KeyboardLayout.swift`, `AppSettingsAndMacros.swift`
- `BluePad/Services/` — `HOGPUUIDs.swift`, `HIDReportMap.swift`, `MouseMotionProcessor.swift`, `BLEHIDPeripheralService.swift`, `AirMouseMotionService.swift`, `SpeechDictationService.swift`, `MacroStorageService.swift`
- `BluePad/Views/` — `Theme.swift`, `StatusHeaderBar.swift`, `TrackpadView.swift`, `KeyboardView.swift`, `RemotePresenterView.swift`, `ToolsView.swift`, `BarcodeScannerSheet.swift`, `ConnectionSettingsView.swift`
- `BluePad/Resources/` — `Info.plist`, `Assets.xcassets`
- `BluePadTests/` — `BluePadCoreTests.swift` (`XCTest`)

## 4. Yasaklı Eylemler (Do NOT Do)
- **Kısa 16-bit SIG UUID Yasak:** `CBPeripheralManager` veya `CBMutableDescriptor` içinde `"1812"`, `"2908"`, `"180A"`, `"180F"`, `"2A4B"` gibi kısa 16-bit UUID string'leri ASLA kullanılmaz. Daima tam 128-bit kanonik string (`"0000XXXX-0000-1000-8000-00805F9B34FB"`) kullanılır.
- **Önbellekli Dinamik/Şifreli Karakteristik Yasak:** `.readEncryptionRequired`, `.writeEncryptionRequired`, `.write`, `.writeWithoutResponse` veya `.notify` özellikli hiçbir `CBMutableCharacteristic` nesnesine `value:` parametresiyle `nil` dışında değer verilmez (iOS'ta `NSInternalInconsistencyException` çökmesine yol açar). Tüm okumalar `peripheralManager(_:didReceiveRead:)` içinde `request.offset` dilimlemesi ile dinamik sunulur.
- **`.extendedProperties` Yasak:** Protocol Mode (`0x2A4E`), Boot Keyboard Output (`0x2A32`) ve Output Report (`0x2A4D`) karakteristiklerine `.extendedProperties` özelliği ASLA eklenmez (ekstra descriptor enjekte ederek host HID bağlamasını bozar).
- **Özel API / Dış Bağımlılık / Ücretli Entitlement Yasak:** `AppKit`, özel Apple API'leri, üçüncü parti SPM/CocoaPods paketleri veya ücretsiz Apple ID ile yan yüklemeyi (SideStore/AltStore/Sideloadly) bozacak ücretli entitlement'lar eklenmez.
- **GAP/GATT Manuel Kaydı Yasak:** Generic Access (`0x1800`) ve Generic Attribute (`0x1801`) servisleri iOS işletim sistemi tarafından yönetilir; `CBPeripheralManager`'a manuel eklenmez.
