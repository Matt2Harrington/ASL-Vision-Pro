# ASL Vision Pro

Two apps — **visionOS** and **iOS** — sharing one on-device ASL recognition pipeline.
Practise your signing, look signs up, follow live speech, and (where permitted) caption someone
else signing. Nothing leaves the device.

> **Experimental prototype.** The recognizer knows 24 signs. Recognition can be wrong.
> Never rely on it for critical communication.

---

## Status

| Mode | State | Notes |
|---|---|---|
| **Dictionary** | ✅ Working | 55 signs with full phonological parameters. No model needed |
| **Practice** | ✅ Working | Scores your signing against the 24 trained signs |
| **Interpret** | ✅ Working | Captions someone signing. visionOS needs Apple's camera entitlement |
| **Listen** | ✅ Working | Speech → live captions, on-device. Needs Apple Intelligence |
| **Record Clips** | ✅ Working | Captures auto-labelled training data |
| **Translation Check** | ✅ Working | Dev screen: gloss → English on the local LLM |

**Recognizer — 24 signs + NONE**, **72.3% on held-out signers** (chance = 4%).
A 900 KB quantized Core ML model trained on ~3,000 clips from 21 Deaf signers:

| Category | Signs |
|---|---|
| **Greetings** | BYE · HELLO |
| **Courtesy** | PLEASE |
| **Responses** | BAD · FINISH · LIKE · NO · YES |
| **Needs** | DRINK · FOOD · MILK · WATER |
| **Feelings** | HAPPY · HOT · HUNGRY · MAD |
| **People** | DAD · MOM |
| **Places** | BOOK · HOME |
| **Time** | MORNING · NIGHT |
| **Conversation repair** | LISTEN · LOOK |

The vocabulary comes from a child-focused corpus, which is why it covers family, food and
feelings well and lacks question words. WHERE, WHO, WHY and THANK-YOU are queued; SORRY is not
in the corpus at all, though the dictionary describes it.

**Translation:** ASL gloss → English via Apple's on-device foundation model. No training was
needed; prompt engineering alone took it from 2/6 to 5/6 correct. Off by default — sentence
assembly is behind a setting, since it costs seconds per phrase and layers an interpretation
over recognition.

**Voice:** speaks recognized signing aloud, by sign or by sentence, for use without the screen.

Runs today on iPhone. visionOS runs everything except Interpret, which is gated on an Apple
enterprise entitlement (see [ENTITLEMENT_GUIDE.md](ENTITLEMENT_GUIDE.md)).

---

## How it works

```
camera / hand tracking
   → landmarks (Vision, or ARKit 3D on visionOS)
   → segmentation (~1.3s span)
   → Core ML classifier          → glosses
   → on-device language model    → English
```

Two stages, split by what each is good at. The classifier *perceives* — fast, calibrated,
reads motion — but cannot produce English, because ASL is not English word order. The language
model closes exactly that gap, and only ever sees text, never footage.

**24 source files are shared** between the two apps. Only the sensor source and app shell
differ.

---

## Getting started

This section assumes **no** prior experience with git, GitHub, Xcode, or the terminal. It's
long because it explains what each step is doing, not because there's much to do.

- **Part A — Run it** gets the app onto a simulator and then your iPhone.
- **Part B — Make it yours** sets up GitHub and Claude Code so you can change the project and
  save your work.

If you only want to see it run and never touch git, do Part A and stop. If you'd rather avoid
the terminal completely, [QUICKSTART.md](QUICKSTART.md) covers downloading a ZIP instead.

**You need:** a Mac (Apple Silicon or Intel, macOS Sonoma or later). Roughly an hour, most of
it waiting for Xcode to download. Everything here is free — no paid Apple developer account.

### Words you'll see, in plain English

| Word | What it actually means |
|---|---|
| **Terminal** | An app on your Mac where you type commands instead of clicking. Applications → Utilities → Terminal, or press ⌘-Space and type "Terminal" |
| **git** | A tool that tracks every version of a project, so nothing is ever lost |
| **GitHub** | A website that stores git projects online. git is the tool; GitHub is the place |
| **repo** (repository) | One project's folder plus its entire history |
| **clone** | Download a copy of a repo onto your Mac |
| **fork** | Your own copy of someone else's repo on GitHub, which you're allowed to change |
| **commit** | A save point, with a note saying what changed and why |
| **push** | Upload your commits to GitHub |
| **pull** | Download other people's commits |
| **branch** | A parallel line of work, so unfinished changes don't disturb the working version |

