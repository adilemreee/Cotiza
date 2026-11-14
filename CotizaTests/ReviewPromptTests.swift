import Foundation
import Testing
@testable import Cotiza

@Suite("Rating prompt")
struct ReviewPromptTests {
    private func prompt(installed daysAgo: Double) throws -> ReviewPrompt {
        let defaults = try #require(UserDefaults(suiteName: "review-\(UUID())"))
        defaults.set(Date.now.addingTimeInterval(-daysAgo * 86_400), forKey: "review.firstSeen")
        return ReviewPrompt(defaults: defaults)
    }

    @Test func `asks only after three good moments and a few days`() throws {
        let fresh = try prompt(installed: 1)
        for _ in 0..<5 { fresh.recordGoodMoment() }
        #expect(!fresh.shouldAsk(), "too soon after install")

        let settled = try prompt(installed: 10)
        settled.recordGoodMoment()
        settled.recordGoodMoment()
        #expect(!settled.shouldAsk(), "two good moments aren't enough")
        settled.recordGoodMoment()
        #expect(settled.shouldAsk())
    }

    @Test func `asks once per version and not again for months`() throws {
        let p = try prompt(installed: 10)
        for _ in 0..<3 { p.recordGoodMoment() }
        p.markAsked(now: .now, version: "1.0")
        #expect(!p.shouldAsk(now: .now, version: "1.0"))
        #expect(!p.shouldAsk(now: .now.addingTimeInterval(30 * 86_400), version: "1.1"), "a new version, but too soon")
        #expect(p.shouldAsk(now: .now.addingTimeInterval(130 * 86_400), version: "1.1"))
    }
}
