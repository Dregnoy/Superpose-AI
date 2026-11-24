# NetPulse iOS — Ağ Doktoru ve Modem Kontrolü

**NetPulse iOS**, bilgisayar gerektirmeden iPhone üzerinden ev internetinizin neden yavaşladığını veya koptuğunu analiz eden saf SwiftUI (iOS 17+) uygulamasıdır.

## Neler Yapabilir? (iOS Sandbox Dahilinde)

- **3 Katmanlı Canlı Teşhis (`Özet`):** Modem (`en0` ağ geçidi), İnternet (`1.1.1.1` / `8.8.8.8`) ve UDP DNS gecikmesini ölçer, 3 örneklik histerezis ile geçici dalgalanmaları ayıklar ve Swift Charts grafiğinde canlı gösterir.
- **Modem Kontrol & Fiziksel DSL Sağlığı (`Air5650TT`):**
  - UPnP WAN durumu (`Connected`/`Disconnected`), dış IP ve onaylı **WAN Bağlantısını Tazele (UPnP)**.
  - Modem kullanıcı adı ve şifresini **iOS Keychain** içinde şifreli saklama.
  - Fiziksel DSL senkron hızı, **SNR Marjı**, **CRC Hataları** ve hat zayıflaması okuma + onaylı **Modemi Yeniden Başlat**.
- **DNS Hız Testi & iOS DoH Profili:** Gerçek UDP DNS ölçümü yapar ve seçtiğiniz sağlayıcı için doğrudan iOS Ayarlar'a kurulabilen `.mobileconfig` şifreli DNS (DoH) profili oluşturur.
- **Bufferbloat & Peering:** Yük altında ping şişmesini (`A+`–`F` notu) ve Oyun (EU) / Toplantı / Yayın gecikmesini ölçer.
- **24 Saatlik Hafıza & ISS Kanıt Raporu:** 7 günlük olay geçmişi, 24 saatlik ısı haritası ve WhatsApp/e-posta üzerinden paylaşılabilen tek parça HTML ISS teknik raporu üretir.

> **Apple iOS Sandbox Sınırları:** iOS güvenlik kuralları gereği hiçbir üçüncü taraf iOS uygulaması başka uygulamaların internet hızını/önceliğini kısıtlayamaz, çevredeki Wi-Fi kanallarını tarayamaz veya yerel ağ ARP tablosunu okuyamaz; bu özellikler Windows masaüstü [NetPulse.exe](../netpulse/dist/NetPulse.exe) sürümünde yer almaktadır.

---

## iPhone'a Nasıl Kurulur?

### Yöntem 1: Mac Olmadan Windows'tan Kurulum (GitHub Actions + SideStore / AltStore / Sideloadly)
Bu projede hazır [build-ios.yml](.github/workflows/build-ios.yml) dosyası bulunur:
1. `netpulse-ios` klasörünü GitHub'da yeni (ör. özel/private) bir depoya gönderin (`git init && git add . && git commit -m "NetPulse iOS"`).
2. GitHub deposunda **Actions → Build & Test NetPulse iOS → Run workflow** çalıştırın (veya `main`'e push yaptığınızda otomatik çalışır).
3. İşlem bitince oluşan **Artifacts → `NetPulse-Unsigned-IPA`** içinden `NetPulse.ipa` dosyasını indirin.
4. Windows PC'den **Sideloadly**, **AltStore** veya **SideStore** aracılığıyla iPhone'unuza imzasız `NetPulse.ipa`'yı kendi Apple ID'nizle imzalayıp kurun.
5. İlk açılışta **Yerel Ağ (`Local Network`)** iznine **İzin Ver** deyin (modeminizin `192.168.2.1` adresine erişebilmesi için gereklidir).

### Yöntem 2: Mac + Xcode ile Doğrudan Kurulum
1. Mac'te [NetPulse.xcodeproj](NetPulse.xcodeproj) dosyasını açın (veya `xcodegen generate` çalıştırın).
2. `Signing & Capabilities` sekmesinde kendi Apple Team'inizi ve benzersiz bir Bundle ID seçin.
3. iPhone'u bağlayıp `⌘R` ile doğrudan cihazınıza yükleyin.
