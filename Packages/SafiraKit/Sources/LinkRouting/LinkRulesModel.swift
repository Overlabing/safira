// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore

/// What the Link rules window last did, in words the user (and VoiceOver) can read.
public struct LinkRulesMessage: Hashable, Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}

/// One Link rule as the Link rules window lists it.
public struct LinkRuleEntry: Hashable, Identifiable, Sendable {
    /// The place in the list, starting at 1: the first rule that matches wins.
    public let position: Int
    public let rule: LinkRule
    /// What the rule matches, for example "github.com/example-org".
    public let match: String
    /// Where the rule sends a link, for example "Work › Dev"; the reference as written when it names nothing that exists.
    public let destination: String
    /// Why the rule cannot apply right now. Nil for a rule that can.
    public let problem: String?

    public var id: Int { position }

    /// The whole rule in one sentence, which is what VoiceOver reads for the row.
    public var accessibilityLabel: String {
        var parts = [String(localized: "Rule \(position)", table: "LinkRouting", bundle: .module, comment: "Link rules window: VoiceOver label of a rule row starts with its position"), match + " → " + destination]
        if rule.forcesNewTab { parts.append(String(localized: "always a new Tab", table: "LinkRouting", bundle: .module, comment: "Link rules window: VoiceOver label of a rule row, a rule that forces a new Tab")) }
        if let problem { parts.append(problem) }
        return parts.joined(separator: ", ")
    }
}

/// The state behind the Link rules window: the rules in order with delete, reorder, import and export, and the check
/// "Where would this link go?". It edits the file through `LinkRulesStore`, so the file is the single source of truth and
/// is read again after each change; the check asks the same router that real links go through.
@MainActor
@Observable
public final class LinkRulesModel {
    public private(set) var entries: [LinkRuleEntry] = []
    /// Set while the file on disk is not valid: the list is empty and nothing can be edited.
    public private(set) var fileProblem: LinkRulesError?
    /// The position of the selected rule.
    public var selection: Int?
    public private(set) var message: LinkRulesMessage?
    public var checkedAddress = ""
    public var checkedOpener = ""
    public private(set) var checkResult: String?

    private let store: LinkRulesStore
    private let profiles: @MainActor () -> [Profile]
    private let spacesOf: @MainActor (ProfileID) -> [SpaceChoice]
    private let route: @MainActor (IncomingLink) -> LinkRoute

    /// - Parameter route: where a link would go, by the same decision real links get.
    public init(store: LinkRulesStore, profiles: @escaping @MainActor () -> [Profile],
                spacesOf: @escaping @MainActor (ProfileID) -> [SpaceChoice],
                route: @escaping @MainActor (IncomingLink) -> LinkRoute) {
        self.store = store
        self.profiles = profiles
        self.spacesOf = spacesOf
        self.route = route
        reload()
    }

    public var canEdit: Bool { fileProblem == nil }

    public var selectedEntry: LinkRuleEntry? {
        selection.flatMap { position in entries.first { $0.position == position } }
    }

    public var canMoveUp: Bool { (selection ?? 1) > 1 && selectedEntry != nil }
    public var canMoveDown: Bool { selectedEntry != nil && (selection ?? entries.count) < entries.count }

    /// Reads the file again, for example after the user edited it by hand.
    public func reload() {
        switch store.load() {
        case .invalid(let error):
            fileProblem = error
            entries = []
            selection = nil
        case .rules(let set):
            fileProblem = nil
            let profiles = profiles()
            entries = set.rules.enumerated().map { entry(for: $1, position: $0 + 1, profiles: profiles) }
            if let selection, selection > entries.count { self.selection = entries.last?.position }
        }
    }

    // MARK: - Editing

    public func deleteSelected() {
        guard let entry = selectedEntry else { return }
        let next = min(entry.position, entries.count - 1)
        perform(String(localized: "Deleted rule \(entry.position), \(entry.match).", table: "LinkRouting", bundle: .module, comment: "Link rules window: status message; the rule position and what it matches")) {
            try store.remove(at: entry.position - 1)
        }
        if message?.isError == false { selection = next > 0 ? next : nil }
    }

