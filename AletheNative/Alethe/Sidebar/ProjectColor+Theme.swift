import AletheDesign
import AletheModel
import SwiftUI

extension ProjectColor {
    var token: ThemeToken {
        if case .orange = self {
            return .projectOrange
        } else if case .pink = self {
            return .projectPink
        } else if case .purple = self {
            return .projectPurple
        } else if case .blue = self {
            return .projectBlue
        } else if case .teal = self {
            return .projectTeal
        } else if case .green = self {
            return .projectGreen
        } else if case .yellow = self {
            return .projectYellow
        } else if case .red = self {
            return .projectRed
        } else if case .gray = self {
            return .projectGray
        } else {
            return .projectBlack
        }
    }

    var localizedName: LocalizedStringKey {
        if case .orange = self {
            return "color.orange"
        } else if case .pink = self {
            return "color.pink"
        } else if case .purple = self {
            return "color.purple"
        } else if case .blue = self {
            return "color.blue"
        } else if case .teal = self {
            return "color.teal"
        } else if case .green = self {
            return "color.green"
        } else if case .yellow = self {
            return "color.yellow"
        } else if case .red = self {
            return "color.red"
        } else if case .gray = self {
            return "color.gray"
        } else {
            return "color.black"
        }
    }

    static func next(after count: Int) -> ProjectColor {
        allCases[count % allCases.count]
    }
}
