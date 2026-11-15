// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CryptoKit
import Foundation

/// The identifier an extension is known by: `browser.runtime.id`, and the host of its `webkit-extension://` pages.
enum ExtensionIdentity {
    /// Chrome's identifier for a manifest `key`: the first 16 bytes of the SHA-256 of the decoded public key, each
    /// hexadecimal digit written as a letter from `a` to `p`. WebKit ignores `key` and would give a new random
    /// identifier at every load, which would change the extension's storage origin and the id its own app knows.
    /// Nil when the manifest has no `key` or it is not Base64.
    static func identifier(forManifestKey key: String?) -> String? {
        guard let key, let der = Data(base64Encoded: key, options: .ignoreUnknownCharacters), !der.isEmpty else {
            return nil
        }
        let letters = SHA256.hash(data: der).prefix(16).flatMap { byte in [byte >> 4, byte & 0x0F] }
        return String(String.UnicodeScalarView(letters.map { Unicode.Scalar(UInt8(ascii: "a") + $0) }))
    }

    /// The identifier for an extension's manifest: from its `key`, otherwise a new one.
    static func identifier(forManifest manifest: [String: Any]) -> String {
        identifier(forManifestKey: manifest["key"] as? String) ?? UUID().uuidString.lowercased()
    }
}
