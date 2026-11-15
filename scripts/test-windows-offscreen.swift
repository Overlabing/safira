// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin
//
// Runs a command (normally `swift test`) and watches the windows of its process tree while it runs. Fails when one of
// them intersects a connected display, or when one of those processes becomes the frontmost app.
//
//   swift scripts/test-windows-offscreen.swift <command> [argument]...
//
// Prints one `OK:` or `FAILED:` summary line, plus one line per offending window. Exits 1 on a finding, otherwise with
// the command's own status.
import AppKit
import CoreGraphics
import Darwin

let arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else {
    FileHandle.standardError.write(Data("usage: test-windows-offscreen.swift <command> [argument]...\n".utf8))
    exit(2)
}

func parent(of pid: pid_t) -> pid_t? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return pid_t(info.pbi_ppid)
}

/// The root and every live process below it.
func tree(of root: pid_t) -> Set<pid_t> {
    var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
    let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
    var children: [pid_t: [pid_t]] = [:]
    for pid in pids.prefix(max(count, 0)) where pid > 0 {
        if let ppid = parent(of: pid) { children[ppid, default: []].append(pid) }
    }
    var found: Set<pid_t> = [root]
    var queue = [root]
    while let pid = queue.popLast() {
        for child in children[pid] ?? [] where found.insert(child).inserted { queue.append(child) }
    }
    return found
}

func displays() -> [CGRect] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return ids.prefix(Int(count)).map(CGDisplayBounds)
}

struct Sighting { let pid: pid_t; let bounds: CGRect }

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = arguments
try process.run()
let root = process.processIdentifier

var testWindows: Set<Int> = []
/// The first place each window was seen on a display.
var onScreen: [Int: Sighting] = [:]
var frontmost: Set<pid_t> = []
var polls = 0
while process.isRunning {
    let watched = tree(of: root)
    let screens = displays()
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in list {
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, watched.contains(pid),
              let number = window[kCGWindowNumber as String] as? Int,
              let raw = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: raw) else { continue }
        testWindows.insert(number)
        let shown = window[kCGWindowIsOnscreen as String] as? Bool ?? false
        if shown, screens.contains(where: { !$0.intersection(bounds).isEmpty }) {
            if onScreen[number] == nil { onScreen[number] = Sighting(pid: pid, bounds: bounds) }
        }
    }
    if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier, watched.contains(front) {
        frontmost.insert(front)
    }
    polls += 1
    // The run loop delivers the activation notifications frontmostApplication reads.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
}

let summary = "\(polls) polls, \(testWindows.count) windows of the test processes seen, \(onScreen.count) on a display, "
    + "\(frontmost.count) frontmost test processes"
for (number, sighting) in onScreen.sorted(by: { $0.key < $1.key }) {
    print("  window \(number) of pid \(sighting.pid) at \(sighting.bounds) intersects a display")
}
for pid in frontmost.sorted() { print("  pid \(pid) became the frontmost app") }
if onScreen.isEmpty && frontmost.isEmpty {
    print("OK: no test window on a display: \(summary)")
    exit(process.terminationStatus)
}
print("FAILED: test windows reached the screen: \(summary)")
exit(1)
