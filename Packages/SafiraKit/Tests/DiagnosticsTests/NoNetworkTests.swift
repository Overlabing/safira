// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Testing

/// Debug mode never sends anything: the module names no networking API, and the only way a log leaves the machine is
/// the archive the user saves by hand.
@Test func theDiagnosticsModuleNamesNoNetworkingAPI() throws {
    let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/Diagnostics", directoryHint: .isDirectory)
    let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    #expect(files.count >= 6)

    let banned = ["URLSession", "URLRequest", "NWConnection", "NWListener", "CFNetwork", "import Network", "WebKit",
                  "Socket", "NSURLConnection"]
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        for name in banned {
            #expect(!text.contains(name), "\(file.lastPathComponent) names \(name)")
        }
    }
}
