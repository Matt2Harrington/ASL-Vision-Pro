# On-Device ML Playbook

A reusable procedure for taking any sensor-or-text model from idea to working on a device,
plus how to decide what to do about a local LLM.

Derived from building ASL recognition on visionOS/iOS. **Almost every bug in that project was
the same bug wearing a different hat: the data at inference did not look like the data at
training.** The model was never the hard part. This document is organized around finding those
mismatches early, because each one costs days when found late and minutes when found first.

---

## 0. The one idea

> A model learns a *representation*, not a *thing*. It does not learn "hands" — it learns the
> exact numbers your preprocessing produced. Any difference between how those numbers are made
> at training time and at inference time is a silent accuracy bug, and it will look like a bad
> model.

Symptoms that you have one, rather than a data-volume problem:
- Validation accuracy is high; real use is near chance
- Some inputs work and most don't, and you can't see the pattern
- Fixes help "slightly" without ever converging
- The debug view looks *correct* while predictions are wrong ← especially this one

---

## 1. Questions to answer before writing any model code

Answer these in writing. Vague answers here become weeks later.

### Scope
1. **What is one prediction?** One frame? A window? A whole utterance? This decides your
   architecture more than anything else.
2. **What can the model refuse to say?** If the answer is "nothing," you need a rest/negative
   class. A softmax always names a class, however alien the input.
3. **What is chance?** 5 classes = 20%. Report accuracy against it, always.
4. **What is the smallest version that is still useful?** Ship that. A reliable 5-class model
   beats an unreliable 250-class one.

### Data
5. **Where does the data come from, and how was it captured?** Device, viewpoint, lighting,
   mirroring, frame rate. Each is a mismatch waiting to happen.
6. **Do I need all of it?** Usually not. Index files often let you fetch a subset — check
   before writing off a 100 GB corpus.
7. **What identifies a subject?** You must split by *person* (or session, or site), not by
   sample. Splitting by sample inflates accuracy and tells you nothing about generalization.
8. **What is the licence?** Check before building on it.

### Truth
9. **How will I know it is wrong?** Design the failure-visible path before the happy path.
10. **What does the user see when the model is unsure?** "Nothing" and "I'm not sure" must look
    different from each other, and from "not running."

---

## 2. Write the contract down, in one file

Put every preprocessing constant in **one machine-readable file** read by *both* the training
code and the inference code. Not two constants that agree today.

```jsonc
{
  "version": 3,
  "sequence_length": 24,
  "features_per_frame": 198,
  "input_shape": [1, 24, 198],
  "normalization": { "method": "...", "anchor": "...", "scale": "..." },
  "io": { "input_feature_name": "landmarks", "output_feature_name": "probabilities" },
  // Every decision that could differ between the two sides belongs here:
  "hands_only": true,
  "uses_depth": false
}
```

**Version it.** When you change preprocessing, bump the version and retrain — a model and a
spec version are a matched pair, and mixing them silently destroys accuracy.

---

## 3. The mismatch checklist

Walk this before blaming the model. Each line is a real bug that shipped in the source project.

### Ordering and identity
- [ ] **Is feature index *i* always the same thing?** Beware anything iterating a dictionary,
      set, or map — ordering may be unspecified or hash-seeded per process.
- [ ] **Does filtering shift positions?** Dropping a low-confidence item moves everything after
      it. Emit a zero placeholder instead; keep the slot.

### Coordinate systems
- [ ] **Origin.** Top-left or bottom-left? Vision uses lower-left; MediaPipe uses upper-left.
      A Y flip inverts every vertical motion.
- [ ] **Handedness / mirroring.** Front cameras are usually mirrored; back cameras are not.
      Mirroring flips apparent chirality — left and right swap.
- [ ] **Units.** Normalized [0,1], pixels, or metres? Relative to what?
- [ ] **Extra channels.** If training had depth and inference doesn't (or vice versa), zero it
      on both sides or retrain. Never feed a channel the model never saw.

> **The trap:** a debug overlay often quietly compensates for one of these when drawing. Then
> the picture looks right while the model gets garbage. **Assert on the values you feed the
> model, not on what you render.**

### Time
- [ ] **What is one sample, temporally?** A fixed number of frames, or a whole event resampled?
- [ ] **Truncating vs resampling.** If training resampled whole events to N steps, inference
      must too. Taking the most recent N frames feeds the tail of an event at a different
      time-scale and drops its start.
- [ ] **Frame rate.** 24 frames means 0.8s at 30fps and 2.4s at 10fps.

### Source
- [ ] **Same extractor?** Two libraries that both produce "landmarks" rarely produce the *same*
      landmarks. Check topology counts and ordering before assuming they interchange.
- [ ] **Which parts actually transfer?** In the source project only the hands did; face and body
      came from incompatible topologies and were *actively harmful*. Removing them: **67% → 93%**.
- [ ] **Capture conditions.** Selfie vs rear camera, distance, lighting, background.

---

## 4. Validate in stages, cheapest first

Each stage answers one question. Don't skip ahead — a later stage can't tell you what an
earlier one would have.

| Stage | Question | Cost |
|---|---|---|
| 1. **Synthetic** | Does the toolchain run end to end? | minutes |
| 2. **Tiny real subset** | Does it learn anything above chance? | ~1 hour |
| 3. **On device** | Does the representation survive the trip? | ~1 hour |
| 4. **Scale up** | Is it accurate enough to use? | days |

**Stage 1** uses random data with a learnable structure. 100% accuracy is expected and
meaningless — you are testing plumbing: train → export → convert → load in app.

