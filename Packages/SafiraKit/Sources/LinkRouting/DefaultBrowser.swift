// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// What the system can tell and do about the default application for web links. The app backs it with `NSWorkspace`;
/// tests record the calls.
@MainActor
public protocol DefaultApplicationRegistry {
    /// The bundle URL of the app that opens links with this scheme, or nil when none does.
    func defaultApplication(forScheme scheme: String) -> URL?
    func setDefaultApplication(toOpenScheme scheme: String) async throws
    func setDefaultApplication(toOpenContentType identifier: String) async throws
}

/// Safira as the default browser. macOS counts an app as the default browser when it opens both http and https, and
/// the system settings move HTML files with them, so all of them are set together.
@MainActor
public struct DefaultBrowser {
    public static let schemes = ["http", "https"]
    /// Local HTML files: the kinds the app declares in its Info.plist.
    public static let contentTypes = ["public.html", "public.xhtml"]

    private let registry: any DefaultApplicationRegistry
    private let appURL: URL

    public init(registry: any DefaultApplicationRegistry, appURL: URL) {
        self.registry = registry
        self.appURL = appURL
    }

    /// True when Safira opens both http and https links.
    public var isDefault: Bool {
        Self.schemes.allSatisfy { registry.defaultApplication(forScheme: $0)?.standardizedFileURL == appURL.standardizedFileURL }
    }

    /// Asks the system to make Safira the default for http, https and HTML files. The system asks the user to confirm.
    /// Every request is attempted; the first failure is thrown after the others have been tried.
    public func makeDefault() async throws {
        var firstError: (any Error)?
        for scheme in Self.schemes {
            do { try await registry.setDefaultApplication(toOpenScheme: scheme) } catch { firstError = firstError ?? error }
        }
        for type in Self.contentTypes {
            do { try await registry.setDefaultApplication(toOpenContentType: type) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }
}
