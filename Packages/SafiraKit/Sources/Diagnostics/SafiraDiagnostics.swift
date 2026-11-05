// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DiagnosticsKit
import Foundation

extension DiagnosticsConfiguration {
    /// Safira's Debug mode: files `safira-YYYY-MM-DD.log` kept 7 days, 5 MB each and 25 MB in all, exported as
    /// `Safira-diagnostics-<UTC stamp>/`. A line without a private value always reaches the system log; a line with one
    /// (a host, a page timing) only while Debug mode is on.
    public static func safira(subsystem: String) -> DiagnosticsConfiguration {
        DiagnosticsConfiguration(subsystem: subsystem, fileNamePrefix: "safira", archiveName: "Safira",
                                 osLog: .publicMessagesAlways)
    }
}

extension DiagnosticLogger {
    /// Lets a call site write `.pageLoaded(…)`: the kit's `record(_:)` is generic, so it cannot infer the case.
    public func record(_ event: DiagnosticEvent) {
        recordConvertible(event)
    }

    private func recordConvertible(_ event: some DiagnosticEventConvertible) {
        record(event)
    }

    /// Turning Debug mode on writes its first line; turning it off writes its last one, which is on disk before the
    /// log stops: the kit drops what still waits when it is disabled.
    public func setDebugMode(_ enabled: Bool) {
        guard enabled != sink.isEnabled else { return }
        if enabled {
            sink.setEnabled(true)
            record(.debugMode(isOn: true))
        } else {
            record(.debugMode(isOn: false))
            sink.flushBeforeExit()
            sink.setEnabled(false)
        }
    }
}

/// `environment.txt` of an export: what Safira says of itself. Versions only, no path, user or address.
public enum DiagnosticEnvironment {
    public static func text(appVersion: String, build: String, system: OperatingSystemVersion) -> String {
        """
        Safira \(appVersion) (\(build))
        macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)
        """
    }
}

/// Debug mode's files from before DiagnosticsKit: `safira-20261103T100000.250Z.log`, or `…Z-1.log` for a second file
/// started in the same millisecond. They hold site hosts, and the kit neither prunes nor exports them.
public enum LegacyLogFiles {
    /// Deletes the files of exactly that name directly in `directory`, nothing else; a missing folder is left missing.
    public static func remove(in directory: URL) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        for name in names where isLegacyName(name) {
            let file = directory.appending(path: name, directoryHint: .notDirectory)
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            try? manager.removeItem(at: file)
        }
    }

    static func isLegacyName(_ name: String) -> Bool {
        name.wholeMatch(of: #/safira-\d{8}T\d{6}\.\d{3}Z(?:-\d+)?\.log/#) != nil
    }
}
