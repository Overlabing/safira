// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

// The benchmark mode exists only in the Benchmark configuration (SWIFT_ACTIVE_COMPILATION_CONDITIONS = BENCHMARK).
// scripts/check.sh proves it is absent from the Release binary.
#if BENCHMARK
import AppKit
import Foundation
import SafiraCore
import SafiraSession

/// Opens a frozen list of addresses without interaction, so that the memory of the resting Tabs can be measured
/// (docs/architecture-v1.md §9.4). Launch with `-SafiraBenchURLs <file>`, one address per line; `-SafiraBenchGapSeconds`
/// sets the pause between two addresses (5 by default, as in the protocol of docs/research-tab-discarding.md §5.3).
///
/// The run writes `bench-status.jsonl` to Application Support, one JSON object per line, for the harness to read:
/// `launched`, then one `opened` per address, then `ready` once the last load ended and the first Tab is selected.
@MainActor
final class BenchmarkRun {
    private let addresses: [URL]
    private let gap: Duration
    private let status: StatusFile

    /// Nil when the launch arguments do not ask for a benchmark.
    init?(statusDirectory: URL) {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "SafiraBenchURLs"),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        addresses = text.split(whereSeparator: \.isNewline).compactMap { URL(string: String($0)) }
        let seconds = defaults.object(forKey: "SafiraBenchGapSeconds") == nil ? 5 : defaults.integer(forKey: "SafiraBenchGapSeconds")
        gap = .seconds(seconds)
        status = StatusFile(url: statusDirectory.appending(path: "bench-status.jsonl", directoryHint: .notDirectory))
    }

    func start(session: ProfileSession) {
        status.reset()
        status.write(["event": "launched", "pid": ProcessInfo.processInfo.processIdentifier,
                      "addresses": addresses.count, "registeredForHTTP": Self.isRegisteredBrowser(scheme: "http"),
                      "registeredForHTTPS": Self.isRegisteredBrowser(scheme: "https")])
        Task { @MainActor in
            var opened: [TabID] = []
            for (index, address) in addresses.enumerated() {
                session.openCommandBar(for: .newTab)
                session.submitCommandBar(address.absoluteString)
                if let id = session.selectedTabID { opened.append(id) }
                status.write(["event": "opened", "index": index, "url": address.absoluteString])
                try? await Task.sleep(for: gap)
            }
            while session.tabs.contains(where: { $0.state.isLoading }) {
                try? await Task.sleep(for: .seconds(1))
            }
            if let first = opened.first { session.select(first) }
            let tabs = session.tabs.map { tab -> [String: Any] in
                ["url": tab.address?.absoluteString ?? "", "title": tab.state.title ?? "", "isLoading": tab.state.isLoading]
            }
            status.write(["event": "ready", "tabs": tabs])
        }
    }

    /// Whether LaunchServices lists this app among the apps that open the scheme: the condition under which WebKit
    /// treats the app as a full web browser and keeps its process cache (docs/research-tab-discarding.md §1.5).
    private static func isRegisteredBrowser(scheme: String) -> Bool {
        guard let probe = URL(string: "\(scheme)://example.com/") else { return false }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe).contains {
            $0.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
        }
    }

    private struct StatusFile {
        let url: URL

        func reset() {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data().write(to: url)
        }

        func write(_ fields: [String: Any]) {
            var fields = fields
            fields["at"] = Date().timeIntervalSince1970
            guard let line = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
                  let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line + Data("\n".utf8))
        }
    }
}
#endif
