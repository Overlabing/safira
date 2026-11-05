// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SafiraSession
import SwiftUI

/// The sites one Profile remembers a camera, microphone or location decision for, and the kinds of link it remembers
/// whether to open an app for, with a button to revoke each. It lists the Profile it was opened for and no other:
/// there is no global permission screen.
struct SitePermissionsView: View {
    let profileName: String
    let permissions: SitePermissions
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Site permissions of “\(profileName)”")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("A site or a link asks each time until you choose to remember your choice. Revoking a choice makes it ask again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if permissions.all.isEmpty && permissions.appLinks.isEmpty {
                Text("No site or link has a remembered choice in this Profile.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                List {
                    if !permissions.all.isEmpty {
                        Section("Sites") {
                            ForEach(permissions.all) { permission in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: permission.origin.identifier)
                                        Text("\(Self.name(of: permission.kind)): \(Self.name(of: permission.decision))")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Revoke") { permissions.revoke(permission.kind, at: permission.origin) }
                                        .accessibilityLabel(Text("Revoke \(Self.name(of: permission.kind)) for \(permission.origin.identifier)"))
                                }
                            }
                        }
                    }
                    if !permissions.appLinks.isEmpty {
                        Section("Links that open an app") {
                            ForEach(permissions.appLinks) { choice in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: "\(choice.scheme.rawValue):")
                                        Text(Self.name(of: choice.decision, forLinks: true))
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Revoke") { permissions.revokeAppLink(choice.scheme) }
                                        .accessibilityLabel(Text("Revoke the choice for \(choice.scheme.rawValue): links"))
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 160)
            }
            Text("A camera, microphone or location a page is already using keeps running until the page stops it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Revoke All", role: .destructive) { permissions.revokeAll() }
                    .disabled(permissions.all.isEmpty && permissions.appLinks.isEmpty)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    static func name(of kind: PermissionKind) -> String {
        switch kind {
        case .camera: String(localized: "Camera", comment: "Site permissions sheet")
        case .microphone: String(localized: "Microphone", comment: "Site permissions sheet")
        case .location: String(localized: "Location", comment: "Site permissions sheet")
        }
    }

    static func name(of decision: PermissionDecision, forLinks: Bool) -> String {
        switch decision {
        case .allow: String(localized: "Opens its app without asking", comment: "Site permissions sheet")
        case .deny: String(localized: "Never opens an app", comment: "Site permissions sheet")
        }
    }

    static func name(of decision: PermissionDecision) -> String {
        switch decision {
        case .allow: String(localized: "Allowed", comment: "Site permissions sheet")
        case .deny: String(localized: "Not allowed", comment: "Site permissions sheet")
        }
    }
}