**Stage 3 is the one people skip and shouldn't.** It's where every mismatch in §3 shows up. Do
not collect more data until it passes; more data cannot fix a representation mismatch.

---

## 5. Instrument before you tune

When something "isn't picking it up," you cannot fix what you cannot see.

- **Surface the model's top prediction and confidence even when rejected.** A gated result and
  a model that never ran look identical from outside, and that ambiguity wastes hours.
- **Make gates adjustable at runtime.** Held-out accuracy says little about where a confidence
  threshold belongs on a real device, in a real room.
- **Log what you feed the model**, at least once, and compare it numerically against a training
  sample of the same class.

Three distinguishable failures, once instrumented:

| Symptom | Meaning |
|---|---|
| right label, low confidence | threshold too strict — tune it |
| wrong label, high confidence | genuine accuracy problem — more/better data |
| nothing at all | upstream: capture, detection, or segmentation |

---

## 6. Honesty belongs in the UI

For anything assistive, decision-supporting, or speaking on someone's behalf:

- **Stub output must be visibly labelled.** Placeholder feedback is indistinguishable from real
  recognition and far more damaging, because it is confidently encouraging. Drive the label off
  a real check (is a model actually bundled?) so it disappears by itself.
- **Show the raw prediction alongside any polished output.** If an LLM turns predictions into
  fluent prose, keep the underlying tokens visible — fluency reads as certainty.
- **A refusal is a feature.** Design "I don't know" as a first-class state.
- **Never let a decline erase a good previous answer.** Silence is not evidence the last answer
  was wrong.

---

## 7. Local LLMs (Apple Foundation Models and similar)

### First: can you even train it?
Usually **no**. Apple's on-device model is fixed; what exists is **LoRA adapter training**
(Python toolkit, Apple Silicon + 32 GB RAM, ~160 MB per adapter, shipped via Background
Assets). Adapters are **pinned to a base model version** — when the vendor updates the model,
you retrain.

### Second: don't. Try the prompt.
Vendor guidance is to train an adapter only when prompt engineering falls short. In the source
project it didn't:

| Input | Before prompt work | After |
|---|---|---|
| ME NAME M-A-T-T | "Matt" | "My name is Matt." |
| BATHROOM WHERE | "Bathroom where?" | "Where is the bathroom?" |

**2/6 → 5/6 correct**, from writing the domain's actual rules into the instructions. Adapter
training would have been days for something a paragraph fixed.

### How to prompt a small local model well
- **State the domain rules explicitly.** Small models don't know your field's conventions.
  Enumerate them ("WH-words come last in this language and first in English").
- **Constrain against invention.** "Translate only what you are given. Never add facts."
  Especially where output represents a person.
- **Give it a refusal token.** "If the input is too short or incoherent, reply exactly:
  UNCLEAR." Then treat that as a decline, not as text.
- **Demand bare output.** No preamble, no alternatives, no quotes.
- **Iterate against real failures**, not imagined ones — collect actual bad outputs first.

### Getting into the right state
- [ ] **Availability is not capability.** The source project's model reported itself available
      while its assets were absent and every request failed. Probe with a real call; count
      consecutive failures and fall back permanently.
- [ ] **Always have a non-LLM fallback path**, and make it honest (show raw tokens rather than
      nothing).
- [ ] **Measure latency on device.** The source project sees 4–8s per short phrase. That rules
      out per-word interaction and shapes the UX: emit fast output immediately, let the LLM
      refine on a pause.
- [ ] **Simulators lie.** Model assets are often absent or stubbed. Build an in-app evaluation
      screen — you cannot judge quality from a build machine.
- [ ] **Only text should cross the boundary.** Keep raw sensor data out of the LLM stage. That
      preserves the privacy story and lets you swap in a hosted model later without changing
      what leaves the device.

---

## 8. Reusable repo shape

```
config/feature_spec.json      # THE contract, read by both sides, versioned
training/
  feature_spec.py             # reads the JSON — never redeclare constants
  fetch_subset.py             # pull only what you need from a large corpus
  import_<source>.py          # source format -> the contract
  add_none_class.py           # synthesize negatives so the model can abstain
  synth.py                    # fake data to prove the toolchain
  train.py                    # splits by SUBJECT, reports against chance
  export_<runtime>.py         # -> Core ML / ONNX / TFLite, quantized
app/
  Shared/…                    # everything platform-agnostic
  <Platform>/…                # only the sensor source and shell differ
```

Two rules that paid off repeatedly:

1. **One swappable inference stage.** Everything upstream (capture, preprocessing) and
   downstream (UI) is model-agnostic, so a stub, a classifier, a sequence model, or a hosted
   API swap behind one interface.
2. **Record training data through the inference encoder.** If your app can capture data, route
   it through the *same* preprocessing used at inference. Parity then holds by construction
   instead of by discipline.

---

## 9. Worked example: the numbers from this project

| Change | Held-out accuracy |
|---|---|
| Synthetic data (plumbing check only) | 100% — meaningless |
| Real data, all landmark regions | 67.4% |
| Hands only (dropped incompatible face/body) | **92.6%** |
| Added NONE class so it can abstain | 91.8% |

Fixed after the model was already "done," each of which had blocked real-world use:
non-deterministic joint ordering · Y-axis origin inversion · camera mirroring · temporal
truncation instead of resampling · depth present at inference but not in training.

**Every one was a representation mismatch. None was the model.** That ratio is the reason this
document is mostly a checklist for §3.
