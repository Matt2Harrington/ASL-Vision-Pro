# Training Guide

How the current model was built, where everything lives, and how to improve it.
Written so this can be picked up cold months from now.

Companion docs: [ARCHITECTURE.md](ARCHITECTURE.md) (system design),
[MODEL_PLAN.md](MODEL_PLAN.md) (strategy), [RECOGNITION_APPROACH.md](RECOGNITION_APPROACH.md)
(why alphabet / words / sentences are different problems).

---

## 1. What exists today

A 6-class isolated-sign recognizer — **HELLO, NO, PLEASE, WATER, YES, NONE** — at
**91.8% accuracy on held-out signers**, running on device as a 900 KB quantized Core ML model.

"Held-out signers" is the number that matters: the model is validated on people it never
trained on. Validating on unseen *clips* from known signers would score far higher and mean
much less.

---

## 2. Where the data lives

| What | Where | Notes |
|---|---|---|
| Source dataset | [Kaggle: asl-signs](https://www.kaggle.com/competitions/asl-signs) | 250 signs, ~94k clips, 21 Deaf signers, CC BY 4.0 |
| Index | `~/Downloads/train.csv` | path, participant_id, sequence_id, sign |
| Downloaded clips | `training/data/asl_signs/` | gitignored — re-fetchable |
| Converted tensors | `training/data/*.npz` | gitignored |
| Trained model | `ASLVisionPro/Shared/Models/SignModel.mlpackage` | gitignored |
| Labels | `ASLVisionPro/Shared/Resources/labels.json` | committed; must match the model |
| Kaggle token | `~/.kaggle/kaggle.json` | never commit |

**The full corpus is ~100 GB and you don't need it.** `train.csv` lists every clip's path, so
clips are fetched individually. The current model used **500 clips / 266 MB — 0.5%**.

---

## 3. The pipeline, end to end

```bash
cd training

# 1. Fetch a subset (5 signs x 100 clips ~= 0.5 GB)
.venv/bin/python fetch_subset.py --signs hello please yes no water --per-sign 100

# 2. MediaPipe landmarks -> our [24, 198] tensors
.venv/bin/python import_kaggle.py --data data/asl_signs \
    --labels labels_kaggle.json --out data/kaggle_hands.npz

# 3. Add the "not signing" class
.venv/bin/python add_none_class.py --in data/kaggle_hands.npz \
    --labels labels_kaggle.json --out data/kaggle_none.npz

# 4. Train (splits by signer automatically)
.venv/bin/python train.py --data data/kaggle_none.npz \
    --labels labels_kaggle.json --epochs 60 --out ckpt.pt

# 5. Export to Core ML
.venv/bin/python export_coreml.py --ckpt ckpt.pt \
    --labels labels_kaggle.json --out SignModel.mlpackage --quantize

# 6. Install into the app
cp -R SignModel.mlpackage ../ASLVisionPro/Shared/Models/
cp labels_kaggle.json ../ASLVisionPro/Shared/Resources/labels.json
cd .. && xcodegen generate
```

Xcode compiles the `.mlpackage` to `SignModel.mlmodelc`, and `RecognizerFactory` picks it up
with **no code change**. The app falls back to a stub — and says so on screen — when no model
is present.

### Setup

```bash
cd training
python3.10 -m venv .venv          # 3.10: coremltools and torch lag newer Pythons
.venv/bin/pip install -r requirements.txt numpy torch coremltools kaggle pandas pyarrow
```

Kaggle also needs an API token at `~/.kaggle/kaggle.json` (Kaggle → Settings → Create New API
Token) and the competition rules accepted, or downloads 403.

---

## 4. What was learned the hard way

These cost real time. They are the reason the numbers moved.

### Only the hands transfer between landmark systems
MediaPipe and Apple Vision agree on the 21-point hand skeleton — same layout, same order — but
not on face (468 points vs ~76) or body (different pose joints). Training on those regions
taught the model patterns that were **noise at inference**.

**67.4% → 92.6%** from zeroing face and body. They were not merely useless; they were harmful.
`hands_only` in `config/feature_spec.json` controls this on both sides.

### Normalize hands against themselves
Anchoring on the torso fails on a phone held close, where no body is visible. Each hand is now
centred on its own wrist and scaled by wrist-to-middle-MCP span — self-contained, and computed
identically from either landmark system.

### The model needs a way to say nothing
A softmax over N signs always names one. Pointed at an empty room, the model reported
`YES 93%`. `add_none_class.py` synthesizes negatives *from the real clips* (held still frame,
no hands, a stretched two-frame slice, jittered pose) so they share the positives' statistics
and the model must learn motion rather than "are hands present". Cost: 92.6% → 91.8%. Worth it.

### Camera must match the training viewpoint
These corpora were captured on **selfie cameras**. Using the back camera flipped every hand's
chirality, putting the signer's right hand into the left hand's feature slots. The app now
defaults to the front camera with mirrored orientation.

### Depth must be consistent
Vision supplies no `z`, so models train with depth zeroed — but visionOS hand tracking *does*
supply real depth. The encoder zeroes it (`uses_depth: false`) so the headset can't feed the
model a channel it never saw.

### Joint order is part of the contract
The extractor originally read a dictionary's `values` and filtered by confidence, so ordering
came from Swift's per-process hash seed and the count shifted per frame. Feature index 3 could
be the wrist in one frame and a fingertip in the next. Joints are now read by name from
explicit ordered lists, with missing ones as zero placeholders.

---

## 5. How to improve accuracy

In descending value:

1. **More clips per sign.** Currently 100; the dataset has ~380.
   `fetch_subset.py --per-sign 380` — already-downloaded files are skipped.
2. **More signs.** `--catalog-overlap` fetches all 15 the app's dictionary describes (~2.4 GB),
   so every recognized sign also has parameter data for Practice.
3. **Real negatives.** Synthetic NONE is a stand-in. Recording actual not-signing footage
   through *Record Clips* would be better, and it writes features through the same encoder.
4. **Tune the head.** Only worth doing once the data is right.

Re-run steps 2–6 above after any of these.

---

## 6. Foundation Models (the LLM half)

Separate from the recognizer, and **already working**. Glosses → English via Apple's on-device
model. No training was needed.

### You cannot fine-tune the base model
It is Apple's, fixed. What is available is **LoRA adapter training** (Python toolkit,
Apple Silicon + 32 GB RAM, ~160 MB per adapter, deployed via Background Assets).

