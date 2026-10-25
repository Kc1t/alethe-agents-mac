import AletheFoundation
import AletheModel
import AppKit

@MainActor
enum AppIcon {
    private static var applied: AppIconTheme?

    static func image(for theme: AppIconTheme) -> NSImage? {
        NSImage(named: theme.assetName)
    }

    static func apply(_ theme: AppIconTheme) {
        guard theme != applied else { return }
        if theme == .default {
            NSApp.applicationIconImage = AppIdentity.isDebugBuild
                ? Bundle.main.url(forResource: "AppIconDebug", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
                : nil
        } else {
            guard let image = image(for: theme) else { return }
            NSApp.applicationIconImage = dockImage(image)
        }
        applied = theme
    }

    private static func dockImage(_ art: NSImage) -> NSImage {
        let canvas = NSSize(width: 1024, height: 1024)
        return NSImage(size: canvas, flipped: false) { rect in
            let side = rect.width * 824 / 1024
            let frame = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 10 / 1024)
            shadow.shadowBlurRadius = rect.width * 24 / 1024
            shadow.set()
            art.draw(in: frame)
            if AppIdentity.isDebugBuild { drawDebugBand(in: frame) }
            return true
        }
    }
}

extension AppIcon {
    fileprivate static func drawDebugBand(in frame: NSRect) {
        let band = NSRect(x: frame.minX, y: frame.minY + frame.height * 0.20, width: frame.width, height: frame.height * 0.20)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: frame.width * 0.225, yRadius: frame.width * 0.225).addClip()
        NSColor.systemRed.setFill()
        band.fill()
        let font = NSFont.systemFont(ofSize: band.height * 0.62, weight: .heavy)
        let text = NSAttributedString(string: "DEBUG", attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = text.size()
        text.draw(at: NSPoint(x: band.midX - size.width / 2, y: band.midY - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension AppEnvironment {
    func followAppIcon() {
        let theme = withObservationTracking {
            preferences?.document.iconTheme ?? .default
        } onChange: { [weak self] in
            Task { @MainActor in self?.followAppIcon() }
        }
        AppIcon.apply(theme)
    }
}
