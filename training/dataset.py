"""Dataset + augmentation over cached landmark windows.

Expects an .npz produced by the landmark-extraction step (or synth.py) with:
  X      : float32 [N, SEQ_LEN, FEATURES_PER_FRAME]  (already normalized per feature_spec)
  y      : int64   [N]                                (class index)
  signer : int64   [N]                                (signer id, for signer-split)

The extraction step MUST apply the same torso-centered / shoulder-scaled normalization the
Swift FeatureEncoder applies. This class assumes that has already happened.
"""
import numpy as np
import torch
from torch.utils.data import Dataset

from feature_spec import SEQ_LEN, FEATURES_PER_FRAME


class SignWindowDataset(Dataset):
    def __init__(self, X, y, augment: bool = False):
        assert X.shape[1:] == (SEQ_LEN, FEATURES_PER_FRAME), \
            f"expected windows of shape [*, {SEQ_LEN}, {FEATURES_PER_FRAME}], got {X.shape}"
        self.X = X.astype(np.float32)
        self.y = y.astype(np.int64)
        self.augment = augment

    def __len__(self):
        return len(self.y)

    def __getitem__(self, i):
        x = self.X[i]
        if self.augment:
            x = self._augment(x)
        return torch.from_numpy(x), int(self.y[i])

    def _augment(self, x):
        x = x.copy()
        # Coordinate noise (missed/jittery detections).
        x += np.random.normal(0, 0.01, x.shape).astype(np.float32)
        # Global scale + translation (signer distance / position invariance).
        x *= np.random.uniform(0.9, 1.1)
        x += np.random.uniform(-0.05, 0.05)
        # Point dropout (occlusion / a hand leaving frame).
        if np.random.rand() < 0.3:
            mask = np.random.rand(x.shape[1]) < 0.1
            x[:, mask] = 0.0
        return x


def load_npz(path):
    d = np.load(path)
    return d["X"], d["y"], d["signer"]


def signer_split(X, y, signer, holdout_frac=0.2, seed=0):
    """Split by SIGNER, not by clip — measures generalization to new people."""
    rng = np.random.default_rng(seed)
    signers = np.unique(signer)
    rng.shuffle(signers)
    n_holdout = max(1, int(len(signers) * holdout_frac))
    val_signers = set(signers[:n_holdout].tolist())
    val_mask = np.array([s in val_signers for s in signer])
    return (X[~val_mask], y[~val_mask]), (X[val_mask], y[val_mask])
