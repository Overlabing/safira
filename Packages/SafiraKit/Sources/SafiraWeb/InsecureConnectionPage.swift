// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// The page Safira shows when an address has no secure connection. It is built from the warning alone and loaded from
/// a string, so it needs no network and no resource.
enum InsecureConnectionPage {
    static func html(for warning: InsecureConnectionWarning) -> String {
        let host = escaped(warning.host)
        let cause = switch warning.reason {
        case .noSecureConnection:
            String(localized: "could not connect securely", table: "SafiraWeb", bundle: .module,
                   comment: "HTTPS warning page: ends “Safira tried <host> over HTTPS and …”")
        case .invalidCertificate:
            String(localized: "could not verify its certificate", table: "SafiraWeb", bundle: .module,
                   comment: "HTTPS warning page: ends “Safira tried <host> over HTTPS and …”")
        }
        let title = escaped(String(localized: "No secure connection to \(warning.host)", table: "SafiraWeb", bundle: .module,
                                   comment: "HTTPS warning page: the page title; the argument is a host"))
        let heading = escaped(String(localized: "This site does not offer a secure connection", table: "SafiraWeb",
                                     bundle: .module, comment: "HTTPS warning page: heading"))
        let tried = bold(host, in: escaped(String(
            localized: "Safira tried \(warning.host) over HTTPS and \(cause).", table: "SafiraWeb", bundle: .module,
            comment: "HTTPS warning page: the first argument is a host, the second says what failed")))
        let risk = escaped(String(localized: """
            If you continue, the page and anything you type into it travel unencrypted and can be read or changed by \
            others on the network.
            """, table: "SafiraWeb", bundle: .module, comment: "HTTPS warning page: the risk of continuing"))
        let continueTitle = escaped(String(localized: "Continue over HTTP", table: "SafiraWeb", bundle: .module,
                                           comment: "HTTPS warning page: the link that loads the site without encryption"))
        let language = Bundle.module.preferredLocalizations.first ?? "en"
        return """
        <!DOCTYPE html>
        <html lang="\(escaped(language))"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
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
        <h1>\(heading)</h1>
        <p>\(tried) \(risk)</p>
        <p><a class="continue" id="continue-over-http" href="\(escaped(warning.httpURL.absoluteString))">\(continueTitle)</a></p>
        </main></body></html>
        """
    }

    /// The host in bold, where the sentence names it.
    private static func bold(_ host: String, in sentence: String) -> String {
        guard let range = sentence.range(of: host) else { return sentence }
        return sentence.replacingCharacters(in: range, with: "<strong>\(host)</strong>")
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
