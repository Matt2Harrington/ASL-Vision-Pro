"""Convert Kaggle asl-signs MediaPipe landmarks into the tensors our trainer expects.

The dataset stores 543 MediaPipe Holistic landmarks per frame (468 face, 33 pose, 21 per
hand) with x/y/z. Our model consumes 66 points — 21 per hand, 8 body, 16 face — normalized
exactly as the Swift FeatureEncoder does at inference. This script performs that mapping and
nothing else clever, because any divergence here shows up as a model that trains well and
fails on device (MODEL_PLAN.md §2).

Hands map one-to-one: MediaPipe's 21-point skeleton is the same layout and order as
LandmarkExtractor.handJointOrder (wrist, then thumb→little, four joints each). That
correspondence is why this dataset is usable at all without re-extracting from video.

Usage:
  python import_kaggle.py --train-csv ~/Downloads/train.csv --data data/asl_signs \
      --labels labels_kaggle.json --out data/kaggle.npz
"""
import argparse
import glob
import json
import os

import numpy as np
import pandas as pd

from feature_spec import SEQ_LEN, FEATURES_PER_FRAME, POINTS, MIN_SCALE, HANDS_ONLY

HAND_POINTS = POINTS["left_hand"]
BODY_POINTS = POINTS["body"]
FACE_POINTS = POINTS["face"]

# MediaPipe pose indices for the joints LandmarkExtractor.bodyJointOrder defines.
# Order matters: indices 0 and 1 must be the shoulders, because FeatureEncoder anchors on
# point 0 and scales by the 0–1 distance (shoulder width).
POSE_LEFT_SHOULDER, POSE_RIGHT_SHOULDER = 11, 12
BODY_SOURCE = [
    POSE_LEFT_SHOULDER,     # 0 leftShoulder  (anchor)
    POSE_RIGHT_SHOULDER,    # 1 rightShoulder (scale partner)
    None,                   # 2 neck — MediaPipe has none; midpoint of the shoulders
    0,                      # 3 nose
    13,                     # 4 leftElbow
    14,                     # 5 rightElbow
    15,                     # 6 leftWrist
    16,                     # 7 rightWrist
]


def frame_points(group, kind, count, source_indices=None):
    """Pull `count` points of one landmark type, in a fixed order, as an (count, 3) array.

    Missing or undetected landmarks arrive as NaN and become zeros — the same placeholder the
    Swift extractor emits — so a point's slot in the feature vector is preserved either way.
    """
    sub = group[group["type"] == kind]
    if sub.empty:
        return np.zeros((count, 3), dtype=np.float32)

    lookup = {int(r.landmark_index): (r.x, r.y, r.z) for r in sub.itertuples()}
    out = np.zeros((count, 3), dtype=np.float32)
    for i in range(count):
        src = i if source_indices is None else source_indices[i]
        if src is None:
            continue
        v = lookup.get(src)
        if v is not None:
            out[i] = [0.0 if pd.isna(c) else c for c in v]
    return out


def write_hand(pts, out, offset):
    """One hand, centred on its wrist and scaled by wrist-to-middle-MCP span.

    Mirrors FeatureEncoder.writeHand exactly. Wrist-relative normalization removes any
    dependence on detecting a torso, which the phone often can't see, and is computed the
    same way from MediaPipe and Vision landmarks because their hand topology matches.
    """
    if not np.any(pts):
        return
    wrist = pts[0].copy()
    span = float(np.sqrt(((pts[9][0] - wrist[0]) ** 2) + ((pts[9][1] - wrist[1]) ** 2)))
    span = max(0.02, span)
    for i in range(len(pts)):
        out[offset + i * 3: offset + i * 3 + 3] = (pts[i] - wrist) / span


