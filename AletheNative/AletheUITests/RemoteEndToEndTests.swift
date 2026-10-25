import WebKit
import XCTest

@MainActor
final class RemoteEndToEndTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func testPhoneClientPairsControlsSharedTerminalAndIsRevoked() async throws {
        let dataRoot = makeTemporaryDataRoot()
        let (app, _) = launchAlethe(dataRoot: dataRoot, arguments: ["-AletheUITestSeed", "remoteE2E"])
        XCTAssertTrue(element(app, "pane.header.shared").waitForExistence(timeout: 10))

        let firstURL = try openPairingURL(app)
        XCTAssertEqual(firstURL.host(), "127.0.0.1", "test launches bind loopback only")
        let phone = RemotePage()
        phone.load(firstURL, view: "terminal")
        let paired = await phone.waitFor("document.querySelectorAll('[data-chat]').length > 0")
        XCTAssertTrue(paired, "the page paired and listed the workspace")
        let names = await phone.strings("[...document.querySelectorAll('[data-chat] .terminal-name')].map((e) => e.textContent)")
        XCTAssertEqual(names, ["shared"], "only the shared terminal is listed")
        let sessionToken = await phone.string("sessionStorage.getItem('alethe.remote.session') || ''") ?? ""
        XCTAssertEqual(sessionToken.count, 40, "the page holds a device session")
        XCTAssertTrue(element(app, "remote.pairing.device.1").waitForExistence(timeout: 5), "the Mac lists the device")
        element(app, "remote.pairing.done").click()

        try await exerciseTerminal(app, phone: phone)

        let secondURL = try openPairingURL(app)
        XCTAssertNotEqual(secondURL, firstURL, "a new pairing token")
        let second = RemotePage()
        second.load(secondURL)
        let limited = await second.waitFor(
            "(document.querySelector('.state-page code')?.textContent || '').includes('Maximum remote devices reached')")
        XCTAssertTrue(limited, "the second device is refused at the limit")
        XCTAssertFalse(element(app, "remote.pairing.device.2").exists)

        let replay = RemotePage()
        replay.load(firstURL)
        let replayRefused = await replay.waitFor(
            "(document.querySelector('.state-page code')?.textContent || '').includes('Invalid pairing token')")
        XCTAssertTrue(replayRefused, "a used pairing token is refused")

        element(app, "remote.pairing.revoke.1").click()
        let ended = await phone.waitFor("document.querySelector('.state-page h1')?.textContent === 'Remote session ended'", timeout: 15)
        XCTAssertTrue(ended, "the revoked page shows the session ended")
        let dropped = await phone.bool("sessionStorage.getItem('alethe.remote.session') === null")
        XCTAssertTrue(dropped, "the page dropped its session")
        XCTAssertTrue(element(app, "remote.pairing.noDevices").waitForExistence(timeout: 5))
        let status = try await infoStatus(of: firstURL, sessionToken: sessionToken)
        XCTAssertEqual(status, 401, "a revoked session token is refused")
        element(app, "remote.pairing.done").click()
        app.terminate()

