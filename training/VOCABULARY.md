# Level-2 Starter Vocabulary

`labels_signs.json` — **69 glosses + NONE** for the isolated-sign classifier
(RECOGNITION_APPROACH.md §Level 2). Use it in place of `labels.json` (fingerspelling) once
you have sign data:

```bash
python train.py --data data/signs.npz --labels labels_signs.json --out ckpt_signs.pt
python export_coreml.py --ckpt ckpt_signs.pt --labels labels_signs.json --out SignModel.mlpackage --quantize
```

## Why these signs

Chosen for **practical first-conversation utility**, not frequency in a corpus. The list is
deliberately small — a reliable 70-sign vocabulary beats an unreliable 2000-sign one, and
confidence gating means a miss shows nothing rather than something wrong.

| Group | Examples | Why |
|---|---|---|
| Greetings / courtesy | HELLO, THANK-YOU, PLEASE, SORRY | Open and close nearly every exchange |
| Core responses | YES, NO, MAYBE, GOOD, BAD, FINE | Highest-value single-sign replies |
| Repair signals | AGAIN, SLOW-DOWN, REPEAT, WAIT, UNDERSTAND | **Critical** — how a conversation recovers when recognition fails |
| Question words | WHO, WHAT, WHERE, WHEN, WHY, HOW | Carry most information-seeking utterances |
| Pronouns | ME, YOU, MY, YOUR | Frequent; also anchor spatial reference |
| States / needs | HUNGRY, THIRSTY, TIRED, SICK, HELP | High-stakes, practical |
| Everyday nouns/verbs | EAT, DRINK, GO, HOME, WORK, WATER, BATHROOM | Common concrete content |
| Domain-relevant | DEAF, HEARING, SIGN, NAME | Recur constantly in this app's actual context |
| Urgent | EMERGENCY, DOCTOR, PHONE, STOP | Worth recognizing even at low frequency |

## Notes on the label format

- **Glosses, not English words.** ASL convention writes signs in CAPS; multi-word glosses use
  hyphens (`THANK-YOU`, `NICE-TO-MEET-YOU`) because they are *one sign*, not a phrase.
- **`NONE` stays at index 0** — the negative/rest class. The segmenter's activity gate is
  coarse, so the model needs a way to say "no sign here." Do not remove it.
- **One gloss ≠ one English word.** These labels are recognition targets, not translations;
  turning gloss sequences into fluent English is the Level-3 problem.

## Growing the list

1. Add glosses that your **actual users** need — this list is a starting point, not a
   prescription. Deaf/ASL-community input should drive it (MODEL_PLAN §3).
2. Ensure every added gloss has **enough training clips across multiple signers**; a class
   with thin data hurts the whole model's calibration.
3. Watch for **minimal pairs** — signs differing only in a non-manual marker or small movement
   (e.g. question forms). If the confusion matrix shows them collapsing, that's evidence the
   face/body points need more weight, not just more data.
4. Re-check thermals and latency as classes grow; the head widens but the encoder doesn't, so
   cost grows slowly — verify rather than assume.
