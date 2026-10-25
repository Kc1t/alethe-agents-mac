import AletheDesign
import AppKit
import SwiftUI

final class WebMenuTriggerView: NSView {
    var content: (() -> AnyView)?
    nonisolated(unsafe) static let registry = NSHashTable<WebMenuTriggerView>.weakObjects()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { Self.registry.add(self) } else { Self.registry.remove(self) }
    }
}

private struct WebMenuTrigger: NSViewRepresentable {
    let content: () -> AnyView
    func makeNSView(context: Context) -> WebMenuTriggerView {
        let view = WebMenuTriggerView()
        view.content = content
        return view
    }
    func updateNSView(_ view: WebMenuTriggerView, context: Context) { view.content = content }
}

struct WebMenuMonitor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        context.coordinator.view = view
        context.coordinator.install()
        WebMenuHost.shared.layerView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { WebMenuHost.shared.layerView = view }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }

    final class MonitorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor final class Coordinator {
        weak var view: NSView?
        private var monitor: Any?
        private var resign: NSObjectProtocol?

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .keyDown]) { [weak self] event in
                nonisolated(unsafe) let unsafeEvent = event
                let consumed = MainActor.assumeIsolated { self?.handle(unsafeEvent) ?? false }
                return consumed ? nil : event
            }
            resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                            object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { WebMenuHost.shared.dismiss() }
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resign { NotificationCenter.default.removeObserver(resign) }
            monitor = nil
            resign = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard let view, let window = view.window, event.window === window else { return false }
            let host = WebMenuHost.shared
            if case .keyDown = event.type {
                return host.presentation != nil && key(event, host: host)
            } else if case .rightMouseDown = event.type {
                return rightClick(event, view: view, window: window, host: host)
            } else if event.type == .leftMouseDown && event.modifierFlags.contains(.control) {
                return rightClick(event, view: view, window: window, host: host)
            } else {
                return false
            }
        }

        private func rightClick(_ event: NSEvent, view: NSView, window: NSWindow, host: WebMenuHost) -> Bool {
            host.dismiss()
            var best: (WebMenuTriggerView, CGFloat)?
            for trigger in WebMenuTriggerView.registry.allObjects where trigger.window === window && !trigger.isHiddenOrHasHiddenAncestor {
                let local = trigger.convert(event.locationInWindow, from: nil)
                guard trigger.visibleRect.contains(local) else { continue }
                let area = trigger.bounds.width * trigger.bounds.height
                if best.map({ area < $0.1 }) ?? true { best = (trigger, area) }
            }
            guard let trigger = best?.0, let content = trigger.content else { return false }
            let point = view.convert(event.locationInWindow, from: nil)
            host.present(at: CGPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y),
                         content: content())
            return true
        }

        private func key(_ event: NSEvent, host: WebMenuHost) -> Bool {
            guard let root = host.session else { return false }
            let active = root.active
            if case 53 = event.keyCode {
                if let parent = active.parent { parent.openSubmenu = nil } else { host.dismiss() }
            } else if case 125 = event.keyCode {
                active.move(1)
            } else if case 126 = event.keyCode {
                active.move(-1)
            } else if case 48 = event.keyCode {
                active.move(event.modifierFlags.contains(.shift) ? -1 : 1)
            } else if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 {
                active.activateHighlighted()
            } else if case 124 = event.keyCode {
                if let entry = active.entries.first(where: { $0.id == active.highlighted && $0.opensSubmenu }) { entry.trigger() }
            } else if case 123 = event.keyCode {
                if let parent = active.parent { parent.openSubmenu = nil }
            } else {
                return false
            }
            return true
        }
    }
}

private struct WebContextMenuModifier<Menu: View>: ViewModifier {
    @ViewBuilder let menu: () -> Menu
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        if metrics.isWebInterface {
            content.background(WebMenuTrigger { AnyView(menu()) })
        } else {
            content.contextMenu { menu() }
        }
    }
}

extension View {
    func webContextMenu<Menu: View>(@ViewBuilder _ menu: @escaping () -> Menu) -> some View {
        modifier(WebContextMenuModifier(menu: menu))
    }
}

struct WebMenu<Content: View, Label: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label
    var trailing = false
    @Environment(\.metrics) private var metrics
    @State private var frame: CGRect = .zero

    var body: some View {
        if metrics.isWebInterface {
            Button {
                WebMenuHost.shared.present(anchor: frame, trailing: trailing, content: AnyView(content()))
            } label: { label() }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        } else {
            Menu(content: content, label: label)
        }
    }
}
