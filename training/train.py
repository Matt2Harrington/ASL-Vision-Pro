"""Train the sign classifier on cached landmark windows.

Usage:
  python train.py --data data/synth.npz --labels labels.json --epochs 20 --out ckpt.pt
"""
import argparse
import json

import numpy as np
import torch
from torch.utils.data import DataLoader

from dataset import SignWindowDataset, load_npz, signer_split
from model import SignClassifier


def evaluate(model, loader, device):
    model.eval()
    correct = total = 0
    with torch.no_grad():
        for x, y in loader:
            x, y = x.to(device), y.to(device)
            pred = model(x).argmax(dim=1)
            correct += (pred == y).sum().item()
            total += y.numel()
    return correct / max(1, total)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="data/synth.npz")
    ap.add_argument("--labels", default="labels.json")
    ap.add_argument("--epochs", type=int, default=20)
    ap.add_argument("--batch-size", type=int, default=64)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--out", default="ckpt.pt")
    args = ap.parse_args()

    labels = json.load(open(args.labels))
    device = "mps" if torch.backends.mps.is_available() else "cpu"

    X, y, signer = load_npz(args.data)
    (Xtr, ytr), (Xval, yval) = signer_split(X, y, signer, holdout_frac=0.2)
    print(f"train={len(ytr)} val={len(yval)} (split by signer) classes={len(labels)} device={device}")

    train_loader = DataLoader(SignWindowDataset(Xtr, ytr, augment=True),
                              batch_size=args.batch_size, shuffle=True)
    val_loader = DataLoader(SignWindowDataset(Xval, yval, augment=False),
                            batch_size=args.batch_size)

    model = SignClassifier(num_classes=len(labels)).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    loss_fn = torch.nn.CrossEntropyLoss(label_smoothing=0.05)

    best = 0.0
    for epoch in range(1, args.epochs + 1):
        model.train()
        for x, y in train_loader:
            x, y = x.to(device), y.to(device)
            opt.zero_grad()
            loss = loss_fn(model(x), y)
            loss.backward()
            opt.step()
        acc = evaluate(model, val_loader, device)
        print(f"epoch {epoch:3d}  val_acc(held-out signers)={acc:.3f}")
        if acc >= best:
            best = acc
            torch.save(model.state_dict(), args.out)
    print(f"best held-out-signer accuracy={best:.3f}  saved -> {args.out}")


if __name__ == "__main__":
    main()
