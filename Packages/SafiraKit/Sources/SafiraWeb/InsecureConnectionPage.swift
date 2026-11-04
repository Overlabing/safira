// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore

/// The page Safira shows when an address has no secure connection. It is built from the warning alone and loaded from
/// a string, so it needs no network and no resource.
enum InsecureConnectionPage {
    static func html(for warning: InsecureConnectionWarning) -> String {
        let host = escaped(warning.host)
        let cause = switch warning.reason {
        case .noSecureConnection: "could not connect securely"
        case .invalidCertificate: "could not verify its certificate"
        }
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>No secure connection to \(host)</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: -apple-system-body; font-family: -apple-system, sans-serif; margin: 0; min-height: 100vh;
               display: flex; align-items: center; justify-content: center; }
        main { max-width: 34em; padding: 2em; }
        h1 { font-size: 1.5em; }
        a.continue { display: inline-block; margin-top: 1em; padding: .5em 1em; border: 1px solid currentColor;
                     border-radius: 6px; text-decoration: none; color: inherit; }
        </style></head>
        <body><main>
        <h1>This site does not offer a secure connection</h1>
        <p>Safira tried <strong>\(host)</strong> over HTTPS and \(cause).
        If you continue, the page and anything you type into it travel unencrypted and can be read or changed by others
        on the network.</p>
        <p><a class="continue" id="continue-over-http" href="\(escaped(warning.httpURL.absoluteString))">Continue over HTTP</a></p>
        </main></body></html>
        """
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
