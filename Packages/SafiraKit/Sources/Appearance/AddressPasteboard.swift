// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore

/// What Copy Link puts on a pasteboard: the full address as plain text, and as a URL for a web address only. A file's
/// address is never written as a file URL, so pasting it in the Finder pastes text, not the file.
public enum AddressPasteboard {
    @MainActor
    public static func write(_ address: URL, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(address.absoluteString, forType: .string)
        if AddressDisplay(address).isWebAddress {
            pasteboard.setString(address.absoluteString, forType: .URL)
        }
    }
}
