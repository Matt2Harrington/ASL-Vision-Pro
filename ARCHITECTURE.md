# ASL Vision Pro — Architecture & Roadmap (Max-Scope Build)

**Committed direction:** Wearer looks at *another person* signing ASL; the app captions their signing live, targeting **continuous, open-domain translation** — pushed as far as the technology allows.

Date: 2026-07-01
Companion to: [FEASIBILITY.md](FEASIBILITY.md)

---

## 0. Locked Decisions

| Decision | Choice | Consequence |
|---|---|---|
| Whose hands | **Another person** in view | Requires passthrough main-camera access → Enterprise entitlement |
| Scope | **Maximum** — continuous sentence-level translation | Research-grade ML; cloud compute; accuracy ceiling is real |
| Distribution | Enterprise / in-house / research (not consumer App Store, initially) | Managed Apple Developer entitlement required |
| Camera access | **Enterprise main-camera entitlement** (confirmed available) | Native Vision Pro passthrough path; no companion device |
| Compute | **Fully on-device** (Neural Engine) | Maximum privacy + offline; **caps the translation ceiling** (see §4) — no giant off-device models |

---

## 1. Gating Dependency #1 — Camera Access (solve this before writing ML code)

To *see* another person, the app needs forward main-camera frames. On visionOS this is **not** available to normal apps.

- **API:** ARKit `CameraFrameProvider` + `com.apple.developer.arkit.main-camera-access.allow` entitlement (Enterprise API family, introduced visionOS 2.0; stereo/both-camera access expanded in later 2.x).
- **Path chosen:** **Enterprise entitlement (confirmed available).** Apps using it are distributed **in-house/enterprise**, not on the consumer App Store — acceptable for this project.
- **Action items:**
  1. Add the managed entitlement + Apple-issued license file to the app's provisioning.
  2. Validate you receive frames on real hardware (simulator provides no camera).
  3. Confirm which cameras/resolution the entitlement grants for your account (mono vs stereo affects depth/robustness).

> This is still **Phase 0** — prove frames arrive on-device before building ML on top. The iPhone-companion fallback (§8) is now unused but kept as a contingency.

---

## 2. Capability Ladder — What "Maximum Scope" Means, Staged

Translation quality is a spectrum, not a switch. We build up the ladder; each rung is independently useful and de-risks the next.

| Rung | Capability | State of the art | Our realistic target |
|---|---|---|---|
| 1 | Fingerspelling recognition | Solved-ish | High accuracy |
| 2 | Isolated signs, fixed vocabulary (100s) | Achievable | Good accuracy |
| 3 | Isolated signs, large vocabulary (1000s, e.g. WLASL) | Research, moderate | Usable with confidence gating |
| 4 | **Continuous** signing → gloss sequence | Research | Partial, domain-limited |
| 5 | **Continuous → fluent English** (gloss-free translation) | **Open frontier** | Best-effort, unreliable on open domain |

**Honest ceiling:** rung 5 on unrestricted, real-world ASL is **not a solved problem** in 2026. Best published continuous sign-language-translation systems perform well only in narrow domains (e.g., weather) and degrade sharply on open vocabulary, fast signing, regional variation, and poor framing.

**The fully-on-device choice lowers the ceiling further.** Rungs 4–5 in current research lean on large models that exceed the Neural Engine's budget. On-device, we push as far as a **quantized/compact translation model** allows — realistically **strong at rungs 1–3 and partial at rung 4**, with rung 5 as an aspirational stretch rather than a deliverable. This is the deliberate cost of maximum privacy and offline operation. If you later want to trade some privacy for a higher ceiling, adding an *optional* server path (the earlier hybrid design) is the lever — the pipeline is built so that swap is localized to one stage.

---

## 3. End-to-End Pipeline

Everything runs **on-device on Vision Pro** — no network, no footage leaves the headset.

```
┌─────────────────────────────────────────────────────────────────────┐
│ ON-DEVICE (Apple Vision Pro) — nothing leaves the device            │
│                                                                     │
│  ARKit CameraFrameProvider ── main-camera frames (the other person) │
│            │                                                        │
│            ▼                                                        │
│  Person detection + tracking ── isolate the signer, crop ROI        │
│            │                                                        │
│            ▼                                                        │
│  Holistic landmark extraction ── hands (2×21) + body pose + face    │
│    (Vision framework and/or on-device MediaPipe → ~500+ keypoints)  │
│            │                                                        │
│            ▼                                                        │
│  Feature normalization + sliding-window buffering                   │
│            │                                                        │
│            ▼                                                        │
│  Temporal segmentation ── detect sign boundaries / active-signing   │
│            │                                                        │
│            ▼                                                        │
│  Core ML models (Neural Engine)                                     │
│    • rungs 1–3: fingerspelling + isolated-sign classifier          │
│    • rung 4 (stretch): compact/quantized continuous translator     │
│            │                                                        │
│            ▼                                                        │
│  Post-processing ── confidence gating, debounce, sentence assembly  │
│            │                                                        │
│            ▼                                                        │
│  SwiftUI caption overlay ── live text near/over the person view     │
└─────────────────────────────────────────────────────────────────────┘
```

**Design the Core ML stage as a swappable module.** If you ever choose to raise the ceiling by adding an optional server path for rungs 4–5, only this one stage changes — everything upstream (capture, landmarks, segmentation) and downstream (captions) is identical. Keeping the boundary clean now costs nothing and preserves that option.

---

## 4. Model Strategy

All models run on the **Neural Engine via Core ML**. Model size is now a hard design constraint — favor compact architectures and quantization.

