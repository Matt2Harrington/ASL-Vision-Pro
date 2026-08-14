"""Generate a synthetic dataset so the full train -> export toolchain can be validated
end-to-end BEFORE any real ASL data exists. The numbers are meaningless; this only proves
the pipeline runs and produces a working .mlpackage of the right shape.

Usage:  python synth.py --labels labels.json --out data/synth.npz
"""
import argparse
import json

import numpy as np

from feature_spec import SEQ_LEN, FEATURES_PER_FRAME


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--labels", default="labels.json")
    ap.add_argument("--out", default="data/synth.npz")
    ap.add_argument("--per-class", type=int, default=40)
    ap.add_argument("--signers", type=int, default=6)
    args = ap.parse_args()

    labels = json.load(open(args.labels))
    n_classes = len(labels)
    rng = np.random.default_rng(0)

    X, y, signer = [], [], []
    # Give each (class) a random prototype so a model can actually learn something.
    protos = rng.normal(0, 1, (n_classes, SEQ_LEN, FEATURES_PER_FRAME)).astype(np.float32)
    for c in range(n_classes):
        for _ in range(args.per_class):
            noise = rng.normal(0, 0.5, (SEQ_LEN, FEATURES_PER_FRAME)).astype(np.float32)
            X.append(protos[c] + noise)
            y.append(c)
            signer.append(rng.integers(0, args.signers))

    X = np.stack(X)
    y = np.array(y, dtype=np.int64)
    signer = np.array(signer, dtype=np.int64)
    np.savez_compressed(args.out, X=X, y=y, signer=signer)
    print(f"wrote {args.out}: X={X.shape} y={y.shape} signers={args.signers} classes={n_classes}")


if __name__ == "__main__":
    main()
