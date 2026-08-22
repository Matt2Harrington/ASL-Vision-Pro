#!/bin/bash
# Double-clickable setup for people who don't use the terminal.
#
# Finder runs .command files on double-click, which is the whole point: the Xcode project is
# generated from project.yml rather than committed, and generating it needs a command-line
# tool. This does that, explains each step, and asks before anything that installs software.

cd "$(dirname "$0")" || exit 1

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
ok()   { printf "  ✅ %s\n" "$1"; }
warn() { printf "  ⚠️  %s\n" "$1"; }
fail() { printf "  ❌ %s\n" "$1"; }

echo
bold "ASL Vision Pro — Setup"
echo "This prepares the project so you can open it in Xcode."
echo

# ---- 1. Xcode ---------------------------------------------------------------
bold "1. Checking for Xcode"
if [ ! -d "/Applications/Xcode.app" ]; then
    fail "Xcode isn't installed."
    echo "     Get it free from the App Store (search \"Xcode\"), then run this again."
    echo "     It's a large download — expect a while."
    echo; read -r -p "Press return to close."
    exit 1
fi
ok "Xcode is installed"

# Xcode must be the active developer directory or its build tools can't find any SDKs.
if ! xcodebuild -version >/dev/null 2>&1; then
    warn "macOS is pointed at the wrong developer tools. Fixing needs your password."
    sudo xcode-select -s /Applications/Xcode.app || { fail "Couldn't switch."; exit 1; }
fi
sudo xcodebuild -license accept >/dev/null 2>&1
ok "Xcode command line tools ready"
echo

# ---- 2. XcodeGen ------------------------------------------------------------
bold "2. Checking for XcodeGen"
echo "   The Xcode project file is generated rather than stored, so this tool builds it."
if command -v xcodegen >/dev/null 2>&1; then
    ok "XcodeGen is installed"
else
    if ! command -v brew >/dev/null 2>&1; then
        warn "This needs Homebrew, a package installer for macOS."
        echo "     It will download and install from https://brew.sh"
        read -r -p "     Install Homebrew now? [y/N] " reply
        [[ "$reply" =~ ^[Yy]$ ]] || { echo; echo "  Stopped. Nothing was changed."; read -r -p "Press return to close."; exit 1; }
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || exit 1
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null
    fi
    echo "   Installing XcodeGen..."
    brew install xcodegen || { fail "Install failed."; read -r -p "Press return to close."; exit 1; }
    ok "XcodeGen installed"
fi
echo

# ---- 3. Bundle identifier ---------------------------------------------------
bold "3. Naming the app for your Apple ID"
echo "   Apple needs an identifier unique to you. If two people use the same one,"
echo "   the second person can't install on a phone."
echo
current=$(grep -m1 "bundleIdPrefix:" project.yml | awk '{print $2}')
echo "   Currently: $current"
read -r -p "   Your prefix (e.g. com.yourname) — or press return to keep it: " prefix

if [ -n "$prefix" ]; then
    # Rewrite every identifier, not just the prefix option, so the targets match.
    sed -i '' "s|bundleIdPrefix: .*|bundleIdPrefix: $prefix|" project.yml
    sed -i '' "s|PRODUCT_BUNDLE_IDENTIFIER: [^ ]*\.ASLVisionPro$|PRODUCT_BUNDLE_IDENTIFIER: $prefix.ASLVisionPro|" project.yml
    sed -i '' "s|PRODUCT_BUNDLE_IDENTIFIER: [^ ]*\.ASLVisionPro\.iOS|PRODUCT_BUNDLE_IDENTIFIER: $prefix.ASLVisionPro.iOS|" project.yml
    sed -i '' "s|PRODUCT_BUNDLE_IDENTIFIER: [^ ]*\.ASLVisionPro\.Tests|PRODUCT_BUNDLE_IDENTIFIER: $prefix.ASLVisionPro.Tests|" project.yml
    ok "Set to $prefix"
else
    warn "Keeping $current — fine for the simulator, may fail on a phone"
fi
echo

# ---- 4. Generate ------------------------------------------------------------
bold "4. Creating the Xcode project"
if xcodegen generate >/dev/null 2>&1; then
    ok "ASLVisionPro.xcodeproj created"
else
    fail "Couldn't create the project."
    read -r -p "Press return to close."
    exit 1
fi
echo

bold "Done."
echo
echo "  Opening Xcode now. Next steps:"
echo
echo "    1. Top-left dropdown: choose  ASLVisionPro-iOS"
echo "    2. Next to it, choose your iPhone (plug it in) or a simulator"
echo "    3. Press the ▶ Play button"
echo
echo "  Running on a real phone also needs your Apple ID:"
echo "    Xcode menu > Settings > Accounts > + > Apple ID  (free account is fine)"
echo "    then click ASLVisionPro-iOS in the left sidebar > Signing & Capabilities"
echo "    > pick your name under Team"
echo
open ASLVisionPro.xcodeproj
read -r -p "Press return to close this window."
