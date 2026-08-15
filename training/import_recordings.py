"""Convert recordings.jsonl (from the in-app DataCollector) into the .npz the trainer wants.

The app writes one JSON object per line:
    {"gloss": "HELLO", "signer": "matt", "features": [[...198 floats...] x 24]}

Because those features came from the app's own FeatureEncoder, they are already normalized
exactly as they will be at inference — this importer does no feature math at all, which is
precisely the point (MODEL_PLAN §2: train/inference parity).

Usage:
  python import_recordings.py --input recordings.jsonl --labels labels_signs.json \
      --out data/collected.npz
"""
import argparse
import json

import numpy as np

from feature_spec import SEQ_LEN, FEATURES_PER_FRAME


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="recordings.jsonl")
    ap.add_argument("--labels", default="labels_signs.json")
    ap.add_argument("--out", default="data/collected.npz")
    args = ap.parse_args()

    labels = json.load(open(args.labels))
    label_index = {g: i for i, g in enumerate(labels)}

    X, y, signer_ids = [], [], []
    signers = {}
    skipped = 0

    with open(args.input) as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            feats = np.asarray(rec["features"], dtype=np.float32)

            if feats.shape != (SEQ_LEN, FEATURES_PER_FRAME):
                print(f"  line {line_no}: shape {feats.shape} != "
                      f"({SEQ_LEN}, {FEATURES_PER_FRAME}) — skipped")
                skipped += 1
                continue
            if rec["gloss"] not in label_index:
                print(f"  line {line_no}: gloss {rec['gloss']!r} not in labels — skipped")
                skipped += 1
                continue

            s = rec["signer"]
            if s not in signers:
                signers[s] = len(signers)

            X.append(feats)
            y.append(label_index[rec["gloss"]])
            signer_ids.append(signers[s])

    if not X:
        raise SystemExit("No usable recordings found.")

    X = np.stack(X)
    y = np.array(y, dtype=np.int64)
    signer = np.array(signer_ids, dtype=np.int64)
    np.savez_compressed(args.out, X=X, y=y, signer=signer)

    print(f"\nwrote {args.out}")
    print(f"  clips   : {len(y)} ({skipped} skipped)")
    print(f"  signers : {len(signers)} -> {signers}")
    counts = {labels[i]: int((y == i).sum()) for i in sorted(set(y.tolist()))}
    print(f"  per-class: {counts}")

    # Signer-split needs >= 2 signers to mean anything.
    if len(signers) < 2:
        print("\n  WARNING: only one signer. train.py splits by signer to measure "
              "generalization to new people — collect from more signers before trusting "
              "validation accuracy.")


if __name__ == "__main__":
    main()
