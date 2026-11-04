// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SwiftUI
import ThemeStandIn

extension Text {
    /// The text in a type role: its font, tracking and case.
    public func role(_ role: TextRole) -> some View {
        font(role.font).tracking(role.tracking).textCase(role.uppercased ? .uppercase : nil)
    }
}

/// The window's frame: the plain background, then the Theme's gradient over it, and an optional glow. A flat layer;
/// only a change of Theme animates it.
public struct FrameBackground: View {
    @Environment(\.designTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ColorRolesReader { roles in
            let frame = tokens.frame
            Rectangle()
                .fill(.background)
                .overlay {
                    switch frame.axis {
                    case .vertical:
                        LinearGradient(stops: roles.frameStops, startPoint: .top, endPoint: .bottom)
                    case .diagonal:
                        LinearGradient(stops: roles.frameStops, startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .overlay {
                    if frame.glow > 0 {
                        GeometryReader { proxy in
                            RadialGradient(
                                colors: [roles.theme.secondary.color.opacity(frame.glow), .clear],
                                center: .topTrailing, startRadius: 0,
                                endRadius: max(proxy.size.width, proxy.size.height) * 0.6)
                        }
                    }
                }
                .animation(MotionRole.themeChange.animation(reduceMotion: reduceMotion), value: roles.theme)
                .accessibilityHidden(true)
        }
    }
}

/// Content inset in the frame with rounded corners, a hairline and the page's shadow.
public struct InsetPage<Content: View>: View {
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var contrast
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.radius.page, style: .continuous)
        content
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    contrast == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.separator),
                    lineWidth: contrast == .increased ? DesignTokens.Size.contrastStroke : DesignTokens.Size.hairline)
            }
            .shadow(color: .black.opacity(tokens.emphasis.pageShadow), radius: tokens.spacing.pageInset, y: DesignTokens.Spacing.xxs)
    }
}

/// A square tile with a glyph, the leading element of rows.
public struct Tile: View {
    @Environment(\.designTokens) private var tokens
    let systemImage: String
    let color: Color

    public init(systemImage: String, color: Color) {
        self.systemImage = systemImage
        self.color = color
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: tokens.radius.tile, style: .continuous)
            .fill(color)
            .frame(width: tokens.size.tile, height: tokens.size.tile)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: tokens.size.glyph, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// The interaction state of a row.
public struct RowState: Sendable, Equatable {
    public var isSelected: Bool
    public var isHovered: Bool

    public init(isSelected: Bool = false, isHovered: Bool = false) {
        self.isSelected = isSelected
        self.isHovered = isHovered
    }
}

/// A list row in a column: a leading tile, a title, a trailing accessory; its fill shows hover and selection and never
/// touches the neighbouring row's. `indent` counts levels of nesting.
public struct ListRow<Leading: View, Trailing: View>: View {
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let state: RowState
    let indent: Int
    let leading: Leading
    let trailing: Trailing

    public init(
        _ title: String, state: RowState = RowState(), indent: Int = 0,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.state = state
        self.indent = indent
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        let spacing = tokens.spacing
        let shape = RoundedRectangle(cornerRadius: tokens.radius.row, style: .continuous)
        ColorRolesReader { roles in
            HStack(spacing: spacing.tileToText) {
                leading
                Text(title)
                    .role(state.isSelected ? tokens.type.rowSelected : tokens.type.row)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                trailing
            }
            .padding(.leading, CGFloat(indent) * spacing.listMargin)
            .padding(.horizontal, spacing.rowInsetHorizontal)
            .frame(minHeight: tokens.size.row - spacing.rowGap)
            .background {
                shape.fill(fill(roles))
                    .shadow(color: liftShadow, radius: DesignTokens.Spacing.xxs, y: DesignTokens.Size.hairline)
            }
            .overlay {
                if contrast == .increased && state.isSelected {
                    shape.strokeBorder(.secondary, lineWidth: DesignTokens.Size.contrastStroke)
                }
            }
            .padding(.horizontal, spacing.listMargin - spacing.rowInsetHorizontal)
            .padding(.vertical, spacing.rowGap / 2)
            .contentShape(.rect)
            .animation(MotionRole.hoverFill.animation(reduceMotion: reduceMotion), value: state)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(state.isSelected ? [.isSelected, .isButton] : .isButton)
        }
    }

