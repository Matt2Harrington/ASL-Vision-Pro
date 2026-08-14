# ASL Vision Pro — Feasibility Study

**A visionOS app that watches a person signing ASL and displays the translated words live on screen.**

Date: 2026-07-01
Status: Feasibility assessment / pre-planning

> **DECISION (2026-07-01):** Build **Scenario A** — translate *another person* in view — and **push scope to the maximum** (continuous, open-domain ASL → English, not just fingerspelling). This commits us to the Apple Enterprise camera-access entitlement and a research-grade translation pipeline. See **[ARCHITECTURE.md](ARCHITECTURE.md)** for the committed design and roadmap. This document remains the honest record of *why* those choices are hard.

---

## 1. Concept

A visionOS application that:

1. Shows a live view of a person performing American Sign Language (ASL).
2. Runs sign recognition on the video/hand data in real time.
3. Overlays the recognized words as live captions in the UI.

Simple UI, minimal controls — a camera/person view with a running text caption.

---

## 2. The Central Feasibility Question: *Whose* Hands?

This single design decision determines whether the app is buildable with standard APIs or requires special Apple approval. There are two very different products hiding in the same one-line description.

### Scenario A — Translate **another person** in front of the wearer
"I wear the headset, look at a friend signing, and see captions."

- Requires access to the **passthrough camera** to *see* the other person.
- On visionOS, raw main-camera frames are **gated behind Apple's Enterprise APIs** (`com.apple.developer.arkit.main-camera-access.allow`). These entitlements are granted only to organizations for internal/enterprise distribution — **not available for consumer App Store apps** as of visionOS 2.x.
- **Verdict: Not feasible for a general/consumer app** without an Apple enterprise entitlement. Feasible only as an in-house/enterprise build or a research prototype under a managed account.

### Scenario B — Translate the **wearer's own** signing
"I wear the headset and sign; the app captions me."

- Uses **ARKit `HandTrackingProvider`**, which is available to normal apps. It gives 3D skeletal joint positions for both of the wearer's hands (~26 joints each).
- No raw camera access needed — you work from the hand skeleton, which sidesteps the entitlement wall and most privacy concerns.
- **Verdict: Feasible** as a consumer app, with major accuracy caveats (see §4).

> **Recommendation:** Build **Scenario B** first. It is the only version shippable to the App Store today, and it de-risks the hard ML problem before you touch camera entitlements. Treat Scenario A as a future/enterprise track.

---

## 3. Platform Capabilities (visionOS / Apple frameworks)

| Capability | API | Available to consumer apps? | Notes |
|---|---|---|---|
| Wearer hand skeleton (3D joints) | ARKit `HandTrackingProvider` | ✅ Yes | ~26 joints/hand, high frequency. Core enabler for Scenario B. |
| Passthrough / main camera frames | `CameraFrameProvider` (Enterprise) | ⚠️ Enterprise entitlement only | Needed for Scenario A. Not for App Store. |
| On-device ML inference | Core ML | ✅ Yes | Runs custom models on the Neural Engine. |
| Vision (2D pose/hand landmarks) | Vision framework | ✅ Yes | `VNDetectHumanHandPoseRequest` — but needs image input, so tied to camera access. |
| Body/face pose | ARKit / Vision | Partial | Face + non-manual markers matter for ASL grammar (see §4). |
| UI overlays | SwiftUI + RealityKit | ✅ Yes | Captions as a windowed or volumetric view is straightforward. |

**Language/toolchain:** Swift, SwiftUI, RealityKit, ARKit, Core ML. Xcode + visionOS SDK. Requires an actual **Apple Vision Pro** or the simulator (note: the simulator does **not** provide real hand-tracking data, so on-device testing needs hardware).

---

## 4. The Hard Part: ASL Recognition Is Not a Solved Problem

The UI and plumbing are easy. The recognition is where ambitious projects fail. Key realities:

1. **ASL ≠ fingerspelling.** Fingerspelling (spelling words letter-by-letter with handshapes) is the *easiest* sub-problem and is where most "ASL translator" demos actually operate. Full ASL is a distinct language.

2. **ASL is not word-for-word English.** It has its own grammar, spatial syntax, and does not map linearly to English words. True "translation" (not transcription) is an open research problem.

3. **Signs are multi-channel.** Meaning comes from handshape, location, movement, palm orientation, **and non-manual markers** — facial expression, eyebrows, head tilt, mouth morphemes. Hand-only skeleton data (Scenario B) misses these, capping achievable accuracy.

