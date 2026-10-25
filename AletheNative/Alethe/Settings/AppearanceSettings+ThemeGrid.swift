import AletheDesign
import AletheFoundation
import AletheModel
import AlethePluginKit
import SwiftUI

struct ThemeGrid: View {
    var webMinimum: CGFloat = 150
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    private var themes: [Theme] {
        let catalog = environment.themeCatalog
        let builtin = ThemeCatalog.builtinOrder.compactMap { catalog.theme(id: $0) }
        let ids = Set(builtin.map(\.id))
        return builtin + catalog.themes.filter { !ids.contains($0.id) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.size(metrics.isWebInterface ? webMinimum : 100)),
            spacing: metrics.size(metrics.isWebInterface ? 10 : 12))],
                  spacing: metrics.size(metrics.isWebInterface ? 10 : 12)) {
            ForEach(themes) { option in
                if metrics.isWebInterface { webTile(option) } else { tile(option) }
            }
        }
        .padding(.vertical, metrics.space(.xs))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.theme")
    }

    private func webTile(_ option: Theme) -> some View {
        let selected = option.id == theme.id
        return Button {
            environment.preferences?.update { $0.themeID = option.id }
        } label: {
            VStack(alignment: .leading, spacing: metrics.size(8)) {
                HStack(spacing: metrics.size(4)) {
                    ForEach(Array(option.swatch.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: metrics.size(4))
                            .fill(color.color)
                            .frame(width: metrics.size(25), height: metrics.size(17))
                            .overlay(RoundedRectangle(cornerRadius: metrics.size(4))
                                .strokeBorder(theme[.fg].opacity(0.16), lineWidth: metrics.size(1)))
                    }
                }
                HStack(spacing: metrics.size(8)) {
                    option.localizedName.font(metrics.font(size: 12))
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark").webProfileSized(15).font(metrics.font(size: 15)) }
                }
                if let summary = option.localizedSummary {
                    summary.font(metrics.font(size: 10))
                        .foregroundStyle(theme[.fgMuted])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(metrics.size(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme[selected ? .accentFaint : .bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                .strokeBorder(theme[selected ? .accent : .border], lineWidth: metrics.size(1)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(Text(verbatim: selected ? "1" : "0"))
        .accessibilityIdentifier("settings.theme.\(option.id)")
    }

    private func tile(_ option: Theme) -> some View {
        let isSelected = option.id == theme.id
        return Button {
            environment.preferences?.update { $0.themeID = option.id }
        } label: {
            VStack(spacing: metrics.space(.xs)) {
                HStack(spacing: 0) {
                    ForEach(Array(option.swatch.enumerated()), id: \.offset) { _, color in
                        Rectangle().fill(color.color)
                    }
                }
                .frame(height: metrics.size(34))
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius(.md)))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.radius(.md))
                        .strokeBorder(isSelected ? theme[.accent] : theme[.borderSubtle], lineWidth: metrics.size(isSelected ? 2 : 1))
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
        .help(option.localizedSummary ?? option.localizedName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(Text(verbatim: isSelected ? "1" : "0"))
        .accessibilityIdentifier("settings.theme.\(option.id)")
    }
}
