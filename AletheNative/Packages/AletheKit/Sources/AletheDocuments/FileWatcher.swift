import Darwin
import Foundation

public final class FileWatcher: @unchecked Sendable {
    public let path: String
    private let onChange: @MainActor () -> Void
    private let queue = DispatchQueue(label: "alethe.filewatcher", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var pendingNotify = false
    private var stopped = false

    public init(path: String, onChange: @escaping @MainActor () -> Void) {
        self.path = path
        self.onChange = onChange
        queue.async { [self] in open(attempt: 0) }
    }

    public func stop() {
        queue.async { [self] in
            stopped = true
            source?.cancel()
            source = nil
        }
    }

    deinit {
        source?.cancel()
    }

    private func open(attempt: Int) {
        guard !stopped else { return }
        let descriptor = Darwin.open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            if attempt < 50 {
                queue.asyncAfter(deadline: .now() + 0.1) { [self] in open(attempt: attempt + 1) }
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename, .revoke], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let events = source.data
            notify()
            if !events.isDisjoint(with: [.delete, .rename, .revoke]) {
                source.cancel()
                self.source = nil
                queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.open(attempt: 0) }
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
        if attempt > 0 { notify() }
    }

    private func notify() {
        guard !pendingNotify else { return }
        pendingNotify = true
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, !stopped else { return }
            pendingNotify = false
            let onChange = onChange
            DispatchQueue.main.async { MainActor.assumeIsolated { onChange() } }
        }
    }
}
