import AletheDesign
import AppKit
import Foundation
import GhosttyTerminal
import Synchronization

@MainActor
public final class TerminalPaneView: NSView {
    public static var inputMetrics: @MainActor () -> Metrics? = { nil }
    public let terminalView: TerminalView
    private let controller: TerminalController
    private let session: InMemoryTerminalSession
    private let process: PTYProcess
    public let tap: TerminalIOTap
    private let activity = TerminalActivity()
    private let forceKill = ForceKillState()
    private let forceKillNotice: Data
    private let grid: GridSizeState
    public let search = TerminalSearch()
    private let history: PromptHistoryState
    public let scrollback: ScrollbackFile?

    public var onPromptHistoryChange: (([String]) -> Void)?
    public var onOpenLink: ((String) -> Void)?
    public internal(set) var hoveredLink: String?
    let linkHighlight = TerminalLinkHighlightView()
    var linkGrid: TerminalGridMetrics?
    public var onLocalServer: ((URL) -> Void)? {
        get { servers.onFound }
        set { servers.onFound = newValue }
    }
    private let servers = LocalServerState()
    public private(set) var reportedDirectory: String?

    public var onExit: ((Int32) -> Void)?

    public var wasForceKilled: Bool { forceKill.triggered }

    public var processID: pid_t { process.pid }
    public var quietFor: Duration { activity.quietFor }
    public let startedAt = Date()
    public nonisolated var gridSize: PTYSize { grid.size }

    public init(launch: PTYLaunch, theme: Theme, fontSize: Float = TerminalAppearance.defaultFontSize,
                forceKillNotice: String = "Force kill: process terminated", promptHistory: [String] = [],
                scrollback: ScrollbackFile? = nil) throws {
        let process = try PTYProcess(launch, spawnNow: false)
        self.process = process
        let tap = TerminalIOTap()
        self.tap = tap
        let history = PromptHistoryState(PromptHistory(entries: promptHistory))
        self.history = history
        self.scrollback = scrollback
        let forceKill = forceKill
        let spawner = DeferredSpawn()
        let grid = GridSizeState(launch.size)
        self.grid = grid
        let notice = Data("\r\n\u{1b}[33m[\(forceKillNotice)]\u{1b}[0m\r\n".utf8)
        self.forceKillNotice = notice
        session = InMemoryTerminalSession(
            write: { data in
                tap.input(data)
                history.record(data)
                if forceKill.register(data) {
                    forceKill.session?.receive(notice)
                    ProcessTree.kill(process.pid)
                    return
                }
                process.write(data)
            },
            resize: { viewport in
                let size = PTYSize(
                    columns: viewport.columns,
                    rows: viewport.rows,
                    widthPixels: UInt16(clamping: viewport.widthPixels),
                    heightPixels: UInt16(clamping: viewport.heightPixels)
                )
                TerminalResizeLog.write("ghostty resize \(size.columns)x\(size.rows)")
                if size.columns > 0, size.rows > 0 { grid.size = size }
                if spawner.spawnIfNeeded(size) { return }
                process.resizeCoalesced(size)
            }
        )
        controller = TerminalController(theme: TerminalAppearance.terminalTheme(
            for: theme, fontSize: fontSize, metrics: Self.inputMetrics()))
        terminalView = TerminalView(frame: .zero)
        super.init(frame: .zero)
        TerminalResizeLog.enableIfRequested()

        configureSession(theme: theme, spawner: spawner, fallbackSize: launch.size)
    }

