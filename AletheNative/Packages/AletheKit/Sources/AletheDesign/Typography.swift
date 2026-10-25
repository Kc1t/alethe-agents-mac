import AppKit
import CoreText
import SwiftUI

public enum TextStyle: CaseIterable, Sendable {
    case caption, footnote, body, headline, title3, title2, title1, largeTitle

    var size: CGFloat {
        if case .caption = self {
            return 10
        } else if case .footnote = self {
            return 11
        } else if case .body = self {
            return 13
        } else if case .headline = self {
            return 13
        } else if case .title3 = self {
            return 15
        } else if case .title2 = self {
            return 17
        } else if case .title1 = self {
            return 22
        } else {
            return 26
        }
    }

    var weight: Font.Weight {
        if case .headline = self {
            return .semibold
        } else if case .title1 = self {
            return .bold
        } else if case .title2 = self {
            return .bold
        } else if case .title3 = self {
            return .bold
        } else if case .largeTitle = self {
            return .bold
        } else {
            return .regular
        }
    }

    var leading: CGFloat {
        if case .caption = self {
            return 0.25
        } else if case .footnote = self {
            return 0.25
        } else if case .body = self {
            return 0.25
        } else if case .headline = self {
            return 0.2
        } else if case .title3 = self {
            return 0.2
        } else if case .title2 = self {
            return 0.12
        } else if case .title1 = self {
            return 0.12
        } else {
            return 0.06
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