4. **Signs are temporal.** A sign is a *motion over time*, not a static pose. Recognition needs sequence models (LSTM/GRU/Transformer over joint-sequence windows), not single-frame classification.

5. **Continuous signing has no clear word boundaries** (co-articulation), unlike isolated-sign datasets. Segmenting a live stream into signs is itself hard.

6. **Data & signer variation.** Accuracy varies with signing speed, dialect, individual style, and lighting. Public datasets (e.g., WLASL, MS-ASL, How2Sign) exist but are limited, and hand-skeleton-only data narrows options further.

### Realistic accuracy tiers

| Scope | Difficulty | Realistic outcome |
|---|---|---|
| Fingerspelling (A–Z static-ish handshapes) | Low–Medium | Demoable, decent accuracy |
| Isolated signs, small fixed vocabulary (~50–200) | Medium | Achievable with a trained sequence model |
| Continuous signing, medium vocabulary | High | Research-grade, unreliable |
| Full unrestricted ASL → fluent English | Very High | **Not currently achievable** — open research |

**Framing the goal honestly:** aim for **live recognition of fingerspelling + a limited set of isolated signs**, described as an *assistive/educational* tool, not a general-purpose interpreter. Overpromising "translate ASL to English live" sets up failure and — for a deployed accessibility tool — real harm if users rely on wrong output.

---

## 5. Recommended MVP

**"Live wearer-signed fingerspelling + small-vocabulary recognizer with on-screen captions."**

- **Scenario B** (wearer's hands) via ARKit hand tracking.
- Recognize the ASL **fingerspelling alphabet** plus ~20–50 common isolated signs.
- Feed normalized joint-sequence windows into a **Core ML sequence model**.
- SwiftUI caption view that appends recognized tokens live with a confidence threshold.
- Clearly labeled as experimental/assistive.

### High-level architecture

```
ARKit HandTrackingProvider
        │  (3D joint stream, both hands)
        ▼
Preprocessing  ─ normalize/scale, sliding time window, buffering
        │
        ▼
Core ML sequence model  ─ (temporal classifier: signs / letters / "none")
        │  (label + confidence)
        ▼
Debounce / smoothing  ─ threshold, dedupe, word assembly
        │
        ▼
SwiftUI caption overlay  ─ live text in the person-view UI
```

### Suggested phases

1. **Spike:** Prove ARKit hand tracking on-device; log joint streams; render a live caption placeholder.
2. **Data + model:** Assemble/record a small labeled dataset; train a sequence classifier; export to Core ML.
3. **Integrate:** Wire model into the live joint pipeline with smoothing and thresholds.
4. **UI polish:** Confidence display, clear "experimental" labeling, caption history.
5. **(Later / enterprise track):** Explore Scenario A with camera entitlements for third-person signing.

---

## 6. Risks & Open Questions

| Risk | Impact | Mitigation |
|---|---|---|
| Scenario A camera access unavailable to consumer apps | Blocks "watch another person" concept | Ship Scenario B; pursue enterprise entitlement separately |
| Recognition accuracy below usable bar | Product feels broken | Scope to fingerspelling + small vocab; show confidence; label experimental |
| No hand data in simulator | Slows iteration | Requires physical Vision Pro for real testing |
| Missing non-manual markers (face/grammar) | Ceiling on real ASL comprehension | Set expectations; position as assistive, not interpreter |
| Training data scarcity for skeleton-only ASL | Weak model | Record custom dataset; start with fingerspelling |
| Accessibility harm from wrong translations | Users mislead in real communication | Never present as authoritative; disclaimers |

### Open questions to decide before building
- Is the target the **wearer** (Scenario B, shippable) or **another person** (Scenario A, enterprise-only)?
- Is the acceptable scope **fingerspelling + limited vocabulary**, or is full-sentence translation a hard requirement (currently infeasible)?
- Consumer App Store distribution, or internal/enterprise/research use?
- Do you have access to **Vision Pro hardware** for testing?

---

## 7. Bottom Line

- **Simple UI with live captions on visionOS:** ✅ Straightforward.
- **Recognizing the wearer's own fingerspelling / small vocabulary (Scenario B):** ✅ Feasible, real ML work required, hardware needed.
- **Watching a *third person* sign (Scenario A):** ⚠️ Blocked for consumer apps by camera-access entitlements; enterprise/research only.
- **Full, reliable ASL→English translation:** ❌ Not achievable today — open research problem.

**Recommended path:** Build the Scenario B MVP scoped to fingerspelling plus a small sign vocabulary, positioned as an experimental/assistive tool, and keep third-person translation as a future enterprise track.