def encode_clip(df, keep_depth):
    """One clip -> (SEQ_LEN, FEATURES_PER_FRAME), normalized like FeatureEncoder."""
    hand_n = POINTS["left_hand"]
    frames = []
    for _, group in df.groupby("frame", sort=True):
        left = frame_points(group, "left_hand", hand_n)
        right = frame_points(group, "right_hand", hand_n)

        if HANDS_ONLY:
            # Face and body slots stay in the tensor but carry zeros: MediaPipe and Vision
            # disagree on those topologies, so training on them teaches noise.
            vec = np.zeros(FEATURES_PER_FRAME, dtype=np.float32)
            write_hand(left, vec, 0)
            write_hand(right, vec, hand_n * 3)
            if not keep_depth:
                vec[2::3] = 0.0
            frames.append(vec)
            continue

        body = frame_points(group, "pose", BODY_POINTS, BODY_SOURCE)
        body[2] = (body[0] + body[1]) / 2.0
        face_all = frame_points(group, "face", 468)
        face = face_all[np.linspace(0, 467, FACE_POINTS).astype(int)]

        pts = np.concatenate([left, right, body, face], axis=0)
        anchor = body[0].copy()
        dx, dy = body[0][0] - body[1][0], body[0][1] - body[1][1]
        scale = max(MIN_SCALE, float(np.sqrt(dx * dx + dy * dy)))
        pts = (pts - anchor) / scale
        if not keep_depth:
            pts[:, 2] = 0.0
        frames.append(pts.reshape(-1))

    if not frames:
        return None
    arr = np.stack(frames).astype(np.float32)

    # Resample time to a fixed window rather than crop, so slow and fast signings both keep
    # their full trajectory.
    if len(arr) != SEQ_LEN:
        idx = np.linspace(0, len(arr) - 1, SEQ_LEN)
        arr = np.stack([arr[int(round(i))] for i in idx])
    return arr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train-csv", default="~/Downloads/train.csv")
    ap.add_argument("--data", default="data/asl_signs")
    ap.add_argument("--labels", default="labels_kaggle.json")
    ap.add_argument("--out", default="data/kaggle.npz")
    ap.add_argument("--keep-depth", action="store_true",
                    help="keep MediaPipe z (only correct if inference also supplies depth)")
    args = ap.parse_args()

    index = pd.read_csv(os.path.expanduser(args.train_csv))
    have = {p.replace(args.data + "/", "")
            for p in glob.glob(os.path.join(args.data, "train_landmark_files/*/*.parquet"))}
    index = index[index["path"].isin(have)]
    if index.empty:
        raise SystemExit(f"No downloaded clips found under {args.data}")

    signs = sorted(index["sign"].unique())
    label_index = {s: i for i, s in enumerate(signs)}
    print(f"clips {len(index):,} | signs {len(signs)} | signers {index['participant_id'].nunique()}")

    signer_ids = {p: i for i, p in enumerate(sorted(index["participant_id"].unique()))}
    X, y, signer, skipped = [], [], [], 0

    for n, row in enumerate(index.itertuples(), 1):
        arr = encode_clip(pd.read_parquet(os.path.join(args.data, row.path)), args.keep_depth)
        if arr is None or arr.shape != (SEQ_LEN, FEATURES_PER_FRAME):
            skipped += 1
            continue
        X.append(arr)
        y.append(label_index[row.sign])
        signer.append(signer_ids[row.participant_id])
        if n % 100 == 0:
            print(f"  {n}/{len(index)}")

    X = np.stack(X)
    np.savez_compressed(args.out, X=X, y=np.array(y, np.int64), signer=np.array(signer, np.int64))
    json.dump([s.upper().replace(" ", "-") for s in signs], open(args.labels, "w"))

    print(f"\nwrote {args.out}  X={X.shape}  ({skipped} skipped)")
    print(f"wrote {args.labels}: {signs}")
    counts = {signs[i]: int((np.array(y) == i).sum()) for i in sorted(set(y))}
    print("per class:", counts)


if __name__ == "__main__":
    main()
