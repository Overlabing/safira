// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import SafiraCore
import UserFacing

/// Safira's catalogue of the errors it shows, on AppSupportKit's model. Every one is an alert but the unreadable
/// settings, which are a banner (`PreferenceError.userFacingError`).
extension UserFacingError {
    /// The action of `linkRulesFileInvalid`, handled by the Link controller.
    static let showLinkRulesFile = "linkRules.showInFinder"

    // MARK: Links and the default browser

    static func linkRulesFileInvalid(_ error: LinkRulesError) -> UserFacingError {
        UserFacingError(
            title: String(localized: "The Link rules file is not valid", comment: "Link rules, Slack folder and default browser"),
            message: error.explanation + " "
                + String(localized: "No Link rule applies until it is fixed: links go to the Link picker.", comment: "Link rules, Slack folder and default browser"),
            action: .custom(id: showLinkRulesFile,
                            title: String(localized: "Show in Finder", comment: "Link rules, Slack folder and default browser")))
    }

    /// The Link rules window shows it inline, in place of the list.
    static func linkRulesFileInvalidInWindow(_ error: LinkRulesError) -> UserFacingError {
        UserFacingError(
            title: String(localized: "The Link rules file is not valid", comment: "Link rules, Slack folder and default browser"),
            message: error.explanation + " "
                + String(localized: "Safira never overwrites it. No rule applies until it is fixed: links go to the Link picker. Fix it in an editor, or delete it to start again.", comment: "Link rules window"),
            action: .custom(id: showLinkRulesFile,
                            title: String(localized: "Show in Finder", comment: "Link rules, Slack folder and default browser")))
    }

    static func linkRuleNotSaved(_ error: LinkRulesEditError) -> UserFacingError {
        UserFacingError(
            title: String(localized: "The Link rule was not saved", comment: "Link rules, Slack folder and default browser"),
            message: error.explanation + " "
                + String(localized: "The link opened where you chose.", comment: "Link rules, Slack folder and default browser"))
    }

    static var notSlackFolder: UserFacingError {
        UserFacingError(
            title: String(localized: "That is not Slack's folder", comment: "Link rules, Slack folder and default browser"),
            message: String(localized: "Choose the folder named Slack inside Application Support. It holds a folder named storage.", comment: "Link rules, Slack folder and default browser"))
    }

    /// The system's own words are the message, as before; the full error is the technical detail.
    static func defaultBrowserNotSet(_ error: any Error) -> UserFacingError {
        UserFacingError(
            title: String(localized: "Safira could not be made the default browser", comment: "Link rules, Slack folder and default browser"),
            message: error.localizedDescription, technicalDetail: String(reflecting: error))
    }

    // MARK: The Link rules window

    static func linkRulesNotExported(_ error: any Error) -> UserFacingError {
        UserFacingError(title: String(localized: "The Link rules could not be saved", comment: "Link rules window"),
                        message: error.localizedDescription, technicalDetail: String(reflecting: error))
    }

    static func notALinkRulesFile(_ explanation: String) -> UserFacingError {
        UserFacingError(
            title: String(localized: "That file is not a valid Link rules file", comment: "Link rules window"),
            message: explanation + " " + String(localized: "Your existing rules were not changed.", comment: "Link rules window"))
    }

    static func notAZenPickerFile(_ explanation: String) -> UserFacingError {
        UserFacingError(
            title: String(localized: "That is not a ZenPicker rules file", comment: "Link rules window"),
            message: explanation + " " + String(localized: "Your existing rules were not changed.", comment: "Link rules window"))
    }

    static var nothingToImport: UserFacingError {
        UserFacingError(title: String(localized: "Nothing to import", comment: "Link rules window"),
                        message: String(localized: "The file has no rule that names a target.", comment: "Link rules window"))
    }

    static var fileUnreadable: UserFacingError {
        UserFacingError(title: String(localized: "The file could not be read", comment: "Link rules window"), message: "")
    }

    // MARK: Diagnostics

    static var noDiagnosticLogs: UserFacingError {
        UserFacingError(
            title: String(localized: "There are no diagnostic logs to export", comment: "Alert title"),
            message: String(localized: "Turn on Debug mode in the Help menu, use Safira, then export again.",
                            comment: "Alert text, under There are no diagnostic logs to export"))
    }

    static func diagnosticLogsNotExported(_ error: any Error) -> UserFacingError {
        UserFacingError(title: String(localized: "The diagnostic logs could not be exported", comment: "Alert title"),
                        message: error.localizedDescription, technicalDetail: String(reflecting: error))
    }

    // MARK: Profiles

    static func historyNotCleared(profileName: String) -> UserFacingError {
        UserFacingError(
            title: String(localized: "The history of “\(profileName)” could not be cleared", comment: "Main window"),
            message: String(localized: "Its website data was cleared. Try clearing the history again.", comment: "Main window"))
    }

    static var websiteDataNotErasedYet: UserFacingError {
        UserFacingError(
            title: String(localized: "Some of the Profile’s website data could not be erased yet", comment: "Main window"),
            message: String(localized: "Safira erases it the next time it opens.", comment: "Main window"))
    }

    // MARK: Links to other apps

    static func noApp(for refusal: AppLinkRefusal) -> UserFacingError {
        UserFacingError(
            title: String(localized: "No app can open “\(refusal.scheme.rawValue):” links.", comment: "Permission sheet of a site or a link to another app"),
            message: String(localized: "Nothing was opened. No app on this Mac is set up for this kind of link.", comment: "Permission sheet of a site or a link to another app"))
    }

    static func appCouldNotOpenLink(_ app: ExternalApp) -> UserFacingError {
        UserFacingError(
            title: String(localized: "\(app.name) could not open the link.", comment: "Permission sheet of a site or a link to another app"),
            message: "")
    }
}
