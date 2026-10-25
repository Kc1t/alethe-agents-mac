@testable import AletheModel
import Testing

@Suite struct FuzzyMatchTests {
    @Test func charactersMustAppearInOrder() {
        #expect(FuzzyMatch.match("cld", in: "Claude Code") != nil)
        #expect(FuzzyMatch.match("dlc", in: "Claude Code") == nil)
        #expect(FuzzyMatch.match("", in: "anything")?.score == 0)
        #expect(FuzzyMatch.match("new term", in: "New Terminal") != nil, "spaces are ignored")
    }

    @Test func positionsTightenToTheShortestWindow() {
        #expect(FuzzyMatch.match("ab", in: "a_xab")?.positions == [3, 4])
    }

    @Test func prefixesAndWordStartsBeatScatteredMatches() throws {
        let prefix = (try #require(FuzzyMatch.match("api", in: "api-server"))).score
        let scattered = (try #require(FuzzyMatch.match("api", in: "a pretty idea"))).score
        let inside = (try #require(FuzzyMatch.match("api", in: "rapid"))).score
        #expect(prefix > inside && prefix > scattered)
        let camel = (try #require(FuzzyMatch.match("nt", in: "newTerminal"))).score
        let plain = (try #require(FuzzyMatch.match("nt", in: "count"))).score
        #expect(camel > plain, "a camel-case word start counts as a boundary")
    }

    @Test func rankingOrdersByScoreAndKeepsTiesStable() {
        let items = ["web", "api", "api-gateway", "rapid"]
        let ranked = FuzzyMatch.rank(items, query: "api") { [$0] }.map(\.item)
        #expect(ranked.first == "api")
        #expect(!ranked.contains("web"))
        #expect(FuzzyMatch.rank(items, query: "") { [$0] }.map(\.item) == items, "an empty query keeps the order")
    }

    @Test func theBestFieldCounts() {
        let ranked = FuzzyMatch.rank([("Shell", "docs"), ("Claude Code", "api")], query: "api") { [$0.0, $0.1] }
        #expect(ranked.map(\.item.0) == ["Claude Code"])
    }
}
