# Bundled model

`SignModel.mlpackage` — **committed on purpose.** It is 900 KB, and without it the app
recognizes nothing, so a fresh clone would have little to test.

| | |
|---|---|
| Classes | BAD · BOOK · BYE · DAD · DRINK · FINISH · FOOD · HAPPY · HELLO · HOME · HOT · HUNGRY · LIKE · LISTEN · LOOK · MAD · MILK · MOM · MORNING · NO · PLEASE · WATER · YES · NONE |
| Accuracy | 71.2% on **held-out signers** (chance ≈ 4%) |
| Trained on | 2,224 clips (100/sign), 21 Deaf signers — Kaggle `asl-signs`, CC BY 4.0 |
| Input | `landmarks` [1, 24, 198] |
| Output | `probabilities` [1, 24] |
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

Twenty-three signs is a demo, not a product, and 71.2% is measured on the source corpus —
real-world accuracy on a phone in a room is a different and unverified number.

Accuracy has tracked vocabulary size at a fixed 100 clips per sign: 91.8% at five signs, 82.3%
at nine, 76.9% at fifteen, 76.6% at seventeen, 71.2% at twenty-three. That is the expected
trade rather than a regression — more classes is a harder problem on the same data per class.
The lever that buys it back is clips per sign, where the dataset holds roughly 380 against the
100 used here.

Kaggle rate limits per-file downloads to roughly 550 to 600 files per window, recovering after
some hours. `fetch_subset.py` is resumable, so the vocabulary has been built across several
sessions.
