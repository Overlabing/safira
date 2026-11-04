// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// The app from which an external link was clicked, as far as macOS tells.
public struct Opener: Hashable, Sendable {
    public let bundleIdentifier: String?
    /// The name the user knows the app by, shown in the Link picker.
    public let name: String?

    public init(bundleIdentifier: String?, name: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// What the system knows about a running process. The app backs it with `NSRunningApplication`; tests give literal
/// answers, so identifying an Opener never needs LaunchServices.
public protocol RunningApplicationLookup: Sendable {
    /// The application running as `processIdentifier`, or nil for a process that is not an application (a command-line
    /// tool such as `open`) or that has already exited.
    func application(processIdentifier: Int32) -> Opener?
}

/// Finds the Opener of a link from the process that sent the open event. The sender is reported on a best-effort
/// basis: a launcher (Spotlight, `open`) may be reported instead of the app the user clicked in, and an event may name
/// no sender at all, in which case there is no Opener.
public struct OpenerIdentifier: Sendable {
    private let lookup: any RunningApplicationLookup
    private let ownProcessIdentifier: Int32

    public init(lookup: any RunningApplicationLookup, ownProcessIdentifier: Int32) {
        self.lookup = lookup
        self.ownProcessIdentifier = ownProcessIdentifier
    }

    public func identify(senderProcessIdentifier: Int32?) -> Opener? {
        guard let pid = senderProcessIdentifier, pid > 0, pid != ownProcessIdentifier,
              let opener = lookup.application(processIdentifier: pid),
              opener.bundleIdentifier != nil || opener.name != nil else { return nil }
        return opener
    }
}
