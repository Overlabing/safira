// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import WebKit

@MainActor func leak(_ id: UUID) -> WKWebsiteDataStore { WKWebsiteDataStore(forIdentifier: id) }
