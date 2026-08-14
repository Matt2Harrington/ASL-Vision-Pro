# ASL Vision Pro

A visionOS app that observes a person signing ASL and displays live, on-device captions.

- **Who signs:** another person in view (Enterprise main-camera access).
- **Compute:** fully on-device (Neural Engine) — no footage or landmarks leave the headset.
- **Scope:** fingerspelling + isolated signs now; continuous translation as a stretch.

See **[FEASIBILITY.md](FEASIBILITY.md)** (why this is hard) and **[ARCHITECTURE.md](ARCHITECTURE.md)** (the committed design). Model work is in **[MODEL_PLAN.md](MODEL_PLAN.md)**.

> **Experimental.** Recognition can be wrong. Never rely on it for critical communication.

---

## Project layout

```
ASLVisionPro/
  App/
    ASLVisionProApp.swift      # @main entry, injects the pipeline
    ContentView.swift          # the single screen: person view + captions + controls
  Pipeline/
    SignFrame.swift            # landmark / result data types
    CameraFeedProvider.swift   # Phase 0 — enterprise main-camera frames
    LandmarkExtractor.swift    # Phase 1 — Vision hand/body/face landmarks
    SignSegmenter.swift        # sliding-window segmentation of continuous signing
    FeatureEncoder.swift       # window -> normalized tensor (must match training!)
    SignRecognizer.swift       # the swappable ML stage (stub + Core ML impl)
    TranslationPipeline.swift  # orchestrator, publishes captions to the UI
  UI/
    CaptionView.swift          # live revisable caption
    LandmarkOverlayView.swift  # Phase 1 debug overlay
  Support/
    Info.plist                 # usage strings
    ASLVisionPro.entitlements  # main-camera-access entitlement
```

The pipeline is wired end-to-end today using `StubSignRecognizer`, so on real hardware you can bring up **Phase 0 (frames)** and **Phase 1 (landmark overlay)** before any model exists.

## Build

Requires **Apple Vision Pro hardware** — the simulator provides no camera or hand data.

1. `brew install xcodegen`
2. `xcodegen generate` (creates `ASLVisionPro.xcodeproj`)
3. Open in Xcode, set your **Development Team** and a provisioning profile carrying the
   managed `main-camera-access` entitlement (see ARCHITECTURE.md §1).
4. Run on a connected Vision Pro.

Prefer not to use XcodeGen? Create a new visionOS **App** target in Xcode and add the
`ASLVisionPro/` folder plus the Info.plist / entitlements from `Support/`.

## Phase status

| Phase | What | Code |
|---|---|---|
| 0 | Enterprise camera frames on device | `CameraFeedProvider` |
| 1 | Live landmark overlay | `LandmarkExtractor`, `LandmarkOverlayView` |
| 2 | On-device fingerspelling + isolated signs | swap `StubSignRecognizer` → `CoreMLSignRecognizer` |
| 3 | Compact continuous translator + learned segmentation | `SignRecognizer`, `SignSegmenter` |
| 4 | UX + ethics hardening | UI + consent flow |

To enable Phase 2, drop a trained `SignModel.mlpackage` into the target and construct
`TranslationPipeline(recognizer: CoreMLSignRecognizer(model:labels:))`. See MODEL_PLAN.md.
