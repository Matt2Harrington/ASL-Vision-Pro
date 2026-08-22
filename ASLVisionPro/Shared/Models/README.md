# Bundled model

`SignModel.mlpackage` — **committed on purpose.** It is 900 KB, and without it the app
recognizes nothing, so a fresh clone would have little to test.

| | |
|---|---|
| Classes | BAD · BOOK · BYE · DAD · HELLO · NO · PLEASE · WATER · YES · NONE |
| Accuracy | 82.3% on **held-out signers** (chance = 10%) |
| Trained on | 900 clips (100/sign), 21 Deaf signers — Kaggle `asl-signs`, CC BY 4.0 |
| Input | `landmarks` [1, 24, 198] |
| Output | `probabilities` [1, 10] |
| Spec | `config/feature_spec.json` **v3** — hands-only, depth zeroed |

## It is paired with two other files

Change one and you must change all three, or the app will run and be quietly wrong:

1. **`../Resources/labels.json`** — class names, in the model's output order
2. **`../../../config/feature_spec.json`** — the preprocessing contract

The spec version is stamped into the model's metadata at export. If you alter preprocessing —
point counts, normalization, depth, ordering — **retrain**. A model and a spec version are a
matched pair, and mismatching them degrades accuracy silently rather than failing loudly.

## Replacing it

See [TRAINING_GUIDE.md](../../../TRAINING_GUIDE.md). In short:

```bash
cd training
.venv/bin/python export_coreml.py --ckpt ckpt.pt --labels labels_kaggle.json \
    --out SignModel.mlpackage --quantize
cp -R SignModel.mlpackage ../ASLVisionPro/Shared/Models/
cp labels_kaggle.json ../ASLVisionPro/Shared/Resources/labels.json
cd .. && xcodegen generate
```

Xcode compiles the `.mlpackage` to `SignModel.mlmodelc` at build time; `RecognizerFactory`
finds it by name with no code change.

## Honest scope

Nine signs is a demo, not a product, and 82.3% is measured on the source corpus — real-world
accuracy on a phone in a room is a different and unverified number.

Accuracy fell from 91.8% when the vocabulary was five signs. That is expected: more classes is
a harder problem at the same amount of data per class. Adding clips per sign is the lever that
buys it back, and the dataset holds roughly 380 per sign against the 100 used here.
