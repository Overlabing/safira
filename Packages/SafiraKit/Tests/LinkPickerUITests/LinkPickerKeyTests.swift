// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import LinkPickerUI
import Testing

@Test(arguments: [
    (Character("1"), 0 as Int?),
    (Character("9"), 8 as Int?),
    (Character("0"), nil),
    (Character("a"), nil),
    (Character("٣"), nil),
])
func digitKeysOneToNinePickARow(key: Character, row: Int?) {
    #expect(LinkPickerKey.rowIndex(for: key) == row)
}