    private func fill(_ roles: ColorRoles) -> Color {
        if state.isSelected { return roles.selectionFill }
        if state.isHovered { return roles.hoverFill }
        return .clear
    }

    private var liftShadow: Color {
        tokens.materials.selection == .lift && state.isSelected ? .black.opacity(tokens.emphasis.hover) : .clear
    }
}

/// A short label over a group of rows.
public struct SectionHeader: View {
    @Environment(\.designTokens) private var tokens
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .role(tokens.type.sectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, tokens.spacing.listMargin)
            .padding(.bottom, tokens.spacing.sectionHeaderBottom)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A thin rule across a column, aligned on its margin.
public struct ColumnDivider: View {
    @Environment(\.designTokens) private var tokens

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: DesignTokens.Size.hairline)
            .padding(.horizontal, tokens.spacing.listMargin)
            .padding(.vertical, tokens.spacing.rowGap)
            .accessibilityHidden(true)
    }
}

/// A symbol-only button in a pointer target of at least `Size.minTarget`; the title is its VoiceOver label and help.
public struct IconButton: View {
    @Environment(\.designTokens) private var tokens
    let title: String
    let systemImage: String
    let action: () -> Void

    public init(_ title: String, systemImage: String, action: @escaping () -> Void = {}) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .frame(width: tokens.size.toolbarButton, height: tokens.size.toolbarButton)
                .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityStyle())
        .foregroundStyle(.secondary)
        .help(title)
    }
}

/// A plain button style whose label dims while pressed.
public struct PressedOpacityStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// A capsule push button: `.prominent` fills with the tint (red when destructive), `.standard` with the layer fill.
/// Drawn by the kit so it reads the same in a key or an inactive window; the system glass styles stay available.
public struct CapsuleButtonStyle: ButtonStyle {
    public enum Prominence: Sendable { case standard, prominent }
    let prominence: Prominence

    public init(_ prominence: Prominence) {
        self.prominence = prominence
    }

    public func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, prominence: prominence)
    }
}

private struct CapsuleButtonBody: View {
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var contrast
    let configuration: ButtonStyleConfiguration
    let prominence: CapsuleButtonStyle.Prominence

    var body: some View {
        let isDestructive = configuration.role == .destructive
        configuration.label
            .font(tokens.type.banner.font.weight(.medium))
            .foregroundStyle(prominence == .prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, DesignTokens.Spacing.l)
            .frame(minHeight: DesignTokens.Size.minTarget)
            .background {
                Capsule(style: .continuous).fill(
                    prominence == .prominent
                        ? AnyShapeStyle(isDestructive ? Color.red : Color.accentColor)
                        : AnyShapeStyle(Color.primary.opacity(tokens.emphasis.contrasted(tokens.emphasis.hover, contrast))))
            }
            .overlay {
                if contrast == .increased {
                    Capsule(style: .continuous).strokeBorder(.secondary, lineWidth: DesignTokens.Size.contrastStroke)
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.capsule)
    }
}

/// A field-like pill: one line of text (or nothing), trailing accessories, on the direction's pill surface.
public struct FieldPill<Trailing: View>: View {
    @Environment(\.designTokens) private var tokens
    let text: String?
    let label: String
    let trailing: Trailing

