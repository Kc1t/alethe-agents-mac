import AletheDesign
import AletheFiles
import AletheFoundation
import AletheGit
import AletheModel
import AlethePluginKit
import AppKit
import AVKit
import PDFKit
import Quartz
import SwiftUI

@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    nonisolated(unsafe) var url: URL?

    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        if panel.isVisible { panel.orderOut(nil) } else { panel.makeKeyAndOrderFront(nil) }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url.map { $0 as NSURL }
    }
}

struct WebFileHover: ViewModifier {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.background(theme[.panelHover].opacity(hovering ? 1 : 0))
            .animation(Motion.sidebarColor(reduceMotion: metrics.reducesMotion), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct WebFileDrag: ViewModifier {
    private let url: URL
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.draggable(url) } else { content }
    }
}

struct SidebarFilePreview: View {
    private let url: URL
    let close: () -> Void
    let add: () -> Void
    let markdown: () -> Void
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @Environment(\.newTerminalModalHeight) private var maximumHeight
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var text: String?
    @State private var failure: String?
    private var ext: String { url.pathExtension.lowercased() }
    private var isImage: Bool { ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico", "avif"].contains(ext) }
    private var isVideo: Bool { ["mp4", "webm", "mov", "m4v", "mkv", "avi"].contains(ext) }

    var body: some View {
        GitWebModal(close: close) {
            Text(verbatim: url.lastPathComponent).lineLimit(1)
        } content: {
            VStack(spacing: metrics.size(10)) {
                Text(verbatim: url.path).font(metrics.monoFont(size: 10)).foregroundStyle(theme[.fgFaint])
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                previewContent.frame(height: max(metrics.size(120), min(metrics.size(440), maximumHeight - metrics.size(150))))
            }
        } footer: {
            Button(action: add) { Label("rightSidebar.files.addToGrid", systemImage: "square.grid.2x2") }
                .buttonStyle(AletheButtonStyle(.primary))
            if ["md", "markdown"].contains(ext) {
                Button(action: markdown) { Label("rightSidebar.files.openMarkdown", systemImage: "sidebar.right") }
                    .buttonStyle(AletheButtonStyle(.primary))
            }
        }
        .task(id: url) { await load() }
        .onDisappear { player?.pause() }
        .accessibilityIdentifier("files.preview")
    }

    @ViewBuilder private var previewContent: some View {
        if let failure { Text(verbatim: failure).foregroundStyle(theme[.fgMuted]).frame(maxWidth: .infinity) }
        else if isImage, let image {
            GeometryReader { proxy in
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }.background(theme[.bgSunken])
        } else if isVideo, let player { VideoPlayer(player: player).background(theme[.bgSunken]) }
        else if ext == "pdf" { SidebarPDFPreview(url: url) }
        else if let text {
            ScrollView([.horizontal, .vertical]) {
                Text(verbatim: text).font(metrics.monoFont(size: 11)).textSelection(.enabled)
                    .padding(metrics.size(12)).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        } else { Text("files.loadingPreview").foregroundStyle(theme[.fgMuted]) }
    }

    private func load() async {
        if isVideo { player = AVPlayer(url: url); return }
        if ext == "pdf" { return }
        let source = url
        let media = isImage
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Data, any Error> in
            Result {
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                if !media && size > 2 * 1024 * 1024 { throw PreviewError.tooLarge }
                return try Data(contentsOf: source)
            }
        }.value
        guard !Task.isCancelled else { return }
        if case .success(let data) = result {
            if media {
                image = NSImage(data: data)
                if image == nil { failure = String(localized: "linkPreview.unavailable") }
            } else if let content = String(data: data, encoding: .utf8) { text = content }
            else { failure = String(localized: "linkPreview.unavailable") }
        } else if case .failure(PreviewError.tooLarge) = result {
            failure = String(localized: "files.previewTooLarge")
        } else if case .failure(let error) = result {
            failure = error.localizedDescription
        }
    }

    private enum PreviewError: Error { case tooLarge }
}

private struct SidebarPDFPreview: NSViewRepresentable {
    private let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}
