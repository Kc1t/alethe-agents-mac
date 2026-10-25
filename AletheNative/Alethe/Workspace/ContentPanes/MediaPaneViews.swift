import AletheDesign
import AletheDocuments
import AppKit
import AVKit
import Observation
import SwiftUI

@Observable
@MainActor
final class ImageFile {
    let url: URL
    private(set) var image: NSImage?
    @ObservationIgnored private var watcher: FileWatcher?

    init(path: String) {
        url = URL(filePath: path)
        reload()
        watcher = FileWatcher(path: path) { [weak self] in self?.reload() }
    }

    func reload() {
        image = (try? Data(contentsOf: url)).flatMap(NSImage.init(data:))
    }

    func close() {
        watcher?.stop()
        watcher = nil
    }
}

struct ImagePaneView: View {
    let file: ImageFile
    let isFocused: Bool
    let onClose: () -> Void
    let onDrag: (CGSize?) -> Void
    @State private var actualSize = false
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            ContentPaneHeader(symbol: "photo", url: file.url, isFocused: isFocused, onClose: onClose, onDrag: onDrag) {
                Spacer(minLength: 0)
                if !metrics.isWebInterface {
                ContentPaneButton(symbol: actualSize ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                  label: actualSize ? "media.fit" : "media.actualSize", id: "image.size") {
                    actualSize.toggle()
                }
                .disabled(file.image == nil)
                }
            }
            content
        }
        .background(theme[.bgSunken])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("image.pane")
    }

    @ViewBuilder
    private var content: some View {
        if let image = file.image {
            if actualSize && !metrics.isWebInterface {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).interpolation(.high)
                        .frame(width: image.size.width, height: image.size.height)
                }
                .accessibilityIdentifier("image.actual")
            } else {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .padding(metrics.isWebInterface ? 0 : metrics.space(.m))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("image.fitted")
            }
        } else {
            Text(verbatim: format("media.loadError", file.url.path))
                .foregroundStyle(theme[.textSecondary])
                .multilineTextAlignment(.center)
                .padding(metrics.space(.xl))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("media.error")
        }
    }
}

struct VideoPaneView: View {
    let url: URL
    let player: AVPlayer
    let isFocused: Bool
    let onClose: () -> Void
    let onDrag: (CGSize?) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ContentPaneHeader(symbol: "film", url: url, isFocused: isFocused, onClose: onClose, onDrag: onDrag) {
                Spacer(minLength: 0)
            }
            VideoPlayer(player: player)
                .accessibilityIdentifier("video.player")
        }
        .background(theme[.bgSunken])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("video.pane")
    }
}
