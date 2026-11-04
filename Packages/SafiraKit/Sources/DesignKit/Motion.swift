// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SwiftUI

/// One duration scale, a few curves, and named roles. A view never writes a duration or a curve: it asks for a role's
/// animation. Springs never bounce visibly. Under Reduce Motion a role becomes the shared fade, or nothing.
public enum MotionDuration: Double, Sendable, CaseIterable {
    /// Feedback under the pointer: a hover fill, an overlay fading.
    case instant = 0.12
    /// A small change in place: a chevron, a row's state, the reduced fade.
    case quick = 0.2
    /// A surface changing: a panel, the Theme, the switcher.
    case calm = 0.35
    /// A long travel.
    case deliberate = 0.5
}

public enum MotionCurve: Sendable, CaseIterable {
    /// Critically damped spring, no overshoot.
    case smooth
    /// Slightly underdamped spring for a state change.
    case snappy
    /// A panel's entrance, a hair livelier than `smooth`.
    case spring
    case easeOut

    /// The spring's bounce as `Animation.spring(duration:bounce:)` takes it; nil for a timing curve.
    public var bounce: Double? {
        switch self {
        case .smooth: 0
        case .snappy: 0.15
        case .spring: 0.1
        case .easeOut: nil
        }
    }
}

public enum ReducedMotion: Sendable {
    case fade
    case none
}

public enum MotionRole: String, Sendable, CaseIterable {
    case hoverFill
    case rowState
    case indicatorRotation
    case panelAppear
    case panelContent
    case panelDisappear
    case overlayFade
    case themeChange
    case contentReveal

    public struct Spec: Sendable, Equatable {
        public var duration: MotionDuration
        public var curve: MotionCurve
        public var delay: Double
        public var reduced: ReducedMotion
    }

    public var spec: Spec {
        switch self {
        case .hoverFill: Spec(duration: .instant, curve: .easeOut, delay: 0, reduced: .none)
        case .rowState: Spec(duration: .quick, curve: .snappy, delay: 0, reduced: .none)
        case .indicatorRotation: Spec(duration: .quick, curve: .smooth, delay: 0, reduced: .none)
        case .panelAppear: Spec(duration: .calm, curve: .spring, delay: 0, reduced: .fade)
        case .panelContent: Spec(duration: .quick, curve: .easeOut, delay: 0.08, reduced: .none)
        case .panelDisappear: Spec(duration: .calm, curve: .easeOut, delay: 0, reduced: .fade)
        case .overlayFade: Spec(duration: .instant, curve: .easeOut, delay: 0, reduced: .none)
        case .themeChange: Spec(duration: .calm, curve: .smooth, delay: 0, reduced: .none)
        case .contentReveal: Spec(duration: .calm, curve: .smooth, delay: 0, reduced: .none)
        }
    }

    /// The fade every `.fade` role becomes under Reduce Motion: no movement, no change of size.
    public static let reducedFade = Spec(duration: .quick, curve: .easeOut, delay: 0, reduced: .fade)

    /// The spec to run, or nil when Reduce Motion makes the change immediate.
    public func resolved(reduceMotion: Bool) -> Spec? {
        guard reduceMotion else { return spec }
        return spec.reduced == .fade ? Self.reducedFade : nil
    }

    public func animation(reduceMotion: Bool) -> Animation? {
        guard let spec = resolved(reduceMotion: reduceMotion) else { return nil }
        let seconds = spec.duration.rawValue
        let base: Animation = if let bounce = spec.curve.bounce {
            .spring(duration: seconds, bounce: bounce)
        } else {
            .easeOut(duration: seconds)
        }
        return spec.delay > 0 ? base.delay(spec.delay) : base
    }

    /// The role's transition, or under Reduce Motion a plain fade (a role that fades) or none.
    public func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        guard reduceMotion else { return transition }
        return spec.reduced == .fade ? .opacity : .identity
    }
}
