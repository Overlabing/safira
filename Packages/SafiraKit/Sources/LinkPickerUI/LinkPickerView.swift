// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SwiftUI

/// The size of the real notch, or of the menu bar strip on a display without one, and the panel's open size from it.
struct LinkPickerLayout: Equatable {
    static let tileWidth: CGFloat = 92
    static let tileSpacing: CGFloat = 10
    static let topCorner: CGFloat = 19
    static let maxColumns = 5

    static let rememberRowHeight: CGFloat = 30

    let closedSize: CGSize
    let rowCount: Int
    var hasRememberRow = false

    var columns: Int { max(1, min(rowCount, Self.maxColumns)) }
    var tileRows: Int { max(1, (rowCount + Self.maxColumns - 1) / Self.maxColumns) }

    var contentWidth: CGFloat {
        max(300, CGFloat(columns) * Self.tileWidth + CGFloat(columns - 1) * Self.tileSpacing)
    }

    var openSize: CGSize {
        CGSize(width: contentWidth + 2 * Self.topCorner + 20,
               height: closedSize.height + 80 + CGFloat(tileRows) * 84 + CGFloat(tileRows - 1) * Self.tileSpacing
                   + (hasRememberRow ? Self.rememberRowHeight : 0))
    }
}

/// What the panel asks, and how each row opens the link.
struct LinkPickerWording: Equatable {
    let question: String
    let rowHint: String

    let rememberHint: String

    static let profile = LinkPickerWording(question: String(localized: "Choose a Profile for this link"),
                                           rowHint: String(localized: "Opens the link in this Profile"),
                                           rememberHint: String(localized: "The next links from this site open in the Profile you choose, without asking"))
    static let space = LinkPickerWording(question: String(localized: "Choose a Space for this link"),
                                         rowHint: String(localized: "Opens the link in this Space"),
                                         rememberHint: String(localized: "The next links from this site open in the Profile and Space you choose, without asking"))
}

struct LinkPickerView<ID: Hashable & Sendable>: View {
    let model: LinkPickerModel<ID>
    let layout: LinkPickerLayout
    let wording: LinkPickerWording
    let choose: (ID) -> Void
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open = model.isOpen
        let shape = NotchShape(topCornerRadius: open ? LinkPickerLayout.topCorner : 6, bottomCornerRadius: open ? 24 : 14)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            content
                .frame(width: layout.contentWidth)
                .padding(.top, layout.closedSize.height + 4)
                .opacity(open ? 1 : 0)
                .blur(radius: open || reduceMotion ? 0 : 10)
                .scaleEffect(open || reduceMotion ? 1 : 0.85, anchor: .top)
        }
        .frame(width: open ? layout.openSize.width : layout.closedSize.width,
               height: open ? layout.openSize.height : layout.closedSize.height, alignment: .top)
        .clipShape(shape)
        .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 14, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: open ? 0.42 : 0.4, dampingFraction: open ? 0.8 : 1), value: open)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(wording.question)
    }

    private var content: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(verbatim: model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibleSummary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(LinkPickerLayout.tileWidth), spacing: LinkPickerLayout.tileSpacing),
                                     count: layout.columns), spacing: LinkPickerLayout.tileSpacing) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    tile(row, isHighlighted: model.highlightedIndex == index)
                }
            }
            rememberToggle
        }
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss the link"))
            .help(String(localized: "Dismiss the link (Esc)"))
        }
    }

    @ViewBuilder
    private var rememberToggle: some View {
        if let host = model.rememberedHost {
            Toggle(isOn: Binding(get: { model.remembers }, set: { model.setRemembers($0) })) {
                HStack(spacing: 6) {
                    Text("Always send links from \(host) here")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(verbatim: "A")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(String(localized: "Always send links from \(host) here"))
            .accessibilityHint(wording.rememberHint)
            .help(String(localized: "Creates a Link rule for \(host) (A)"))
        }
    }

    private var subtitle: String {
        guard let opener = model.openerName else { return model.detail }
        return String(localized: "from \(opener)") + "  ·  " + model.detail
    }

    private var accessibleSummary: String {
        if let opener = model.openerName {
            return String(localized: "Link to \(model.title), from \(opener)")
        }
        return String(localized: "Link to \(model.title)")
    }

    /// The number key, and "Open" in green when a Tab of this Profile already shows the link.
    private func keyLine(_ row: LinkPickerRow<ID>) -> Text {
        let key = Text(verbatim: row.numberKey.map(String.init) ?? " ").foregroundStyle(.white.opacity(0.5))
        guard row.isLinkOpen else { return key }
        return key + Text(verbatim: "  ·  ").foregroundStyle(.white.opacity(0.5))
            + Text("Open").foregroundStyle(Color.green)
    }

    private func tile(_ row: LinkPickerRow<ID>, isHighlighted: Bool) -> some View {
        Button { choose(row.id) } label: {
            VStack(spacing: 4) {
                Text(verbatim: row.symbol)
                    .font(.system(size: 30))
                Text(verbatim: row.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(isHighlighted ? 1 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                keyLine(row)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .padding(.vertical, 8)
            .frame(width: LinkPickerLayout.tileWidth, height: 84)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isHighlighted ? 0.2 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(isHighlighted ? 0.8 : 0), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.name)
        .accessibilityValue([row.numberKey.map { String(localized: "Key \(String($0))") },
                             row.isLinkOpen ? String(localized: "The link is already open here") : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(wording.rowHint)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}
