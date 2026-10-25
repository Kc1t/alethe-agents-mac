import AletheAgents
import AletheDesign
import AletheModel
import AppKit
import SwiftUI

struct HomeFooter: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    private static let repository = URL(string: "https://github.com/Kc1t/alethe-agents")!

    var body: some View {
        HStack(spacing: metrics.space(.xl)) {
            Link(destination: Self.repository) { Label { Text("home.repository") } icon: { Image(
                systemName: "chevron.left.forwardslash.chevron.right").webProfileSized(14) } }
            Link(destination: Self.repository.appending(path: "issues")) { Label { Text("home.issues") } icon: { Image(
                systemName: "smallcircle.filled.circle").webProfileSized(14) } }
            Link(destination: Self.repository.appending(path: "releases")) { Label { Text(
                "home.releases") } icon: { Image(systemName: "shippingbox").webProfileSized(14) } }
            Spacer(minLength: 0)
            if !metrics.isWebInterface {
                Button { environment.editorRequest = .findJump } label: { Text("home.footer.search") }
                Button { environment.editorRequest = .onboarding } label: { Text("home.footer.help") }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }
        .buttonStyle(.link)
        .font(metrics.isWebInterface ? metrics.monoFont(size: 10) : metrics.font(.footnote))
        .foregroundStyle(theme[.textTertiary])
        .padding(.top, metrics.isWebInterface ? metrics.size(14) : 0)
        .overlay(alignment: .top) {
            if metrics.isWebInterface { theme[.borderSubtle].frame(height: metrics.size(1)) }
        }
    }
}

struct HomeButton: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme

    var body: some View {
        Button { environment.toggleHome() } label: {
            Image(nsImage: Self.icon).webProfileSized(16)
                .foregroundStyle(environment.showingHome ? theme[.accent] : theme[.textSecondary])
        }
        .help(Text(environment.showingHome ? "menu.view.showWorkspace" : "menu.view.showHome"))
        .accessibilityLabel(Text("menu.view.showHome"))
        .accessibilityValue(Text(environment.showingHome ? "home.shown" : "home.hidden"))
        .accessibilityIdentifier("home.button")
    }

    private static let icon = templateBitmap("house")

    private static func templateBitmap(_ symbol: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return NSImage() }
        let size = glyph.size
        let scale: CGFloat = 2
        guard size.width > 0, size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int((size.width * scale).rounded(.up)),
                                            pixelsHigh: Int((size.height * scale).rounded(.up)),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return NSImage() }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        glyph.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}

extension AppEnvironment {
    func toggleHome() { showingHome.toggle() }
}

