// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import WebKit

/// What an extension asks to be allowed, shown once in the permission sheet: at install, when an update asks for more,
/// and when the extension asks at run time (`permissions.request`).
public struct ExtensionPermissionRequest: Sendable {
    public enum Moment: Sendable, Equatable {
        case install, update, runtime
    }

    public let extensionID: String
    public let displayName: String
    public let moment: Moment
    /// WebKit's names (`storage`, `nativeMessaging`), sorted.
    public let permissions: [String]
    /// Match patterns as the manifest writes them (`https://*/*`), sorted.
    public let matchPatterns: [String]
    /// Whether the patterns reach every website, which the sheet says in Safari's words.
    public let hasAccessToAllHosts: Bool
    public let icon: NSImage?

    public init(extensionID: String, displayName: String, moment: Moment, permissions: [String], matchPatterns: [String],
                hasAccessToAllHosts: Bool, icon: NSImage?) {
        self.extensionID = extensionID
        self.displayName = displayName
        self.moment = moment
        self.permissions = permissions.sorted()
        self.matchPatterns = matchPatterns.sorted()
        self.hasAccessToAllHosts = hasAccessToAllHosts
        self.icon = icon
    }

    /// One line per thing the extension could do, websites first.
    public var summary: [String] {
        ExtensionPermissionWording.lines(permissions: permissions, matchPatterns: matchPatterns,
                                         hasAccessToAllHosts: hasAccessToAllHosts)
    }

    public var isEmpty: Bool {
        permissions.isEmpty && matchPatterns.isEmpty
    }
}

/// The permission sheet's and the Extensions pane's words for what an extension may do.
public enum ExtensionPermissionWording {
    /// How many websites are named before "and N more".
    static let namedHosts = 4

    public static func lines(permissions: [String], matchPatterns: [String], hasAccessToAllHosts: Bool) -> [String] {
        var lines: [String] = []
        if hasAccessToAllHosts {
            lines.append(String(localized: "Can read and modify webpages on all websites", table: "SafiraWeb", bundle: .module,
                                comment: "Extension permission, as Safari words it"))
        } else if !matchPatterns.isEmpty {
            lines.append(websites(matchPatterns))
        }
        var seen = Set<String>()
        for permission in permissions.sorted() {
            let line = line(for: permission)
            if seen.insert(line).inserted { lines.append(line) }
        }
        return lines
    }

    /// The hosts the patterns name, without their scheme and path: `github.com`, `*.example.org`.
    static func hosts(_ matchPatterns: [String]) -> [String] {
        var hosts: [String] = []
        for pattern in matchPatterns {
            guard let schemeEnd = pattern.range(of: "://") else { continue }
            let rest = pattern[schemeEnd.upperBound...]
            let host = String(rest.prefix { $0 != "/" })
            if !host.isEmpty, !hosts.contains(host) { hosts.append(host) }
        }
        return hosts
    }

    private static func websites(_ matchPatterns: [String]) -> String {
        let hosts = hosts(matchPatterns)
        let named = hosts.prefix(namedHosts).formatted(.list(type: .and))
        if hosts.count > namedHosts {
            let more = hosts.count - namedHosts
            return String(localized: "Can read and modify webpages on \(named) and \(more) more websites", table: "SafiraWeb",
                          bundle: .module, comment: "Extension permission; the arguments are a list of websites and a count")
        }
        return String(localized: "Can read and modify webpages on \(named)", table: "SafiraWeb", bundle: .module,
                      comment: "Extension permission; the argument is a list of websites")
    }

    private static func line(for permission: String) -> String {
        switch permission {
        case "activeTab":
            String(localized: "Can read and modify the page you’re on when you use the extension", table: "SafiraWeb",
                   bundle: .module, comment: "Extension permission: activeTab")
        case "tabs":
            String(localized: "Can see the address and title of your Tabs", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: tabs")
        case "storage", "unlimitedStorage":
            String(localized: "Can store data on this Mac", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: storage")
        case "nativeMessaging":
            String(localized: "Can exchange messages with apps on this Mac", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: nativeMessaging")
        case "cookies":
            String(localized: "Can read and change cookies", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: cookies")
        case "scripting":
            String(localized: "Can run scripts in webpages it can access", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: scripting")
        case "webNavigation":
            String(localized: "Can see the pages you open", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: webNavigation")
        case "webRequest":
            String(localized: "Can see the requests webpages make", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: webRequest")
        case "declarativeNetRequest", "declarativeNetRequestWithHostAccess", "declarativeNetRequestFeedback":
            String(localized: "Can block and change content in webpages", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: declarativeNetRequest")
        case "clipboardWrite":
            String(localized: "Can write to the clipboard", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: clipboardWrite")
        case "contextMenus", "menus":
            String(localized: "Can add items to shortcut menus", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: contextMenus")
        case "alarms":
            String(localized: "Can run tasks on a schedule", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: alarms")
        case "notifications":
            String(localized: "Can show notifications", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission: notifications")
        default:
            String(localized: "Can use “\(permission)”", table: "SafiraWeb", bundle: .module,
                   comment: "Extension permission Safira has no words for; the argument is its name in the manifest")
        }
    }
}

extension ExtensionPermissionRequest {
    /// Every permission and match pattern of a manifest that is not granted yet.
    @MainActor
    init(_ webExtension: WKWebExtension, id: String, moment: Moment, alreadyGranted: InstalledGrants = InstalledGrants()) {
        let permissions = webExtension.requestedPermissions.map(\.rawValue).filter { !alreadyGranted.permissions.contains($0) }
        let patterns = webExtension.allRequestedMatchPatterns.filter { !alreadyGranted.matchPatterns.contains($0.string) }
        self.init(extensionID: id, displayName: webExtension.displayName ?? id, moment: moment, permissions: permissions,
                  matchPatterns: patterns.map(\.string),
                  hasAccessToAllHosts: patterns.contains { $0.matchesAllHosts || $0.matchesAllURLs },
                  icon: webExtension.icon(for: CGSize(width: 64, height: 64)))
    }
}

/// What the user allowed an installed extension.
public struct InstalledGrants: Equatable, Sendable {
    public var permissions: Set<String>
    public var matchPatterns: Set<String>

    public init(permissions: Set<String> = [], matchPatterns: Set<String> = []) {
        self.permissions = permissions
        self.matchPatterns = matchPatterns
    }
}
