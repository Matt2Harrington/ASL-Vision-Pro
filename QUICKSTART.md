# Quick Start

For getting this running on your own iPhone without needing to be a developer. No terminal, no
command line — just Xcode.

**Time:** about 20 minutes, most of it waiting for Xcode to download.
**Cost:** free. A regular Apple ID works; no paid developer account.

---

## Will it work on my iPhone?

Two different things, with two different requirements:

| Feature | Needs |
|---|---|
| **Sign recognition** (Practice, Interpret) | Any iPhone on **iOS 17 or later** |
| **Listen** and **Translation Check** | **iPhone 15 Pro or newer** with Apple Intelligence |

Recognition runs a small model included in the project, so it works on essentially any modern
iPhone. Speech captions and English translation use **Apple Intelligence**, which Apple only
supports on:

- **iPhone 15 Pro / 15 Pro Max**, and every iPhone 16 and 17 model
- iPads with M1 or later, or A17 Pro
- Macs with Apple Silicon

It also needs **iOS 26 or later**, about **7 GB free storage**, and Apple Intelligence switched
on in **Settings → Apple Intelligence & Siri**.

On an older iPhone everything else still works — those two modes are simply hidden or show a
message.

---

## 1. Install Xcode

Xcode is Apple's free app for building iPhone apps.

1. Open the **App Store** on your Mac
2. Search for **Xcode**
3. Click **Get** / **Install**

It's a very large download (10 GB+) and can take 30–60 minutes. Start it and go do something
else.

When it finishes, **open Xcode once** and accept the licence agreement it shows. It may install
extra components — let it finish.

## 2. Download the project

On the GitHub page for this project:

1. Click the green **Code** button
2. Choose **Download ZIP**
3. Double-click the downloaded file to unzip it
4. Move the unzipped folder somewhere sensible, like your Documents folder

## 3. Open it

Inside the folder, double-click **`ASLVisionPro.xcodeproj`** — the icon looks like a blue
blueprint.

Xcode opens. It may say "indexing" for a minute; that's normal.

## 4. Try it in the simulator first

This checks everything works before involving your phone.

1. At the top of the Xcode window there's a bar showing a scheme and a device
2. Click the **left** part and choose **ASLVisionPro-iOS**
3. Click the **right** part and choose any **iPhone simulator** from the list
4. Press the **▶ Play** button (top left)

A fake iPhone appears and the app launches. **Dictionary** works fully here. The camera modes
will be black — a simulator has no camera, which is why the next step matters.

## 5. Put it on your iPhone

### Sign in

1. Menu bar: **Xcode → Settings → Accounts**
2. Click **+**, choose **Apple ID**, sign in with your normal Apple ID

### Give the app your own name

Apple requires an identifier unique to you. If you skip this, installing may fail because
someone else already used the default.

1. In the left sidebar, click the blue **ASLVisionPro** at the very top
2. Under TARGETS, select **ASLVisionPro-iOS**
3. Open the **Signing & Capabilities** tab
4. Find **Bundle Identifier** and change `com.example` to something of your own —
   e.g. `com.yourname.ASLVisionPro.iOS`
5. In the **Team** dropdown just above, choose your name (Personal Team)

### Run it

1. Plug your iPhone into the Mac with a cable. Unlock it. Tap **Trust** if asked
2. In the device dropdown at the top, choose **your iPhone**
3. Press **▶ Play**

### One-time trust step

The first run fails with **"Untrusted Developer."** That's expected. On your iPhone:

**Settings → General → VPN & Device Management → tap your Apple ID → Trust**

Then press ▶ in Xcode again.

### Allow permissions

The app asks for **camera** and **microphone**. Both are needed, and everything is processed on
the phone — nothing is uploaded.

---

## What to try

| Mode | What happens |
|---|---|
| **Dictionary** | Browse 32 signs with how each is formed. Works on any device |
| **Interpret** | Point the camera at yourself and sign. Coloured dots track your hands |
| **Practice** | It asks for a sign and scores your attempt |
| **Listen** | Speak and watch live captions appear (needs Apple Intelligence) |

The app currently knows **five signs**: HELLO, NO, PLEASE, WATER, YES. Try HELLO or WATER
first — they involve the largest movement and are recognized most reliably.

Recognition shows a percentage. Green means it's confident; dim means it saw something but
wasn't sure.

---

## If something goes wrong

**"Untrusted Developer"** — expected on the first run. See the trust step above.

**"Failed to register bundle identifier"** — the identifier is already taken. Change it to
something more unusual and try again.

**App disappears or won't open after about a week** — free Apple accounts get 7-day app
licences. Plug in, press ▶ again, and it's renewed.

**No Team available in the dropdown** — the Apple ID wasn't added. Xcode → Settings →
Accounts → **+**.

**Camera screen is black** — you're on the simulator, which has no camera. Choose your iPhone.

**Listen or Translation Check missing** — your iPhone doesn't support Apple Intelligence, or
it isn't enabled in **Settings → Apple Intelligence & Siri**.

---

## Worth knowing

This is an **experimental prototype**. It recognizes five signs and gets them wrong sometimes.
It is not an interpreter and shouldn't be relied on for real communication.

Everything runs on the phone. No video, audio, or hand data is uploaded anywhere.

Developers wanting to build on this: see [SETUP.md](SETUP.md) and
[TRAINING_GUIDE.md](TRAINING_GUIDE.md).
