import Foundation

public enum PromptDelivery {
    public struct IO: Sendable {
        public var now: @Sendable () -> Duration
        public var sleep: @Sendable (Duration) async -> Void
        public var quietFor: @Sendable () -> Duration
        public var isRunning: @Sendable () -> Bool
        public var readScreen: @Sendable () async -> String
        public var write: @Sendable (String) async -> Void

        public init(now: @escaping @Sendable () -> Duration, sleep: @escaping @Sendable (Duration) async -> Void,
                    quietFor: @escaping @Sendable () -> Duration, isRunning: @escaping @Sendable () -> Bool,
                    readScreen: @escaping @Sendable () async -> String, write: @escaping @Sendable (String) async -> Void) {
            self.now = now
            self.sleep = sleep
            self.quietFor = quietFor
            self.isRunning = isRunning
            self.readScreen = readScreen
            self.write = write
        }
    }

    public enum Style: Sendable {
        case paste
        case typeAndConfirm
    }

    public static func waitUntilReady(style: Style, io: IO, deadline: Duration = .seconds(120)) async -> Bool {
        let start = io.now()
        let earliest = start + (style == .typeAndConfirm ? .seconds(4) : .milliseconds(1500))
        let forced = start + .seconds(4)
        while io.now() < start + deadline {
            await io.sleep(.milliseconds(250))
            let now = io.now()
            let settled = style == .typeAndConfirm || io.quietFor() >= .milliseconds(700) || now >= forced
            if now >= earliest, io.isRunning(), settled { return true }
            if !io.isRunning(), now >= earliest { return false }
        }
        return false
    }

    public static func deliver(_ prompt: String, style: Style, io: IO, deadline: Duration = .seconds(120)) async -> Bool {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let start = io.now()
        guard await waitUntilReady(style: style, io: io, deadline: deadline) else { return false }
        if case .paste = style {
            await io.write("\u{1b}[200~" + text + "\u{1b}[201~")
            await io.sleep(.milliseconds(150))
            await io.write("\r")
            Task {
                await io.sleep(.milliseconds(1200))
                if io.isRunning() { await io.write("\r") }
            }
            return true
        }
        return await typeAndConfirm(text, io: io, deadline: start + deadline)
    }

    static let placeholder = normalizedForMatch("Ask anything")

    static func normalizedForMatch(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        })).lowercased()
    }

    private static func typeAndConfirm(_ prompt: String, io: IO, deadline: Duration) async -> Bool {
        let normalized = normalizedForMatch(prompt)
        let head = String(normalized.prefix(20)), tail = String(normalized.suffix(20))
        func onScreen(_ screen: String) -> Bool {
            let text = normalizedForMatch(screen)
            return (!head.isEmpty && text.contains(head)) || (!tail.isEmpty && text.contains(tail))
        }
        func type() async {
            var index = prompt.startIndex
            while index < prompt.endIndex {
                let end = prompt.index(index, offsetBy: 6, limitedBy: prompt.endIndex) ?? prompt.endIndex
                await io.write(String(prompt[index..<end]))
                await io.sleep(.milliseconds(30))
                index = end
            }
        }

        var confirmed = false
        var firstRound = true
        while !confirmed, io.now() < deadline {
            let screen = await io.readScreen()
            if firstRound || normalizedForMatch(screen).contains(placeholder) || !onScreen(screen) {
                firstRound = false
                await type()
            }
            let roundDeadline = min(deadline, io.now() + .seconds(8))
            while io.now() < roundDeadline {
                if onScreen(await io.readScreen()) {
                    confirmed = true
                    break
                }
                await io.sleep(.milliseconds(700))
            }
        }
        guard confirmed else { return false }

        await io.sleep(.milliseconds(150))
        var previous = await io.readScreen()
        for _ in 0..<4 where io.now() < deadline {
            await io.write("\r")
            await io.sleep(.milliseconds(1500))
            let current = await io.readScreen()
            if current != previous { break }
            previous = current
        }
        return true
    }
}
