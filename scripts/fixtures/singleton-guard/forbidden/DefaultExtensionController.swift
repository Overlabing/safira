// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import WebKit

// The default configuration gives the extensions the default data store, shared by every Profile.
@MainActor func leak() -> WKWebExtensionController { WKWebExtensionController() }
