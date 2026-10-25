import AletheDesign
import AppKit
import SwiftUI

struct WebContextMenuLayer: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay { WebContextMenuLayerBody() }
    }
}

private struct WebContextMenuLayerBody: View {
    private let host = WebMenuHost.shared
    @State private var origin: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let presentation = host.presentation {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { host.dismiss() }
                        .accessibilityHidden(true)
                    WebMenuPanel(presentation: presentation, bounds: geometry.size)
                        .id(presentation.id)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: {
                origin = $0
                host.layerOrigin = $0
            }
        }
        .background(WebMenuMonitor())
        .allowsHitTesting(host.presentation != nil)
    }
}

private struct WebMenuPanel: View {
    let presentation: WebMenuHost.Presentation
    let bounds: CGSize
    @Environment(\.metrics) private var metrics
    @State private var session = WebMenuSession()
    @State private var size: CGSize = .zero
    @State private var shown = false

    var body: some View {
        let margin = metrics.size(presentation.usesDefaultChrome ? 8 : 10)
        let spot = position(margin: margin)
        let clean = metrics.style == .clean
        panelContent
            .environment(\.webMenuSession, session)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .scaleEffect(clean && !shown ? 0.96 : 1, anchor: .topLeading)
            .opacity(size == .zero || (clean && !shown) ? 0 : 1)
            .offset(x: spot.x, y: spot.y)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("web.contextMenu")
            .onAppear {
                WebMenuHost.shared.session = session
                withAnimation(metrics.reducesMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.18)) { shown = true }
            }
    }

    @ViewBuilder private var panelContent: some View {
        if presentation.usesDefaultChrome {
            WebMenuChrome { presentation.content }
        } else {
            presentation.content
        }
    }

    private func position(margin: CGFloat) -> CGPoint {
        var x: CGFloat = 0
        var y: CGFloat = 0
        if case let .point(point) = presentation.placement {
            x = point.x
            y = point.y
        } else if case let .anchor(rect, trailing) = presentation.placement {
            x = trailing ? rect.maxX - size.width : rect.minX
            y = rect.maxY + metrics.size(4)
            if y + size.height + margin > bounds.height, rect.minY - metrics.size(4) - size.height >= margin {
                y = rect.minY - metrics.size(4) - size.height
            }
        }
        x = max(margin, min(x, bounds.width - size.width - margin))
        y = max(margin, min(y, bounds.height - size.height - margin))
        return CGPoint(x: x, y: y)
    }
}