    public init(_ text: String?, label: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = text
        self.label = label
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: tokens.spacing.tileToText) {
            Text(text ?? "")
                .role(tokens.type.pill)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, tokens.spacing.listMargin)
        .frame(height: tokens.size.pill)
        .surface(tokens.materials.pill, in: TokenShape(radius: tokens.radius.pill))
        .padding(.horizontal, tokens.spacing.listMargin - tokens.spacing.rowInsetHorizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(text ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// One item of a glass switcher.
public struct SwitcherItem: Identifiable, Sendable {
    public let id: String
    public let label: String
    /// An emoji or a short symbol drawn as text.
    public let glyph: String

    public init(id: String, label: String, glyph: String) {
        self.id = id
        self.label = label
        self.glyph = glyph
    }
}

/// A row of glyphs on glass; the selected item becomes a tinted capsule showing its label. Shapes merge and morph
/// inside one `GlassEffectContainer`.
public struct GlassSwitcher: View {
    @Environment(\.designTokens) private var tokens
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Namespace private var namespace
    let items: [SwitcherItem]
    let selection: String
    let label: String

    public init(_ items: [SwitcherItem], selection: String, label: String) {
        self.items = items
        self.selection = selection
        self.label = label
    }

    public var body: some View {
        ColorRolesReader { roles in
            GlassEffectContainer(spacing: tokens.spacing.glassMerge) {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(items) { item in
                        itemView(item, isSelected: item.id == selection, roles: roles)
                    }
                }
                .padding(DesignTokens.Spacing.xxs)
                .surface(tokens.materials.switcher, in: Capsule(style: .continuous))
            }
            .animation(MotionRole.themeChange.animation(reduceMotion: reduceMotion), value: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }
    }

    private func itemView(_ item: SwitcherItem, isSelected: Bool, roles: ColorRoles) -> some View {
        Button {} label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(item.glyph)
                if isSelected {
                    Text(item.label).role(tokens.type.switcherLabel).lineLimit(1)
                }
            }
            .padding(.horizontal, isSelected ? tokens.spacing.rowInsetHorizontal : 0)
            .frame(minWidth: tokens.size.switcherItem, minHeight: tokens.size.switcherHeight)
            .contentShape(.capsule)
        }
        .buttonStyle(PressedOpacityStyle())
        .glassEffect(isSelected && !reduceTransparency ? .regular.tint(roles.glassTint) : .identity, in: .capsule)
        .glassEffectID(item.id, in: namespace)
        .background {
            if isSelected && reduceTransparency {
                Capsule().fill(roles.tint.opacity(tokens.emphasis.contrasted(tokens.emphasis.glassTint, contrast)))
            }
        }
        .help(item.label)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A panel floating over content: a field on top, rows under it, on the direction's panel surface with a veil for
/// legibility and an optional Theme-coloured glow.
public struct FloatingPanel<Field: View, Rows: View>: View {
    @Environment(\.designTokens) private var tokens
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let field: Field
    let rows: Rows

    public init(@ViewBuilder field: () -> Field, @ViewBuilder rows: () -> Rows) {
        self.field = field()
        self.rows = rows()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.radius.panel, style: .continuous)
        ColorRolesReader { roles in
            VStack(spacing: 0) {
                field
                    .padding(.vertical, tokens.spacing.panelFieldVertical)
                    .padding(.horizontal, tokens.spacing.panelFieldHorizontal)
                Rectangle().fill(.separator).frame(height: DesignTokens.Size.hairline)
                    .padding(.horizontal, tokens.spacing.panelInset)
                VStack(spacing: 0) { rows }
                    .padding(tokens.spacing.panelInset)
            }
            .frame(width: tokens.size.panelWidth)
            .background {
                if tokens.emphasis.panelVeil > 0 && !reduceTransparency {
                    shape.fill(.background.opacity(tokens.emphasis.panelVeil))
                }
            }
            .surface(tokens.materials.panel, in: shape)
            .shadow(color: roles.tint.opacity(tokens.emphasis.panelGlow), radius: tokens.radius.panel * 2)
            .shadow(color: .black.opacity(tokens.emphasis.pageShadow), radius: tokens.spacing.pageInset * 2, y: DesignTokens.Spacing.xs)
        }
    }
}

/// The field at the top of a floating panel; `isAllSelected` draws its text as a selection.
public struct PanelField: View {
    @Environment(\.designTokens) private var tokens
    let text: String
    let isAllSelected: Bool

    public init(_ text: String, isAllSelected: Bool) {
        self.text = text
        self.isAllSelected = isAllSelected
    }

    public var body: some View {
        HStack(spacing: tokens.spacing.panelFieldVertical) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text)
                .role(tokens.type.panelField)
                .lineLimit(1)
                .padding(.horizontal, DesignTokens.Spacing.xxs)
                .background {
                    if isAllSelected {
                        RoundedRectangle(cornerRadius: DesignTokens.Spacing.xxs).fill(Color.accentColor.opacity(tokens.emphasis.glassTint))
                    }
                }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A suggestion row of a floating panel: tile, title, an optional detail after an en dash, an optional trailing action.
public struct PanelRow<Leading: View>: View {
    @Environment(\.designTokens) private var tokens
    let title: String
    let detail: String?
    let action: String?
    let isSelected: Bool
    let leading: Leading

    public init(_ title: String, detail: String? = nil, action: String? = nil, isSelected: Bool = false, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.detail = detail
        self.action = action
        self.isSelected = isSelected
        self.leading = leading()
    }

    public var body: some View {
        ColorRolesReader { roles in
            HStack(spacing: tokens.spacing.tileToText) {
                leading
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(title).role(tokens.type.panelTitle).lineLimit(1)
                    if let detail {
                        Text(verbatim: "—").foregroundStyle(.tertiary)
                        Text(detail).role(tokens.type.panelDetail).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let action {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(action).role(tokens.type.panelAction)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .padding(DesignTokens.Spacing.xxs)
                            .background(RoundedRectangle(cornerRadius: tokens.radius.tile, style: .continuous).fill(.quaternary))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, tokens.spacing.rowInsetHorizontal)
            .frame(height: tokens.size.panelRow)
            .background {
                RoundedRectangle(cornerRadius: tokens.radius.panel - tokens.spacing.panelInset, style: .continuous)
                    .fill(isSelected ? roles.selectionFill : .clear)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        }
    }
}

/// A discreet one-line message with an action and a close button, floating on glass.
public struct Banner: View {
    @Environment(\.designTokens) private var tokens
    let systemImage: String
    let message: String
    let actionTitle: String

    public init(systemImage: String, message: String, actionTitle: String) {
        self.systemImage = systemImage
        self.message = message
        self.actionTitle = actionTitle
    }

    public var body: some View {
        HStack(spacing: tokens.spacing.tileToText) {
            Image(systemName: systemImage).foregroundStyle(.tint).accessibilityHidden(true)
            Text(message).role(tokens.type.banner).lineLimit(1)
            Button(actionTitle) {}
                .buttonStyle(CapsuleButtonStyle(.standard))
            Button {} label: {
                Label(String(localized: "Close"), systemImage: "xmark").labelStyle(.iconOnly).font(.caption.weight(.bold))
                    .frame(width: DesignTokens.Size.minTarget * 0.75, height: DesignTokens.Size.minTarget * 0.75)
                    .contentShape(.rect)
            }
            .buttonStyle(PressedOpacityStyle())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, tokens.spacing.bannerVertical)
        .padding(.leading, tokens.spacing.bannerHorizontal)
        .padding(.trailing, tokens.spacing.bannerVertical)
        .surface(tokens.materials.banner, in: TokenShape(radius: tokens.radius.banner))
        .accessibilityElement(children: .contain)
    }
}

/// A confirmation laid out as a sheet: symbol, title, message, then Cancel and the confirming action trailing.
public struct ConfirmationCard: View {
    @Environment(\.designTokens) private var tokens
    let systemImage: String
    let title: String
    let message: String
    let confirmTitle: String
    let isDestructive: Bool

    public init(systemImage: String, title: String, message: String, confirmTitle: String, isDestructive: Bool) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.radius.sheet, style: .continuous)
        VStack(alignment: .leading, spacing: tokens.spacing.groupGap) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).role(tokens.type.sheetTitle)
            Text(message).role(tokens.type.sheetBody).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DesignTokens.Spacing.s) {
                Spacer()
                Button(String(localized: "Cancel")) {}
                    .buttonStyle(CapsuleButtonStyle(.standard))
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: isDestructive ? .destructive : nil) {}
                    .buttonStyle(CapsuleButtonStyle(.prominent))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, tokens.spacing.rowGap)
        }
        .padding(tokens.spacing.sheetMargin)
        .frame(width: tokens.size.sheetWidth, alignment: .leading)
        .background { shape.fill(.background) }
        .surface(.glass(tint: 0), in: shape)
        .shadow(color: .black.opacity(tokens.emphasis.pageShadow * 2), radius: tokens.spacing.sheetMargin, y: DesignTokens.Spacing.s)
    }
}
