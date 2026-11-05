// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DefaultApps
import Foundation
import Preferences
import SafiraCore
import UniformTypeIdentifiers

/// Making an app the default for a kind of file. AppSupportKit's `DefaultApplicationClient` reads the default of a
/// content type but changes the default of URL schemes only, so Safira keeps this one call for its HTML files.
public protocol DefaultDocumentApplications: Sendable {
    func makeDefault(_ application: URL, forContentType type: UTType) async throws
}

/// Safira as the default browser. macOS counts an app as the default browser when it opens both http and https, and
/// the system settings move HTML files with them, so all of them are set together.
public struct DefaultBrowser: Sendable {
    public static let schemes = ["http", "https"]
    /// Local HTML files: the kinds the app declares in its Info.plist.
    public static let contentTypes = ["public.html", "public.xhtml"]

    private let check: DefaultApplicationCheck
    private let documents: any DefaultDocumentApplications
    private let applicationURL: URL

    /// - Parameters:
    ///   - applicationURL: the running app's bundle (`Bundle.main.bundleURL`).
    ///   - bundleIdentifier: its bundle identifier; another copy of Safira that is the default counts as Safira.
    public init(client: any DefaultApplicationClient, documents: any DefaultDocumentApplications, applicationURL: URL,
                bundleIdentifier: String) {
        check = DefaultApplicationCheck(client: client, applicationURL: applicationURL, bundleIdentifier: bundleIdentifier)
        self.documents = documents
        self.applicationURL = applicationURL
    }

    /// True when Safira opens both http and https links. Read when it is shown and when Safira comes back to the front:
    /// the user can change the default browser elsewhere in between.
    public func isDefault() async -> Bool {
        for scheme in Self.schemes {
            guard await check.status(forScheme: scheme).isThisApp else { return false }
        }
        return true
    }

    /// Asks the system to make Safira the default for http, https and HTML files. The system asks the user to confirm.
    /// Every request is attempted; the first failure is thrown after the others have been tried.
    public func makeDefault() async throws {
        var firstError: (any Error)?
        for scheme in Self.schemes {
            do { try await check.makeDefault(forScheme: scheme) } catch { firstError = firstError ?? error }
        }
        for identifier in Self.contentTypes {
            guard let type = UTType(identifier) else { continue }
            do { try await documents.makeDefault(applicationURL, forContentType: type) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
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
