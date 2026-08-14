# Phase 2 Model Plan — On-Device Sign Recognizer

**Goal:** train a compact sequence model that maps a window of holistic landmarks to a
fingerspelled letter or isolated-sign gloss, export it to Core ML, and run it on the
Vision Pro Neural Engine inside the existing pipeline.

Companion to [ARCHITECTURE.md](ARCHITECTURE.md) (rungs 1–3). This is the shippable core.

---

## 1. Scope for Phase 2

| Rung | Target | Vocabulary |
|---|---|---|
| 1 | Fingerspelling A–Z | 26 static-ish handshapes |
| 2 | Isolated common signs | ~50–200 glosses (start small) |
| 3 | Larger isolated vocab | scale toward 1000s (WLASL) as data allows |

Deliberately **isolated-sign** classification first. Continuous translation (rung 4) is
Phase 3 and reuses this feature pipeline. Ship a small, reliable vocabulary before a large,
unreliable one.

---

## 2. The Cardinal Rule: Train and Infer on Identical Features

The model never sees pixels — it sees the normalized tensor produced by
[`FeatureEncoder`](ASLVisionPro/Pipeline/FeatureEncoder.swift). **The training pipeline must
reproduce that exact encoding**, or accuracy collapses in ways that are hard to debug.

Locked contract (keep these in sync on both sides):

| Property | Value | Source of truth |
|---|---|---|
| Sequence length | 24 frames | `FeatureEncoder.sequenceLength` / `SignSegmenter.windowSize` |
| Hand points | 21 × 2 hands | Vision hand pose |
| Body points | 8 (upper-body subset) | Vision body pose |
| Face points | 16 (brow/mouth/head subset) | Vision face landmarks |
| Features/frame | (21·2 + 8 + 16) · 2 (x,y) = 132 | `FeatureEncoder.featuresPerFrame` |
| Normalization | torso-centered, shoulder-width scaled | `FeatureEncoder.flatten` |
| Input tensor | `[24, 132]` float32, key `"landmarks"` | model input spec |
| Output | softmax over labels, key `"probabilities"` | model output spec |

> Recommended: extract the normalization math into a shared spec (even a short JSON of the
> constants) that both the Swift encoder and the Python trainer read, so they can't drift.

---

## 3. Data

**Public datasets (bootstrap):**
- **WLASL** — Word-Level ASL, ~2000 glosses (video). Largest isolated-ASL vocab.
- **MS-ASL** — isolated ASL, ~1000 signs.
- **ASL fingerspelling** sets (e.g. ChicagoFSWild) for rung 1.
- **How2Sign** — continuous ASL; reserve for Phase 3.

**Preprocessing:** run each clip through the **same Vision (or MediaPipe) landmark
extraction** used on-device, then the same normalization → cache `[24,132]` tensors + label.
Cache to disk; don't re-extract every epoch.

**Custom data (the real unlock):** public data is filmed head-on at a distance; your input
is the Vision Pro's forward camera at conversational range and viewpoint. Record a **custom
set under real conditions** — multiple signers, distances, lighting, and (critically) with
Deaf/ASL-community participation for correctness and trust. Even a few hundred clips per sign
in-domain beats far more out-of-domain data.

**Class balance & the "none" class:** include a **negative/rest class** so the model can
say "no sign here" — the segmenter's activity gate is coarse and will pass junk windows.

---

## 4. Model Architecture

Small enough for the Neural Engine, expressive enough for temporal signs:

- **Baseline:** 2–4 layer **temporal CNN** or **GRU** over the `[24,132]` sequence → mean-pool
  → dense → softmax. Fast, tiny, a strong first baseline.
- **Recommended:** a **small Transformer encoder** (2–4 layers, d≈128, 4 heads) with learned
  positional encoding over the 24 steps → CLS/pool → softmax. Best accuracy per parameter for
  this data shape; this is the standard shape in recent sign-recognition work.
- **Keep it compact:** target a model that quantizes to a few MB and runs in <100 ms/window.
  Continuous camera + Vision + inference is sustained head-worn load — profile thermals.

**Augmentation** (matters a lot with small data): temporal jitter/resampling (signing speed),
small rotation/scale/translation of landmarks, horizontal flip **with L/R hand swap**, point
dropout (simulate occlusion/missed detections), and Gaussian noise on coordinates.

---

## 5. Training

- **Framework:** PyTorch (dev-time only; nothing Python ships in the app).
- **Split by signer** (not by clip) so you measure generalization to *new people*, not
  memorization of known signers. This is the honest metric.
- **Loss:** cross-entropy with label smoothing; class weighting for the long tail.
- **Metrics:** top-1 and top-5 accuracy per rung; confusion matrix (find sign pairs that
  differ only by non-manual markers — evidence for whether face points are earning their keep).
- **Calibration:** tune the confidence threshold on a held-out set. The app gates captions on
  confidence ([`CoreMLSignRecognizer.confidenceThreshold`](ASLVisionPro/Pipeline/SignRecognizer.swift));
  a well-calibrated score is what makes "show nothing rather than show wrong" work.

---

## 6. Export to Core ML

1. Export PyTorch → Core ML via **coremltools** (`ct.convert`), input `landmarks: [24,132]`,
   output `probabilities`.
2. **Quantize** (e.g. linear/palettization) and confirm accuracy holds; target Neural Engine
   compute units.
3. Attach the **label list** as metadata (or ship `labels.json`) — order must match the
   softmax index used by `CoreMLSignRecognizer.topLabel`.
4. Add `SignModel.mlpackage` to the app target.
5. Swap the recognizer:

   ```swift
   let model = try MLModel(contentsOf: SignModel.urlOfModelInThisBundle)
   let labels = loadLabels()               // same order as training
   let pipeline = TranslationPipeline(recognizer:
       CoreMLSignRecognizer(model: model, labels: labels))
   ```

6. Verify feature parity: log an on-device encoded window and the corresponding training
   tensor for the same clip — they should match numerically.

---

## 7. Validation on Device

- Confirm end-to-end latency stays within the §5 budget of ARCHITECTURE.md (<~100 ms/window).
- Test across signers, distances, and lighting **not** in training.
- Watch the confusion cases; if minimal-pair signs collapse, revisit face/body point inclusion.
- **Never present output as authoritative** — keep the on-screen "experimental" disclaimer and
  confidence gating regardless of metrics.

---

## 8. Definition of Done (Phase 2)

- [ ] Landmark extraction + normalization identical in Python and Swift (numerically verified).
- [ ] Cached, signer-split dataset with a "none" class.
- [ ] Trained compact model; top-1 reported on **held-out signers**.
- [ ] Quantized `.mlpackage` running on Neural Engine within latency + thermal budget.
- [ ] `CoreMLSignRecognizer` live in the app with a calibrated confidence threshold.
- [ ] Reliable captions for the chosen fixed vocabulary in real conditions.
