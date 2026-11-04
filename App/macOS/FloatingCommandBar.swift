// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit

/// The Command bar as a floating panel centred over the page, with its suggestions under the field. It covers the
/// page: a click anywhere outside the panel, in the page or in the rest of the window, asks to close it. The window
/// owns what Return, Escape and typing do; this view only lays the panel out and watches for outside clicks.
@MainActor
final class FloatingCommandBarView: NSView {
    /// A click landed outside the panel.
    var onOutsideClick: (() -> Void)?
    private(set) var isShown = false

    private let panel = NSView()
    private let effect = NSVisualEffectView()
    private var panelTop: NSLayoutConstraint?
    private var clickMonitor: Any?

    init(field: NSTextField, suggestions: NSView?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        isHidden = true
        setAccessibilityElement(false)

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.setAccessibilityElement(false)
        let fieldRow = NSStackView(views: [icon, field])
        fieldRow.orientation = .horizontal
        fieldRow.spacing = 10
        fieldRow.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        fieldRow.heightAnchor.constraint(equalToConstant: 52).isActive = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let separator = NSBox()
        separator.boxType = .separator

        var rows: [NSView] = [fieldRow]
        if let suggestions {
            rows += [separator, suggestions]
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        effect.material = .popover
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        effect.translatesAutoresizingMaskIntoConstraints = false

        // The glow around the panel lives on a view that does not clip, so the rounded effect view can.
        panel.wantsLayer = true
        panel.shadow = NSShadow()
        panel.layer?.shadowColor = NSColor.black.cgColor
        panel.layer?.shadowOpacity = 0.5
        panel.layer?.shadowRadius = 36
        panel.layer?.shadowOffset = .zero
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(effect)
        panel.setAccessibilityElement(false)
        addSubview(panel)

        let top = panel.topAnchor.constraint(equalTo: topAnchor)
        panelTop = top
        let preferredWidth = panel.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            top,
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            preferredWidth,
            panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 780),
            panel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
            effect.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            effect.topAnchor.constraint(equalTo: panel.topAnchor),
            effect.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Keeps the field in the upper third, so the panel does not move while suggestions come and go.
    override func layout() {
        panelTop?.constant = (bounds.height * 0.22).rounded()
        super.layout()
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        isHidden = false
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            // Delivered on the main thread, like every event of the application.
            MainActor.assumeIsolated { self?.watch(event) ?? event }
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        isHidden = true
        clickMonitor.map(NSEvent.removeMonitor)
        clickMonitor = nil
    }

    /// A click outside the panel closes it. One over the page is swallowed, so it never reaches the page behind; one
    /// elsewhere in the window (the sidebar) goes on to the control it landed on.
    private func watch(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        let point = convert(event.locationInWindow, from: nil)
        guard !panel.frame.contains(point) else { return event }
        onOutsideClick?()
        return bounds.contains(point) ? nil : event
    }
}
