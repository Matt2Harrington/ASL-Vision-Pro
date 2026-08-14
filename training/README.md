# Training — Sign Recognizer

Trains the compact temporal model that becomes `SignModel.mlpackage` in the app.
See [../MODEL_PLAN.md](../MODEL_PLAN.md) for the strategy and [../config/feature_spec.json](../config/feature_spec.json) for the locked feature contract.

## Setup

coremltools/torch lag new Python versions — use a **3.11** venv:

```bash
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

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