### Don't train an adapter yet
Apple's own guidance is to train one when prompt engineering falls short. It didn't:

| Gloss | Before prompt work | After |
|---|---|---|
| ME NAME M-A-T-T | "Matt" | **"My name is Matt."** |
| BATHROOM WHERE | "Bathroom where?" | **"Where is the bathroom?"** |
| ME DEAF YOU HEARING | "I'm deaf, do you hear?" | **"I'm deaf, you're hearing."** |

**2/6 → 5/6 correct**, purely by writing ASL grammar rules into the instructions in
`FoundationModelGlossInterpreter.swift`: WH-words come last in ASL and first in English, NAME
constructions need the English frame restored, topic-comment contrasts stay statements.

**Iterate on the prompt first.** Use the in-app **Translation Check** screen — it runs sample
sequences, takes custom glosses, and shows latency. That screen exists because none of this is
observable on a Mac: the simulator reports the model available while its assets are still
downloading, then fails every request.

If an adapter ever *is* warranted, it needs (gloss → English) text pairs. Continuous-signing
corpora such as How2Sign and ASLLRP carry gloss annotations alongside English.

### Known limit
**4–8 seconds per phrase** in the simulator. Prompting cannot fix that. The pipeline is built
for it — glosses appear live, English arrives once signing pauses — but it rules out
translating word by word.

---

## 7. The prototype, in brief

Two apps sharing one recognition pipeline: **visionOS** (`ASLVisionPro`) and **iOS**
(`ASLVisionPro-iOS`). 20 shared source files; only the camera source and app shell differ.

```
camera/hands → landmarks → segmentation → classifier → glosses → on-device LLM → English
```

| Mode | State |
|---|---|
| **Practice** | Sign along, scored per attempt. Verification (is this a correct X?) not open recognition — far easier, and degrades to "try again" |
| **Dictionary** | 32 signs with full phonological parameters. No model needed |
| **Listen** | Speech → live captions, on-device (OS 26) |
| **Interpret** | Captions for someone else signing. visionOS needs Apple's enterprise camera entitlement |
| **Record Clips** | Auto-labeled training capture, written through the same encoder as inference |
| **Translation Check** | Dev screen for evaluating gloss → English on device |

**Everything runs on device.** No footage or landmarks leave; the language model only ever
sees short gloss lists.

### Design decisions worth keeping
- **`SignRecognizing` is the one swappable stage.** Classifier, CTC, or stub swap behind it
  without touching capture, landmarks, segmentation, or captions.
- **`config/feature_spec.json` is the single source of truth**, read by both the Swift encoder
  and the Python trainer. Drift between them is the failure mode that silently destroys
  accuracy.
- **Honesty is enforced in UI.** A prominent banner appears whenever no trained model is
  present, because stub feedback is otherwise indistinguishable from real recognition — the
  tutor cycles encouraging scores regardless of what is signed.
- **The gloss line is never hidden** behind the English, so a wrong translation stays
  inspectable rather than authoritative.

### Still open
- visionOS **Interpret** needs Apple's enterprise entitlement (likely unavailable on an
  individual account — see [ENTITLEMENT_GUIDE.md](ENTITLEMENT_GUIDE.md))
- 5 signs is a demo, not a product
- The **CTC path for continuous signing is scaffolded but untrained**
- On-device translation quality is verified; **real-world recognition accuracy is not**