    /// Moves the selected rule up (-1) or down (1) by one place.
    public func moveSelected(by offset: Int) {
        guard let entry = selectedEntry else { return }
        let destination = entry.position + offset
        guard (1...entries.count).contains(destination) else { return }
        perform(String(localized: "Moved \(entry.match) to place \(destination) of \(entries.count).", table: "LinkRouting", bundle: .module, comment: "Link rules window: status message; what the rule matches, its new place and the count")) {
            try store.move(from: entry.position - 1, to: destination - 1)
        }
        if message?.isError == false { selection = destination }
    }

    /// The rules file for the user to save, or nil (with a message) when it cannot be exported.
    public func exportData() -> Data? {
        do {
            let data = try store.exportData()
            message = LinkRulesMessage(text: String(localized: "Exported \(entries.count) rules.", table: "LinkRouting", bundle: .module, comment: "Link rules window: status message after export"), isError: false)
            return data
        } catch {
            fail(error)
            return nil
        }
    }

    public func importFile(_ data: Data, mode: LinkRulesImportMode) {
        let previous = entries.count
        perform(nil) { try store.importFile(data, mode: mode) }
        guard message?.isError != true else { return }
        let count = mode == .replace ? entries.count : entries.count - previous
        message = LinkRulesMessage(text: String(localized: "Imported \(count) rules.", table: "LinkRouting", bundle: .module, comment: "Link rules window: status message after import"), isError: false)
    }

    /// The targets named in a ZenPicker rules file, for the user to map to Profiles.
    public func zenPickerTargets(in data: Data) -> Result<[String], ZenPickerImportError> {
        ZenPickerRules.parse(data).map(\.targets)
    }

    /// Adds the rules of a ZenPicker file at the end. A target missing from `profileFor` is not imported.
    public func importZenPicker(_ data: Data, profileFor: [String: ProfileID]) {
        switch ZenPickerRules.parse(data) {
        case .failure(let error):
            message = LinkRulesMessage(text: String(localized: "That is not a ZenPicker rules file. \(error.explanation)", table: "LinkRouting", bundle: .module, comment: "Link rules window: error message; the argument is the reason"),
                                       isError: true)
        case .success(let zen):
            let (rules, skipped) = zen.linkRules(profileReference: profileFor.mapValues { $0.rawValue.uuidString })
            let text = skipped == 0 ? String(localized: "Imported \(rules.count) rules.", table: "LinkRouting", bundle: .module, comment: "Link rules window: status message after a ZenPicker import")
                : String(localized: "Imported \(rules.count) rules; left out \(skipped) without a Profile or without a host or Opener.", table: "LinkRouting", bundle: .module, comment: "Link rules window: status message after a ZenPicker import; imported and skipped counts")
            perform(text) { try store.append(contentsOf: rules) }
        }
    }

    // MARK: - The check

