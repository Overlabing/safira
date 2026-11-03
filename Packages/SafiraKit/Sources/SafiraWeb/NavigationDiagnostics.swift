// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import WebKit

/// Reports a web view's navigations to the diagnostic logger. It forwards the failing address and the error to
/// `PageLoadTracker`, which keeps only the host, the domain and the code.
@MainActor
final class NavigationDiagnostics: NSObject, WKNavigationDelegate {
    private let logger: DiagnosticLogger
    private var tracker = PageLoadTracker()

    init(logger: DiagnosticLogger) {
        self.logger = logger
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tracker.didCommit(url: webView.url, at: .now)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let event = tracker.didFinish(at: .now) {
            logger.record(event)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        logger.record(tracker.didFail(url: failingURL(of: error) ?? webView.url, error: error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        logger.record(tracker.didFail(url: failingURL(of: error), error: error))
    }

    private func failingURL(of error: any Error) -> URL? {
        (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
    }
}
