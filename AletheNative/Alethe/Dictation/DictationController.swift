import AletheFoundation
import AletheTerminal
import AppKit
import AVFoundation
import Observation

@Observable
@MainActor
final class DictationController {
    let settings = DictationSettings()
    let jev = JevController()
    @ObservationIgnored private var voiceCommand = false
    @ObservationIgnored private var heldWebKey: UInt16?
    @ObservationIgnored private var deactivation: NSObjectProtocol?
    @ObservationIgnored private var generation = 0
    private(set) var machine = DictationMachine()
    private(set) var liveText = ""
    private(set) var downloadingModel = false
    @ObservationIgnored private weak var environment: AppEnvironment?
    @ObservationIgnored private var engine: DictationEngine?
    @ObservationIgnored private var target: Target?
    @ObservationIgnored private var lastInserted = ""
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var ready = false

    private enum Target {
        case terminal(TerminalPaneView)
        case text(NSTextInputClient)
    }

    func start(environment: AppEnvironment) {
        guard monitor == nil else { return }
        self.environment = environment
        jev.start(environment: environment)
        deactivation = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.environment?.interfaceStyle == .web else { return }
                self?.cancelSession()
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if environment?.interfaceStyle == .web, let handled = handleWeb(event, flags: flags) { return handled }
        guard event.type != .flagsChanged else { return false }
        if event.type == .keyDown, event.keyCode == 53, machine.isActive || machine.phase != .idle {
            apply(machine.escape())
            return true
        }
        guard event.charactersIgnoringModifiers?.lowercased() == "e", flags == [.command, .option] else { return false }
        if event.type == .keyDown {
            if !event.isARepeat { apply(machine.keyDown(at: event.timestamp)) }
        } else {
            apply(machine.keyUp(at: event.timestamp))
        }
        return true
    }

