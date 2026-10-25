import AletheDesign
import AletheFoundation
import AletheModel
import AlethePluginKit
import SwiftUI

struct AppIconGrid: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    private var current: AppIconTheme { environment.preferences?.document.iconTheme ?? .default }

    var body: some View {
        if metrics.isWebInterface { webBody } else { nativeBody }
    }

    private var nativeBody: some View {
        HStack(spacing: metrics.space(.l)) {
            ForEach(AppIconTheme.allCases, id: \.self) { tile($0) }
            Spacer(minLength: 0)
        }
        .padding(.vertical, metrics.space(.xs))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.appIcon")
    }

    private var webBody: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.size(90)), spacing: metrics.space(.l))], spacing: metrics.space(.l)) {
            ForEach(AppIconTheme.allCases, id: \.self) { tile($0) }
        }
        .padding(.vertical, metrics.space(.xs))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.appIcon")
    }

    private func tile(_ option: AppIconTheme) -> some View {
        let isSelected = option == current
        return Button {
            environment.preferences?.update { $0.iconTheme = option }
        } label: {
            VStack(spacing: metrics.space(.xs)) {
                Group {
                    if let image = AppIcon.image(for: option) {
                        Image(nsImage: image).resizable().interpolation(.high).webProfileSized(56)
                    } else {
                        Image(systemName: "app").webProfileSized(56)
                    }
                }
                .frame(width: metrics.size(56), height: metrics.size(56))
                .padding(metrics.space(.xxs))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.radius(.lg))
                        .strokeBorder(isSelected ? theme[.accent] : .clear, lineWidth: metrics.size(2))
                }
                option.localizedName
                    .font((metrics.isWebInterface ? metrics.font(size: 10) : metrics.font(.footnote)))
                    .foregroundStyle(isSelected ? theme[.textPrimary] : theme[.textSecondary])
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(Text(verbatim: isSelected ? "1" : "0"))
        .accessibilityIdentifier("settings.appIcon.\(option.rawValue)")
    }
}
