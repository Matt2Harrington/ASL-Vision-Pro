# Training — Sign Recognizer

Trains the compact temporal model that becomes `SignModel.mlpackage` in the app.
See [../MODEL_PLAN.md](../MODEL_PLAN.md) for the strategy and [../config/feature_spec.json](../config/feature_spec.json) for the locked feature contract.

## Setup

coremltools/torch lag new Python versions — use a **3.10** venv (verified working):

```bash
python3.10 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Verified end-to-end

The full chain has been run and confirmed:

```bash
.venv/bin/python synth.py --labels labels.json --out data/synth.npz
.venv/bin/python train.py --data data/synth.npz --labels labels.json --epochs 20 --out ckpt.pt
.venv/bin/python export_coreml.py --ckpt ckpt.pt --labels labels.json --out SignModel.mlpackage --quantize
```

Produces a 904 KB quantized `.mlpackage` with input `landmarks` `[1, 24, 198]` and output
`probabilities` `[1, 27]` — matching the Swift `FeatureEncoder` and `CoreMLSignRecognizer`
exactly. Copying it to `ASLVisionPro/Shared/Models/` and `labels.json` to
`ASLVisionPro/Shared/Resources/` makes Xcode compile it to `SignModel.mlmodelc`, which
`RecognizerFactory` then loads with no code change.

> **The synthetic model is meaningless.** `synth.py` builds each class from a distinct random
> prototype, so 100% validation accuracy is expected and says nothing about recognition. It
> exists only to prove the toolchain before investing in data collection. The trained model is
> gitignored for exactly this reason — a committed placeholder would mislead. Without it the
> app falls back to the stub recognizer by design, and still builds.

## Prove the toolchain (synthetic data, no ASL data needed)

```bash
python synth.py --labels labels.json --out data/synth.npz   # fake dataset
python train.py --data data/synth.npz --labels labels.json --epochs 20 --out ckpt.pt
python export_coreml.py --ckpt ckpt.pt --labels labels.json --out SignModel.mlpackage --quantize
```

This runs train → export end-to-end and produces a real `.mlpackage` of the correct shape.
The accuracy is meaningless (random data) — it only validates that the pipeline works and
the model I/O matches what the app expects.

## Real data

The hard requirement (MODEL_PLAN §2): **landmark extraction + normalization must be
IDENTICAL to the on-device Swift `FeatureEncoder`.** The safe way to guarantee that is to
extract landmarks with the *same Vision code* the app uses — a small macOS command-line
tool that reuses `ASLVisionPro/Shared` — rather than a different library (e.g. MediaPipe),
whose landmark topology differs and will not match.

Extraction (however done) must emit an `.npz` with:
- `X` float32 `[N, 24, 132]` — normalized windows per `feature_spec.json`
- `y` int64 `[N]` — class index into `labels.json`
- `signer` int64 `[N]` — signer id (training splits by signer, not by clip)

Then `train.py` / `export_coreml.py` are unchanged.

## Files

| File | Role |
|---|---|
| `feature_spec.py` | Reads `config/feature_spec.json` — the shared contract. Don't hardcode shapes elsewhere. |
| `model.py` | Compact Transformer classifier (+ softmax wrapper for export). |
| `dataset.py` | Windowed dataset, augmentation, **signer-split**. |
| `synth.py` | Synthetic data to validate the pipeline. |
| `train.py` | Training loop; reports held-out-**signer** accuracy. |
| `export_coreml.py` | → `SignModel.mlpackage`, input `landmarks`, output `probabilities`. |
| `model_ctc.py` | Level-3 **continuous** recognizer (CTC head) — sketch for sentences/phrases. |
| `labels.json` | Class list (starter: NONE + A–Z fingerspelling). |

## Level 3 — continuous (CTC) path

`model_ctc.py` sketches the sentence/phrase recognizer (see
[../RECOGNITION_APPROACH.md](../RECOGNITION_APPROACH.md) §Level 3). It differs from the
classifier in three ways:

- Output is **per-timestep logits** `[B, T, V]` over glosses + a **blank** at index 0, not a
  single class.
- Trained with **CTC loss** (`nn.CTCLoss`) — needs only the target gloss *sequence* per clip,
  not frame-level alignment.
- Export with output name **`logits`** and **no softmax** — the Swift `CTCDecoder` takes
  argmax over raw logits. (config/feature_spec.json → `continuous`.)

Pairs with the Swift `ContinuousSignRecognizer`. A true seq2seq/SLT model (fluent English,
autoregressive decode) is the further step beyond CTC.

## Resuming an interrupted download

Kaggle rate limits per-file downloads to roughly 500–600 files, then returns HTTP 429 for
longer than an hour. `fetch_subset.py` is resumable and skips what's already on disk, so a
large vocabulary is fetched across several sessions rather than one.

The signs still wanted are listed in `remaining_signs.json`:

```bash
cd training
.venv/bin/python fetch_subset.py --train-csv ~/Downloads/train.csv \
    --signs $(python3 -c "import json;print(' '.join(json.load(open('remaining_signs.json'))))") \
    --per-sign 100
```

Run in bash, not zsh — zsh doesn't word-split the unquoted substitution, so all the sign names
arrive as a single argument and nothing matches.

Then retrain on whatever arrived. `--min-per-class` drops partially fetched signs, so this
never has to wait for the whole set:

```bash
.venv/bin/python import_kaggle.py --train-csv ~/Downloads/train.csv --data data/asl_signs \
    --labels labels_kaggle.json --out data/next.npz --max-per-class 100 --min-per-class 60
.venv/bin/python add_none_class.py --in data/next.npz --labels labels_kaggle.json --out data/next_none.npz
.venv/bin/python train.py --data data/next_none.npz --labels labels_kaggle.json --epochs 80 --out ckpt.pt
.venv/bin/python export_coreml.py --ckpt ckpt.pt --labels labels_kaggle.json --out SignModel.mlpackage --quantize
cp -R SignModel.mlpackage ../ASLVisionPro/Shared/Models/
cp labels_kaggle.json ../ASLVisionPro/Shared/Resources/labels.json
```

Every sign in the queue already has a dictionary entry, so no content work is needed — the
formation hints appear in Practice as soon as a sign is trained.
