import AletheAgents
import AletheDesign
import AletheModel
import AletheTerminal
import AppKit
import Observation
import SwiftUI

extension PaneView {
    func contentView(pane: Pane, project: Project, focused: Bool,
                             context: PaneHostContext, onDrag: @escaping (CGSize?) -> Void) -> AnyView {
        let view: AnyView
        if case .markdown(let path) = pane.content {
            setAccessibilityIdentifier("pane.\((path as NSString).lastPathComponent)")
            let file = context.environment.contentPanes.markdown(for: pane.id, path: path)
            view = context.hosted(MarkdownPaneView(file: file, isFocused: focused,
                                                   onClose: { context.closePane(pane.id) }, onDrag: onDrag))
        } else if case .image(let path) = pane.content {
            setAccessibilityIdentifier("pane.\((path as NSString).lastPathComponent)")
            let file = context.environment.contentPanes.image(for: pane.id, path: path)
            view = context.hosted(ImagePaneView(file: file, isFocused: focused,
                                                onClose: { context.closePane(pane.id) }, onDrag: onDrag))
        } else if case .video(let path) = pane.content {
            setAccessibilityIdentifier("pane.\((path as NSString).lastPathComponent)")
            let player = context.environment.contentPanes.player(for: pane.id, path: path)
            view = context.hosted(VideoPaneView(url: URL(filePath: path), player: player, isFocused: focused,
                                                onClose: { context.closePane(pane.id) }, onDrag: onDrag))
        } else if case .diff(let path, let staged) = pane.content {
            setAccessibilityIdentifier("pane.diff")
            let model = context.environment.contentPanes.diff(for: pane.id, folder: project.folder, path: path, staged: staged)
            view = context.hosted(DiffPaneView(
                model: model, isFocused: focused,
                onStagedChange: { context.setContent(.diff(path: path, staged: $0), for: pane.id) },
                onClose: { context.closePane(pane.id) }, onDrag: onDrag))
        } else if case .web(let url, let options) = pane.content {
            view = webContent(pane: pane, url: url, options: options, focused: focused, context: context, onDrag: onDrag)
        } else if case .graphify = pane.content {
            setAccessibilityIdentifier("pane.graphify")
            let graphify = context.environment.graphify
            let model = context.environment.contentPanes.graph(for: pane.id, root: graphify.root(for: project.folder),
                                                                controller: graphify)
            view = context.hosted(GraphifyPaneView(model: model, project: project.id, isFocused: focused,
                                                   onClose: { context.closePane(pane.id) }, onDrag: onDrag))
        } else if case .orchestrator = pane.content {
            setAccessibilityIdentifier("pane.orchestrator")
            view = context.hosted(OrchestratorPaneView(project: project.id, isFocused: focused,
                                                       onClose: { context.closePane(pane.id) },
                                                       onDrag: onDrag))
        } else {
            view = AnyView(EmptyView())
        }
        return view
    }

    private func webContent(pane: Pane, url: String, options: WebPaneOptions, focused: Bool,
                            context: PaneHostContext, onDrag: @escaping (CGSize?) -> Void) -> AnyView {
        setAccessibilityIdentifier("pane.web")
        let page = context.environment.contentPanes.page(for: pane.id, url: url, options: options)
        page.onAddressChange = { [weak page] address in
            context.setContent(.web(url: address.absoluteString, options: page?.options ?? options), for: pane.id)
        }
        return context.hosted(WebPaneView(
            page: page, isFocused: focused,
            onOptionsChange: { [weak page] in
                context.setContent(.web(url: page?.url?.absoluteString ?? url, options: $0), for: pane.id)
            },
            onClose: { context.closePane(pane.id) }, onDrag: onDrag))
    }
}
