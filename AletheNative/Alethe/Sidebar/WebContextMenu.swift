import AletheDesign
import AppKit
import SwiftUI

@MainActor @Observable
final class WebMenuSession {
    struct Entry {
        let id: UUID
        let enabled: Bool
        let opensSubmenu: Bool
        let trigger: () -> Void
    }

    @ObservationIgnored var entries: [Entry] = []
    @ObservationIgnored weak var parent: WebMenuSession?
    var highlighted: UUID?
    var openSubmenu: UUID?
    @ObservationIgnored var child: WebMenuSession?

    func register(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
    }

    func unregister(_ id: UUID) {
        entries.removeAll { $0.id == id }
        if highlighted == id { highlighted = nil }
    }

    var active: WebMenuSession {
        if openSubmenu != nil, let child { return child.active }
        return self
    }

    func move(_ delta: Int) {
        let enabled = entries.filter(\.enabled)
        guard !enabled.isEmpty else { return }
        if let current = enabled.firstIndex(where: { $0.id == highlighted }) {
            highlighted = enabled[(current + delta + enabled.count) % enabled.count].id
        } else {
            highlighted = delta > 0 ? enabled.first?.id : enabled.last?.id
        }
    }

    func activateHighlighted() {
        guard let entry = entries.first(where: { $0.id == highlighted && $0.enabled }) else { return }
        entry.trigger()
    }
}

extension EnvironmentValues {
    @Entry var webMenuSession: WebMenuSession?
    @Entry var webMenuItemDanger = false
}

@MainActor @Observable
final class WebMenuHost {
    static let shared = WebMenuHost()

    enum Placement {
        case point(CGPoint)
        case anchor(CGRect, trailing: Bool)
    }

    struct Presentation: Identifiable {
        let id = UUID()
        let placement: Placement
        var content: AnyView
        var usesDefaultChrome = true
    }

    var presentation: Presentation?
    @ObservationIgnored var session: WebMenuSession?
    @ObservationIgnored var layerOrigin: CGPoint = .zero
    @ObservationIgnored weak var layerView: NSView?

    func present(at point: CGPoint, content: AnyView, usesDefaultChrome: Bool = true) {
        presentation = Presentation(placement: .point(point), content: content, usesDefaultChrome: usesDefaultChrome)
    }

    func present(anchor rect: CGRect, trailing: Bool, content: AnyView) {
        let local = rect.offsetBy(dx: -layerOrigin.x, dy: -layerOrigin.y)
        presentation = Presentation(placement: .anchor(local, trailing: trailing), content: content)
    }

    func dismiss() {
        guard presentation != nil else { return }
        presentation = nil
        session = nil
    }

    func activate(_ trigger: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.async(execute: trigger)
    }
}

struct WebMenuButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WebMenuItemView(configuration: configuration)
    }
}

private struct WebMenuItemView: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.webMenuSession) private var session
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var id = UUID()

    private var danger: Bool { configuration.role == .destructive }
    private var highlighted: Bool { isEnabled && session?.highlighted == id }

    var body: some View {
        let clean = metrics.style == .clean
        configuration.label
            .labelStyle(WebMenuLabelStyle())
            .environment(\.webMenuItemDanger, danger)
            .font(metrics.font(size: 13))
            .foregroundStyle(danger ? theme[.statusOffline] : theme[.fg])
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: clean ? metrics.size(30) : nil, alignment: .leading)
            .padding(.horizontal, metrics.size(clean ? 9 : 10))
            .padding(.vertical, metrics.size(clean ? 5 : 6))
            .background(
                RoundedRectangle(cornerRadius: clean ? metrics.size(4) : metrics.radius(.sm))
                    .fill(highlighted ? (danger ? theme[.statusOffline].opacity(0.12) : theme[.panelHover]) : .clear))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { inside in
                guard isEnabled, let session else { return }
                if inside {
                    session.highlighted = id
                    if session.openSubmenu != nil { session.openSubmenu = nil }
                } else if session.highlighted == id {
                    session.highlighted = nil
                }
            }
            .onTapGesture {
                guard isEnabled else { return }
                run()
            }
            .onAppear {
                session?.register(.init(id: id, enabled: isEnabled, opensSubmenu: false, trigger: run))
            }
            .onChange(of: isEnabled) {
                session?.register(.init(id: id, enabled: isEnabled, opensSubmenu: false, trigger: run))
            }
            .onDisappear { session?.unregister(id) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if isEnabled { run() } }
    }

    private func run() {
        let trigger = configuration.trigger
        WebMenuHost.shared.activate(trigger)
    }
}

