# BluePad iOS — Sunucusuz Bluetooth HID Klavye, Mouse & Kumanda

**BluePad**, Android'deki `io.appground.blek` (*Bluetooth Keyboard & Mouse*) uygulamasının iOS 17+ için sıfır dış bağımlılıkla yazılmış saf native **SwiftUI** karşılığıdır.

Karşı bilgisayara, tablete veya akıllı TV'ye **hiçbir yardımcı sunucu (server) programı veya sürücü kurmadan**, iPhone/iPad'inizi doğrudan standart bir **Bluetooth HID (HOGP)** klavye, çoklu dokunmatik trackpad, medya/TV kumandası ve sunum aracı olarak kullanabilirsiniz.

## Özellikler (`io.appground.blek` Karşılaştırması)

| Özellik | Açıklama |
|---|---|
| **Sunucusuz Bluetooth HID (HOGP)** | CoreBluetooth `CBPeripheralManager` üzerinden tam 128-bit UUID'li GATT HID (`0x1812`), Batarya (`0x180F`) ve Cihaz Bilgisi (`0x180A`) servisleri |
| **Çoklu Dokunmatik Trackpad** | 1 parmak imleç, 2 parmak dikey/yatay kaydırma, dokunarak tık, 2 parmak sağ tık, 3 parmak orta tık, çift dokun+sürükle ve basılı tutulabilen Sol/Orta/Sağ tuşlar |
| **Hava Faresi (Jiroskop)** | `CoreMotion` tabanlı jiroskop ile telefonu havada hareket ettirerek imleç ve sunum işaretçisi kontrolü |
| **Tam PC Klavyesi & 6 Dil Düzeni** | `Türkçe Q`, `Türkçe F`, `US QWERTY`, `UK QWERTY`, `Almanca QWERTZ`, `Fransızca AZERTY` + canlı iOS klavye (`UIKeyInput`) + tek/çift dokunuşlu yapışkan/kilitli `Ctrl/Alt/AltGr/Shift/Win-⌘` + `F1–F12`, `Numpad`, `Oklar` |
| **Medya, TV & Sunum Kumandası** | Oynat/Duraklat, Ses/Parlaklık, TV D-Pad, Sistem Uyku/Uyandır/Güç ve zamanlayıcılı büyük butonlu Sunum Kumandası |
| **Uyanık Tut (Mouse Jiggler)** | Bilgisayarın kilitlenmesini veya uyumasını önleyen ayarlanabilir aralıklı Mikro Fare (±1px) / Shift Darbesi |
| **QR / Barkod Tarayıcı** | Kamera ile QR, EAN-13, Code128 vb. kodları okuyup bağlı cihaza anında klavyeden yazma |
| **Sesle Yazma (Dikte) & Pano** | Türkçe/İngilizce konuşma tanıma ve iPhone panosundaki metni tek dokunuşla hedef cihaza yazma |
| **Özel Makro Editörü** | Hazır 12 makro + kullanıcı tanımlı tuş kombinasyonu, metin, medya ve sistem makroları |

## Nasıl Çalışır? (Sunucusuz BLE HOGP)

1. iPhone, `CBPeripheralManager` ile standart Bluetooth HID (`00001812-0000-1000-8000-00805F9B34FB`) servisini yayınlar.
2. Composite **USB HID 1.11 Report Map** sayesinde Windows, macOS, Linux, SteamOS, ChromeOS, Android/Google TV ve iPadOS cihazları iPhone'u gerçek bir donanım Klavye + 5 Tuşlu Fare + Medya Kumandası olarak tanır.
3. Host işletim sisteminden gelen `Caps Lock` / `Num Lock` LED durumları bile Bluetooth üzerinden iPhone arayüzüne anlık yansır.

## Kurulum ve Derleme

### 1. Xcode ile Doğrudan Derleme (Mac)
1. Depoyu Mac'e aktarın ve `BluePad.xcodeproj` dosyasını açın (veya `xcodegen generate` çalıştırın).
2. `Signing & Capabilities` sekmesinde kendi Apple ID Team'inizi seçin (`com.bluepad.ios` bundle ID'sini benzersiz bir adla değiştirebilirsiniz).
3. Gerçek bir iPhone/iPad seçip **Run (`⌘R`)** yapın. *(Not: iOS Simülatörü Bluetooth LE Çevre Birimi radyosunu simüle etmez; Bluetooth testi gerçek cihaz gerektirir.)*

### 2. GitHub Actions ile Ücretsiz İmzasız `.ipa` Üretme (SideStore / AltStore / Sideloadly)
Bu projede ücretsiz Apple ID ile uyumlu **`.github/workflows/build-ios.yml`** hazırdır:
1. Projeyi GitHub deposuna yükleyin (`main` / `master` dalına push veya `Actions → Run workflow`).
2. `macos-15` koşucusu `BluePadTests` birim testlerini çalıştırır ve imzasız **`BluePad-Unsigned-IPA`** (`BluePad.ipa`) çıktısını üretir.
3. İndirdiğiniz `.ipa` dosyasını Windows/Mac üzerinden **Sideloadly**, **AltStore** veya **SideStore** ile iPhone'unuza yükleyin. (Ücretli Apple Developer entitlement'ı gerekmez.)

## Eşleştirme Adımları
1. Uygulamayı iPhone'da açın ve Bluetooth iznini onaylayın (üst çubukta `Eşleştirmeye Hazır` görünür).
2. Kontrol edeceğiniz cihazda (Windows / Mac / TV) **Bluetooth Ayarları → Yeni Cihaz Ekle** bölümüne girin.
3. Listeden **`BluePad`** cihazını seçip eşleştirme onayını kabul edin.
4. Bağlantı kurulunca üst çubuk yeşile (`Bağlı (1 cihaz)`) döner.

> **Not:** Bir cihazı yeniden eşleştirirken bağlantı hemen düşüyorsa eski şifreleme anahtarı (bond) takılmış olabilir. Hem hedef cihazdan hem iPhone *Ayarlar → Bluetooth* menüsünden aygıtı **Unut** yapıp yeniden eşleştirin.
