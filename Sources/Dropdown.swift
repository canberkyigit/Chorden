import AppKit
import SwiftUI

// Chorden's own dropdowns: a quiet text button that opens a floating, themed panel instead of a
// system menu. Panels can nest (a dropdown inside Settings), and close on outside clicks or Esc.

/// Holds the AppKit view behind a SwiftUI button, so the panel can be placed under it.
final class AnchorBox { weak var view: NSView? }

private struct AnchorReader: NSViewRepresentable {
    let box: AnchorBox
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        box.view = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { box.view = nsView }
}

struct Dropdown<Label: View, Content: View>: View {
    var chevron = true
    /// Changing this value opens the dropdown programmatically (e.g. ⌘, for Settings).
    var trigger = 0
    @ViewBuilder var label: () -> Label
    @ViewBuilder var content: () -> Content

    @State private var anchor = AnchorBox()
    @State private var hover = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                label()
                if chevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.ghost)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hover ? Theme.line.opacity(0.55) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .background(AnchorReader(box: anchor))
        .onChange(of: trigger) { _ in toggle() }
    }

    private func toggle() {
        guard let view = anchor.view else { return }
        Dropdowns.shared.toggle(from: view, content: AnyView(content()))
    }
}

/// A selectable row with a checkmark and optional trailing detail (e.g. a tuning's notes).
struct DropdownItem: View {
    let title: String
    var detail: String? = nil
    let selected: Bool
    /// Optional favorite star; read live so toggling it updates while the panel stays open.
    var starred: (() -> Bool)? = nil
    var onStar: (() -> Void)? = nil
    let action: () -> Void
    @State private var hover = false
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.good)
                .opacity(selected ? 1 : 0)
                .frame(width: 10)
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(Theme.text)
                // ♭/♯ come from a fallback font and get under-measured; never truncate the title.
                .fixedSize()
            Spacer(minLength: 18)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .fixedSize()
            }
            if let starred, let onStar {
                let on = starred()
                Button(action: onStar) {
                    Image(systemName: on ? "star.fill" : "star")
                        .font(.system(size: 9))
                        .foregroundStyle(on ? Theme.warn : Theme.ghost)
                        .frame(width: 14, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(on || hover ? 1 : 0)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 26)
        .background(hover ? Theme.line.opacity(0.75) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            action()
            Dropdowns.shared.closeAll()
        }
    }
}

struct DropdownHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(Theme.ghost)
            .padding(.leading, 26)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Panels

final class DropdownPanel: NSPanel {
    weak var anchor: NSView?
    override var canBecomeKey: Bool { true }
}

private struct Chrome: View {
    let content: AnyView
    var height: CGFloat?

    var body: some View {
        Group {
            if let height {
                ScrollView { content.padding(5) }.frame(height: height)
            } else {
                content.padding(5)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

final class Dropdowns {
    static let shared = Dropdowns()
    private var stack: [DropdownPanel] = []
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var recentlyClosed: (anchors: [ObjectIdentifier], at: Date) = ([], .distantPast)

    var isOpen: Bool { !stack.isEmpty }
    func contains(_ window: NSWindow?) -> Bool { stack.contains { $0 === window } }

    func toggle(from anchor: NSView, content: AnyView) {
        // A click on the anchor of a panel that just closed (the mouse-down closed it) must not reopen it.
        if recentlyClosed.anchors.contains(ObjectIdentifier(anchor)),
           Date().timeIntervalSince(recentlyClosed.at) < 0.4 { return }
        if let i = stack.firstIndex(where: { $0.anchor === anchor }) { return close(from: i) }
        guard let parent = anchor.window, let screen = parent.screen ?? NSScreen.main else { return }
        close(from: stack.firstIndex { $0 === parent }.map { $0 + 1 } ?? 0)

        let anchorRect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = screen.visibleFrame
        // Measure at ideal size (fittingSize alone would compress and truncate the rows).
        var size = NSHostingView(rootView: Chrome(content: content).fixedSize()).fittingSize
        let below = anchorRect.minY - visible.minY - 12
        let above = visible.maxY - anchorRect.maxY - 12
        let room = max(below, above)
        let host: NSHostingView<Chrome>
        if size.height > room {
            size.height = room
            host = NSHostingView(rootView: Chrome(content: content, height: room))
        } else {
            host = NSHostingView(rootView: Chrome(content: content))
        }
        host.sizingOptions = []
        var origin = NSPoint(x: anchorRect.minX, y: anchorRect.minY - 4 - size.height)
        if size.height > below { origin.y = anchorRect.maxY + 4 }
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))

        let panel = DropdownPanel(contentRect: NSRect(origin: origin, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.anchor = anchor
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: max(parent.level.rawValue, NSWindow.Level.popUpMenu.rawValue) + 1)
        panel.appearance = parent.effectiveAppearance
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        stack.append(panel)
        installMonitors()
    }

    func closeAll() { close(from: 0) }

    private func close(from index: Int) {
        guard index < stack.count else { return }
        let closing = Array(stack[index...])
        recentlyClosed = (closing.compactMap { $0.anchor.map(ObjectIdentifier.init) }, Date())
        for p in closing.reversed() {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        }
        stack.removeSubrange(index...)
        if stack.isEmpty { removeMonitors() }
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            guard let self else { return e }
            // Clicking inside a panel closes only the panels opened from it.
            let i = self.stack.firstIndex { $0 === e.window }
            self.close(from: i.map { $0 + 1 } ?? 0)
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard let self, e.keyCode == 53, !self.stack.isEmpty else { return e }
            self.close(from: self.stack.count - 1)
            return nil
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.closeAll()
        }) { monitors.append(m) }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            self?.closeAll()
        })
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        observers.forEach(NotificationCenter.default.removeObserver)
        monitors = []
        observers = []
    }
}