    private func configureSession(theme: Theme, spawner: DeferredSpawn, fallbackSize: PTYSize) {
        let forceKill = forceKill
        let history = history
        let process = process
        let tap = tap
        let scrollback = scrollback
        forceKill.session = session
        history.onChange = { [weak self] entries in self?.onPromptHistoryChange?(entries) }
        terminalView.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        terminalView.delegate = self
        registerForDraggedTypes([.fileURL] + SmartPaste.imageTypes)
        dropHighlight = theme.nsColor(.accent)
        terminalView.controller = controller
        terminalView.translatesAutoresizingMaskIntoConstraints = true
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
        linkHighlight.color = theme.nsColor(.accent)
        linkHighlight.thickness = Self.inputMetrics()?.size(1) ?? 1
        addSubview(linkHighlight)

        let session = session
        let activity = activity
        if let restored = scrollback?.load(), !restored.isEmpty {
            session.receive(ScrollbackFile.withoutQueries(restored) + ScrollbackFile.replayReset)
            scrollback?.append(ScrollbackFile.replayReset)
        }
        let servers = servers
        process.onOutput = { data in
            activity.touch()
            servers.scan(data)
            tap.output(data)
            scrollback?.append(data)
            session.receive(data)
        }
        process.onExit = { [weak self] code in
            activity.finish()
            Task { @MainActor in self?.onExit?(code) }
        }
        spawner.configure(process: process, fallback: fallbackSize) { [weak self] code in
            session.receive(Data("\r\n\u{1b}[31m[\(String(cString: strerror(code)))]\u{1b}[0m\r\n".utf8))
            Task { @MainActor in self?.onExit?(127) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { spawner.spawnIfNeeded(nil) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override public func layout() {
        super.layout()
        syncSurfaceSize()
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSurfaceSize()
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { syncSurfaceSize() }
    }

    override public func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil { syncSurfaceSize() }
    }

    override public func viewDidUnhide() {
        super.viewDidUnhide()
        syncSurfaceSize()
    }

    public func syncSurfaceSize() {
        let frame = TerminalAppearance.surfaceFrame(in: bounds, metrics: Self.inputMetrics())
        if terminalView.frame != frame { terminalView.frame = frame }
        terminalView.fitToSize()
        scheduleSettle()
    }

    private var settleWork: DispatchWorkItem?

    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, window != nil, bounds.width > 0, bounds.height > 0 else { return }
            let frame = TerminalAppearance.surfaceFrame(in: bounds, metrics: Self.inputMetrics())
            if terminalView.frame != frame { terminalView.frame = frame }
            terminalView.fitToSize()
            let size = grid.size
            if size.columns > 0, size.rows > 0 { process.reassertSize(size) }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    public func focus() {
        window?.makeFirstResponder(terminalView)
    }

    public func applyTheme(_ theme: Theme, fontSize: Float = TerminalAppearance.defaultFontSize) {
        _ = controller.setTheme(TerminalAppearance.terminalTheme(
            for: theme, fontSize: fontSize, metrics: Self.inputMetrics()))
        syncSurfaceSize()
        dropHighlight = theme.nsColor(.accent)
        linkHighlight.color = theme.nsColor(.accent)
        linkHighlight.thickness = Self.inputMetrics()?.size(1) ?? 1
        highlightWebLink(at: nil)
    }

    public var hasSelection: Bool { terminalView.selectionMenuPoint(at: .zero) != nil }

    @discardableResult
    public func copySelection() -> Bool {
        guard terminalView.copySelectedTextToPasteboard() else { return false }
        terminalView.performBindingAction("clear_selection")
        return true
    }

    public func copyOrInterrupt() {
        if !copySelection() {
            terminalView.sendKey(.c, modifiers: .ctrl)
        }
    }

    @discardableResult
    public func pasteClipboard(from pasteboard: NSPasteboard = .general) -> Bool {
        let text: String
        let payload = SmartPaste.payload(from: pasteboard)
        if case .paths(let paths) = payload {
            text = SmartPaste.format(paths: paths)
        } else if case .image(let data) = payload {
            guard let path = try? SmartPaste.saveImage(data) else { return false }
            text = SmartPaste.format(paths: [path])
        } else if case .text(let value) = payload {
            text = SmartPaste.normalizeText(value)
        } else {
            return false
        }
        return terminalView.paste(text: text)
    }

    public func copyOrPaste() {
        if !copySelection() {
            pasteClipboard()
        }
    }

    private var dropHighlight = NSColor.controlAccentColor

    public func pasteImageIfNeeded(from pasteboard: NSPasteboard = .general) -> Bool {
        guard case .image(let data) = SmartPaste.payload(from: pasteboard),
              let path = try? SmartPaste.saveImage(data) else { return false }
        return terminalView.paste(text: SmartPaste.format(paths: [path]))
    }

    override public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard SmartPaste.payload(from: sender.draggingPasteboard) != .empty else { return [] }
        setDropHighlighted(true)
        return .copy
    }

    override public func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setDropHighlighted(false)
    }

    override public func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        setDropHighlighted(false)
    }

