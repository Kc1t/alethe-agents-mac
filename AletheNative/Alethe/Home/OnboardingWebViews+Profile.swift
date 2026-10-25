import AletheAgents
import AletheDesign
import AletheFoundation
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct OnboardingWebProfileStep: View {
    @Binding var name: String
    @Binding var photo: String
    let nameError: String?
    var focus: FocusState<Bool>.Binding
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @State private var showsPhoto = false
    @State private var showsGithub = false
    @State private var handle = ""
    @FocusState private var handleFocused: Bool

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        VStack(spacing: 0) {
            avatar
            Text("onboarding.web.photoHint")
                .font(metrics.font(size: 10.5)).foregroundStyle(theme[.fgFaint])
                .padding(.top, metrics.size(9))
            Text("onboarding.web.profileTitle")
                .font(metrics.font(size: 19, weight: .semibold)).tracking(metrics.size(-0.285))
                .padding(.top, metrics.size(18)).padding(.bottom, metrics.size(6))
            Text("onboarding.web.profileSubtitle")
                .font(metrics.font(size: 12.5)).foregroundStyle(theme[.fgMuted])
                .lineSpacing(metrics.size(4)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, metrics.size(18))
            nameField
            if let nameError {
                Text(verbatim: nameError)
                    .font(metrics.font(size: 10.5)).foregroundStyle(theme[.statusStopped])
                    .padding(.top, metrics.size(6))
                    .accessibilityIdentifier("onboarding.name.error")
            }
            if showsPhoto {
                ImageInputField(value: $photo, name: name, color: nil,
                                label: "settings.web.reference.prefs.photoPlaceholder",
                                placeholder: "onboarding.web.photoUrlPlaceholder",
                                hint: "settings.web.reference.image.urlOrUpload")
                    .frame(maxWidth: metrics.size(290), alignment: .leading)
                    .padding(.top, metrics.size(14))
            }
            divider
            if showsGithub { githubRow } else { githubButton }
            Text("onboarding.web.localNote")
                .font(metrics.font(size: 10.5)).foregroundStyle(theme[.fgFaint])
                .lineSpacing(metrics.size(4)).multilineTextAlignment(.center)
                .frame(maxWidth: metrics.size(300))
                .padding(.top, metrics.size(10))
        }
        .frame(maxWidth: .infinity)
    }

    private var avatar: some View {
        OnboardingHover { hovering in
            Button { showsPhoto.toggle() } label: {
                SidebarCoverImage(source: photo.trimmingCharacters(in: .whitespacesAndNewlines),
                                  side: 76, cornerRadius: 38) {
                    if photo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Image("DefaultProfile").resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Text(verbatim: initial)
                            .font(metrics.font(size: 27, weight: .semibold)).foregroundStyle(theme[.fgMuted])
                    }
                }
                .background(theme[.surfaceCardDefault], in: Circle())
                .overlay {
                    Text("onboarding.web.photoChange")
                        .font(metrics.font(size: 10.5, weight: .medium)).foregroundStyle(theme[.fg])
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.72))
                        .opacity(hovering ? 1 : 0)
                        .animation(metrics.reducesMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(theme[hovering ? .accentBorder : .borderStrong],
                                               lineWidth: metrics.size(1)))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(Text("onboarding.web.photoTitle"))
        .accessibilityIdentifier("onboarding.photo")
        .webAvatarIn()
    }

    private var nameField: some View {
        OnboardingHover { hovering in
            TextField(text: $name, prompt: Text("onboarding.web.namePlaceholder")
                .foregroundStyle(theme[.textQuaternary])) { Text("onboarding.web.name") }
                .textFieldStyle(.plain)
                .font(metrics.font(size: 16, weight: .medium))
                .foregroundStyle(theme[.fg])
                .multilineTextAlignment(.center)
                .focused(focus)
                .padding(.horizontal, metrics.size(14)).padding(.vertical, metrics.size(11))
                .background(theme[.bg], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                    .strokeBorder(theme[focus.wrappedValue ? .accentBorder : hovering ? .borderStrong : .border],
                                  lineWidth: metrics.size(1)))
                .onChange(of: name) { _, value in
                    if value.count > 60 { name = String(value.prefix(60)) }
                }
        }
        .frame(maxWidth: metrics.size(290))
        .accessibilityIdentifier("onboarding.name")
    }

    private var divider: some View {
        HStack(spacing: metrics.size(12)) {
            Rectangle().fill(theme[.border]).frame(height: metrics.size(1))
            Text("onboarding.web.orImportFrom").fixedSize()
            Rectangle().fill(theme[.border]).frame(height: metrics.size(1))
        }
        .font(metrics.font(size: 11)).foregroundStyle(theme[.fgFaint])
        .frame(maxWidth: metrics.size(290))
        .padding(.top, metrics.size(22)).padding(.bottom, metrics.size(13))
    }

    private var githubButton: some View {
        OnboardingHover { hovering in
            Button { showsGithub = true; handleFocused = true } label: {
                HStack(spacing: metrics.size(10)) {
                    Image(systemName: "person.crop.circle").font(metrics.font(size: 16))
                    Text("onboarding.web.githubImport").font(metrics.font(size: 13))
                }
                .foregroundStyle(theme[.fg])
                .frame(maxWidth: .infinity).padding(metrics.size(11))
                .background(theme[hovering ? .panelHover : .surfaceCardDefault],
                            in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                    .strokeBorder(theme[hovering ? .borderStrong : .border], lineWidth: metrics.size(1)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: metrics.size(290))
        .accessibilityIdentifier("onboarding.github")
    }

    private var githubRow: some View {
        HStack(spacing: metrics.size(8)) {
            TextField(text: $handle, prompt: Text("onboarding.web.githubHandlePlaceholder")
                .foregroundStyle(theme[.fgFaint])) { Text("onboarding.web.githubHandlePlaceholder") }
                .textFieldStyle(.plain)
                .font(metrics.font(size: 12.5)).foregroundStyle(theme[.fg])
                .focused($handleFocused)
                .padding(.horizontal, metrics.size(11)).padding(.vertical, metrics.size(9))
                .background(theme[.bg], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                    .strokeBorder(theme[handleFocused ? .accentBorder : .border], lineWidth: metrics.size(1)))
                .onSubmit(apply)
                .accessibilityIdentifier("onboarding.github.handle")
            OnboardingHover { hovering in
                Button(action: apply) {
                    Text("onboarding.web.githubUse").font(metrics.font(size: 12.5)).foregroundStyle(theme[.fg])
                        .padding(.horizontal, metrics.size(13)).padding(.vertical, metrics.size(9))
                        .background(theme[hovering ? .panelHover : .surfaceCardDefault],
                                    in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                            .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("onboarding.github.use")
        }
        .frame(maxWidth: metrics.size(290))
    }

    private func apply() {
        var value = handle.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("@") { value.removeFirst() }
        guard !value.isEmpty, value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." })
        else { return }
        photo = "https://github.com/\(value).png"
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = value }
        showsGithub = false
    }
}
