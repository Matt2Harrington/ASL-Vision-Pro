# Interpreting ASL — Alphabet vs. Words vs. Sentences

The one-line goal ("translate ASL to words") hides **three different problems**. They differ
not in difficulty-of-degree but in *kind* — each needs a different ML formulation, and the
jump between them is where the real engineering (and the real limits) live.

Companion to [ARCHITECTURE.md](ARCHITECTURE.md) (capability ladder) and
[MODEL_PLAN.md](MODEL_PLAN.md) (the classifier we scaffolded).

---

## The three levels at a glance

| Level | Unit | ML problem | Output | Our model handles it? |
|---|---|---|---|---|
| 1. Fingerspelling | a letter (handshape) | short-window **classification** | letters → spell words | ✅ the scaffolded classifier |
| 2. Isolated signs | one whole sign | windowed **sequence classification** | one gloss at a time | ✅ same classifier, bigger vocab |
| 3. Continuous | a full utterance | **sequence-to-sequence** | phrase / sentence | ❌ needs a different model head |

The key insight: **levels 1–2 are classification** ("which of N labels is this window?").
**Level 3 is translation** ("this variable-length motion → this variable-length sentence").
Those are different model families. The classifier in `model.py` is built for 1–2. Level 3
is not "the same thing scaled up" — it's a new architecture.

---

## Level 1 — Fingerspelling (the alphabet)

**What it is:** spelling words letter-by-letter with 26 handshapes. Used for names, brands,
and words with no sign.

**Why it's the easiest:** most letters are near-*static* handshapes, so a short window (or
even a single well-chosen frame) carries the label. Small, closed set (26 + "none").

**How it's interpreted:**
- Classify each short window → a letter.
- Debounce repeats (a held handshape spans many windows) — the `CaptionAssembler` already
  concatenates consecutive letters into a word.
- Two catches: **J and Z involve motion** (need the temporal window, not one frame), and
  fingerspelling in the wild is *fast and co-articulated* — letters blur together, which is
  a mini version of the Level-3 segmentation problem.

**Verdict:** genuinely shippable. This is the concrete first win and what `labels.json`
currently targets (NONE + A–Z).

---

## Level 2 — Isolated signs (words)

**What it is:** one lexical sign at a time — HELLO, THANK-YOU, NAME — signed with a pause
around it. This is what datasets like WLASL/MS-ASL contain.

**Why it's harder than fingerspelling:**
- A sign is a **motion over time** — handshape + location + movement + palm orientation.
  You cannot classify a single frame; the whole ~0.5–1.5s trajectory *is* the label. (This
  is exactly why our features are a `[24, 132]` window, not one frame.)
- The vocabulary is **large and open** (thousands of signs), with a long tail. Accuracy
  drops as vocab grows; minimal pairs differ only by, say, a facial expression.
- Two-handed signs, and signs that reuse the same handshape in different locations.

**How it's interpreted:**
- The exact same windowed classifier, with the label set expanded from letters to glosses.
- Confidence gating matters more — with thousands of classes, "show nothing" beats "show a
  wrong guess." That's the `confidenceThreshold` in `CoreMLSignRecognizer`.

**Verdict:** achievable for a fixed vocabulary (start ~50–200), scaling toward thousands as
data allows. Still *classification* — no architecture change from Level 1.

---

## Level 3 — Continuous signing (sentences & phrases)

**What it is:** natural signing with no pauses between signs — a real conversation.

**Why it's a different problem entirely:**

1. **No boundaries (segmentation).** Continuous signing has no spaces. Signs blur into each
   other (co-articulation) — the end of one sign is already morphing into the next. You
   can't classify "each sign" because you don't know where each sign *is*. Our
   `SignSegmenter`'s activity gate is a crude stand-in; real segmentation is learned.

2. **ASL grammar ≠ English word order.** ASL is its own language. It uses **spatial
   grammar** (positioning referents in space and pointing back to them), topic-comment
   structure, and time markers that don't map linearly to English words. So Level 3 is
   **translation, not transcription** — you can't just concatenate recognized glosses into
   good English.

3. **Non-manual markers carry grammar.** Eyebrows raise for yes/no questions; head tilt,
   mouth morphemes, and facial expression change meaning and mark clauses. Hand-only models
   miss this. (This is why our features include face and body points, not just hands — but
   it also means hand-centric data caps the ceiling.)

4. **One sign ≠ one word.** A single sign may need a whole English phrase, or several signs
   may collapse to one word.

**How it's interpreted — this needs a new model head:**
- **CTC** (Connectionist Temporal Classification): maps an unsegmented frame sequence to a
  sequence of glosses without needing per-frame alignment. Good for continuous *recognition*
  (sign order), a stepping stone that still isn't English.
- **Sequence-to-sequence (encoder–decoder Transformer)**: encodes the landmark/motion
  stream, decodes a spoken-language sentence. This is **Sign Language Translation (SLT)**.
  Two flavors:
  - *Gloss-based*: video → glosses → text (two stages; needs gloss annotations).
  - *Gloss-free*: video → text directly (what recent research pushes; needs lots of data).
- A **language model** on the decoder side produces fluent English rather than word salad.

**Verdict:** research frontier. Works in narrow domains (e.g. weather), degrades sharply on
open vocabulary, speed, and dialect. Fully on-device, model size is the extra limiter. We
build *toward* it but present its output as assistive, never authoritative.

---

## What this means for our code

Our scaffolded model (`model.py`, a windowed classifier) is the **right tool for Levels 1–2
and the wrong tool for Level 3.** That's a deliberate, correct staging — not a gap to
apologize for. Concretely:

- **Levels 1–2:** ship with the current architecture. Grow `labels.json` from letters to a
  fixed sign vocabulary. Nothing structural changes; the `SignRecognizer` swap is all it takes.
- **Level 3:** requires a **second model type** behind the same `SignRecognizing` protocol —
  a CTC or seq2seq/SLT model with its own decoder. Because the recognizer is the one
  swappable stage (ARCHITECTURE.md §3), the app shell, camera, landmarks, and captions don't
  change — only what sits behind `recognize(_:)`. The UI is already built for it: captions
  are **revisable** (`CaptionAssembler`, `CaptionView`), which is exactly what streaming
  seq2seq output needs.

## Recommended interpretation strategy (staged)

1. **Fingerspelling** — closed set, immediate win, handles names/unknowns. *(now)*
2. **Isolated signs** — fixed vocabulary, same classifier, confidence-gated. *(next)*
3. **Continuous recognition (CTC)** — sign *order* without English fluency. *(research)*
4. **Continuous translation (seq2seq/SLT)** — fluent phrases, non-manual markers, LM-assisted
   decoding. *(frontier; on-device is the stretch)*

Each stage is independently useful, ships value, and de-risks the next. Fingerspelling +
isolated signs is a genuinely useful assistive tool on its own — and it's the part that is
actually solvable today.