    override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        setDropHighlighted(false)
        let text: String
        let payload = SmartPaste.payload(from: sender.draggingPasteboard)
        if case .paths(let paths) = payload {
            text = SmartPaste.format(paths: paths)
        } else if case .image(let data) = payload {
            guard let path = try? SmartPaste.saveImage(data) else { return false }
            text = SmartPaste.format(paths: [path])
        } else if case .text(let string) = payload {
            text = string
        } else {
            return false
        }
        focus()
        return terminalView.paste(text: text)
    }

    private func setDropHighlighted(_ highlighted: Bool) {
        wantsLayer = true
        layer?.borderWidth = highlighted ? 2 : 0
        layer?.borderColor = dropHighlight.cgColor
    }

    public func deliverPrompt(_ prompt: String, style: PromptDelivery.Style) async -> Bool {
        let clock = ContinuousClock()
        let origin = clock.now
        let activity = activity
        let process = process
        let tap = tap
        let io = PromptDelivery.IO(
            now: { origin.duration(to: clock.now) },
            sleep: { try? await Task.sleep(for: $0) },
            quietFor: { activity.quietFor },
            isRunning: { activity.isRunning },
            readScreen: { [weak self] in await MainActor.run { self?.viewportText() ?? "" } },
            write: { text in
                let data = Data(text.utf8)
                tap.input(data)
                process.write(data)
            })
        return await PromptDelivery.deliver(prompt, style: style, io: io)
    }

    public func type(_ text: String) {
        let data = Data(text.utf8)
        tap.input(data)
        process.write(data)
    }

    public func viewportText() -> String? {
        session.readViewportText()
    }

    @discardableResult
    public func jumpToPrompt(_ delta: Int) -> Bool {
        terminalView.jumpToPrompt(by: Int16(clamping: delta))
    }

    public func clearScrollback() {
        terminalView.performBindingAction("clear_screen")
        scrollback?.clear()
    }

    @discardableResult
    public func recallPrompt(_ direction: PromptHistory.Direction) -> Bool {
        guard let entry = history.recall(direction) else { return false }
        let data = Data(PromptHistory.recallInput(entry).utf8)
        tap.input(data)
        process.write(data)
        return true
    }

    public func showSearch(needle: String? = nil) {
        search.isPresented = true
        search.focusRequest += 1
        if let needle, !needle.isEmpty {
            updateSearch(needle, resetProgress: Self.inputMetrics()?.isWebInterface == true)
        }
    }

    public func updateSearch(_ text: String, resetProgress: Bool = false) {
        let needle = search.setNeedle(text, resetProgress: resetProgress)
        terminalView.performBindingAction("search:\(needle)")
    }

    public func searchSelection() {
        terminalView.performBindingAction("search_selection")
    }

    @discardableResult
    public func searchNext() -> Bool {
        terminalView.performBindingAction("navigate_search:next")
    }

    @discardableResult
    public func searchPrevious() -> Bool {
        terminalView.performBindingAction("navigate_search:previous")
    }

    public func closeSearch() {
        terminalView.performBindingAction("end_search")
        resetSearch()
        focus()
    }

    private func resetSearch() {
        search.isPresented = false
        search.needle = ""
        search.total = nil
        search.selected = nil
    }

    public func forceKillTree() {
        guard forceKill.trigger() else { return }
        forceKill.session?.receive(forceKillNotice)
        ProcessTree.kill(process.pid)
    }

    public func terminate() {
        process.terminate()
    }
}

extension TerminalPaneView: TerminalSurfaceOpenURLDelegate, TerminalSurfacePwdDelegate, TerminalSurfaceHoverLinkDelegate {
    public func terminalDidUpdateHoverLink(_ url: String?) {
        if Self.inputMetrics()?.isWebInterface != true { hoveredLink = url }
    }

    public func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        if let onOpenLink {
            onOpenLink(url)
        } else if let target = URL(string: url) {
            NSWorkspace.shared.open(target)
        }
    }

    public func terminalDidChangeWorkingDirectory(_ path: String) {
        reportedDirectory = TerminalLink.workingDirectory(fromReported: path) ?? reportedDirectory
    }
}

