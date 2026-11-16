// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CryptoKit
import Foundation

/// The identifier an extension is known by: `browser.runtime.id`, and the host of its `webkit-extension://` pages.
/// It is chosen once, at install, and kept with the installed extension.
enum ExtensionIdentity {
    /// Chrome's identifier for a manifest `key`: the first 16 bytes of the SHA-256 of the decoded public key, each
    /// hexadecimal digit written as a letter from `a` to `p`. WebKit ignores `key` and would give a new random
    /// identifier at every load, which would change the extension's storage origin and the id its own app knows.
    /// Nil when the manifest has no `key` or it is not Base64.
    static func identifier(forManifestKey key: String?) -> String? {
        guard let key, let der = Data(base64Encoded: key, options: .ignoreUnknownCharacters), !der.isEmpty else {
            return nil
        }
        return letters(SHA256.hash(data: der).prefix(16))
    }

    /// The identifier a CRX3 header names (`crx_id`, 16 bytes), in Chrome's letters. Nil when it is not 16 bytes.
    static func identifier(forCRXID bytes: [UInt8]) -> String? {
        bytes.count == 16 ? letters(bytes) : nil
    }

    /// The identifier for a new install: the manifest `key`'s, otherwise the CRX header's, otherwise a new UUID.
    static func identifier(forManifest manifest: [String: Any], crxIdentifier: String? = nil) -> String {
        identifier(forManifestKey: manifest["key"] as? String) ?? crxIdentifier ?? UUID().uuidString.lowercased()
    }

    private static func letters(_ bytes: some Sequence<UInt8>) -> String {
        let digits = bytes.flatMap { byte in [byte >> 4, byte & 0x0F] }
        return String(String.UnicodeScalarView(digits.map { Unicode.Scalar(UInt8(ascii: "a") + $0) }))
    }
}
