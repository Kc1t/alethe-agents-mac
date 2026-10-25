import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

public final class RemotePairingQR: @unchecked Sendable {
    public static let shared = RemotePairingQR()

    public static let minimumSide = 220

    private let lock = NSLock()
    private var cache: (url: String, image: CGImage)?
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    public init() {}

    public func image(for url: String) -> CGImage? {
        lock.withLock {
            if let cache, cache.url == url { return cache.image }
            guard let image = render(url) else { return nil }
            cache = (url, image)
            return image
        }
    }

    var cachedURL: String? {
        lock.withLock { cache?.url }
    }

    private func render(_ url: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage, code.extent.width > 0 else { return nil }
        let scale = ceil(CGFloat(Self.minimumSide) / code.extent.width)
        let scaled = code.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}
