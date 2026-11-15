// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import WebKit

@MainActor func privateStore() -> WKWebsiteDataStore { WKWebsiteDataStore.nonPersistent() }
func ownSession() -> URLSession { URLSession(configuration: .ephemeral) }
@MainActor func ownExtensions(_ store: WKWebsiteDataStore) -> WKWebExtensionController {
    let configuration = WKWebExtensionController.Configuration.nonPersistent()
    configuration.defaultWebsiteDataStore = store
    return WKWebExtensionController(configuration: configuration)
}