        let tokens = [pairingToken(firstURL), pairingToken(secondURL), sessionToken].compactMap { $0 }.filter { !$0.isEmpty }
        XCTAssertEqual(tokens.count, 3)
        let scanned = scanForTokens(tokens, under: dataRoot)
        XCTAssertTrue(scanned.files.contains("workspace.json"), "workspace.json was scanned")
        XCTAssertTrue(scanned.hits.isEmpty, "a remote token was written to \(scanned.hits.joined(separator: ", "))")
    }

    private func exerciseTerminal(_ app: XCUIApplication, phone: RemotePage) async throws {
        let live = await phone.waitFor("document.querySelector('[data-connection]')?.dataset.state === 'live'")
        XCTAssertTrue(live, "the WebSocket authenticated")
        await phone.run("document.querySelector('[data-chat]').click()")
        let composer = await phone.waitFor("document.querySelector('#composer') !== null")
        XCTAssertTrue(composer)
        let subscribed = await phone.waitFor("window.__e2e.types().includes('scrollback')")
        XCTAssertTrue(subscribed, "subscribing sent the scrollback")
        await phone.send("e2e-ping")
        let echoed = await phone.waitFor("window.__e2e.output().includes('fake-claude got: e2e-ping')", timeout: 15)
        XCTAssertTrue(echoed, "the message reached the terminal and its output reached the page")

        await phone.run("document.querySelector('.view-switch [data-view=\"messages\"]').click()")
        let interruptShown = await phone.waitFor("document.querySelector('[data-interrupt]') !== null")
        XCTAssertTrue(interruptShown)
        await phone.run("document.querySelector('[data-interrupt]').click()")
        let interrupted = await phone.waitFor("window.__e2e.output().includes('fake-claude interrupted')", timeout: 15)
        XCTAssertTrue(interrupted, "Interrupt sent Ctrl-C to the agent")
        await phone.run("document.querySelector('.view-switch [data-view=\"terminal\"]').click()")
        let backToTerminal = await phone.waitFor("document.querySelector('#terminal-host') !== null")
        XCTAssertTrue(backToTerminal)

        setReadOnly(app)
        await phone.send("e2e-blocked")
        let refused = await phone.waitFor("(document.querySelector('#composer-error')?.textContent || '').includes('read-only')")
        XCTAssertTrue(refused, "the page shows the read-only refusal")
        try await Task.sleep(for: .seconds(2))
        let blockedOutput = await phone.bool("window.__e2e.output().includes('fake-claude got: e2e-blocked')")
        XCTAssertFalse(blockedOutput, "nothing was typed while read-only")
    }

    private func openPairingURL(_ app: XCUIApplication) throws -> URL {
        let pill = element(app, "remote.toolbarPill")
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        if !element(app, "remote.pairing").exists { pill.click() }
        let text = element(app, "remote.pairing.urlText")
        XCTAssertTrue(text.waitForExistence(timeout: 10), "the pairing window opened")
        var found: URL?
        _ = eventually(timeout: 5) {
            let label = [text.label, text.value as? String ?? ""].joined(separator: " ")
            found = label.firstMatch(of: #/http:
            return found != nil
        }
        return try XCTUnwrap(found, "the pairing URL is shown")
    }

    private func setReadOnly(_ app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command)
        let tab = app.toolbars.buttons["Remote"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        let probe = element(app, "settings.remote.probe")
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        element(app, "settings.remote.readOnly").click()
        XCTAssertTrue(eventually(timeout: 8) {
            let text = (probe.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? probe.label
            return text.contains("readOnly=true")
        }, "read-only reached the hub")
        app.typeKey("w", modifierFlags: .command)
    }

    private func pairingToken(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pair" }?.value
    }

    private func infoStatus(of pairingURL: URL, sessionToken: String) async throws -> Int {
        var components = try XCTUnwrap(URLComponents(url: pairingURL, resolvingAgainstBaseURL: false))
        components.query = nil
        components.path = "/api/info"
        var request = URLRequest(url: try XCTUnwrap(components.url), timeoutInterval: 10)
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let (_, response) = try await URLSession(configuration: configuration).data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private func scanForTokens(_ tokens: [String], under root: URL) -> (files: Set<String>, hits: [String]) {
        var files = Set<String>()
        var hits: [String] = []
        let needles = tokens.map { Data($0.utf8) }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey,
            .fileSizeKey]) else {
            return (files, hits)
        }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) < 64 * 1024 * 1024,
                  let data = try? Data(contentsOf: url) else { continue }
            files.insert(url.lastPathComponent)
            if needles.contains(where: { data.range(of: $0) != nil }) {
                hits.append(String(url.path.dropFirst(root.path.count)))
            }
        }
        return (files, hits)
    }
}

@MainActor
private final class RemotePage {
    let webView: WKWebView

    private static let recorder = """
    (() => {
      const frames = []
      const Native = window.WebSocket
      class RecordingWebSocket extends Native {
        constructor(...args) {
          super(...args)
          this.addEventListener('message', (event) => {
            try {
              const message = JSON.parse(event.data)
              frames.push({ type: String(message.type || ''), text: String(message.text || '') })
            } catch {}
          })
        }
      }
      window.WebSocket = RecordingWebSocket
      window.__e2e = {
        types: () => frames.map((frame) => frame.type),
        output: () => frames
          .filter((frame) => frame.type === 'pty_output' || frame.type === 'scrollback')
          .map((frame) => frame.text)
          .join(''),
      }
    })()
    """

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.recorder, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
    }

    func load(_ url: URL, view: String? = nil) {
        if let view {
            let script = "try { localStorage.setItem('alethe.remote.chatView', '\(view)') } catch {}"
            webView.configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        webView.load(URLRequest(url: url))
    }

    func send(_ text: String) async {
        let literal = String(decoding: (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
        await run("""
        (() => {
          const input = document.querySelector('#message')
          input.value = \(literal)
          input.dispatchEvent(new Event('input'))
          document.querySelector('#composer').requestSubmit()
        })()
        """)
    }

    func run(_ script: String) async {
        _ = await json("(() => { \(script); return true })()")
    }

    func bool(_ expression: String) async -> Bool {
        await json("Boolean(\(expression))") == "true"
    }

    func string(_ expression: String) async -> String? {
        guard let json = await json("String(\(expression))") else { return nil }
        return try? JSONDecoder().decode(String.self, from: Data(json.utf8))
    }

    func strings(_ expression: String) async -> [String] {
        guard let json = await json(expression) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    func waitFor(_ condition: String, timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await bool("(() => { try { return \(condition) } catch { return false } })()") { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private func json(_ expression: String) async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("JSON.stringify(\(expression))") { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
    }
}
