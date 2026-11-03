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

## Licence

Safira is free software under the GNU General Public License, version 3 only (`GPL-3.0-only`); see `LICENSE`.
Every source file starts with:

```swift
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin
```

Third-party notices are in `THIRD_PARTY_NOTICES.md`. The theme module is a separate MIT repository, so that it can be
shared with a closed-source app (`docs/adr/0003-theme-module-separate-mit-repository.md`).
