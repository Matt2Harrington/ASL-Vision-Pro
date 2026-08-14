# Applying for visionOS Main Camera Access

Step-by-step for the entitlement that unblocks the Vision Pro app's "watch another person
sign" capability. See [ARCHITECTURE.md](ARCHITECTURE.md) §1 for why this gate exists.

**Your bundle ID:** `com.mattharrington.ASLVisionPro`
**Entitlement key:** `com.apple.developer.arkit.main-camera-access.allow`

---

## ⚠️ Read this first — eligibility

Main Camera Access is an **Enterprise API**. Apple's terms:

- Intended for apps **"for use in a business setting only."**
- Apps using it may be distributed **only** as in-house/proprietary apps or custom apps via
  **Apple Business Manager** — **not on the public App Store**.
- It is designed around **organization** accounts, not individual developer accounts.

**If your Apple Developer account is a personal/individual account, this request will most
likely be denied or unavailable.** That is not a failure of the app — it is Apple's policy.
Find this out *before* investing time; the fallback is already built (see bottom).

---

## Step 1 — Confirm your account type

1. Sign in at <https://developer.apple.com/account>.
2. Look at **Membership details** → *Entity Type*.
   - **Organization** (company, D-U-N-S number on file) → you can proceed.
   - **Individual / Sole Proprietor** → you are very likely ineligible. Consider enrolling as
     an organization, or use the iOS fallback.

## Step 2 — Register the bundle ID (if not already)

Certificates, Identifiers & Profiles → **Identifiers** → **+**
Register `com.mattharrington.ASLVisionPro` under your team. The entitlement is granted to a
**specific team + bundle ID pair**, so this must exist first and must match exactly.

## Step 3 — Submit the entitlement request

Two equivalent routes:

- **From Xcode:** the error dialog you saw has a **"Request Access…"** button that deep-links
  to the right form.
- **From the web:** Apple Developer → Support / Contact → request for **visionOS Enterprise
  APIs** (the "Enterprise APIs for visionOS" request form).

You will be asked for:

| Field | What to give |
|---|---|
| Team ID / account | Your organization's team |
| Bundle ID | `com.mattharrington.ASLVisionPro` |
| Entitlement(s) | **Main Camera Access** |
| Business justification | See template below |
| Distribution method | In-house or Custom App (Apple Business Manager) |

### Justification template

> Our visionOS application provides real-time American Sign Language recognition to support
> communication accessibility in [your business setting — e.g. our clinics / our support desks].
> The app requires main camera access because it must observe a **second person** (the signer)
> in front of the wearer; ARKit hand tracking only reports the wearer's own hands and therefore
> cannot serve this use case. Camera frames are processed **entirely on-device**, are not
> recorded, and are not transmitted off the headset. Distribution is limited to
> [in-house / custom app via Apple Business Manager] for [organization].

Be concrete about the business setting and that processing is on-device — both materially
help. Do not describe it as a consumer App Store product; that contradicts the program terms.

## Step 4 — Receive the license file

On approval, Apple emails an **`Enterprise.license`** file. This is *separate from* the
entitlement — the app needs both.

## Step 5 — Add the license to the project

In Xcode: **File → Add Files to "ASLVisionPro"…** → select `Enterprise.license` → check
**"Copy items if needed"** and add it to the **ASLVisionPro** (visionOS) target.

## Step 6 — Switch the project to the real entitlements

Already staged for you. In [project.yml](project.yml), under the `ASLVisionPro` target,
change:

```yaml
CODE_SIGN_ENTITLEMENTS: ASLVisionPro/visionOS/Support/ASLVisionPro-NoCamera.entitlements
```

to:

```yaml
CODE_SIGN_ENTITLEMENTS: ASLVisionPro/visionOS/Support/ASLVisionPro.entitlements
```

Then regenerate:

```bash
xcodegen generate
```

The real entitlements file already contains the `main-camera-access.allow` key — no editing
needed.

## Step 7 — Refresh provisioning and verify on device

1. In Xcode → Settings → Accounts → **Download Manual Profiles** (or let automatic signing
   refresh) so the new profile carrying the capability is picked up.
2. Build and run on **real Vision Pro hardware** (the simulator has no camera).
3. Expected: the app requests camera authorization and `VisionProCameraSource` starts
   yielding frames. Toggle **"Show landmarks"** in the UI — coloured dots over the person
   confirm the whole capture → landmark path works.
4. If authorization is denied, check the Console for the `VisionCamera` logger category; the
   usual causes are a missing/expired license file or a profile that predates the approval.

---

## Renewal

Enterprise API licenses **expire**. When yours nears expiry, generate a fresh license file in
the Developer portal and replace the bundled `Enterprise.license`. Put a calendar reminder on
this — an expired license silently disables the camera path in shipped builds.

---

## If you are denied (or ineligible)

Nothing is wasted — the fallback is already built and needs **no entitlement, no approval,
and can ship on the App Store**:

- **`ASLVisionPro-iOS` target** — the iPhone/iPad app. Point the device at the signer;
  captions render over the live viewfinder.
- It runs the **identical** recognition pipeline (all 11 shared source files), so any model
  you train serves both apps.
- Practical note: this is also your **fastest path to a working demo and to collecting real
  training data**, since it has no approval gate at all.

The visionOS target can stay in the repo, building against the no-camera entitlements, ready
to switch on the day approval lands.
