// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import SwiftUI

/// The part of a sidebar row that changes under the pointer (a Tab's close button), read from the list's `ListHover`
/// for the row `id`, the same id as its cell's `hoverID`. A hover step re-evaluates this view alone, never the row
/// around it, so a row keeps no hover state of its own. With no `ListHover` around, it shows `idle`.
public struct HoverAccessory<Hovered: View, Idle: View>: View {
    @Environment(ListHover.self) private var hover: ListHover?
    private let id: AnyHashable
    private let hovered: Hovered
    private let idle: Idle

    public init(id: AnyHashable, @ViewBuilder hovered: () -> Hovered, @ViewBuilder idle: () -> Idle) {
        self.id = id
        self.hovered = hovered()
        self.idle = idle()
    }

    public var body: some View {
        if hover?.isHovered(id) == true {
            hovered
        } else {
            idle
        }
    }
}
