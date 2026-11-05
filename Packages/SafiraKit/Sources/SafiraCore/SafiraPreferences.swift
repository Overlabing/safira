// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Preferences
import UserFacing

extension Preference {
    /// The stored value. One that can no longer be read is replaced by the default on disk too, so the user is told once,
    /// through `unreadable`, and the next launch reads the default.
    public func loadRestoringDefault(_ unreadable: (PreferenceError) -> Void) -> Value {
        do {
            return try load()
        } catch {
            try? save(defaultValue)
            unreadable(error)
            return defaultValue
        }
    }
}

extension PreferenceError {
    /// A banner: the defaults are already back and nothing is left for the user to do.
    public var userFacingError: UserFacingError {
        UserFacingError(
            title: String(localized: "Some settings were reset", table: "SafiraCore", bundle: .module,
                          comment: "Banner title when a saved setting could not be read"),
            message: errorDescription ?? "", presentation: .banner)
    }
}

/// A preference Safira kept as a plain property-list value (a Boolean, a string, a dictionary) before it moved to
/// AppSupportKit's `Preference`, which keeps JSON under the same key.
public struct LegacyPreference: Sendable {
    public let key: String
    private let rewrite: @Sendable (Any, any KeyValueStore) -> Void

    /// - Parameters:
    ///   - type: the `Value` of the `Preference` that reads the key now, named so that it is never inferred as an
    ///     optional of itself.
    ///   - decode: the value the old store read from what it had written; nil when it read nothing usable, and the old
    ///     value is then dropped, so the preference starts at its default as it did before.
    public init<Value: Codable & Sendable>(key: String, as type: Value.Type,
                                           decode: @escaping @Sendable (Any) -> Value?) {
        self.key = key
        rewrite = { old, store in
            guard let value = decode(old) else {
                store.setData(nil, forKey: key)
                return
            }
            try? Preference(key: key, defaultValue: value, store: store).save(value)
        }
    }

    /// Rewrites, once, every key of `preferences` that still holds an old value in the persistent domain `domain` of
    /// `defaults`. A value that is already JSON data is left alone, so it can run at every launch, before any store reads.
    /// A value passed as a launch argument is not in the persistent domain and is never written.
    public static func migrate(_ preferences: [LegacyPreference], in defaults: UserDefaults, domain: String) {
        guard let stored = defaults.persistentDomain(forName: domain) else { return }
        for preference in preferences {
            guard let old = stored[preference.key], !(old is Data) else { continue }
            preference.rewrite(old, defaults)
        }
    }

    /// A Boolean as `UserDefaults.bool(forKey:)` read it: a number, or the text YES, true or a number.
    public static func bool(_ old: Any) -> Bool? {
        switch old {
        case let number as NSNumber: number.boolValue
        case let text as String:
            switch text.lowercased() {
            case "yes", "true": true
            case "no", "false": false
            default: Int(text).map { $0 != 0 }
            }
        default: nil
        }
    }
}
