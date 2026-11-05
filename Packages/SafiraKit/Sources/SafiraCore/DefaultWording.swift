// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// The words several entries of the registry of defaults share, translated once.
public enum DefaultWording {
    public static func onOff(_ isOn: Bool) -> String {
        isOn ? String(localized: "On", table: "SafiraCore", bundle: .module, comment: "Defaults: the value of a switch that is on")
            : String(localized: "Off", table: "SafiraCore", bundle: .module, comment: "Defaults: the value of a switch that is off")
    }

    public static let safiraMenu = String(localized: "Safira menu", table: "SafiraCore", bundle: .module,
                                          comment: "Defaults: where to change a default, the app menu")
    public static let viewMenu = String(localized: "View menu", table: "SafiraCore", bundle: .module,
                                        comment: "Defaults: where to change a default")
    public static let helpMenu = String(localized: "Help menu", table: "SafiraCore", bundle: .module,
                                        comment: "Defaults: where to change a default")
}
