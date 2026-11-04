// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import LinkRouting
import SafiraCore
import SwiftUI

/// A borderless panel that takes the keyboard without activating the app, so the question drops out of the notch
/// whatever app the user is in, and keys work at once.
final class LinkPickerPanel: NSPanel {
    /// Returns true when the key was handled.
    var onKey: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    // Intercepted here rather than in keyDown so Tab is not eaten by the key-view loop.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    // Lets the panel sit over the menu bar, flush with the top of the screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Shows the Link picker as a panel that drops out of the notch. It is not modal: the app keeps running while the
/// question is open, and a second link waits for the first answer.
@MainActor
public final class LinkPickerPresenter: ProfileChoosing {
    private var session: AnySession?

    public init() {}

    public func chooseProfile(for link: IncomingLink, among profiles: [Profile],
                              alreadyOpenIn: Set<ProfileID>) async -> ProfileID? {
        guard !profiles.isEmpty else { return nil }
        let open = profiles.filter { alreadyOpenIn.contains($0.id) }.map(\.name).formatted(.list(type: .and))
        let announcement = Self.announcement(for: link, rowCount: profiles.count) {
            String(localized: "Choose a Profile for the link to \($0)")
        } + (open.isEmpty ? "" : " " + String(localized: "Already open in \(open)."))
        return await ask(LinkPickerModel(link: link, profiles: profiles, alreadyOpenIn: alreadyOpenIn),
                         wording: .profile, announcement: announcement)
    }

    public func chooseSpace(for link: IncomingLink, in profile: Profile, among spaces: [SpaceChoice]) async -> SpaceID? {
        guard !spaces.isEmpty else { return nil }
        let announcement = Self.announcement(for: link, rowCount: spaces.count) {
            String(localized: "Choose a Space of \(profile.name) for the link to \($0)")
        }
        return await ask(LinkPickerModel(link: link, spaces: spaces), wording: .space, announcement: announcement)
    }

    private func ask<ID: Hashable & Sendable>(_ model: LinkPickerModel<ID>, wording: LinkPickerWording,
                                              announcement: String) async -> ID? {
        await withCheckedContinuation { continuation in
            let open = Session(model: model, wording: wording, announcement: announcement) { [weak self] choice in
                self?.session = nil
                continuation.resume(returning: choice)
            }
            session = AnySession(open)
        }
    }

    private static func announcement(for link: IncomingLink, rowCount: Int, question: (String) -> String) -> String {
        let from = link.opener?.name.map { String(localized: ", from \($0)") } ?? ""
        return question(link.title) + from + String(localized: ". Press a number from 1 to \(min(rowCount, 9)), or use the arrow keys and Return. Escape dismisses it.")
    }

    /// Keeps the open question alive without naming its choice type.
    private struct AnySession {
        let keepAlive: AnyObject

        init(_ session: AnyObject) {
            keepAlive = session
        }
    }

    /// One open question: its model, its panel, and the single answer that closes it.
    @MainActor
    private final class Session<ID: Hashable & Sendable> {
        private let model: LinkPickerModel<ID>
        private let panel: LinkPickerPanel
        private let finished: (ID?) -> Void
        private var isDone = false

        init(model: LinkPickerModel<ID>, wording: LinkPickerWording, announcement: String,
             finished: @escaping (ID?) -> Void) {
            self.model = model
            self.finished = finished
            let screen = Self.screenForPanel()
            let layout = LinkPickerLayout(closedSize: Self.closedSize(of: screen), rowCount: model.rows.count)
            // A fixed transparent canvas; only the notch shape inside it animates.
            let size = NSSize(width: layout.openSize.width + 80, height: layout.openSize.height + 60)
            panel = LinkPickerPanel(contentRect: NSRect(origin: .zero, size: size),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .mainMenu + 3
            panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
            panel.setAccessibilityLabel(String(localized: "Link picker"))
            panel.contentView = NSHostingView(rootView: LinkPickerView(
                model: model, layout: layout, wording: wording,
                choose: { [weak self] id in self?.apply(self?.model.choose(id) ?? .none) },
                dismiss: { [weak self] in self?.apply(.cancelled) }))
            panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                                  width: size.width, height: size.height), display: true)
            panel.onKey = { [weak self] event in self?.handle(event) ?? false }

            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self] in
                self?.model.isOpen = true
                Self.announce(announcement)
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            // Menu shortcuts (⌘Q, ⌘H) are not the panel's to swallow.
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
            let before = model.highlightedRow
            if let input = Self.input(for: event) {
                apply(model.handle(input))
                if let row = model.highlightedRow, row != before, !isDone {
                    Self.announce(String(localized: "\(row.name), key \(row.number)"))
                }
            }
            // Swallow the rest rather than leak half a keystroke to the app behind.
            return true
        }

        private func apply(_ outcome: LinkPickerOutcome<ID>) {
            switch outcome {
            case .none: break
            case .chose(let id): finish(id)
            case .cancelled: finish(nil)
            }
        }

        private func finish(_ choice: ID?) {
            guard !isDone else { return }
            isDone = true
            model.isOpen = false  // let it fold back into the notch before the link opens
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 220))
                panel.orderOut(nil)
                finished(choice)
            }
        }

        private static func input(for event: NSEvent) -> LinkPickerKeyInput? {
            switch event.keyCode {
            case 123: return .left
            case 124: return .right
            case 125: return .down
            case 126: return .up
            case 36, 76: return .return
            case 53: return .escape
            default:
                return event.charactersIgnoringModifiers?.first.map(LinkPickerKeyInput.character)
            }
        }

        private static func screenForPanel() -> NSScreen {
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        }

        /// The real notch when there is one, otherwise a strip the height of the menu bar.
        private static func closedSize(of screen: NSScreen) -> CGSize {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                return CGSize(width: screen.frame.width - left.width - right.width + 12, height: screen.safeAreaInsets.top)
            }
            return CGSize(width: 190, height: menuBar > 0 ? menuBar : 24)
        }

        private static func announce(_ message: String) {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
}
