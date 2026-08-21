# ASL Vision Pro

Two apps — **visionOS** and **iOS** — sharing one on-device ASL recognition pipeline.
Practise your signing, look signs up, follow live speech, and (where permitted) caption someone
else signing. Nothing leaves the device.

> **Experimental prototype.** The recognizer knows five signs. Recognition can be wrong.
> Never rely on it for critical communication.

---

## Status

| Mode | State | Notes |
|---|---|---|
| **Dictionary** | ✅ Working | 32 signs with full phonological parameters. No model needed |
| **Listen** | ✅ Working | Speech → live captions, on-device. Needs OS 26 |
| **Translation Check** | ✅ Working | Dev screen: gloss → English on the local LLM |
| **Practice** | ⚠️ 5 signs | Trained model, real but narrow |
| **Interpret** | ⚠️ 5 signs | Works on iPhone; visionOS needs Apple's camera entitlement |
| **Record Clips** | ✅ Working | Captures auto-labelled training data |

**Recognizer:** HELLO · NO · PLEASE · WATER · YES · NONE — **91.8% on held-out signers**
(chance = 17%), a 900 KB quantized Core ML model trained on 500 clips from 21 Deaf signers.

**Translation:** ASL gloss → English via Apple's on-device foundation model. No training
required; prompt engineering alone reached 5/6 correct on the evaluation set.

Runs today on iPhone. visionOS runs everything except Interpret, which is gated on an Apple
enterprise entitlement (see [ENTITLEMENT_GUIDE.md](ENTITLEMENT_GUIDE.md)).

---

## How it works

```
camera / hand tracking
   → landmarks (Vision, or ARKit 3D on visionOS)
   → segmentation (~1.3s span)
   → Core ML classifier          → glosses
   → on-device language model    → English
```

Two stages, split by what each is good at. The classifier *perceives* — fast, calibrated,
reads motion — but cannot produce English, because ASL is not English word order. The language
model closes exactly that gap, and only ever sees text, never footage.

**24 source files are shared** between the two apps. Only the sensor source and app shell
differ.

---

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
export DEVELOPMENT_TEAM=XXXXXXXXXX   # your Apple Team ID; omit for simulator-only
xcodegen generate
open ASLVisionPro.xcodeproj
```

**Setting up from scratch?** [SETUP.md](SETUP.md) walks through it step by step, including
signing to a physical iPhone and the failures worth knowing about in advance.

Schemes: **ASLVisionPro** (visionOS) · **ASLVisionPro-iOS** · **ASLVisionProTests** (85 tests).

The trained model is gitignored — the app builds without it and says so on screen. To produce
one, see [TRAINING_GUIDE.md](TRAINING_GUIDE.md).

### Hardware
- **iPhone** — everything except visionOS-specific modes. This is the fastest path to seeing it work.
- **Vision Pro** — required for Practice's 3D hand tracking; the simulator has no camera or hand data.

---

## Layout

```
ASLVisionPro/
  Shared/
    Pipeline/       FrameSource, LandmarkExtractor, SignSegmenter, FeatureEncoder,
                    SignRecognizer, SignVerifier, TutorSession, DataCollector,
                    GlossInterpreter, SignCatalog, TranslationPipeline, RecognizerFactory
    UI/             DesignSystem, DictionaryView, ListenView, CaptionView,
                    DataCollectorView, TranslationCheckView, LandmarkOverlayView
    Resources/      signs.json (dictionary), labels.json (model classes)
    Models/         SignModel.mlpackage (gitignored)
  visionOS/         app shell, HandTrackingSource, VisionProCameraSource, TutorView
  iOS/              app shell, iPhoneCameraSource, CameraPreview
Tests/              13 suites, 85 tests
training/           Python: fetch → import → train → export
config/
  feature_spec.json THE preprocessing contract, read by Swift and Python alike
```

Two structural decisions worth preserving:

- **`SignRecognizing` is the one swappable stage.** Stub, classifier, or CTC model swap behind
  it without touching capture, landmarks, segmentation, or captions.
- **`config/feature_spec.json` is the single source of truth.** Drift between the Swift encoder
  and the Python trainer is the failure mode that silently destroys accuracy — so neither side
  declares these constants itself.

---

## Documentation

| Doc | What it covers |
|---|---|
| [SETUP.md](SETUP.md) | Step-by-step: clone → build → run on your own iPhone |
| [TRAINING_GUIDE.md](TRAINING_GUIDE.md) | How the model was trained, where data lives, how to improve it |
| [ML_PLAYBOOK.md](ML_PLAYBOOK.md) | Reusable procedure for any on-device model + local LLM |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design and the capability ladder |
| [RECOGNITION_APPROACH.md](RECOGNITION_APPROACH.md) | Why alphabet, words and sentences are different problems |
| [MODEL_PLAN.md](MODEL_PLAN.md) | Model strategy and the train/inference contract |
| [ENTITLEMENT_GUIDE.md](ENTITLEMENT_GUIDE.md) | Applying for visionOS main-camera access |
| [FEASIBILITY.md](FEASIBILITY.md) | Original assessment — why this is hard |
| [ALTERNATIVE_DIRECTIONS.md](ALTERNATIVE_DIRECTIONS.md) | Other products this pipeline supports |

---

## Honest limitations

- **Five signs.** A demo, not a product. Expanding is a download and a retrain, not new code.
- **Real-world accuracy is unverified.** 91.8% is measured on the source corpus; on-device
  performance in a real room is still being calibrated.
- **Continuous signing is scaffolded, not trained.** The CTC path exists and is unit-tested;
  no model behind it.
- **Translation takes 4–8s per phrase.** Glosses appear live; English arrives on a pause.
- **visionOS Interpret is blocked** on an Apple enterprise entitlement, which is generally
  unavailable to individual developer accounts.
- **ASL is not English.** Gloss-to-English is an interpretation layered on recognition, and the
  raw glosses stay visible so a wrong translation is inspectable rather than authoritative.