> **Copying commands:** each grey box below is one command. Paste it into Terminal and press
> Return. Don't type the box itself, and ignore any `$` you see in other tutorials.

---

## Part A — Run it

### 1. Install Xcode

Xcode is Apple's free app for building iPhone apps.

1. Open the **App Store** on your Mac
2. Search for **Xcode**
3. Click **Get** / **Install**

It's a 10 GB+ download and can take 30–60 minutes. Start it now and read on while it goes.

When it finishes, **open Xcode once** and accept the licence agreement. Let it install any
extra components it asks for.

This also installs **git**, so there's nothing separate to install for that.

### 2. Get the code onto your Mac

Open **Terminal** and paste these two lines, one at a time:

```bash
git clone https://github.com/Matt2Harrington/ASL-Vision-Pro.git
```

```bash
cd ASL-Vision-Pro
```

`clone` downloads the project into a new folder called `ASL-Vision-Pro` (inside whatever folder
Terminal started in — your home folder, unless you changed it). `cd` means "change directory",
i.e. step into that folder. Every command from here on assumes you're inside it.

The first time you run a git command, macOS may offer to install command line tools. Say yes
and wait for it to finish.

> Prefer buttons to typing? [GitHub Desktop](https://desktop.github.com) does clone, commit and
> push with a graphical interface.

### 3. Open the project

```bash
open ASLVisionPro.xcodeproj
```

Xcode opens and says "Indexing" for a minute or two. That's it reading the code — normal.

The `.xcodeproj` file is committed to this repo, so there is nothing to generate or configure.
The trained recognition model is committed too, so sign recognition works immediately.

### 4. Run it in the simulator

The simulator is a fake iPhone on your Mac. It's the fastest way to check everything works.

1. At the top of the Xcode window is a bar with two dropdowns
2. Set the **left** one to **ASLVisionPro-iOS**
3. Set the **right** one to any **iPhone** simulator
4. Press **▶** (top left), or ⌘R

The app launches. **Dictionary** works fully here. Camera modes will be black — a simulator has
no camera, which is exactly why step 5 exists.

### 5. Run it on your own iPhone

This is the only way to see recognition actually work. A **free** Apple ID is enough.

**Sign in to Xcode**
Menu bar → **Xcode → Settings → Accounts → +** → **Apple ID** → sign in.

**Give the app an identifier that belongs to you**
Apple requires every app to have a worldwide-unique identifier. The one in this repo is a
neutral placeholder, and if someone else has already claimed it your install will be refused.

1. Click the blue **ASLVisionPro** at the very top of the left sidebar
2. Under **TARGETS**, select **ASLVisionPro-iOS**
3. Open the **Signing & Capabilities** tab
4. Change **Bundle Identifier** from `com.example…` to your own, e.g.
   `com.yourname.ASLVisionPro.iOS`
5. In **Team** just above it, choose your name (Personal Team)

**Run**
Plug the iPhone in with a cable, unlock it, tap **Trust** if asked. Choose it in the device
dropdown and press **▶**.

**The first launch will fail** with "Untrusted Developer". That is expected, not a mistake. On
the phone: **Settings → General → VPN & Device Management → tap your Apple ID → Trust**. Then
press ▶ again.

Allow **camera** and **microphone** when asked. Everything is processed on the phone; nothing
is uploaded.

> Free Apple accounts get 7-day app licences. When the app stops opening after about a week,
> plug in and press ▶ again. Nothing is broken.

### 6. Getting updates later

```bash
git pull
```

Run that inside the project folder to fetch newer versions. (After Part B, use
`git pull upstream main` instead — Part B explains why.)

---

## Part B — Make it yours

Everything above was read-only. This part sets you up to **change** the project and save your
work, using Claude Code to do the git parts while explaining them.

You can't save changes into someone else's repo on GitHub, so the first job is making a copy
that belongs to you.

### 7. Make a GitHub account

Go to [github.com](https://github.com) and sign up. Free. Pick a username you're happy having
in public — it appears on everything you publish.

### 8. Fork this repo

A **fork** is your own copy of the project on GitHub.

1. Open <https://github.com/Matt2Harrington/ASL-Vision-Pro>
2. Click **Fork** (top right) → **Create fork**

You now have `https://github.com/YOUR-USERNAME/ASL-Vision-Pro`, which you can push to.

### 9. Point your Mac's copy at your fork

The folder you cloned in step 2 still points at the original repo. Two commands fix that.
Replace `YOUR-USERNAME` with yours in both:

```bash
git remote set-url origin https://github.com/YOUR-USERNAME/ASL-Vision-Pro.git
```

```bash
git remote add upstream https://github.com/Matt2Harrington/ASL-Vision-Pro.git
```

A **remote** is a nickname for a repo on the internet. You now have two:

- **`origin`** — your fork. This is where your work goes (`git push`)
- **`upstream`** — the original. This is where updates come from (`git pull upstream main`)

Check it worked:

```bash
git remote -v
```

You should see your own username on the `origin` lines.

### 10. Tell git who you are

Commits are stamped with a name and email. Set them once:

```bash
git config --global user.name "Your Name"
```

```bash
git config --global user.email "you@example.com"
```

Use the same email as your GitHub account so your commits are linked to your profile.

### 11. Let your Mac log in to GitHub

Pushing requires proving you're you. GitHub stopped accepting account passwords for this, so
the smooth route is GitHub's own command line tool.

Install [Homebrew](https://brew.sh) (a package installer for macOS) if you don't have it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then:

```bash
brew install gh
```

```bash
gh auth login
```

Answer: **GitHub.com** → **HTTPS** → **Yes** (authenticate git) → **Login with a web browser**.
It shows a one-time code, opens your browser, and you approve there.

> You log in on GitHub's own website. Never paste a password or access token into a chat
> window — including a chat with Claude. Anything typed into a conversation stays in its
> transcript.

### 12. Install Claude Code

Claude Code is a coding assistant that runs in your Terminal, in the same folder as the
project. It can read the code, explain it, make changes, and handle git for you.

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Then, from inside the project folder:

```bash
claude
```

The first run walks you through signing in with your Claude account. Current instructions live
at <https://docs.claude.com/en/docs/claude-code/setup> if that command has moved on.

Type your request in plain English and press Return. `/help` lists commands, and Ctrl-C stops
whatever it's doing.

### 13. Work on a branch, not on `main`

A **branch** is a separate line of work. Keeping `main` clean means you always have a version
that works to go back to.

```bash
git checkout -b my-first-change
```

That creates a branch and switches to it. `git branch` lists your branches; the one with `*` is
where you are.

### 14. Make a change, and have Claude commit it

Start Claude in the project folder and ask for something small and real. For example:

> Add my name to the bottom of the README under a "Learning notes" heading, then commit it.

Claude will edit the file and, when you approve, run the git commands. Some things worth asking
for while you're learning — the explanations are the point:

> What changed in this repo since my last commit?

> Explain what a merge conflict is, using this project as the example.

> I broke something. How do I get back to the last working version?

To see it for yourself at any time:

```bash
git status
```

```bash
git log --oneline -5
```

`status` shows what you've changed but not yet committed; `log` shows recent commits, newest
first.

### 15. Push it to your fork

```bash
git push -u origin my-first-change
```

Refresh your fork on GitHub and your branch is there. The `-u` sets up the link, so future
pushes on this branch are just `git push`.

If you want the change considered for the original project, GitHub will offer a **Compare &
pull request** button. A **pull request** is a proposal: "here's my change, have a look."

### 16. Staying up to date with the original

```bash
git pull upstream main
```

Do this on `main` before starting new work, so you're building on the latest version rather
than an old one.

---

### When git goes wrong

| What you see | What it means | What to do |
|---|---|---|
| `not a git repository` | You're in the wrong folder | `cd ~/ASL-Vision-Pro`, or wherever you cloned it |
| `Permission denied` / `403` on push | Pushing to someone else's repo, or not logged in | Redo steps 9 and 11 |
| `Please tell me who you are` | Name and email not set | Step 10 |
| `Your local changes would be overwritten` | A pull would clobber uncommitted work | Commit it first, or ask Claude what's uncommitted |
| `CONFLICT (content): Merge conflict in …` | You and someone else changed the same lines | Not an error. Ask Claude to walk you through it |
| `detached HEAD` | You're looking at an old commit, not a branch | `git checkout main` |

Nothing here can lose committed work. Once something is committed, git keeps it — that's the
entire point of committing early and often.

---

## Build reference

The project file is committed, so **XcodeGen is not needed to build**. It's only needed if you
change the project's *structure* — adding files, targets, or settings — which is done in
`project.yml`:

```bash
brew install xcodegen   # only if changing project structure
xcodegen generate
```

Schemes: **ASLVisionPro** (visionOS) · **ASLVisionPro-iOS** · **ASLVisionProTests** (103 tests).

```bash
xcodebuild test -project ASLVisionPro.xcodeproj -scheme ASLVisionProTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

> `xcodebuild test` can appear to hang for minutes *after* printing results. The tests are
> done; it's a teardown quirk.

The trained model (`SignModel.mlpackage`, 900 KB) **is committed**, so recognition works from a
fresh clone. To train your own, see [TRAINING_GUIDE.md](TRAINING_GUIDE.md).

### Hardware
- **iPhone** — everything except visionOS-specific modes. Fastest path to seeing it work.
- **Vision Pro** — required for Practice's 3D hand tracking; the simulator has no camera or hand data.
- **Apple Intelligence** (iPhone 15 Pro or newer) — needed for Listen and English translation only.

---

## Layout

```
ASLVisionPro/
  Shared/
    Pipeline/       FrameSource, LandmarkExtractor, SignSegmenter, FeatureEncoder,
                    SignRecognizer, SignVerifier, TutorSession, DataCollector,
                    GlossInterpreter, SignCatalog, TranslationPipeline, RecognizerFactory
    UI/             DesignSystem, DictionaryView, ListenView, CaptionView,
                    DataCollectorView, TranslationCheckView, LandmarkOverlayView
    Resources/      signs.json (dictionary), labels.json (model classes)
    Models/         SignModel.mlpackage (committed — recognition works from a fresh clone)
  visionOS/         app shell, HandTrackingSource, VisionProCameraSource, TutorView
  iOS/              app shell, iPhoneCameraSource, CameraPreview
Tests/              15 suites, 103 tests
training/           Python: fetch → import → train → export
config/
  feature_spec.json THE preprocessing contract, read by Swift and Python alike
```

Two structural decisions worth preserving:

- **`SignRecognizing` is the one swappable stage.** Stub, classifier, or CTC model swap behind
  it without touching capture, landmarks, segmentation, or captions.
- **`config/feature_spec.json` is the single source of truth.** Drift between the Swift encoder
  and the Python trainer is the failure mode that silently destroys accuracy — so neither side
  declares these constants itself.

---

## Documentation

| Doc | What it covers |
|---|---|
| [QUICKSTART.md](QUICKSTART.md) | Non-technical: install Xcode → run on your iPhone |
| [SETUP.md](SETUP.md) | Developer setup: clone → build → device → training |
| [TRAINING_GUIDE.md](TRAINING_GUIDE.md) | How the model was trained, where data lives, how to improve it |
| [ML_PLAYBOOK.md](ML_PLAYBOOK.md) | Reusable procedure for any on-device model + local LLM |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design and the capability ladder |
| [RECOGNITION_APPROACH.md](RECOGNITION_APPROACH.md) | Why alphabet, words and sentences are different problems |
| [MODEL_PLAN.md](MODEL_PLAN.md) | Model strategy and the train/inference contract |
| [ENTITLEMENT_GUIDE.md](ENTITLEMENT_GUIDE.md) | Applying for visionOS main-camera access |
| [FEASIBILITY.md](FEASIBILITY.md) | Original assessment — why this is hard |
| [ALTERNATIVE_DIRECTIONS.md](ALTERNATIVE_DIRECTIONS.md) | Other products this pipeline supports |

---

## Honest limitations

- **Twenty-four signs.** A demo, not a product. The corpus is child-focused, so there are no
  question words yet and SORRY isn't in it at all.
- **72.3% is measured on the source corpus**, not on a phone in a room. Real-world accuracy is
  still unverified — that's what testing on your own device tells you.
- **More data has diminishing returns.** 30% more clips per sign bought about a point. Closing
  the gap further likely needs a different approach, not more of the same.
- **Continuous signing is scaffolded, not trained.** The CTC path exists and is unit-tested;
  there's no model behind it.
- **Translation takes seconds per phrase**, so it's off by default. Glosses appear live;
  English arrives on a pause.
- **visionOS Interpret is blocked** on an Apple enterprise entitlement, which individual
  developer accounts generally cannot get.
- **ASL is not English.** Gloss-to-English layers an interpretation over recognition, so the
  raw glosses stay visible — a wrong translation should be inspectable, not authoritative.
- **Kaggle limits downloads** to roughly 700 files a day, so growing the vocabulary is paced by
  that rather than by effort.
