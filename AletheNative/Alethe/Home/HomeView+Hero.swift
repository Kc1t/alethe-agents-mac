import AletheAgents
import AletheDesign
import AletheModel
import AppKit
import SwiftUI

struct HomeHero: View {
    @AppStorage("sidebar.web.avatarImages") private var avatarImages = "{}"
    let streak: Int
    var availableWidth: CGFloat = .infinity
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: metrics.size(7)) {
                if metrics.isWebInterface {
                    avatar
                        .frame(width: metrics.size(116), height: metrics.size(46))
                        .overlay(alignment: .center) {
                            WebHomeNowPlaying(homeDockInfoWidth: min(metrics.size(126), max(0, availableWidth / 2 - metrics.size(69))))
                                .fixedSize()
                                .frame(width: 0, alignment: .leading)
                                .offset(x: metrics.size(21))
                        }
                        .padding(.bottom, metrics.size(4))
                } else { ViewThatFits(in: .horizontal) {
                    HStack(spacing: metrics.space(.xl)) {
                        avatar
                        NowPlayingCard()
                    }
                    VStack(spacing: metrics.space(.m)) {
                        avatar
                        NowPlayingCard()
                    }
                }
                }
                Text(verbatim: "\(greeting(context.date)), \(metrics.isWebInterface ? firstName.lowercased() : firstName).")
                    .font(metrics.font(size: metrics.isWebInterface
                                       ? max(25, min(34, (NSApp.keyWindow?.frame.width ?? availableWidth) / metrics.scale * 0.03))
                                       : 34, weight: .medium))
                    .tracking(metrics.isWebInterface ? -metrics.size(0.34) : 0)
                    .minimumScaleFactor(25.0 / 34.0)
                    .lineLimit(1)
                    .foregroundStyle(theme[.textPrimary])
                Group {
                    if metrics.isWebInterface {
                        Text(verbatim: webDate(context.date))
                    } else {
                        Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    }
                }
                    .font(metrics.font(size: metrics.isWebInterface ? 13 : 11, weight: .medium))
                    .foregroundStyle(theme[.fg])
                    .padding(.vertical, metrics.size(3))
                    .padding(.horizontal, metrics.size(8))
                    .background(theme[.bg].opacity(metrics.isWebInterface ? 0.52 : 1),
                        in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.greeting")
    }

    private var profileImage: Image {
        let avatars = (try? JSONDecoder().decode([String: String].self, from: Data(avatarImages.utf8))) ?? [:]
        if let encoded = avatars[environment.profileID?.rawValue ?? "default"],
           let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            return Image(nsImage: image)
        }
        return Image("DefaultProfile")
    }

    private func webDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE, d MMM · HH:mm"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "").lowercased()
    }

    private var firstName: String {
        let profile = environment.activeProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty { return metrics.isWebInterface ? String(profile.split(separator: " ").first ?? Substring(profile)) : profile }
        return NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
    }

    @ViewBuilder private var avatar: some View {
        if metrics.isWebInterface {
            profileImage
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: metrics.size(44), height: metrics.size(44))
                .clipShape(Circle())
                .background(theme[.bgSunken].opacity(0.82), in: Circle())
                .overlay(Circle().strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                .overlay(alignment: .leading) {
                    Text(verbatim: "\(streak)")
                        .font(metrics.monoFont(size: 11, weight: .semibold))
                        .foregroundStyle(theme[.fg])
                        .frame(width: metrics.size(30), height: metrics.size(30))
                        .background(theme[.bgSunken], in: Circle())
                        .overlay(Circle().strokeBorder(theme[.statusWaiting], lineWidth: metrics.size(1)))
                        .overlay(alignment: .top) {
                            Image(systemName: "flame").webProfileSized(11)
                                .font(metrics.font(size: 11))
                                .foregroundStyle(theme[.statusWaiting])
                                .frame(width: metrics.size(17), height: metrics.size(14))
                                .background(theme[.bgSunken], in: Capsule())
                                .offset(y: -metrics.size(6))
                        }
                        .offset(x: -metrics.size(31), y: -metrics.size(1))
                        .help(Text(String(format: String(localized: "home.activity.streak"), streak)))
                        .accessibilityLabel(Text(String(format: String(localized: "home.activity.streak"), streak)))
                }
        } else {
            Text(verbatim: String(firstName.prefix(1)).uppercased())
                .font(metrics.font(size: metrics.isWebInterface ? 16 : 28, weight: .medium))
                .foregroundStyle(theme[.accent])
                .frame(width: metrics.size(metrics.isWebInterface ? 44 : 64), height: metrics.size(metrics.isWebInterface ? 44 : 64))
                .background(theme[.bgSunken], in: Circle())
                .overlay(alignment: metrics.isWebInterface ? .leading : .bottomTrailing) {
                    Label { Text(verbatim: "\(streak)") } icon: { Image(systemName: "flame.fill").webProfileSized(14) }
                        .font(metrics.font(.caption))
                        .padding(metrics.space(.xs))
                        .background(theme[.panel], in: Capsule())
                        .offset(x: metrics.isWebInterface ? -metrics.size(30) : 0)
                        .accessibilityLabel(Text(String(format: String(localized: "home.activity.streak"), streak)))
                }
        }
    }

    private func greeting(_ date: Date) -> String {
        let matchedValue = Greeting(hour: Calendar.current.component(.hour, from: date))
        return if case .morning = matchedValue {
            String(localized: "home.greeting.morning")
        } else if case .afternoon = matchedValue {
            String(localized: "home.greeting.afternoon")
        } else {
            String(localized: "home.greeting.evening")
        }
    }
}