- **Rungs 1–3 (primary target):** temporal classifier (compact Transformer or GRU/LSTM over landmark sequences). Trainable on public isolated-sign datasets. Low latency, fully private, offline. This is the shippable core.
- **Rung 4 (stretch):** a **compact/quantized gloss-free translation model** — a small landmark encoder + sequence decoder sized to fit the Neural Engine. Expect domain-limited quality; this is the frontier of what fits on-device.
- **Rung 5 (aspirational):** fluent open-domain translation is not realistic fully on-device in 2026 — flagged honestly, not promised.
- **Segmentation:** continuous signing has no spaces — a boundary/activity detector chunks the stream so the classifier/translator sees coherent spans.
- **Non-manual markers:** eyebrows, mouth morphemes, head tilt carry grammar. Face landmarks feed the model at rungs 4–5; this is a key reason full RGB/face data (not hands alone) matters and why the ceiling is high.

**Training data:** public sets — WLASL, MS-ASL (isolated); How2Sign (continuous ASL). Expect to record a **custom dataset** for your real conditions (headset viewpoint, framing, distance). Data scarcity is a primary limiter for rungs 4–5.

---

## 5. "Live" Latency Budget

Fully on-device removes the network round trip, so latency is dominated by the inherent duration of a sign. "Live" realistically means **~0.5–2 s rolling lag**. Budget per stage (targets):

| Stage | Target |
|---|---|
| Frame capture → landmarks | < 50 ms/frame (real-time) |
| Segmentation window | 0.5–1.5 s (inherent — a sign takes time) |
| On-device Core ML inference | < 100 ms/window (Neural Engine) |
| Caption render | < 50 ms |

Watch the **thermal/battery budget**: continuous camera + vision + Neural Engine inference is sustained load on a head-worn device. Profile for thermal throttling early. Design the UI for **streaming, revisable captions** (tokens appear, then refine) rather than final-only — this hides latency and matches how the model actually resolves meaning.

---

## 6. Tech Stack

- **App:** Swift, SwiftUI, RealityKit
- **Sensing:** ARKit (`CameraFrameProvider`, world/scene), Vision framework (hand/body/face pose)
- **Landmarks:** Vision and/or MediaPipe Holistic
- **On-device ML:** Core ML (Neural Engine); Create ML / coremltools for conversion + quantization
- **Model training (offline, dev-time only):** Python (PyTorch), exported to Core ML
- **Hardware:** **Apple Vision Pro required** (simulator lacks camera + hand data). No server needed at runtime.
- **Tooling:** Xcode + visionOS SDK; enterprise provisioning + managed camera entitlement

---

## 7. Legal, Privacy & Ethical (non-optional)

Filming and interpreting another person raises real obligations. **The fully-on-device choice is a major privacy win** — no footage or landmarks leave the headset — but it does not remove these duties:

- **Consent:** you are still capturing video of a person. Build in visible recording indication and a consent model, even though processing is local.
- **Minimize data:** process on-device (✅ by design); don't retain frames beyond the processing window; no persistence of raw footage.
- **Accuracy harm:** wrong translations in real communication can mislead or misrepresent a Deaf/HoH signer. **Never present output as authoritative.** Show confidence; label experimental; make errors visibly likely.
- **Community:** engage Deaf/ASL community input early. Tools *about* a language and culture should involve its users; this also improves data and trust.

---

## 8. Fallback Architectures (if the entitlement is blocked)

1. **iPhone/iPad companion camera:** a phone films the signer and streams landmarks to the Vision Pro app. Sidesteps the visionOS main-camera entitlement entirely; the standard camera APIs on iOS are open. Adds a device but unblocks the whole concept for non-enterprise distribution.
2. **Wearer-signs (Scenario B):** ship the App-Store-viable version in parallel as a proving ground for the ML.

---

## 9. Roadmap

| Phase | Goal | Exit criterion |
|---|---|---|
| **0. Entitlement** | Wire up the managed main-camera entitlement + provisioning | Camera frames received on real hardware |
| **1. Capture spike** | Camera → person detection → live landmark stream, rendered as debug overlay | Stable real-time landmarks of a person on-device |
| **2. Rungs 1–3** | On-device Core ML: fingerspelling + isolated-sign vocabulary, live captions | Reliable captions for a fixed vocabulary |
| **3. Rung 4 push** | Compact on-device continuous translator; segmentation; non-manual markers; profile thermals | Best-effort continuous captions, domain-limited, within thermal budget |
| **4. UX + ethics hardening** | Streaming/revisable captions, consent flow, confidence UI, custom dataset | Demoable, honestly-labeled assistive tool |

---

## 10. Bottom Line

- **Camera access** is the first hard gate — resolved via the confirmed **Enterprise entitlement**. Prove frames on-device (Phase 0) before ML.
- **Fully on-device** gives maximum privacy and offline operation, and removes network latency — at the cost of a **lower translation ceiling** (no giant models on the Neural Engine).
- **Rungs 1–3** (fingerspelling + fixed vocabulary) are genuinely achievable and demoable — this is the shippable core.
- **Rung 4** (continuous, domain-limited) is a realistic on-device **stretch**; **rung 5** (fluent open-domain ASL → English) stays **aspirational**, not promised.
- The plumbing, UI, and on-device sensing are well within reach. Translation quality on unrestricted ASL is the true limiter — a limitation of the field (and, secondarily, of the on-device budget), not of this design. The Core ML stage is kept swappable so an optional server path could later raise the ceiling if you ever choose to trade some privacy for capability.
