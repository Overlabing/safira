// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraSession
import WebKit

/// One icon or manifest fetched as a WebKit download of a page's web view, into a temporary file that is read and
/// removed. It never reaches the Profile's list of downloads, and it stops at the first byte over its limit.
@MainActor
final class SiteResourceDownload: NSObject, WKDownloadDelegate {
    private let byteLimit: Int
    private let file = FileManager.default.temporaryDirectory
        .appending(path: "SiteIcons", directoryHint: .isDirectory)
        .appending(path: UUID().uuidString, directoryHint: .notDirectory)
    private var download: WKDownload?
    private var response: HTTPURLResponse?
    private var refused = false
    private var continuation: CheckedContinuation<SiteResourceResponse, Never>?
    private var result: SiteResourceResponse?
    private var observation: NSKeyValueObservation?

    init(byteLimit: Int) {
        self.byteLimit = byteLimit
    }

    func run(_ request: URLRequest, in webView: WKWebView) async -> SiteResourceResponse {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            // The delegate is set in the completion handler itself: WebKit asks it for a destination as soon as the
            // response arrives, and a download with no delegate by then is cancelled.
            webView.startDownload(using: request) { [weak self] download in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard self.result == nil else {
                        download.cancel(nil)
                        return
                    }
                    self.download = download
                    download.delegate = self
                    self.observation = download.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
                        let received = progress.completedUnitCount
                        Task { @MainActor in self?.received(received) }
                    }
                }
            }
        }
    }

    /// Stops the fetch, as its page closes.
    func cancel() {
        download?.cancel(nil)
        finish(.failed)
    }

    private func received(_ bytes: Int64) {
        guard bytes > byteLimit, result == nil else { return }
        refused = true
        download?.cancel(nil)
        finish(.unusable)
    }

    private func finish(_ response: SiteResourceResponse) {
        guard result == nil else { return }
        result = response
        observation?.invalidate()
        observation = nil
        try? FileManager.default.removeItem(at: file)
        continuation?.resume(returning: response)
        continuation = nil
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let http = response as? HTTPURLResponse
        self.response = http
        guard let http, (200..<300).contains(http.statusCode), response.expectedContentLength <= byteLimit else {
            refused = true
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            refused = true
            return nil
        }
        return file
    }

    /// Icons are HTTPS only, so a redirect to anything else is not followed.
    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest) async -> WKDownload.RedirectPolicy {
        request.url?.scheme?.lowercased() == "https" ? .allow : .cancel
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let data = try? Data(contentsOf: file), data.count <= byteLimit else {
            finish(.unusable)
            return
        }
        finish(.resource(data, cacheControl: response?.value(forHTTPHeaderField: "Cache-Control")))
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        finish(refused || response != nil ? .unusable : .failed)
    }
}
