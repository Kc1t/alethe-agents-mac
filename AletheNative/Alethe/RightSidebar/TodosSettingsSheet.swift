import AletheDesign
import AletheFoundation
import AletheTodos
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TodosSettingsSheet: View {
    let store: TodoStore
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @Environment(\.dismiss) private var nativeDismiss
    @Environment(\.modalsM2Close) private var closeOverlay
    private func dismiss() {
        if let closeOverlay { closeOverlay() } else { nativeDismiss() }
    }
    @State private var path = ""
    @State private var choosingFolder = false
    @State private var confirming: Confirmation?
    @State private var busy = false
    @State private var message: String?
    @State private var error: String? { didSet { if error != oldValue { AppLog.shown(error, .integrations) } } }

    private enum Confirmation: Identifiable {
        case importTemplate, exportTemplate, reset
        var id: Self { self }
    }

    var body: some View {
        if metrics.isWebInterface { webBody } else { nativeBody }
    }

    private var webBody: some View {
        GitWebModal(close: dismiss) {
            Text("todos.settings.web.title")
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                ProjectGroupWebField(title: "todos.settings.web.pathLabel") {
                    HStack(spacing: metrics.size(6)) {
                        TextField("", text: $path, prompt: Text("todos.settings.web.pathPlaceholder"))
                            .modifier(ProjectGroupWebInput())
                            .accessibilityIdentifier("todos.settings.folder")
                        Button { choosingFolder = true } label: {
                            Image(systemName: "folder").font(metrics.font(size: 14))
                        }
                        .help(Text("todos.settings.web.choosePath"))
                        .accessibilityLabel(Text("todos.settings.web.choosePath"))
                        Button { path = "" } label: {
                            Image(systemName: "arrow.counterclockwise").font(metrics.font(size: 14))
                        }
                        .help(Text("todos.settings.web.clearPath"))
                        .accessibilityLabel(Text("todos.settings.web.clearPath"))
                    }
                }
                ProjectGroupWebField(title: "todos.settings.web.defaultLabel") {
                    Button("todos.settings.web.resetDefault") { confirming = .reset }
                        .accessibilityIdentifier("todos.settings.reset")
                }
                ProjectGroupWebField(title: "todos.settings.template") {
                    VStack(alignment: .leading, spacing: metrics.size(6)) {
                        if let url = store.templateURL {
                            Text(verbatim: url.path).font(metrics.monoFont(size: 11)).foregroundStyle(theme[.fgMuted])
                                .textSelection(.enabled)
                        }
                        HStack(spacing: metrics.size(6)) {
                            Button("todos.settings.open") { Task { await openTemplate() } }
                            Button("todos.settings.import") { confirming = .importTemplate }
                            Button("todos.settings.export") { confirming = .exportTemplate }
                        }.disabled(store.templateURL == nil || busy)
                    }
                }
                if let message { Text(verbatim: message).font(metrics.font(size: 12)).foregroundStyle(theme[.statusActive]) }
                if let error {
                    Text(verbatim: error).font(metrics.font(size: 12)).foregroundStyle(theme[.statusStopped]).textSelection(.enabled)
                }
            }
        } footer: {
            Spacer()
            Button("editor.cancel", action: dismiss)
            Button("editor.save") { Task { await saveAndClose() } }
                .buttonStyle(AletheButtonStyle(.primary))
                .disabled(busy)
                .keyboardShortcut(.defaultAction).accessibilityIdentifier("todos.settings.done")
        }
        .onAppear { path = store.settings.storagePath }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { path = url.path }
        }
        .gitWebSheet(item: $confirming, width: 440) { action in
            WebConfirmationModal(title: Text(confirmationTitle), message: Text(confirmationMessage(action)),
                confirm: confirmationButton(action)) { Task { await perform(action) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todos.settings.sheet")
    }

    private var nativeBody: some View {
        VStack(alignment: .leading, spacing: metrics.space(.l)) {
            Text("todos.settings.title").font(.headline)
            Form {
                Section("todos.settings.template") {
                    HStack {
                        TextField("todos.settings.folder", text: $path, prompt: Text("todos.settings.folder.placeholder"))
                            .onSubmit { Task { await savePath() } }
                            .accessibilityIdentifier("todos.settings.folder")
                        Button("todos.settings.choose") { choosingFolder = true }
                        Button("todos.settings.clear") {
                            path = ""
                            Task { await savePath() }
                        }
                        .disabled(path.isEmpty)
                    }
                    if let url = store.templateURL {
                        Text(verbatim: url.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(theme[.textSecondary])
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("todos.settings.open") { Task { await openTemplate() } }
                        Button("todos.settings.import") { confirming = .importTemplate }
                        Button("todos.settings.export") { confirming = .exportTemplate }
                    }
                    .disabled(store.templateURL == nil || busy)
                }
                Section {
                    Button("todos.settings.reset", role: .destructive) { confirming = .reset }
                        .accessibilityIdentifier("todos.settings.reset")
                }
            }
            .formStyle(.grouped)
            if let message {
                Text(message).font(.caption).foregroundStyle(theme[.statusActive])
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(theme[.statusStopped]).textSelection(.enabled)
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("todos.settings.done") { Task { await close() } }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("todos.settings.done")
            }
        }
        .padding(metrics.space(.xl))
        .frame(width: metrics.size(520))
        .accessibilityIdentifier("todos.settings.sheet")
        .onAppear { path = store.settings.storagePath }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                path = url.path
                Task { await savePath() }
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: confirmingBinding, presenting: confirming) { action in
            Button(confirmationButton(action), role: .destructive) { Task { await perform(action) } }
        } message: { action in
            Text(confirmationMessage(action))
        }
    }

    private func savePath() async {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateSettings { $0.storagePath = trimmed }
        guard !trimmed.isEmpty else { return }
        await run { plugin in
            _ = try await plugin.ensureTemplate()
            return nil
        }
    }

    private func openTemplate() async {
        await savePath()
        await run { plugin in
            NSWorkspace.shared.open(try await plugin.ensureTemplate())
            return nil
        }
    }

    private func perform(_ action: Confirmation) async {
        switch action {
        case .importTemplate:
            await savePath()
            await run { plugin in
                try await plugin.importTemplate()
                return String(localized: "todos.settings.imported")
            }
        case .exportTemplate:
            await savePath()
            await run { plugin in
                _ = try await plugin.exportTemplate()
                return String(localized: "todos.settings.exported")
            }
        case .reset:
            store.resetToDefaults()
            message = String(localized: "todos.settings.resetDone")
            if metrics.isWebInterface { dismiss() }
        }
    }

    private func saveAndClose() async {
        await savePath()
        if error == nil { dismiss() }
    }

    private func close() async {
        if path.trimmingCharacters(in: .whitespacesAndNewlines) != store.settings.storagePath { await savePath() }
        if error == nil { dismiss() }
    }

    private func run(_ operation: (TodosPlugin) async throws -> String?) async {
        guard let plugin = TodosPlugin.activePlugin else {
            error = String(localized: "todos.disabled")
            return
        }
        busy = true
        defer { busy = false }
        do {
            message = try await operation(plugin)
            error = nil
        } catch TodoTemplate.TemplateError.invalidDocument(let detail) {
            error = String(format: String(localized: "todos.settings.invalidTemplate"), detail)
        } catch {
            self.error = String(format: String(localized: "todos.settings.templateError"), error.localizedDescription)
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding { confirming != nil } set: { if !$0 { confirming = nil } }
    }

    private var confirmationTitle: LocalizedStringKey {
        switch confirming {
        case .importTemplate: "todos.settings.import.confirm"
        case .exportTemplate: "todos.settings.export.confirm"
        case .reset, nil: "todos.settings.reset.confirm"
        }
    }

    private func confirmationButton(_ action: Confirmation) -> LocalizedStringKey {
        switch action {
        case .importTemplate: "todos.settings.import"
        case .exportTemplate: "todos.settings.export"
        case .reset: "todos.settings.reset"
        }
    }

    private func confirmationMessage(_ action: Confirmation) -> LocalizedStringKey {
        switch action {
        case .importTemplate: "todos.settings.import.message"
        case .exportTemplate: "todos.settings.export.message"
        case .reset: "todos.settings.reset.message"
        }
    }
}
