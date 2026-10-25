import AppKit
import CoreText
import SwiftUI

public enum TextStyle: CaseIterable, Sendable {
    case caption, footnote, body, headline, title3, title2, title1, largeTitle

    var size: CGFloat {
        switch self {
        case .caption: 10
        case .footnote: 11
        case .body: 13
        case .headline: 13
        case .title3: 15
        case .title2: 17
        case .title1: 22
        case .largeTitle: 26
        }
    }

    var weight: Font.Weight {
        switch self {
        case .headline: .semibold
        case .title1, .title2, .title3, .largeTitle: .bold
        default: .regular
        }
    }

    var leading: CGFloat {
        switch self {
        case .caption, .footnote, .body: 0.25
        case .headline, .title3: 0.2
        case .title2, .title1: 0.12
        case .largeTitle: 0.06
        }
    }
}

extension Metrics {
    public func font(_ style: TextStyle) -> Font {
        .system(size: style.size * scale, weight: style.weight)
    }

    public func font(_ style: TextStyle, zoom: CGFloat) -> Font {
        .system(size: style.size * scale * zoom, weight: style.weight)
    }

    public func lineSpacing(_ style: TextStyle) -> CGFloat {
        style.size * scale * style.leading
    }

    public func monoFont(size: CGFloat = 13) -> Font {
        .custom(AletheFonts.terminalFamily, size: size * scale)
    }
}

extension View {
    public func textStyle(_ style: TextStyle, metrics: Metrics) -> some View {
        font(metrics.font(style)).lineSpacing(metrics.lineSpacing(style))
    }
}

public enum AletheFonts {
    public static let terminalFamily = "CaskaydiaCove Nerd Font Mono"

    private static let registration: Bool = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") else {
            return false
        }
        var ok = true
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
                if code != CTFontManagerError.alreadyRegistered.rawValue { ok = false }
            }
        }
        return ok
    }()

    public static func bundledFontURL(named fileName: String) -> URL? {
        Bundle.module.url(forResource: fileName, withExtension: nil, subdirectory: "Fonts")
    }

    @discardableResult
    public static func registerBundledFonts() -> Bool { registration }
}
