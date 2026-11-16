// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// DuckDuckGo's autoconsent (MPL-2.0), vendored unchanged at the version in `scripts/autoconsent.pin` by
/// `scripts/update-autoconsent.sh`. Its rules ship with Safira and change only with a Safira release: nothing is
/// fetched at run time.
public enum AutoconsentBundle {
    public static let version = "18.5.0"

    /// The content script: the library's own iife build, which talks through `window.autoconsentSendMessage`.
    public static let script: String = load("autoconsent", "js")

    /// The compact rule list, sent whole to every frame that asks for it.
    public static let compactRules: String = load("autoconsent-rules", "json")

    private static func load(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("SafiraWeb is missing its vendored \(name).\(ext)")
        }
        return text
    }
}
