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
| **Dictionary** | ✅ Working | 55 signs with full phonological parameters. No model needed |
| **Practice** | ✅ Working | Scores your signing against the 24 trained signs |
| **Interpret** | ✅ Working | Captions someone signing. visionOS needs Apple's camera entitlement |
| **Listen** | ✅ Working | Speech → live captions, on-device. Needs Apple Intelligence |
| **Record Clips** | ✅ Working | Captures auto-labelled training data |
| **Translation Check** | ✅ Working | Dev screen: gloss → English on the local LLM |

**Recognizer — 24 signs + NONE**, **72.3% on held-out signers** (chance = 4%).
A 900 KB quantized Core ML model trained on ~3,000 clips from 21 Deaf signers:

> BAD · BOOK · BYE · DAD · DRINK · FINISH · FOOD · HAPPY · HELLO · HOME · HOT · HUNGRY · LIKE · LISTEN · LOOK · MAD · MILK · MOM · MORNING · NIGHT · NO · PLEASE · WATER · YES

**Translation:** ASL gloss → English via Apple's on-device foundation model. No training was
needed; prompt engineering alone took it from 2/6 to 5/6 correct. Off by default — sentence
assembly is behind a setting, since it costs seconds per phrase and layers an interpretation
over recognition.

**Voice:** speaks recognized signing aloud, by sign or by sentence, for use without the screen.

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

## Getting started

Never used git or Xcode? This section assumes nothing. If you'd rather skip git entirely,
[QUICKSTART.md](QUICKSTART.md) walks through downloading a ZIP instead.

### 1. Install Xcode

Apple's free app for building iPhone apps, from the **App Store** — search "Xcode". It's a
10 GB+ download, so start it and come back later. Open it once when it finishes and accept the
licence it shows.

This also installs **git**, so there's nothing separate to install.

### 2. Get the code

Git copies the project to your Mac and lets you pull updates later. Open **Terminal**
(Applications → Utilities, or ⌘-Space and type "Terminal"), then paste:

```bash
git clone https://github.com/Matt2Harrington/ASL-Vision-Pro.git
cd ASL-Vision-Pro
```

`clone` downloads the project into a folder named `ASL-Vision-Pro`; `cd` moves you into it.
You'll be asked to install command line tools the first time — say yes.

> Prefer not to use Terminal? [GitHub Desktop](https://desktop.github.com) does the same thing
> with buttons, or use the green **Code → Download ZIP** button on the GitHub page.

### 3. Open and run

```bash
open ASLVisionPro.xcodeproj
```

In Xcode, the bar at the top has two dropdowns. Set the left one to **ASLVisionPro-iOS** and
the right one to any iPhone simulator, then press **▶**.

That's it — no configuration, no Apple account, no extra tools. The trained model is included,
so sign recognition works immediately.

### 4. Run on your own iPhone

Needs a free Apple ID, and two changes so the app is registered to *you* rather than someone
else:

1. **Xcode → Settings → Accounts → +** → sign in with your Apple ID
2. Click the blue **ASLVisionPro** at the top of the left sidebar → **ASLVisionPro-iOS** under
   TARGETS → **Signing & Capabilities**
3. Change **Bundle Identifier** from `com.example…` to your own, e.g. `com.yourname.ASLVisionPro.iOS`
4. Pick your name under **Team**
5. Plug in your iPhone, choose it in the device dropdown, press **▶**

The first launch fails with "Untrusted Developer" — that's expected. On the phone:
**Settings → General → VPN & Device Management → your Apple ID → Trust**, then press ▶ again.

> Free accounts get 7-day app licences. When the app stops opening, plug in and press ▶ again.

### 5. Getting updates later

```bash
git pull
```

Run that inside the project folder to fetch newer versions.

---

## Build reference

The project file is committed, so **XcodeGen is not needed to build**. It's only needed if you
change the project's *structure* — adding files, targets, or settings — which is done in
`project.yml`:

```bash
brew install xcodegen   # only if changing project structure
xcodegen generate
```

Schemes: **ASLVisionPro** (visionOS) · **ASLVisionPro-iOS** · **ASLVisionProTests** (103 tests).

```bash
xcodebuild test -project ASLVisionPro.xcodeproj -scheme ASLVisionProTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

> `xcodebuild test` can appear to hang for minutes *after* printing results. The tests are
> done; it's a teardown quirk.

The trained model (`SignModel.mlpackage`, 900 KB) **is committed**, so recognition works from a
fresh clone. To train your own, see [TRAINING_GUIDE.md](TRAINING_GUIDE.md).

### Hardware
- **iPhone** — everything except visionOS-specific modes. Fastest path to seeing it work.
- **Vision Pro** — required for Practice's 3D hand tracking; the simulator has no camera or hand data.
- **Apple Intelligence** (iPhone 15 Pro or newer) — needed for Listen and English translation only.

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
Tests/              15 suites, 103 tests
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
| [QUICKSTART.md](QUICKSTART.md) | Non-technical: install Xcode → run on your iPhone |
| [SETUP.md](SETUP.md) | Developer setup: clone → build → device → training |
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