struct WebMenuLabelStyle: LabelStyle {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @Environment(\.webMenuItemDanger) private var danger

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: metrics.size(8)) {
            configuration.icon
                .frame(width: metrics.size(15), height: metrics.size(15))
                .foregroundStyle(danger ? theme[.statusOffline] : theme[.fgMuted])
            configuration.title
        }
    }
}

struct WebMenuDivider: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme

    var body: some View {
        if metrics.isWebInterface {
            theme[.border]
                .frame(height: metrics.size(1))
                .padding(.vertical, metrics.size(4))
                .padding(.horizontal, metrics.size(2))
                .accessibilityHidden(true)
        } else {
            Divider()
        }
    }
}

struct WebSubmenu<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String?
    @ViewBuilder let content: () -> Content
    @Environment(\.webMenuSession) private var session
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var id = UUID()
    @State private var flyout = WebMenuSession()
    @State private var frame: CGRect = .zero
    @State private var flyoutSize: CGSize = .zero

    init(_ title: LocalizedStringKey, symbol: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content
    }

    private var isOpen: Bool { session?.openSubmenu == id }

    var body: some View {
        if metrics.isWebInterface, let session {
            row(session)
        } else {
            Menu(title, content: content)
        }
    }

    private func row(_ session: WebMenuSession) -> some View {
        let highlighted = isEnabled && (session.highlighted == id || isOpen)
        return HStack(spacing: metrics.size(8)) {
            if let symbol {
                Image(systemName: symbol).webProfileSized(14)
                    .frame(width: metrics.size(15), height: metrics.size(15))
                    .foregroundStyle(theme[.fgMuted])
            }
            Text(title).lineLimit(1)
            Spacer(minLength: metrics.size(12))
            Image(systemName: "chevron.right").webProfileSized(11)
                .foregroundStyle(theme[.fgMuted])
        }
        .font(metrics.font(size: 13))
        .foregroundStyle(theme[.fg])
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, metrics.size(10))
        .padding(.vertical, metrics.size(6))
        .background(RoundedRectangle(cornerRadius: metrics.radius(.sm))
            .fill(highlighted ? theme[.panelHover] : .clear))
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.5)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onHover { inside in
            guard isEnabled else { return }
            if inside { session.highlighted = id; open(session) }
        }
        .onTapGesture { if isEnabled { open(session) } }
        .onAppear { session.register(.init(id: id, enabled: isEnabled, opensSubmenu: true, trigger: { open(session) })) }
        .onDisappear { session.unregister(id) }
        .overlay(alignment: .topLeading) {
            if isOpen {
                flyoutPanel
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { flyoutSize = $0 }
                    .offset(x: flyoutOffsetX, y: -metrics.size(5))
                    .opacity(flyoutSize == .zero ? 0 : 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if isEnabled { open(session) } }
    }

    private var flyoutOffsetX: CGFloat {
        let host = WebMenuHost.shared
        let windowWidth = host.layerView?.bounds.width ?? .greatestFiniteMagnitude
        let right = frame.maxX - host.layerOrigin.x + metrics.size(2) + flyoutSize.width
        return right + metrics.size(8) > windowWidth ? -flyoutSize.width - metrics.size(2) : frame.width + metrics.size(2)
    }

    private var flyoutPanel: some View {
        WebMenuChrome {
            content()
        }
        .environment(\.webMenuSession, flyout)
    }

    private func open(_ session: WebMenuSession) {
        flyout.parent = session
        session.child = flyout
        session.openSubmenu = id
        flyout.highlighted = nil
        DispatchQueue.main.async { flyout.move(1) }
    }
}
