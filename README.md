<img src="assets/icon.svg" width="64" height="64" alt="">

# Safira

A native macOS web browser with an Arc/Zen-style interface, built around strictly separated Profiles (for example Work
and Personal), each holding several Spaces of tabs.

> **Status: not yet usable as a daily browser.** Today the app opens an empty window. Chrome extension support, which
> passwords depend on, has not been tested yet: that go/no-go is deferred until the browser shell exists
> (`docs/adr/0004-shell-first-extensions-later.md`).

Safira renders with the system `WKWebView` and calls only public Apple API; it does not fork or embed WebKit
(`docs/adr/0001-public-api-only-no-webkit-fork.md`). Each Profile has its own website data store, shared by its
Spaces (`docs/adr/0002-one-data-store-per-profile.md`).

## Build

Requirements: macOS 27, Xcode 27.1, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
Apple Silicon only.

```sh
scripts/check.sh
open .build/dd/Build/Products/Debug/Safira.app
```

`scripts/check.sh` generates `Safira.xcodeproj` from `project.yml` (the project file is not committed), runs the
`SafiraKit` tests, builds the app into `.build/dd`, and checks that it is signed (ad hoc), runs with the hardened
runtime, and carries the App Sandbox entitlement. It prints one `OK:` or `FAILED:` line per step and stops at the
first failure. To work in Xcode, run `xcodegen generate` and open `Safira.xcodeproj`.

The code lives in one local Swift package, `Packages/SafiraKit`; the app in `App/macOS` stays thin. The module layout
and its rules are in `docs/architecture-v1.md` §2.

## Continuous integration

`.github/workflows/check.yml` runs `scripts/check.sh` on GitHub's `xcode-27` runner image (macOS 27, Xcode 27.1),
without any secret. It starts only by hand (`workflow_dispatch`). That image is a public preview, not generally
available, so a green local `scripts/check.sh` remains the gate. The standard `xcode-27` runner is free for a public
repository; a private repository pays macOS minutes, and the `xcode-27-xlarge` runner is always billed.

## Releases and updates

Safira is released from the maintainer's Mac, never from CI, so no signing or notarization secret exists in a workflow
or in this repository. `scripts/release.sh` archives the Release build, exports it with the Developer ID certificate,
checks the signature (hardened runtime, App Sandbox, no `get-task-allow`) and the Sparkle keys of the archived
`Info.plist`, builds a DMG with `hdiutil`, notarizes it with `notarytool`, staples the ticket, runs `spctl` on the DMG
and the app inside it, and writes the SHA-256. It prints one `OK:` or `FAILED:` line per step and stops at the first
failure. Nothing is uploaded: the files land in `.build/release/`.

One-time setup on the release Mac:

1. Install a *Developer ID Application* certificate in the login keychain.
2. Store notarization credentials in the login keychain: `xcrun notarytool store-credentials <profile name>`.
3. Copy `Config/Release.local.xcconfig.example` to `Config/Release.local.xcconfig` (git-ignored) and set
   `DEVELOPER_ID_TEAM_ID` and `NOTARY_KEYCHAIN_PROFILE`.
4. The Sparkle EdDSA key pair is made once with Sparkle's `generate_keys`; the private half stays in the login
   keychain and the public half is `SUPublicEDKey` in `project.yml`. Keep an encrypted backup of the private key
   (`generate_keys -x`), because updates signed by another key are refused.

`scripts/release.sh --no-notarize` stops after the signed DMG, to rehearse everything except Apple's service; that DMG
is named `-unnotarized` and must not be distributed.

Updates use [Sparkle](https://sparkle-project.org), pinned to an exact version. Automatic checks are off
(`SUEnableAutomaticChecks` is explicitly `NO`), so Safira sends no update request until the user chooses
Safira > Check for Updates… or turns on Safira > Check for Updates Automatically. No system profile is ever sent, and an
update never installs without a click. A Debug build only can read a local test feed from the `SAFIRA_UPDATE_FEED_URL`
environment variable.

## Licence

Safira is free software under the GNU General Public License, version 3 only (`GPL-3.0-only`); see `LICENSE`.
Every source file starts with:

```swift
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin
```

Third-party notices are in `THIRD_PARTY_NOTICES.md`. The theme module is a separate MIT repository, so that it can be
shared with a closed-source app (`docs/adr/0003-theme-module-separate-mit-repository.md`).
