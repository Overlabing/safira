// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Appearance
import ColorCore
import ColorUI
import DesignKit
import Foundation
import SwiftUI
import Testing

/// A hover step in the sidebar re-evaluates at most the two rows it touches: rows built as Safira's are (the kit's
/// `sidebarRowCell` with a `hoverID`, the close button in a `HoverAccessory`), in a real `List` of 400 rows in a
/// `sidebarColumn`, hosted in a window that is never shown. Counted on the rows' bodies and on their accessories.
@MainActor
@Suite(.serialized)
struct HoverAccessoryTests {
    static let rows = 400
    static var rowBodies = 0
    static var accessoryBodies: [Int] = []
    /// The form each row's accessory last drew: true for the hovered one.
    static var shown: [Int: Bool] = [:]

    /// One accessory body run, recorded with its row.
    struct Probe: View {
        let row: Int
        let isHovered: Bool

        var body: some View {
            HoverAccessoryTests.accessoryBodies.append(row)
            HoverAccessoryTests.shown[row] = isHovered
            return Image(systemName: isHovered ? "xmark" : "speaker.wave.2.fill")
        }
    }

    /// A row as Safira's Tab row is: its content, the accessory reading the hover, the kit's cell tracking it.
    struct Row: View {
        let index: Int

        var body: some View {
            HoverAccessoryTests.rowBodies += 1
            return HStack {
                Text(verbatim: "Tab \(index)")
                Spacer(minLength: 0)
                HoverAccessory(id: index) { Probe(row: index, isHovered: true) } idle: { Probe(row: index, isHovered: false) }
            }
            .sidebarRowCell(state: RowState(isSelected: index == 0), placement: .free(firstInSection: false),
                            hoverID: index)
        }
    }

    struct Sidebar: View {
        let hover: ListHover

        var body: some View {
            List(0..<HoverAccessoryTests.rows, id: \.self) { Row(index: $0) }
                .listHover(hover)
                .sidebarColumn()
        }
    }

    @MainActor final class Host {
        let window: NSWindow

        init(_ view: some View) {
            let hosting = NSHostingView(rootView: view.theme(Palette.standard.themes[0]).frame(width: 360, height: 600))
            hosting.frame = CGRect(x: 0, y: 0, width: 360, height: 600)
            window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            settle()
        }

        func settle() {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
        }

        func close() { window.contentView = nil }
    }

    struct Step: Equatable, CustomStringConvertible {
        let rowBodies: Int
        let accessoryRows: Set<Int>

        var description: String { "\(rowBodies) row bodies, accessories of rows \(accessoryRows.sorted())" }
    }

    private func measure(_ host: Host, _ step: () -> Void) -> Step {
        host.settle()
        Self.rowBodies = 0
        Self.accessoryBodies = []
        step()
        host.settle()
        return Step(rowBodies: Self.rowBodies, accessoryRows: Set(Self.accessoryBodies))
    }

    @Test func aHoverStepReEvaluatesAtMostTheTwoRowsItTouches() {
        let hover = ListHover()
        let host = Host(Sidebar(hover: hover))
        defer { host.close() }
        #expect(Self.rowBodies > 2, "the list drew its rows")

        let enter = measure(host) { hover.setHovered(3, true) }
        let move = measure(host) { hover.setHovered(3, false); hover.setHovered(4, true) }
        let across = measure(host) { hover.move(to: 9) }
        let leave = measure(host) { hover.setHovered(9, false) }
        print("HOVER Safira rows of \(Self.rows): enter \(enter); move \(move); across \(across); leave \(leave)")

        #expect(enter == Step(rowBodies: 0, accessoryRows: [3]))
        #expect(move == Step(rowBodies: 0, accessoryRows: [3, 4]))
        #expect(across == Step(rowBodies: 0, accessoryRows: [4, 9]))
        #expect(leave == Step(rowBodies: 0, accessoryRows: [9]))
    }

    @Test func theAccessoryShowsItsHoveredFormOnlyForItsOwnRow() {
        let hover = ListHover()
        hover.move(to: 2)
        Self.shown = [:]
        let host = Host(VStack {
            HoverAccessory(id: 2) { Probe(row: 2, isHovered: true) } idle: { Probe(row: 2, isHovered: false) }
            HoverAccessory(id: 3) { Probe(row: 3, isHovered: true) } idle: { Probe(row: 3, isHovered: false) }
        }.listHover(hover))
        defer { host.close() }
        #expect(Self.shown == [2: true, 3: false])

        hover.move(to: 3)
        host.settle()
        #expect(Self.shown == [2: false, 3: true])

        hover.move(to: nil)
        host.settle()
        #expect(Self.shown == [2: false, 3: false])
    }

    @Test func withNoListHoverTheAccessoryIsIdle() {
        Self.shown = [:]
        let host = Host(HoverAccessory(id: 1) { Probe(row: 1, isHovered: true) } idle: { Probe(row: 1, isHovered: false) })
        defer { host.close() }
        #expect(Self.shown == [1: false])
    }
}
