// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// The Link picker is driven from the keyboard: digit keys 1 to 9 pick a row.
public enum LinkPickerKey {
    /// The zero-based row a key picks, or nil when the key picks no row.
    public static func rowIndex(for key: Character) -> Int? {
        guard let digit = key.wholeNumberValue, key.isASCII, (1...9).contains(digit) else { return nil }
        return digit - 1
    }
}

/// A key the Link picker answers to. Every other key does nothing.
public enum LinkPickerKeyInput: Hashable, Sendable {
    case character(Character)
    case up, down, left, right
    case `return`
    case escape
}
