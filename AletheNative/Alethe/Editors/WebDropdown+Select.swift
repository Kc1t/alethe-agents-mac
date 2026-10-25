import AletheDesign
import SwiftUI

struct InterfaceSelect<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    let options: [Value]
    var appearance = WebSelectAppearance.standard
    var optionDisabled: (Value) -> Bool = { _ in false }
    var searchText: (Value) -> String = { String(describing: $0) }
    @ViewBuilder let label: (Value) -> Label
    @Environment(\.metrics) private var metrics

    var body: some View {
        if metrics.isWebInterface {
            WebDropdown(selection: $selection, options: options, appearance: appearance, searchText: searchText, optionDisabled: optionDisabled, label: label)
        } else {
            AletheSelect(selection: $selection, options: options, label: label)
        }
    }
}

struct WebSelectAppearance: Sendable {
    var height: CGFloat = 32
    var fontSize: CGFloat = 13
    var leading: CGFloat = 10
    var trailing: CGFloat = 9
    var background: ThemeToken = .bgSunken
    var radius: Metrics.Radius = .sm
    var raw = false
    var showsChevron = true

    static let standard = Self()
    static let input = Self(fontSize: 14, trailing: 10, radius: .md)
    static let pluginFilter = Self(fontSize: 12, leading: 6, trailing: 6, background: .bgElevated, raw: true, showsChevron: false)
    static let marketSort = Self(fontSize: 11, leading: 8, trailing: 8, raw: true, showsChevron: false)
    static let customAgent = Self(fontSize: 12, trailing: 10, background: .panel, radius: .md, raw: true, showsChevron: false)
    static let shortcut = Self(fontSize: 14, trailing: 10, radius: .md, raw: true)
}

enum WebDropdownMenuStyle: Equatable, Sendable {
    case standard, todo, homeAgent, homeMode

    var isHome: Bool { self == .homeAgent || self == .homeMode }
    var minimumWidth: CGFloat { self == .homeAgent ? 176 : self == .homeMode ? 132 : 220 }
    var maximumWidth: CGFloat { self == .homeAgent ? 176 : self == .todo ? 300 : 320 }
    var maximumHeight: CGFloat { self == .todo ? 240 : 280 }
    var optionHeight: CGFloat { self == .homeAgent ? 36 : self == .homeMode ? 28 : 30 }
    var gap: CGFloat { self == .todo ? 0 : self == .standard ? 1 : 3 }
    var padding: CGFloat { self == .homeAgent || self == .homeMode ? 5 : 4 }
}

struct WebChoiceActionLayer: ViewModifier {
    @Environment(\.metrics) private var metrics
    func body(content: Content) -> some View {
        if metrics.isWebInterface { content.modifier(WebContextMenuLayer()) } else { content }
    }
}

struct WebDropdownTriggerState: Sendable {
    let open: Bool
    let hovering: Bool
    let focused: Bool
}
