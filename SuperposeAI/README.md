# SuperposeAI (iOS 18+ SwiftUI)

**Superpose: AI Pose Camera** uygulamasının Swift 6 / SwiftUI / AVFoundation / Apple Vision / StoreKit 2 kullanılarak geliştirilmiş birebir iOS uygulamasıdır.

## Özellikler
- **Gerçek Zamanlı Cihaz İçi Rehberlik (`PoseVisionService`):** `AVCaptureVideoDataOutput` kareleri üzerinden anlık ışık (luma) analizi, kadraj/kompozisyon kontrolü ve Apple `Vision` (`VNDetectHumanBodyPoseRequest`) ile canlı poz eşleştirme skoru (%).
- **Kamera Üzeri Çizgi / Silüet Katmanları (`PoseOverlayView`):** `Off`, `Silhouette` (hızlı kesikli çizgi iskelet) ve `Contour` (detaylı gövde/kontur) modları.
- **4'lü AI Poz Fikirleri (`AIPoseGeneratorService` & `PoseResultsSheet`):** Tek deneme fotoğrafından 4 poz varyasyonu üretme, seçilen pozu kameraya sabitleme (Pin).
- **Çift Taraflı Koçluk (`CoachingSheet`):** Poz veren kişi (Subject) ve fotoğrafçı (Photographer) için ayrılmış adım adım ipuçları.
- **Kütüphane ve Çoklu Seçim (`LibraryView`):** Yerel kaydetme, çoklu seçimle silme, Apple Fotoğraflar'a aktarma ve *Match Pose*.
- **Shot Pack Ekonomisi (`ShotPackStore` & `Products.storekit`):** Abonelik olmadan günlük ücretsiz Shot Pack + StoreKit 2 tek seferlik Starter Pack (\$2.99) ve Value Pack (\$9.99).

## macOS Üzerinde Xcode ile Çalıştırma
Bu proje Windows ortamında oluşturulduğu için derleme ve iPhone simülatör/cihaz çalıştırması macOS üzerinde yapılmalıdır:

```bash
cd SuperposeAI
brew install xcodegen
xcodegen generate
open SuperposeAI.xcodeproj
```

> **Not:** Canlı kamera testi için fiziksel bir iPhone (iOS 18.0+) kullanmanız gerekir; StoreKit 2 satın alımlarını test etmek için Xcode şemasında `Products.storekit` dosyası otomatik tanımlıdır.
