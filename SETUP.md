# Setup

Getting this running on a fresh Mac, from clone to signing on your own iPhone.

**Fastest useful result:** steps 1–4 (~10 minutes) build the app and run the test suite, with
no Apple account or signing setup at all. Step 5 shows it in the simulator. Step 6 puts it on a
real phone — the only way to test the camera — and works with a free Apple ID.

---

## What you need

| | |
|---|---|
| **macOS** | Sonoma or later |
| **Xcode 26+** | from the App Store. The full app, not just Command Line Tools |
| **Apple ID** | free tier is enough; only needed for step 6 |
| **iPhone** | optional but recommended — the simulator has no camera |
| **Apple Vision Pro** | optional; only needed for 3D hand tracking |

You do **not** need: a paid developer account, the Kaggle dataset, or a trained model. The app
builds and runs without one and tells you on screen that recognition is simulated.

---

## 1. Point the command line at Xcode

The single most common setup failure. If you've only ever installed Command Line Tools,
`xcodebuild` won't find any SDKs.

```bash
sudo xcode-select -s /Applications/Xcode.app
```

Verify — this must list visionOS and iOS SDKs, not error:

```bash
xcodebuild -showsdks | head -20
```

Then accept the licence if you haven't:

```bash
sudo xcodebuild -license accept
```

## 2. Clone

```bash
git clone git@github.com:Matt2Harrington/ASL-Vision-Pro.git
cd ASL-Vision-Pro
```

## 3. Install XcodeGen

The Xcode project is **generated** from `project.yml` rather than committed — hand-edited
`.pbxproj` files corrupt easily and produce vicious merge conflicts.

```bash
brew install xcodegen
```

## 4. Generate and build

```bash
xcodegen generate
```

No signing configuration is needed. The project ships with **no development team** and neutral
`com.example` bundle identifiers, so it builds for anyone out of the box. Signing only matters
in step 7, when you put it on a physical device.

Run the tests — no device or model needed, and it proves the toolchain end to end:

