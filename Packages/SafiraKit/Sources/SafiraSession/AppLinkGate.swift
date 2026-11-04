// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// What the system knows about apps, behind a seam so that tests need no installed app.
@MainActor
public protocol ExternalAppLauncher: AnyObject {
    /// The app the system would open `url` with; nil when no app on this Mac takes the scheme.
    func app(toOpen url: URL) -> ExternalApp?
    /// Opens `url` in `app`, the one the user was told about.
    func open(_ url: URL, with app: ExternalApp) async throws
}

/// The parts of the app a Profile's gate needs; each one missing makes the gate refuse, never open.
public struct AppLinkHandlers {
    public var launcher: (any ExternalAppLauncher)?
    /// Asks the user whether the app may open. Without it, such a link is refused and nothing is remembered.
    public var prompt: (@MainActor (AppLinkPrompt) async -> PermissionAnswer)?
    /// Tells the user that no app takes a scheme. It is awaited, so a page cannot pile up notices.
    public var refusal: (@MainActor (AppLinkRefusal) async -> Void)?
    /// Tells the user that the system could not open a link in the app they chose; awaited like `refusal`.
    public var openFailure: (@MainActor (ExternalApp, any Error) async -> Void)?

    public init(launcher: (any ExternalAppLauncher)? = nil,
                prompt: (@MainActor (AppLinkPrompt) async -> PermissionAnswer)? = nil,
                refusal: (@MainActor (AppLinkRefusal) async -> Void)? = nil,
                openFailure: (@MainActor (ExternalApp, any Error) async -> Void)? = nil) {
        self.launcher = launcher
        self.prompt = prompt
        self.refusal = refusal
        self.openFailure = openFailure
    }
}

/// Decides what happens when a page follows a link that only another app can take. The answer is always the Profile's
/// remembered choice for the scheme or else the user's: a page never launches an app by itself, whether the link was
/// clicked, scripted, in an iframe or reached by a redirect.
@MainActor
public final class AppLinkGate {
    public let profileID: ProfileID
    public let permissions: SitePermissions
    public var handlers = AppLinkHandlers()
    private var waiting: Set<URLScheme> = []
    private var running: [UUID: Task<Void, Never>] = [:]

    public init(profileID: ProfileID, permissions: SitePermissions = SitePermissions()) {
        self.profileID = profileID
        self.permissions = permissions
    }

    /// Handles a link in the background; `settled()` returns once it is done.
    func request(_ link: NonWebLink, requestedBy host: String?) {
        let id = UUID()
        running[id] = Task { @MainActor [weak self] in
            _ = await self?.handle(link, requestedBy: host)
            self?.running[id] = nil
        }
    }

    /// Returns once every link requested so far has been answered.
    public func settled() async {
        while let task = running.values.first {
            await task.value
        }
    }

    /// - Parameter host: the host of the page that asked, shown in the question.
    @discardableResult
    public func handle(_ link: NonWebLink, requestedBy host: String?) async -> AppLinkOutcome {
        let scheme = link.scheme
        // A page that fires the same scheme again and again gets one question, not a pile of them.
        guard waiting.insert(scheme).inserted else { return .ignored }
        defer { waiting.remove(scheme) }

        let remembered = permissions.appLinkDecision(for: scheme)
        if remembered == .deny { return .declined }
        guard let launcher = handlers.launcher, let app = launcher.app(toOpen: link.url) else {
            await handlers.refusal?(AppLinkRefusal(profileID: profileID, scheme: scheme, requestedBy: host))
            return .noApp
        }
        if remembered != .allow {
            guard let prompt = handlers.prompt else { return .ignored }
            let answer = await prompt(AppLinkPrompt(profileID: profileID, scheme: scheme, app: app, requestedBy: host))
            if answer.remember {
                permissions.rememberAppLink(answer.decision, for: scheme)
            }
            guard answer.decision == .allow else { return .declined }
        }
        do {
            try await launcher.open(link.url, with: app)
        } catch {
            await handlers.openFailure?(app, error)
            return .failed
        }
        return .opened(app)
    }
}
