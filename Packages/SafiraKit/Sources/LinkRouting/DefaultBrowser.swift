// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DefaultApps
import Foundation
import Preferences
import SafiraCore
import UniformTypeIdentifiers

/// Safira as the default browser. macOS counts an app as the default browser when it opens both http and https, and
/// the system settings move HTML files with them, so all of them are set together.
public struct DefaultBrowser: Sendable {
    public static let schemes = ["http", "https"]
    /// Local HTML files: the kinds the app declares in its Info.plist.
    public static let contentTypes = ["public.html", "public.xhtml"]

    private let check: DefaultApplicationCheck

    /// - Parameters:
    ///   - applicationURL: the running app's bundle (`Bundle.main.bundleURL`).
    ///   - bundleIdentifier: its bundle identifier; another copy of Safira that is the default counts as Safira.
    public init(client: any DefaultApplicationClient, applicationURL: URL, bundleIdentifier: String) {
        check = DefaultApplicationCheck(client: client, applicationURL: applicationURL, bundleIdentifier: bundleIdentifier)
    }

    /// True when Safira opens both http and https links. Read when it is shown and when Safira comes back to the front:
    /// the user can change the default browser elsewhere in between.
    public func isDefault() async -> Bool {
        for scheme in Self.schemes {
            guard await check.status(forScheme: scheme).isThisApp else { return false }
        }
        return true
    }

    /// What the user answered to the system's confirmation.
    public enum Answer: Sendable, Equatable {
        case accepted
        /// The user kept the current browser. Not a failure: nothing is shown, and Safira does not ask again by itself.
        case declined
    }

    /// Asks the system to make Safira the default for http, https and HTML files. The system asks the user to confirm.
    /// A decline stops at once, so the user is asked only once. Otherwise every request is attempted, and the first
    /// failure is thrown after the others have been tried.
    public func makeDefault() async throws -> Answer {
        var firstError: (any Error)?
        let requests: [() async throws -> Void] = Self.schemes.map { scheme in
            { try await check.makeDefault(forScheme: scheme) }
        } + Self.contentTypes.compactMap(UTType.init).map { type in
            { try await check.makeDefault(forContentType: type) }
        }
        for request in requests {
            do {
                try await request()
            } catch where Self.isDecline(error) {
                return .declined
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
        return .accepted
    }

    /// The system's confirmation answered with Keep: `userCanceledErr` (-128), alone or under the Cocoa error that
    /// LaunchServices wraps it in (`NSCocoaErrorDomain` 256, measured on macOS 27 for an HTML request).
    static func isDecline(_ error: any Error) -> Bool {
        var current: NSError? = error as NSError
        while let error = current {
            if error.domain == NSOSStatusErrorDomain, error.code == -128 { return true }
            if error.domain == NSCocoaErrorDomain, error.code == NSUserCancelledError { return true }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

extension DefaultBrowser {
    /// The entry for the default browser: offered, never set without the user's confirmation in the system dialog.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "linkPicker.defaultBrowser",
                title: String(localized: "Make Safira the default browser", table: "LinkRouting", bundle: .module, comment: "Defaults: entry title"),
                value: String(localized: "Offered", table: "LinkRouting", bundle: .module, comment: "Defaults: value of Make Safira the default browser"),
                explanation: String(localized: """
                    Links from other apps then come to Safira, and the Link picker asks which Profile receives each \
                    one, unless a Link rule decides. macOS asks you to confirm.
                    """, table: "LinkRouting", bundle: .module, comment: "Defaults: explanation of Make Safira the default browser"),
                whereToChange: DefaultWording.safiraMenu,
                control: .action
            ),
        ]
    }
}
