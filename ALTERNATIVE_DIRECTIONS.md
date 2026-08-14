# Alternative Directions for the Vision Pro App

The enterprise camera wall blocks exactly one thing: **seeing another person**. Everything
else Vision Pro offers is open. This document explores what's worth building inside that
constraint — and argues one of these is actually a *better* product than the original.

Companion to [ARCHITECTURE.md](ARCHITECTURE.md) and [ENTITLEMENT_GUIDE.md](ENTITLEMENT_GUIDE.md).

---

## The unlock: wearer-hand tracking is free, and the data is better

`ARKit HandTrackingProvider` gives ~26 **3D** joints per hand, at high frequency, with no
entitlement, no Apple approval, and full App Store distribution.

Compare to what we extract from camera frames today:

| | Camera path (blocked) | Hand tracking (open) |
|---|---|---|
| Entitlement | Enterprise, likely denied | **None** |
| Distribution | In-house only | **App Store** |
| Data | 2D landmarks (x, y) | **3D joints (x, y, z)** |
| Tracking quality | Our Vision pipeline | Apple's, already solved |
| Whose hands | Anyone in view | **Wearer only** |

The depth channel matters: handshapes that project identically in 2D (a fist toward the
camera vs. away) are trivially separable in 3D. Moving to hand tracking is a **data upgrade**
that would require widening `FeatureEncoder` from 2 to 3 coords per point — a spec change,
not a redesign.

The cost is the product constraint: **the wearer must be the signer.**

---

## Direction 1 — ASL Tutor ⭐ *recommended*

**You are learning ASL. The headset watches your hands and coaches you in real time.**

A 3D model demonstrates a sign in the space next to your own hand; you attempt it; the app
tells you what to fix — "thumb should touch your chin," "movement needs to be sharper."

### Why this is the strongest option

**1. The ML problem is fundamentally easier.** This is the key insight. The tutor *knows
which sign the learner is attempting*. So it isn't open-vocabulary recognition ("which of
2,000 signs is this?") — it's **verification** ("is this a correct THANK-YOU, and if not,
which parameter is wrong?"). One-vs-rest instead of N-way. Dramatically less data, higher
accuracy, and it degrades gracefully: a wrong answer is "try again," not a mistranslation.

**2. Vision Pro is genuinely the right device**, not a gimmick. Precise 3D hand tracking plus
spatial rendering means you can show the correct handshape *overlaid on or beside your actual
hand*, viewable from any angle. A phone app cannot do this. A webcam app cannot do this. This
is the rare case where the hardware is a real moat.

**3. Real market.** ASL is among the most-studied languages in US universities, and existing
learning apps are video-and-quiz — nobody gets feedback on whether their *actual signing* is
correct. That's the gap.

**4. Ships today.** No entitlement, App Store distribution, no research dependency.

**5. Honest failure mode.** Wrong feedback in a *learning* context is a minor annoyance. Wrong
output in a *live interpretation* context can misrepresent a person — a far higher bar.

### Reuse from what we've built
`SignSegmenter`, `FeatureEncoder` (widened to 3D), the classifier, `RecognizerFactory`, and
the whole training pipeline. The frame source changes from camera → hand tracking; the
recognizer's job changes from classify → verify.

---

## Direction 2 — Two-way conversation assistant

**Deaf/HoH wearer signs → device speaks aloud. Hearing person speaks → captions in headset.**

The strategic point: **one half of this is already a solved problem.** Apple's Speech
framework does live, on-device speech-to-text with no entitlement and high accuracy. So the
hearing→Deaf direction works *today, perfectly, with zero ML risk.*

That asymmetry is worth exploiting: ship the speech-captioning half as a complete, genuinely
useful product, then add sign→speech incrementally as the model improves. Users get value on
day one instead of waiting on the hard direction.

- **Hearing → Deaf:** `SFSpeechRecognizer` → spatial captions. Solved.
- **Deaf → Hearing:** hand tracking → our recognizer → `AVSpeechSynthesizer`. Our existing
  pipeline, constrained to the wearer.

Highest social value of the options; also the highest bar for correctness, since output
speaks *for* a person.

---

## Direction 3 — Spatial ASL dictionary

**Look up any sign; a 3D avatar demonstrates it, viewable from any angle.**

Lowest risk by far — **no recognition at all** in v1. It's a content and rendering product.
Video dictionaries lose exactly the information 3D preserves: depth, orientation, and the
ability to check "what does that look like from the side?"

Good as a companion mode inside Direction 1 rather than a standalone product — it's the
reference material a tutor needs anyway.

---

## Direction 4 — Data collection tool

**Use hand tracking to build the dataset the recognizer needs.**

Meta-useful rather than a product: prompt a signer, record 3D joint sequences, label
automatically from the prompt. Solves the bottleneck that currently blocks *every* other
direction — and the data quality (3D, clean, pre-labeled) beats scraped video.

Worth building as an internal tool regardless of which direction you pick.

---

## Recommendation

**Build the ASL Tutor (Direction 1), with the dictionary (3) as a mode inside it and the
collection tool (4) as internal infrastructure.**

The reasoning in one line: it's the only direction where **the constraint makes the product
better** — because a tutor knowing which sign is being attempted turns an unsolved research
problem into a tractable verification problem, while Vision Pro's 3D hand tracking gives it a
capability no phone or webcam competitor can match.

Direction 2 is the higher-impact accessibility play and worth returning to — its
speech-to-captions half is free and could ship alongside.

### What changes in the code

| Piece | Change |
|---|---|
| `FrameSource` | New `HandTrackingSource` (ARKit) alongside the camera sources |
| `SignFrame` | 3D joints — add `z` |
| `FeatureEncoder` | 2 → 3 coords/point; update `feature_spec.json` (both sides) |
| `SignRecognizing` | Add a `verify(expected:)` path for tutor mode |
| Pipeline, segmenter, captions, training scripts | **Unchanged** |

The `FrameSource` seam we built for the iPhone fallback is exactly the seam this needs — a
third implementation, not a rewrite.
