// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore

/// Turns "always" in the Link picker into a host rule at the bottom of the rules file. The rule names the Profile and
/// the Space by identifier, so renaming either keeps it working.
@MainActor
public final class StoredLinkRuleRemembering: LinkRuleRemembering {
    private let store: LinkRulesStore
    private let didFail: @MainActor (LinkRulesEditError) -> Void
    private let didAdd: @MainActor () -> Void

    /// - Parameters:
    ///   - didFail: called when the rule could not be added, for example because the file is not valid.
    ///   - didAdd: called after a rule was added, so a Link rules window that is open reads the file again.
    public init(store: LinkRulesStore, didFail: @escaping @MainActor (LinkRulesEditError) -> Void,
                didAdd: @escaping @MainActor () -> Void = {}) {
        self.store = store
        self.didFail = didFail
        self.didAdd = didAdd
    }

    public func rememberChoice(host: String, profile: ProfileID, space: SpaceID?) {
        let rule = LinkRule(host: host, profile: profile.rawValue.uuidString, space: space?.rawValue.uuidString)
        do {
            try store.append(rule)
            didAdd()
        } catch let error as LinkRulesEditError {
            didFail(error)
        } catch {
            didFail(.notSaved)
        }
    }
}