    /// Where the pasted link would go right now, by the same decision a real link gets.
    public func runCheck() {
        let typed = checkedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            checkResult = String(localized: "Type or paste a link first.", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check with an empty field")
            return
        }
        // A scheme is a name and a colon not followed by a digit: "example.com:8080/a" has a port, "mailto:a@b.c" a scheme.
        let hasScheme = typed.contains("://") || typed.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.-]*:(?!\d)/) != nil
        let address = hasScheme ? typed : "https://" + typed
        let opener = checkedOpener.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = URL(string: address).map {
            IncomingLink(url: $0, opener: opener.isEmpty ? nil : Opener(bundleIdentifier: opener, name: nil))
        }
        guard let link, link.isOpenable else {
            checkResult = String(localized: "That is not a web link.", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check")
            return
        }
        checkResult = describe(route(link))
    }

    func describe(_ route: LinkRoute) -> String {
        let profiles = profiles()
        func profileName(_ id: ProfileID) -> String { profiles.first { $0.id == id }?.name ?? "?" }
        func spaceName(_ profile: ProfileID, _ id: SpaceID) -> String { spacesOf(profile).first { $0.id == id }?.name ?? "?" }
        var sentence: String
        switch route.decision {
        case .openNative(let native):
            sentence = String(localized: "It opens in the \(native.app.displayName) app.", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check; an app name such as Slack")
        case .open(let target):
            let profile = profileName(target.profile)
            sentence = target.space.map { String(localized: "It opens in a new Tab of \(profile), in the Space \(spaceName(target.profile, $0)).", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check; a Profile and a Space name") }
                ?? String(localized: "It opens in a new Tab of \(profile), in its last active Space.", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check; a Profile name")
            if target.forcesNewTab { sentence += " " + String(localized: "The rule asks for a new Tab even if the link is already open.", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check") }
        case .focus(let match):
            sentence = String(localized: "It shows the Tab that already has this address, in \(profileName(match.profile)), Space \(spaceName(match.profile, match.space)).", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check; a Profile and a Space name")
        case .ask:
            sentence = String(localized: "Safira asks which Profile receives it.", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check")
        }
        if let problem = route.rulesFileProblem {
            sentence = String(localized: "The Link rules file is not valid, so no rule applies. \(problem.explanation)", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check; the argument is the reason") + " " + sentence
        } else if let index = route.ruleIndex {
            sentence += " " + String(localized: "Rule \(index + 1) decided it.", table: "LinkRouting", bundle: .module, comment: "Link rules window: result of the link check; the rule position")
        }
        return sentence
    }

    // MARK: - Internals

    private func perform(_ success: String?, _ change: () throws -> Void) {
        do {
            try change()
            if let success { message = LinkRulesMessage(text: success, isError: false) }
        } catch {
            fail(error)
        }
        reload()
    }

    private func fail(_ error: Error) {
        let text = (error as? LinkRulesEditError)?.explanation ?? String(localized: "The Link rules file could not be changed.", table: "LinkRouting", bundle: .module, comment: "Link rules window: error message")
        message = LinkRulesMessage(text: text, isError: true)
    }

    private func entry(for rule: LinkRule, position: Int, profiles: [Profile]) -> LinkRuleEntry {
        var match = (rule.host ?? "") + (rule.path ?? "")
        if let opener = rule.opener {
            match += (match.isEmpty ? "" : " ") + String(localized: "from \(opener)", table: "LinkRouting", bundle: .module, comment: "Link rules window: what a rule matches, the Opener part; the argument is a bundle identifier")
        }
        if match.isEmpty { match = String(localized: "(no host or Opener)", table: "LinkRouting", bundle: .module, comment: "Link rules window: what a rule matches when it names nothing") }
        var destination = rule.profile
        var problem: String?
        if !rule.isActive {
            problem = String(localized: "Ignored: it has no host and no Opener", table: "LinkRouting", bundle: .module, comment: "Link rules window: why a rule does not apply")
        } else {
            switch LinkRouter.target(for: rule, among: profiles, spacesOf: spacesOf) {
            case .success(let target):
                let profile = profiles.first { $0.id == target.profile }?.name ?? rule.profile
                let space = target.space.flatMap { id in spacesOf(target.profile).first { $0.id == id }?.name }
                destination = space.map { "\(profile) › \($0)" } ?? profile
            case .failure(let reason):
                problem = switch reason {
                case .unknownProfile: String(localized: "Skipped: no such Profile", table: "LinkRouting", bundle: .module, comment: "Link rules window: why a rule does not apply")
                case .ambiguousProfile: String(localized: "Skipped: two Profiles have that name", table: "LinkRouting", bundle: .module, comment: "Link rules window: why a rule does not apply")
                case .unknownSpace: String(localized: "Skipped: no such Space", table: "LinkRouting", bundle: .module, comment: "Link rules window: why a rule does not apply")
                case .ambiguousSpace: String(localized: "Skipped: two Spaces have that name", table: "LinkRouting", bundle: .module, comment: "Link rules window: why a rule does not apply")
                }
            }
        }
        return LinkRuleEntry(position: position, rule: rule, match: match, destination: destination, problem: problem)
    }
}
