// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import WebKit

/// Answers the cookie consent prompts of a Profile's pages with autoconsent (`AutoconsentBundle`), as DuckDuckGo's
/// browser does: one script at document start in every frame, in a content world of its own, and a native handler
/// that sends it the whole rule list. Nothing leaves the machine: the rules are bundled and nothing is reported.
@MainActor
final class CookiePromptScript: NSObject, WKScriptMessageHandlerWithReply {
    static let world = WKContentWorld.world(name: "SafiraCookiePrompts")
    static let handlerName = "safiraCookiePrompts"

    /// The prelude hands autoconsent its sender: every message goes to the handler, and its reply comes back.
    static let userScript = WKUserScript(
        source: """
        window.autoconsentSendMessage = (message) =>
            window.webkit.messageHandlers.\(handlerName).postMessage(message)
                .then((reply) => reply ? window.autoconsentReceiveMessage(reply) : undefined)
                .catch(() => undefined);
        """ + "\n" + AutoconsentBundle.script,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false,
        in: world
    )

    /// Parsed once: every frame gets the same full list.
    private static let rules: Any = {
        guard let rules = try? JSONSerialization.jsonObject(with: Data(AutoconsentBundle.compactRules.utf8)) else {
            preconditionFailure("SafiraWeb's vendored autoconsent rules do not parse")
        }
        return rules
    }()

    /// Within this time after Safira answered a page, the same address loading again counts as a reload the answer
    /// caused, and Safira stops answering it so the page cannot loop.
    static let reloadLoopWindow: TimeInterval = 10

    /// The Profile's settings now: the exceptions reach a page at its next load.
    private let settings: @MainActor () -> CookiePromptSettings
    private let page: @MainActor (WKWebView?) -> WebKitPage?
    private var lastAnswered: [ObjectIdentifier: (url: URL, at: Date)] = [:]

    init(settings: @escaping @MainActor () -> CookiePromptSettings,
         page: @escaping @MainActor (WKWebView?) -> WebKitPage?) {
        self.settings = settings
        self.page = page
    }

    func install(in controller: WKUserContentController) {
        controller.addUserScript(Self.userScript)
        controller.addScriptMessageHandler(self, contentWorld: Self.world, name: Self.handlerName)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return (nil, nil) }
        switch type {
        case "init":
            return (initReply(for: message), nil)
        case "eval":
            return await evaluate(body, in: message)
        case "cmpDetected":
            report(body, .detected, from: message)
        case "optOutResult":
            if body["result"] as? Bool == false { report(body, .failed, from: message) }
        case "autoconsentDone":
            report(body, body["isCosmetic"] as? Bool == true ? .hidden : .rejected, from: message)
            if message.frameInfo.isMainFrame, let webView = message.webView, let url = webView.url {
                lastAnswered[ObjectIdentifier(webView)] = (url, Date())
            }
        case "autoconsentError":
            if body["cmp"] is String { report(body, .failed, from: message) }
        default:
            break
        }
        return (nil, nil)
    }

    private func initReply(for message: WKScriptMessage) -> [String: Any] {
        let pageURL = message.webView?.url
        guard let pageURL, ["http", "https"].contains(pageURL.scheme?.lowercased() ?? ""),
              settings().answers(onHost: pageURL.host()) else {
            return ["type": "initResp", "config": ["enabled": false], "rules": ["autoconsent": [Any]()]]
        }
        var autoAction: Any = "optOut"
        if message.frameInfo.isMainFrame, let webView = message.webView {
            let key = ObjectIdentifier(webView)
            if let last = lastAnswered[key], last.url == pageURL,
               Date().timeIntervalSince(last.at) < Self.reloadLoopWindow {
                autoAction = NSNull()
            }
            lastAnswered[key] = nil
        }
        return [
            "type": "initResp",
            "rules": ["autoconsent": [Any](), "compact": Self.rules],
            "config": [
                "enabled": true,
                "autoAction": autoAction,
                "disabledCmps": [String](),
                "enablePrehide": true,
                "enableCosmeticRules": true,
                "detectRetries": 20,
                "isMainWorld": false,
                "enableHeuristicDetection": false,
                "heuristicMode": "off",
                "logs": ["lifecycle": false, "rulesteps": false, "detectionsteps": false, "evals": false,
                         "errors": false, "messages": false, "waits": false],
            ] as [String: Any],
        ]
    }

    /// Some rules test the page's own scripts (a CMP's JavaScript API), which only the page's world can see.
    private func evaluate(_ body: [String: Any], in message: WKScriptMessage) async -> (Any?, String?) {
        guard let id = body["id"] as? String, let code = body["code"] as? String, let webView = message.webView else {
            return (nil, "no frame")
        }
        let script = "(() => { try { return !!(\(code)); } catch (e) { return false; } })();"
        let result: Bool
        do {
            result = try await webView.evaluateJavaScript(script, in: message.frameInfo, contentWorld: .page) as? Bool
                ?? false
        } catch {
            result = false
        }
        return (["type": "evalResp", "id": id, "result": result], nil)
    }

    private func report(_ body: [String: Any], _ outcome: CookiePromptReport.Outcome, from message: WKScriptMessage) {
        guard let webView = message.webView, let page = page(webView),
              let site = webView.url?.host().flatMap(CookiePromptSettings.site(of:)) else { return }
        let platform = body["cmp"] as? String ?? ""
        // A later step of the same prompt (detected, then rejected) replaces the earlier one, never the reverse.
        if outcome == .detected, let current = page.state.cookiePrompt, current.site == site { return }
        page.cookiePromptChanged(CookiePromptReport(site: site, platform: platform, outcome: outcome))
    }
}
