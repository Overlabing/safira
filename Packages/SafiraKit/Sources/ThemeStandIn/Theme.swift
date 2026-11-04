// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SwiftUI

// The public shape of the shared theme module's types, declared here until that module becomes a dependency (gate G1).
// DesignKit reads only these names, so it can move next to the real types with nothing but its import changed. Delete
// this target then.

/// The system hues a Theme is made of.
public enum Hue: String, Sendable, CaseIterable, Hashable {
    case indigo, blue, orange, pink, teal, green, red, purple, mint, cyan, brown, yellow

    /// The SwiftUI system colour of the hue.
    public var color: Color {
        switch self {
        case .indigo: .indigo
        case .blue: .blue
        case .orange: .orange
        case .pink: .pink
        case .teal: .teal
        case .green: .green
        case .red: .red
        case .purple: .purple
        case .mint: .mint
        case .cyan: .cyan
        case .brown: .brown
        case .yellow: .yellow
        }
    }
}

/// A gradient and tint: the primary hue is the tint and the outer gradient stops, the secondary one the middle stop.
public struct Theme: Sendable, Hashable, Identifiable {
    public let id: String
    public let primary: Hue
    public let secondary: Hue

    public init(id: String, primary: Hue, secondary: Hue) {
        self.id = id
        self.primary = primary
        self.secondary = secondary
    }
}

/// The opacities of a Theme's gradient, top to bottom: primary hue, secondary hue, primary hue.
public struct GradientSpec: Sendable, Hashable {
    public var top: Double
    public var middle: Double
    public var bottom: Double

    public init(top: Double, middle: Double, bottom: Double) {
        self.top = top
        self.middle = middle
        self.bottom = bottom
    }

    public static let light = GradientSpec(top: 0.38, middle: 0.16, bottom: 0.05)
    public static let dark = GradientSpec(top: 0.42, middle: 0.18, bottom: 0.06)
}
