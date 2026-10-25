import AletheAgents
import AletheDesign
import AletheFoundation
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct OnboardingSheet: View {
    let workspace: WorkspaceModel
    let undoManager: UndoManager?
    @Environment(AppEnvironment.self) var environment
    @Environment(\.dismiss) var dismiss
    @Environment(\.modalsM2Close) var closeOverlay
    @Environment(\.newTerminalModalHeight) private var maximumHeight
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics

    @State private var step = OnboardingStep.name
    @State var name = ""
    @State private var nameError: String?
    @State private var saving = false
    @State private var tauriAvailable = false
    @State private var photo = ""
    @State private var bodyHeight: CGFloat = 0
    @FocusState private var nameFocused: Bool

    private var steps: [OnboardingStep] {
        OnboardingStep.steps(tauriDataAvailable: tauriAvailable, mcpEnabled: environment.features.isOn(.mcp))
    }

    private var index: Int { steps.firstIndex(of: step) ?? 0 }
    private var isLast: Bool { index == steps.count - 1 }
    private var canContinue: Bool {
        !saving && (step != .name || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        if metrics.isWebInterface { webBody } else { nativeBody }
    }

    var nativeBody: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(metrics.space(.xxl))
                .id(step)
            Divider()
            footer
        }
        .frame(width: closeOverlay == nil ? metrics.size(620) : nil,
               height: closeOverlay == nil ? metrics.size(580) : min(metrics.size(580), maximumHeight))
        .background(theme[.bg])
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
        .task {
            name = suggestedName
            photo = environment.preferences?.document.profileImageUrl ?? ""
            nameFocused = true
            tauriAvailable = await Task.detached { !TauriImportSheet.availableProfiles().isEmpty }.value
        }
    }

    var webBody: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius(.lg))
        return VStack(spacing: 0) {
            OnboardingWebHeader(count: steps.count, current: index,
                                progressLabel: format("onboarding.progress", index + 1, steps.count))
            ScrollView {
                webStep
                    .padding(metrics.size(26))
                    .frame(maxWidth: .infinity, alignment: .top)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
                    .id(step)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: metrics.size(4))),
                                            removal: .identity))
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(metrics.size(322), bodyHeight), max(metrics.size(120), maximumHeight - metrics.size(104))))
            .clipped()
            .animation(metrics.reducesMotion ? nil : .easeOut(duration: 0.18), value: step)
            webFooter
        }
        .font(metrics.font(size: 13))
        .foregroundStyle(theme[.fg])
        .tint(theme[.accent])
        .background(theme[.surfaceModal], in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
        .task {
            name = suggestedName
            photo = environment.preferences?.document.profileImageUrl ?? ""
            nameFocused = true
            tauriAvailable = await Task.detached { !TauriImportSheet.availableProfiles().isEmpty }.value
        }
    }

    @ViewBuilder
    private var webStep: some View {
        if case .name = step {
            OnboardingWebProfileStep(name: $name, photo: $photo, nameError: nameError, focus: $nameFocused)
        } else if case .importData = step {
            OnboardingImportStep(workspace: workspace, undoManager: undoManager)
        } else if case .appearance = step {
            appearanceStep
        } else if case .agents = step {
            OnboardingWebAgentsStep()
        } else if case .features = step {
            OnboardingWebFeaturesStep()
        } else {
            OnboardingMcpStep(store: environment.mcpStore)
        }
    }

    private var webFooter: some View {
        HStack(spacing: metrics.size(10)) {
            Text(verbatim: webFootnote)
                .font(metrics.font(size: 11.5)).foregroundStyle(theme[.fgFaint])
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("onboarding.skip") { skip() }
                .buttonStyle(OnboardingWebButtonStyle(kind: .ghost))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("onboarding.skip")
            if index > 0 {
                Button("onboarding.web.back") { move(-1) }
                    .buttonStyle(OnboardingWebButtonStyle(kind: .ghost))
                    .keyboardShortcut("[", modifiers: .command)
                    .accessibilityIdentifier("onboarding.back")
            }
            Button {
                next()
            } label: {
                HStack(spacing: metrics.size(7)) {
                    Text(isLast ? LocalizedStringKey("onboarding.web.goToApp") : "onboarding.web.next")
                    Text(verbatim: "\u{23CE}")
                        .font(metrics.monoFont(size: 10.5, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .padding(.horizontal, metrics.size(5)).padding(.vertical, metrics.size(1))
                        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm))
                            .strokeBorder(Color.black.opacity(0.22), lineWidth: metrics.size(1)))
                }
            }
            .buttonStyle(OnboardingWebButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
            .disabled(!canContinue)
            .accessibilityIdentifier("onboarding.next")
        }
        .padding(.horizontal, metrics.size(18)).padding(.vertical, metrics.size(12))
        .background(theme[.bgSunken])
        .overlay(alignment: .top) { Rectangle().fill(theme[.border]).frame(height: metrics.size(1)) }
    }

    private var webFootnote: String {
        step == .features
            ? format("onboarding.web.featuresEnabledOf", Feature.allCases.filter(environment.features.isOn).count,
                     Feature.allCases.count)
            : String(localized: "onboarding.web.footerNote")
    }

    private var header: some View {
        HStack(spacing: metrics.space(.m)) {
            Text("onboarding.kicker")
                .font(metrics.font(.footnote).weight(.semibold))
                .foregroundStyle(theme[.textSecondary])
            Spacer()
            HStack(spacing: metrics.space(.xs)) {
                ForEach(Array(steps.enumerated()), id: \.element) { position, _ in
                    Capsule()
                        .fill(position <= index ? theme[.accent] : theme[.borderSubtle])
                        .frame(width: metrics.size(position == index ? 18 : 6), height: metrics.size(6))
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: format("onboarding.progress", index + 1, steps.count)))
            .accessibilityIdentifier("onboarding.progress")
        }
        .padding(.horizontal, metrics.space(.xxl))
        .padding(.vertical, metrics.space(.l))
    }

    var footer: some View {
        HStack(spacing: metrics.space(.m)) {
            Text(verbatim: footnote)
                .font(metrics.font(.footnote))
                .foregroundStyle(theme[.textTertiary])
                .lineLimit(2)
            Spacer()
            Button("onboarding.skip") { skip() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("onboarding.skip")
            if index > 0 {
                Button("onboarding.back") { move(-1) }
                    .keyboardShortcut("[", modifiers: .command)
                    .accessibilityIdentifier("onboarding.back")
            }
            Button(isLast ? LocalizedStringKey("onboarding.finish") : "onboarding.next") { next() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
                .accessibilityIdentifier("onboarding.next")
        }
        .padding(.horizontal, metrics.space(.xxl))
        .padding(.vertical, metrics.space(.l))
    }

    var footnote: String {
        step == .features
            ? format("onboarding.features.count", Feature.allCases.filter(environment.features.isOn).count,
                     Feature.allCases.count)
            : String(localized: "onboarding.footnote")
    }

    @ViewBuilder
    var content: some View {
        if case .name = step {
            nameStep
        } else if case .importData = step {
            OnboardingImportStep(workspace: workspace, undoManager: undoManager)
        } else if case .appearance = step {
            appearanceStep
        } else if case .agents = step {
            OnboardingAgentsStep()
        } else if case .features = step {
            featuresStep
        } else {
            OnboardingMcpStep(store: environment.mcpStore)
        }
    }

    private var nameStep: some View {
        VStack(spacing: metrics.space(.l)) {
            Spacer(minLength: 0)
            Circle()
                .fill(theme[.accentSoft])
                .frame(width: metrics.size(64), height: metrics.size(64))
                .overlay {
                    Text(verbatim: initial)
                        .font(metrics.font(.title1))
                        .foregroundStyle(theme[.accent])
                }
                .accessibilityHidden(true)
            Text("onboarding.name.title").font(metrics.font(.title2))
            Text("onboarding.name.subtitle")
                .foregroundStyle(theme[.textSecondary])
                .multilineTextAlignment(.center)
            TextField(text: $name, prompt: Text("onboarding.name.placeholder")) {
                Text("onboarding.name.label")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(maxWidth: metrics.size(280))
            .focused($nameFocused)
            .onChange(of: name) { nameError = nil }
            .accessibilityIdentifier("onboarding.name")
            if let nameError {
                Text(verbatim: nameError)
                    .font(metrics.font(.footnote))
                    .foregroundStyle(theme[.statusStopped])
                    .accessibilityIdentifier("onboarding.name.error")
            }
            Text("onboarding.name.note")
                .font(metrics.font(.footnote))
                .foregroundStyle(theme[.textTertiary])
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var appearanceStep: some View {
        VStack(alignment: .leading, spacing: metrics.space(.l)) {
            OnboardingStepTitle(title: "onboarding.appearance.title", subtitle: "onboarding.appearance.subtitle")
            Picker(selection: Binding {
                environment.visualStyle
            } set: { style in
                environment.preferences?.update { $0.visualStyle = style == .normal ? nil : style.rawValue }
            }) {
                ForEach(VisualStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Text("settings.appearance.style")
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("onboarding.style")
            if metrics.isWebInterface {
                ThemeGrid()
            } else {
                ScrollView {
                    ThemeGrid()
                }
            }
        }
    }

    private var featuresStep: some View {
        VStack(alignment: .leading, spacing: metrics.space(.l)) {
            OnboardingStepTitle(title: "onboarding.features.title", subtitle: "onboarding.features.subtitle")
            Form {
                Section {
                    ForEach(Feature.allCases, id: \.self) { FeatureRow(feature: $0, showsOptions: false) }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var suggestedName: String {
        if let profileID = environment.profileID, let entry = environment.profiles?.document.profile(profileID),
           let named = entry.name {
            return named
        }
        return OnboardingName.suggested(fullName: NSFullUserName(), userName: NSUserName())
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    private func next() {
        guard canContinue else { return }
        guard step == .name else {
            if isLast { finish() } else { move(1) }
            return
        }
        guard let profileID = environment.profileID else { return move(1) }
        saving = true
        let trimmedPhoto = photo.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { saving = false }
            do {
                if metrics.isWebInterface {
                    environment.preferences?.update {
                        $0.displayName = name.trimmingCharacters(in: .whitespaces)
                        $0.profileImageUrl = trimmedPhoto.isEmpty ? nil : trimmedPhoto
                    }
                }
                if environment.activeProfileName != name.trimmingCharacters(in: .whitespaces) {
                    try await environment.renameProfile(profileID, to: name)
                }
                move(1)
            } catch let failure as ProfileError {
                nameError = failure.localizedMessage
            } catch {
                nameError = error.localizedDescription
            }
        }
    }

    private func move(_ offset: Int) {
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        step = steps[target]
        if step == .name { nameFocused = true }
    }

    func skip() {
        environment.preferences?.update { $0.onboardingDone = true }
        close()
    }

    func close() {
        if let closeOverlay { closeOverlay() } else { dismiss() }
    }

    private func finish() {
        environment.preferences?.update { preferences in
            preferences.onboardingDone = true
            preferences.setupHidden = nil
        }
        environment.showingHome = true
        close()
    }
}