    private func handleWeb(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool? {
        if event.type == .flagsChanged, heldWebKey == 14,
           !flags.contains(.command) && !flags.contains(.control) {
            heldWebKey = nil
            if machine.phase == .starting || machine.phase == .listening { apply(machine.toggle()) }
            return false
        }
        if event.type == .keyUp, heldWebKey == event.keyCode {
            heldWebKey = nil
            if machine.phase == .starting || machine.phase == .listening { apply(machine.toggle()) }
            return true
        }
        if let handled = handleWebCommand(event, flags: flags) { return handled }
        if event.type == .flagsChanged { return false }
        if !settings.enabled { return false }
        return nil
    }

    private func handleWebCommand(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool? {
        if event.type == .keyDown, !event.isARepeat,
           event.keyCode == 49, flags == [.command, .shift] || flags == [.control, .shift] {
            if jev.open { cancelSession() }
            else {
                if machine.isActive { apply(machine.escape()) }
                voiceCommand = false
                jev.open = true
                jev.message = ""
            }
            return true
        }
        if jev.open, event.type == .keyDown, !event.isARepeat, event.keyCode == 53 { cancelSession(); return true }
        if jev.open, event.type == .keyDown, !event.isARepeat, event.keyCode == 36, jev.pendingID != nil {
            jev.confirm(); return true
        }
        if jev.open, event.keyCode == 101 {
            guard settings.enabled else { return false }
            if event.type == .keyDown, !event.isARepeat, !machine.isActive {
                voiceCommand = true
                jev.heard = ""
                jev.message = ""
                jev.listening = true
                heldWebKey = event.keyCode
                apply(machine.toggle())
            }
            return true
        }
        if event.keyCode == 14, flags == [.command] || flags == [.control] {
            guard settings.enabled, !jev.open else { return false }
            if event.type == .keyDown, !event.isARepeat {
                voiceCommand = false
                if settings.hold { heldWebKey = event.keyCode }
                apply(machine.toggle())
            }
            return true
        }
        return nil
    }

    func toggle() {
        if environment?.interfaceStyle == .web, !settings.enabled { return }
        if jev.open { cancelSession() }
        voiceCommand = false
        apply(machine.toggle())
    }

    func toggleVoice() {
        guard settings.enabled else { return }
        if !machine.isActive {
            voiceCommand = true
            jev.heard = ""
            jev.message = ""
            jev.listening = true
        }
        apply(machine.toggle())
    }

    func cancelSession() {
        heldWebKey = nil
        apply(machine.escape())
        jev.close()
    }

    func dismissFailure() { _ = machine.escape() }

    private func apply(_ effect: DictationMachine.Effect) {
        if case .none = effect { return }
        if case .start = effect {
            Task { await begin() }
        } else if case .stop = effect {
            Task { await end() }
        } else {
            generation += 1
            ready = false
            target = nil
            liveText = ""
            downloadingModel = false
            let engine = engine
            self.engine = nil
            Task { await engine?.cancel() }
        }
    }

    private func begin() async {
        guard machine.isActive else { return }
        generation += 1
        let session = generation
        target = voiceCommand ? nil : Self.focusedTarget()
        lastInserted = ""
        liveText = ""
        ready = false
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "AletheDictationDenied") {
            permissionFailed(session: session)
            return
        }
        #endif
        guard await Self.microphoneAllowed() else {
            permissionFailed(session: session)
            return
        }
        guard machine.isActive, generation == session else { return }
        let engine = DictationEngine()
        self.engine = engine
        do {
            let web = environment?.interfaceStyle == .web
            let fallback = environment?.dictationLocale ?? .current
            try await engine.start(locale: web ? settings.selectedLocale(fallback: fallback) : fallback,
                                   microphone: web ? settings.microphone : "",
                                   onModelDownload: { [weak self] in
                                       guard let self, self.generation == session else { return }
                                       self.downloadingModel = true
                                   },
                                   onResult: { [weak self] text, isFinal in
                                       guard let self, self.generation == session else { return }
                                       self.receive(text, isFinal: isFinal)
                                   })
            guard self.engine === engine else { return await engine.cancel() }
            downloadingModel = false
            ready = true
            if case .starting = machine.phase {
                machine.started()
            } else if case .finishing = machine.phase {
                await end()
            }
        } catch {
            guard self.engine === engine else { return }
            downloadingModel = false
            self.engine = nil
            await engine.cancel()
            if voiceCommand { jev.failed(String(localized: "dictation.unavailable")); voiceCommand = false }
            if machine.isActive {
                machine.failed(error as? DictationEngine.StartError == .languageUnsupported ? .languageUnsupported : .unavailable)
            }
        }
    }

    private func end() async {
        guard let engine else {
            if machine.phase == .finishing, !downloadingModel {
                generation += 1
                machine.finished()
                if voiceCommand { jev.recognize(jev.heard); voiceCommand = false }
            }
            return
        }
        guard ready else { return }
        let session = generation
        ready = false
        await engine.stop()
        guard generation == session else { return }
        self.engine = nil
        if voiceCommand { jev.recognize(jev.heard); voiceCommand = false }
        liveText = ""
        machine.finished()
        target = nil
    }

    private func receive(_ text: String, isFinal: Bool) {
        guard machine.isActive else { return }
        if voiceCommand {
            if isFinal {
                if !jev.heard.isEmpty { jev.heard += " " }
                jev.heard += text
                liveText = ""
            } else { liveText = text }
            return
        }
        if isFinal {
            liveText = ""
            insert(text)
        } else {
            liveText = text
        }
    }

    private func insert(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let last = lastInserted.last, !last.isWhitespace { text = " " + text }
        lastInserted = text
        if case .terminal(let view)? = target {
            view.type(text)
        } else if case .text(let client)? = target {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    private static func focusedTarget() -> Target? {
        let responder = NSApp.keyWindow?.firstResponder
        var view = responder as? NSView
        while let current = view {
            if let terminal = current as? TerminalPaneView { return .terminal(terminal) }
            view = current.superview
        }
        return (responder as? NSTextInputClient).map { .text($0) }
    }

    private func permissionFailed(session: Int) {
        guard generation == session, machine.isActive else { return }
        machine.failed(.microphoneDenied)
        if voiceCommand { jev.failed(String(localized: "dictation.denied")); voiceCommand = false }
    }

    private static func microphoneAllowed() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if case .authorized = status { return true }
        if case .notDetermined = status { return await AVCaptureDevice.requestAccess(for: .audio) }
        return false
    }
}