extension TerminalPaneView: TerminalSurfaceSearchDelegate {
    public func terminalDidRequestSearch(needle: String) {
        showSearch(needle: needle)
    }

    public func terminalDidEndSearch() {
        resetSearch()
    }

    public func terminalDidUpdateSearchTotal(_ total: Int?) {
        search.total = total
    }

    public func terminalDidUpdateSearchSelected(_ selected: Int?) {
        search.selected = selected
    }
}

private final class LocalServerState: @unchecked Sendable {
    private let detector = Mutex(LocalServerDetector())
    @MainActor var onFound: ((URL) -> Void)?

    init() {}

    func scan(_ data: Data) {
        let found = detector.withLock { $0.scan(data) }
        guard !found.isEmpty else { return }
        Task { @MainActor [weak self] in found.forEach { self?.onFound?($0) } }
    }
}

private final class PromptHistoryState: @unchecked Sendable {
    private let state: Mutex<PromptHistory>
    @MainActor var onChange: (([String]) -> Void)?

    init(_ history: PromptHistory) { state = Mutex(history) }

    func record(_ input: Data) {
        guard let text = String(data: input, encoding: .utf8) else { return }
        let changed: [String]? = state.withLock { $0.record(text) ? $0.entries : nil }
        guard let changed else { return }
        Task { @MainActor [weak self] in self?.onChange?(changed) }
    }

    func recall(_ direction: PromptHistory.Direction) -> String? {
        state.withLock { $0.recall(direction) }
    }
}

private final class ForceKillState: @unchecked Sendable {
    private let state = Mutex<(detector: DoubleInterrupt, triggered: Bool)>((DoubleInterrupt(), false))
    weak var session: InMemoryTerminalSession?

    func register(_ input: Data) -> Bool {
        state.withLock { state in
            let fire = !state.triggered && state.detector.register(input, at: .now)
            if fire { state.triggered = true }
            return fire
        }
    }

    func trigger() -> Bool {
        state.withLock { state in
            guard !state.triggered else { return false }
            state.triggered = true
            return true
        }
    }

    var triggered: Bool { state.withLock { $0.triggered } }
}

private final class GridSizeState: Sendable {
    private let state: Mutex<PTYSize>

    init(_ size: PTYSize) { state = Mutex(size) }

    var size: PTYSize {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

private final class TerminalActivity: Sendable {
    private let state = Mutex<(last: ContinuousClock.Instant, running: Bool)>((ContinuousClock.now, true))

    func touch() { state.withLock { $0.last = .now } }
    func finish() { state.withLock { $0.running = false } }
    var quietFor: Duration { state.withLock { $0.last.duration(to: .now) } }
    var isRunning: Bool { state.withLock { $0.running } }
}

private final class DeferredSpawn: @unchecked Sendable {
    private let lock = NSLock()
    private var process: PTYProcess?
    private var fallback = PTYSize(columns: 80, rows: 24)
    private var failed: (@Sendable (Int32) -> Void)?
    private var done = false

    func configure(process: PTYProcess, fallback: PTYSize, failed: @escaping @Sendable (Int32) -> Void) {
        lock.withLock {
            self.process = process
            self.fallback = fallback
            self.failed = failed
        }
    }

    @discardableResult
    func spawnIfNeeded(_ size: PTYSize?) -> Bool {
        let claim: (PTYProcess, PTYSize, (@Sendable (Int32) -> Void)?)? = lock.withLock {
            guard !done, let process, size.map({ $0.columns > 0 && $0.rows > 0 }) ?? true else { return nil }
            done = true
            return (process, size ?? fallback, failed)
        }
        guard let (process, size, failed) = claim else { return false }
        do {
            try process.spawn(size: size)
        } catch PTYError.spawnFailed(let code) {
            failed?(code)
        } catch {
            failed?(EIO)
        }
        return true
    }
}

extension TerminalPaneView: TerminalSurfaceGridResizeDelegate {
    public func terminalDidResize(_ size: TerminalGridMetrics) {
        linkGrid = size
        highlightWebLink(at: nil)
    }
}