```bash
xcodebuild test \
  -project ASLVisionPro.xcodeproj \
  -scheme ASLVisionProTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expect **85 tests, 0 failures**. If your Mac has a different simulator, list them with
`xcrun simctl list devices available` and substitute the name.

> `xcodebuild test` can hang for several minutes *after* the results print. The tests are done;
> it's a teardown quirk. Ctrl-C once you see the summary.

## 5. Run in the simulator

```bash
open ASLVisionPro.xcodeproj
```

Pick the **ASLVisionPro-iOS** scheme and any iPhone simulator, then ⌘R.

**Works in the simulator:** Dictionary (all 32 signs, search, categories, parameter detail),
and the app shell.

**Does not:** anything using the camera — the simulator has none. Translation Check may also
fail, because Apple Intelligence model assets are often absent there.

For visionOS instead, choose the **ASLVisionPro** scheme and an Apple Vision Pro simulator.

## 6. Run on your iPhone

This is where the camera actually works. **A free Apple ID is enough** — no paid developer
account required.

1. **Add your Apple ID to Xcode** if you haven't: Xcode → Settings → Accounts → **+** → Apple ID.
2. **Change the bundle identifier to your own.** In `project.yml`, replace the two
   `com.example.` prefixes with your own reverse-DNS (e.g. `com.yourname.`), then re-run
   `xcodegen generate`.

   This step is not optional for device builds. Free provisioning registers the identifier
   against *your* team, so a shared prefix collides between people — if someone else has
   already registered `com.example.ASLVisionPro.iOS`, yours is refused.
3. Plug the iPhone in, unlock it, and trust the Mac if prompted.
4. Select the **ASLVisionPro-iOS** scheme and pick your iPhone as the destination.
5. Open the target's **Signing & Capabilities** tab and choose **your team** in the Team
   dropdown. Xcode creates a free provisioning profile automatically.
6. ⌘R.
7. First launch fails with **"Untrusted Developer."** On the phone:
   **Settings → General → VPN & Device Management → your Apple ID → Trust**. Launch again.
8. Allow camera and microphone access when asked.

> Free provisioning profiles **expire after 7 days**. When the app stops launching, rebuild
> from Xcode — nothing is wrong.

### What to try

| Mode | What you'll see |
|---|---|
| **Dictionary** | Fully working — browse and search 32 signs |
| **Interpret** | Camera with live hand tracking. Dots follow your hands |
| **Listen** | Speak and watch live captions (needs iOS 26) |
| **Translation Check** | Tap "Run 6 samples" for on-device gloss → English |
| **Practice** | Recognizes 5 signs *if* a model is bundled — otherwise an orange banner says feedback is simulated |

Without a trained model the app is honest about it: a prominent banner appears, because stub
feedback is otherwise indistinguishable from real recognition.

## 7. (Optional) Train a model

Only if you want Practice and Interpret to actually recognize signing. Needs a free Kaggle
account. Full detail in [TRAINING_GUIDE.md](TRAINING_GUIDE.md); the short version:

```bash
cd training
python3.10 -m venv .venv                       # 3.10 — coremltools/torch lag newer Pythons
.venv/bin/pip install -r requirements.txt numpy torch coremltools kaggle pandas pyarrow
```

Then get a Kaggle token (Kaggle → Settings → **Create New API Token**), place it, and accept
the competition rules at <https://www.kaggle.com/competitions/asl-signs>:

```bash
mkdir -p ~/.kaggle && mv ~/Downloads/kaggle.json ~/.kaggle/ && chmod 600 ~/.kaggle/kaggle.json
```

Download `train.csv` from that page's Data tab, then:

```bash
.venv/bin/python fetch_subset.py --signs hello please yes no water --per-sign 100
.venv/bin/python import_kaggle.py --labels labels_kaggle.json --out data/hands.npz
.venv/bin/python add_none_class.py --in data/hands.npz --labels labels_kaggle.json --out data/none.npz
.venv/bin/python train.py --data data/none.npz --labels labels_kaggle.json --epochs 60 --out ckpt.pt
.venv/bin/python export_coreml.py --ckpt ckpt.pt --labels labels_kaggle.json --out SignModel.mlpackage --quantize
cp -R SignModel.mlpackage ../ASLVisionPro/Shared/Models/
cp labels_kaggle.json ../ASLVisionPro/Shared/Resources/labels.json
cd .. && xcodegen generate
```

**Downloads ~266 MB, not the full ~100 GB corpus.** Expect ~92% on held-out signers. Rebuild
and the orange banner disappears — the app finds the model with no code change.

---

## Troubleshooting

**`xcodebuild: error: tool 'xcodebuild' requires Xcode`**
Step 1 wasn't done, or pointed at the wrong path. Check with `xcode-select -p`.

**`Signing for "ASLVisionPro-iOS" requires a development team`**
Expected until you pick a team — step 6.5. Simulator builds don't need one.

**`Failed to register bundle identifier`** or **`... is not available`**
The `com.example.` prefix is still in place, or someone else registered it. Change it to your
own reverse-DNS in `project.yml` and re-run `xcodegen generate` — step 6.2.

**App stops launching after about a week**
Free provisioning profiles expire after 7 days. Rebuild from Xcode.

**"Untrusted Developer" on the phone**
Expected on first install — step 7.5.

**App installs but the camera view is black**
You're on the simulator, which has no camera. Use a real device.

**Translation Check declines everything**
Apple Intelligence assets are missing or still downloading. It's often unavailable in the
simulator entirely; try a real device with Apple Intelligence enabled.

**Practice shows an orange banner**
Working as intended — no trained model is bundled. Step 8, or ignore it and use Dictionary and
Listen.

**Tests fail after you change preprocessing**
Several tests deliberately pin the train/inference contract (feature shape, joint ordering,
depth handling). If you changed `config/feature_spec.json`, the model must be retrained to
match — see [ML_PLAYBOOK.md](ML_PLAYBOOK.md) §2.
