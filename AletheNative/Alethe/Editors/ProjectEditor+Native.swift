import AletheAgents
import AletheDesign
import AletheGit
import AletheModel
import AppKit
import SwiftUI

extension ProjectEditor {
    var nativeBody: some View {
        Form {
            if editing == nil {
                Picker(selection: $source) {
                    Text("editor.project.source.folder").tag(Source.folder)
                    Text("editor.project.source.clone").tag(Source.clone)
                } label: { Text("editor.project.source") }
                    .pickerStyle(.segmented)
                    .disabled(model.cloning)
                    .accessibilityIdentifier("editor.project.source")
            }
            if isCloning {
                TextField(text: $cloneURL, prompt: Text(verbatim: "https://github.com/owner/repository")) {
                    Text("editor.project.cloneURL")
                }
                .accessibilityIdentifier("editor.project.cloneURL")
                .disabled(model.cloning)
                .onChange(of: cloneURL) { _, value in
                    if !nameEdited { name = GitCloneURL.folderName(for: GitCloneURL.normalize(value)) }
                }
            }
            TextField(text: $folder, prompt: Text(verbatim: isCloning ? "~/Alethe" : "~/Projects/app")) {
                Text(isCloning ? "editor.project.cloneInto" : "editor.project.folder")
            }
                .accessibilityIdentifier("editor.project.folder")
                .focused($focused)
                .disabled(model.cloning)
                .onChange(of: folder) { _, value in
                    if !nameEdited, editing == nil, !isCloning { name = URL(filePath: expanded(value)).lastPathComponent }
                }
            HStack {
                Spacer()
                Button("editor.project.chooseFolder") { chooseFolder() }
                    .disabled(model.cloning)
            }
            if !isCloning { folderDetails }
            TextField(text: Binding { name } set: { name = $0; nameEdited = true }) { Text("editor.project.name") }
                .accessibilityIdentifier("editor.project.name")
            ImageInputField(value: $iconUrl, name: name, color: color)
            LabeledContent("editor.color") { ColorSwatchPicker(selection: $color) }
            Picker(selection: $location) {
                Text("sidebar.ungrouped").tag(ProjectLocation.ungrouped)
                ForEach(workspace.document.groups) { group in
                    Text(verbatim: group.name).tag(ProjectLocation.group(group.id))
                }
            } label: { Text("editor.project.group") }
            Section {
                Toggle(isOn: $autoWorktree) {
                    Text("editor.project.autoWorktree")
                    Text("editor.project.autoWorktree.detail").font(metrics.font(.footnote))
                }
                .accessibilityIdentifier("editor.project.autoWorktree")
                Picker(selection: $worktreeMode) {
                    Text("newTerminal.worktree.mode.gitWorktree").tag(ProjectWorktreeMode.gitWorktree)
                    Text("newTerminal.worktree.mode.localCopy").tag(ProjectWorktreeMode.localCopy)
                } label: { Text("newTerminal.worktree.mode") }
                    .accessibilityIdentifier("editor.project.worktreeMode")
            } header: { Text("editor.project.worktrees") }
            if isCloning { cloneStatus }
            if environment.features.isOn(.graphify) {
                Toggle(isOn: $graphifyEnabled) {
                    Text("editor.project.graphify")
                    Text("editor.project.graphify.detail").font(metrics.font(.footnote))
                }
                .accessibilityIdentifier("editor.project.graphify")
            }
            if let problem, !model.cloning {
                Text(problem)
                    .foregroundStyle(theme[.textSecondary])
                    .font(metrics.font(.footnote))
                    .accessibilityIdentifier("editor.problem")
            }
        }
        .formStyle(.grouped)
        .frame(width: metrics.size(460))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("editor.cancel") {
                    if model.cloning { model.cancelClone() } else { dismiss() }
                }
                .accessibilityIdentifier("editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) { save() }
                    .disabled(problem != nil || model.cloning)
                    .accessibilityIdentifier("editor.confirm")
            }
        }
        .interactiveDismissDisabled(model.cloning)
        .navigationTitle(Text(editing == nil ? "editor.project.newTitle" : "editor.project.editTitle"))
        .task(id: isCloning ? "" : expanded(folder)) {
            await model.inspect(isCloning ? "" : expanded(folder))
        }
        .onAppear {
            focused = true
            loadInitial()
        }
    }

    func close() {
        if metrics.isWebInterface, let closeOverlay { closeOverlay() } else { dismiss() }
    }
}
