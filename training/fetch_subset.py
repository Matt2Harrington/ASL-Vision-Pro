"""Download only the clips we actually need from the asl-signs competition.

The full corpus is ~100 GB, which is unnecessary: it covers 250 signs and we need a handful.
train.csv lists every clip's path, so we can fetch individual files and skip the rest.

Two levers keep this small:
  * sign selection — a usable lesson is ~10 signs, not 250
  * clips per sign — ~150 spread across all 21 signers is plenty to train on, and keeping
    every signer matters because train.py validates on held-out signers

Resumable: already-downloaded files are skipped, so interrupting and re-running is safe.

Usage:
  python fetch_subset.py --train-csv ~/Downloads/train.csv --signs HELLO PLEASE YES NO WATER
  python fetch_subset.py --train-csv ~/Downloads/train.csv --catalog-overlap --per-sign 150
"""
import argparse
import collections
import csv
import json
import os
import shutil
import subprocess
import sys
import time
import tempfile
import zipfile

COMP = "asl-signs"


def load_rows(path):
    with open(os.path.expanduser(path)) as f:
        return list(csv.DictReader(f))


def catalog_glosses(repo_root):
    """Signs our app already has parameter data for — the ones worth recognizing first."""
    p = os.path.join(repo_root, "ASLVisionPro/Shared/Resources/signs.json")
    return {e["gloss"] for e in json.load(open(p))}


def pick(rows, signs, per_sign):
    """Choose clips per sign, cycling through signers so every signer stays represented.

    Taking the first N rows would bias toward whichever signers appear early in the file and
    can silently drop signers entirely, which would make held-out-signer validation
    meaningless.
    """
    by_sign = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in rows:
        by_sign[r["sign"]][r["participant_id"]].append(r)

    chosen = []
    for sign in signs:
        signers = by_sign.get(sign)
        if not signers:
            print(f"  ! {sign!r} not in dataset — skipped")
            continue
        pools = [list(v) for v in signers.values()]
        i = 0
        while len([c for c in chosen if c["sign"] == sign]) < per_sign and any(pools):
            pool = pools[i % len(pools)]
            if pool:
                chosen.append(pool.pop())
            i += 1
            if i > per_sign * 50:
                break
    return chosen


