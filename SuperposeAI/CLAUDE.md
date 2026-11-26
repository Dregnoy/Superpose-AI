# SuperposeAI — Project Brain

## Goal
Build an iOS 18+ SwiftUI application replicating **Superpose: AI Pose Camera** — an AI-powered real-time pose coach and camera assistant.

## Tech Stack
- **Language / UI:** Swift 6 / SwiftUI (iOS 18.0+)
- **Camera:** `AVFoundation` (`AVCaptureSession`, `AVCaptureVideoDataOutput`, `AVCapturePhotoOutput`)
- **On-Device Computer Vision:** Apple `Vision` (`VNDetectHumanBodyPoseRequest`, `VNDetectHumanRectanglesRequest`, `VNGeneratePersonSegmentationRequest`)
- **In-App Purchases:** `StoreKit 2` (one-time consumable Shot Packs, no subscriptions)
- **Storage:** `FileManager` (local library) + `UserDefaults` (daily free pack & preferences)
- **Project Generation:** `XcodeGen` (`project.yml`) + pre-generated `SuperposeAI.xcodeproj`

## Directory Map
- `SuperposeAI/App/` — App entry point (`SuperposeAIApp.swift`), `AppState.swift`, `Info.plist`
- `SuperposeAI/Models/` — Domain models (`PoseModels.swift`)
- `SuperposeAI/Services/` — `CameraService.swift`, `PoseVisionService.swift`, `AIPoseGeneratorService.swift`, `LibraryStore.swift`, `ShotPackStore.swift`
- `SuperposeAI/Views/` — `ContentView.swift`, `OnboardingView.swift`, `CameraView.swift`, `PoseOverlayView.swift`, `PoseResultsSheet.swift`, `CoachingSheet.swift`, `LibraryView.swift`, `ShotPacksView.swift`, `PrivacyAndLegalView.swift`
- `SuperposeAI/Resources/` — `Products.storekit`, `Assets.xcassets/`
- `project.yml` — XcodeGen specification

## Style & Architecture Rules
- Keep all real-time lighting, framing, and pose-matching guidance 100% on-device with zero cloud latency.
- Keep AI pose generation behind a `PoseGenerating` protocol so both a live cloud endpoint and an offline demo generator work seamlessly.
- Never include subscription paywalls; use non-expiring Shot Packs (each pack = 4 pose variations).
- Do not store or transmit user photos for model training; allow instant deletion from the in-app library.
