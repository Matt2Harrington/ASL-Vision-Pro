"""Add a NONE (not-signing) class to a dataset.

A softmax over N signs always names one of them. With no rest class the model cannot abstain,
so a camera pointed at an empty room still yields a confident sign — which is exactly what
happened on device. MODEL_PLAN called for this class from the start.

"Not signing" is synthesized from the real clips rather than invented, so the negatives share
the same landmark statistics as the positives and the model must learn motion rather than
merely "are hands present":

  still     — one frame from a clip held for the whole window: hands visible, no motion
  empty     — no hands detected at all
  drift     — a very short slice stretched out: hands moving too little to be a sign
  jitter    — a still pose plus small noise: hand present, incidental movement

Usage:
  python add_none_class.py --in data/kaggle_hands.npz --labels labels_kaggle.json \
      --out data/kaggle_none.npz
"""
import argparse
import json

import numpy as np

from feature_spec import SEQ_LEN, FEATURES_PER_FRAME


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", default="data/kaggle_hands.npz")
    ap.add_argument("--labels", default="labels_kaggle.json")
    ap.add_argument("--out", default="data/kaggle_none.npz")
    ap.add_argument("--ratio", type=float, default=0.25,
                    help="NONE samples as a fraction of the existing set")
    args = ap.parse_args()

    d = np.load(args.src)
    X, y, signer = d["X"], d["y"], d["signer"]
    labels = json.load(open(args.labels))

    rng = np.random.default_rng(0)
    n_none = int(len(X) * args.ratio)
    none_X, none_signer = [], []

    for i in range(n_none):
        src = X[rng.integers(0, len(X))]
        kind = i % 4

        if kind == 0:                                    # still
            sample = np.repeat(src[rng.integers(0, SEQ_LEN)][None, :], SEQ_LEN, axis=0)
        elif kind == 1:                                  # empty
            sample = np.zeros((SEQ_LEN, FEATURES_PER_FRAME), dtype=np.float32)
        elif kind == 2:                                  # drift
            start = rng.integers(0, SEQ_LEN - 2)
            slice_ = src[start:start + 2]
            idx = np.linspace(0, len(slice_) - 1, SEQ_LEN)
            sample = np.stack([slice_[int(round(j))] for j in idx])
        else:                                            # jitter
            base = src[rng.integers(0, SEQ_LEN)]
            sample = np.repeat(base[None, :], SEQ_LEN, axis=0)
            sample = sample + rng.normal(0, 0.03, sample.shape).astype(np.float32)
            sample[:, base == 0] = 0.0                   # keep undetected points undetected

        none_X.append(sample.astype(np.float32))
        # Spread across signers so the signer split stays balanced.
        none_signer.append(int(signer[rng.integers(0, len(signer))]))

    none_label = len(labels)
    X_out = np.concatenate([X, np.stack(none_X)])
    y_out = np.concatenate([y, np.full(len(none_X), none_label, dtype=np.int64)])
    signer_out = np.concatenate([signer, np.array(none_signer, dtype=np.int64)])

    labels_out = labels + ["NONE"]
    np.savez_compressed(args.out, X=X_out, y=y_out, signer=signer_out)
    json.dump(labels_out, open(args.labels, "w"))

    print(f"added {len(none_X)} NONE samples ({args.ratio:.0%} of {len(X)})")
    print(f"wrote {args.out}  X={X_out.shape}")
    print(f"labels -> {labels_out}")


if __name__ == "__main__":
    main()