def unzip_in_place(path):
    """The Kaggle CLI returns some files zipped and others raw, with no way to tell in
    advance. Normalizing on download keeps every file a real parquet, so the importer
    doesn't have to care."""
    if not os.path.exists(path):
        return
    with open(path, "rb") as f:
        if f.read(2) != b"PK":
            return
    try:
        with zipfile.ZipFile(path) as z:
            payload = z.read(z.namelist()[0])
        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp.write(payload)
            tmp_path = tmp.name
        shutil.move(tmp_path, path)
    except Exception:
        pass


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(here)

    ap = argparse.ArgumentParser()
    ap.add_argument("--train-csv", default="~/Downloads/train.csv")
    ap.add_argument("--signs", nargs="*", default=None, help="dataset sign labels (lowercase)")
    ap.add_argument("--catalog-overlap", action="store_true",
                    help="use every sign our app catalog already describes")
    ap.add_argument("--per-sign", type=int, default=150)
    ap.add_argument("--out", default="data/asl_signs")
    ap.add_argument("--dry-run", action="store_true", help="report the plan, download nothing")
    ap.add_argument("--cooldown", type=int, default=0,
                    help="seconds to pause when throttled, then continue instead of aborting. "
                         "Kaggle allows roughly 500-600 files per window, so a long download "
                         "has to be spread across several with waits between.")
    ap.add_argument("--max-rounds", type=int, default=12,
                    help="give up after this many throttle pauses")
    args = ap.parse_args()

    rows = load_rows(args.train_csv)
    available = {r["sign"] for r in rows}

    if args.catalog_overlap:
        norm = {s.upper().replace(" ", "-"): s for s in available}
        signs = sorted(norm[g] for g in catalog_glosses(repo_root) if g in norm)
    elif args.signs:
        signs = [s.lower() for s in args.signs]
    else:
        sys.exit("Pass --signs or --catalog-overlap")

    chosen = pick(rows, signs, args.per_sign)
    signers = {c["participant_id"] for c in chosen}
    est_gb = len(chosen) * 1.1 / 1024

    print(f"signs   : {len(signs)} -> {', '.join(signs)}")
    print(f"clips   : {len(chosen):,} of {len(rows):,} ({len(chosen)/len(rows)*100:.1f}%)")
    print(f"signers : {len(signers)} (train.py validates on held-out signers)")
    print(f"est size: ~{est_gb:.1f} GB at ~1.1 MB/clip")
    if args.dry_run:
        print("\ndry run — nothing downloaded")
        return

    os.makedirs(args.out, exist_ok=True)
    done = skipped = failed = 0
    consecutive = 0
    rounds = 0
    done_at_last_throttle = -1

    for i, row in enumerate(chosen, 1):
        dest = os.path.join(args.out, row["path"])
        if os.path.exists(dest):
            skipped += 1
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)

        # Kaggle throttles sustained request bursts, and a throttled request looks exactly
        # like a failed one. Retrying with a growing pause distinguishes them: a rate limit
        # clears, a genuine error doesn't.
        ok = False
        for attempt in range(3):
            r = subprocess.run(
                ["kaggle", "competitions", "download", "-c", COMP,
                 "-f", row["path"], "-p", os.path.dirname(dest), "--force"],
                capture_output=True, text=True,
            )
            if r.returncode == 0:
                ok = True
                break
            time.sleep(2 ** attempt * 3)   # 3s, 6s, 12s

        if ok:
            unzip_in_place(dest)
            done += 1
            consecutive = 0
        else:
            failed += 1
            consecutive += 1
            if consecutive <= 3:
                print(f"  ! {row['path']}: {r.stderr.strip().splitlines()[-1] if r.stderr else 'failed'}")
            # Only give up on a sustained run of failures. Counting cumulatively would abort a
            # long download over scattered throttling it had already recovered from.
            if consecutive >= 25:
                if not args.cooldown:
                    print("\nAborting: 25 consecutive failures. Either the competition rules "
                          "aren't accepted, or Kaggle is rate limiting hard — wait and re-run; "
                          "already-downloaded files are skipped. Or pass --cooldown to wait "
                          "and continue automatically.")
                    break
                rounds += 1
                # If the previous pause bought nothing, waiting the same amount again won't
                # either — Kaggle's window is longer than the cooldown. Stop rather than
                # cycle, since repeated requests while limited keep it refreshed.
                if done == done_at_last_throttle:
                    print(f"\n  The last pause produced no downloads, so the rate-limit window "
                          f"is longer than {args.cooldown // 60} min. Stopping with {done} files "
                          f"fetched this run.\n  Re-run later (an hour or more) — downloaded "
                          f"files are skipped. A longer --cooldown may also work.")
                    break
                done_at_last_throttle = done

                if rounds > args.max_rounds:
                    print(f"\nStopping after {args.max_rounds} throttle pauses. "
                          f"Re-run to continue — downloaded files are skipped.")
                    break
                mins = args.cooldown / 60
                print(f"\n  Throttled after {done} files. Pausing {mins:.0f} min "
                      f"(round {rounds}/{args.max_rounds}), then continuing...", flush=True)
                time.sleep(args.cooldown)
                consecutive = 0
                print("  Resuming.", flush=True)

        if i % 25 == 0 or i == len(chosen):
            print(f"  {i}/{len(chosen)}  downloaded={done} skipped={skipped} failed={failed}",
                  flush=True)

    print(f"\ndone: {done} downloaded, {skipped} already present, {failed} failed -> {args.out}")


if __name__ == "__main__":
    main()
