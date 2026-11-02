import Foundation

@main
enum AudioDuckingPlannerTests {
    static func main() {
        testMergesNearbySpeechWords()
        testLocalizesRangesToMusicClip()
        testDucksDuringSpeechAndRecoversAfter()
        testBuildsSortedAutomationPoints()
        testIgnoresInvalidRanges()
        print("5 testes de AudioDuckingPlanner passaram.")
    }

    static func testMergesNearbySpeechWords() {
        let result = AudioDuckingPlanner.merge([
            .init(start: 1.0, end: 1.2),
            .init(start: 1.3, end: 1.5),
            .init(start: 2.2, end: 2.4)
        ])
        expect(result.count == 2, "merge count")
        expect(abs(result[0].end - 1.5) < 0.0001, "merge end")
    }

    static func testLocalizesRangesToMusicClip() {
        let result = AudioDuckingPlanner.localize(
            [.init(start: 12, end: 18), .init(start: 25, end: 30)],
            clipStart: 15,
            clipDuration: 10
        )
        // The second interval touches the clip end but has no positive overlap.
        expect(result.count == 1 && result[0] == .init(start: 0, end: 3), "clip range intersection")
    }

    static func testDucksDuringSpeechAndRecoversAfter() {
        let ranges = [AudioDuckingRange(start: 2, end: 4)]
        expect(abs(AudioDuckingPlanner.factor(at: 1.0, ranges: ranges, duckLevel: 0.2) - 1) < 0.0001, "before speech")
        expect(AudioDuckingPlanner.factor(at: 2.2, ranges: ranges, duckLevel: 0.2) < 0.5, "during speech")
        expect(abs(AudioDuckingPlanner.factor(at: 4.5, ranges: ranges, duckLevel: 0.2) - 1) < 0.0001, "after speech")
    }

    static func testBuildsSortedAutomationPoints() {
        let points = AudioDuckingPlanner.automationPoints(
            ranges: [.init(start: 2, end: 4)], duration: 6
        )
        expect(points == points.sorted(), "automation sorted")
        expect(points.first == 0 && points.last == 6, "automation boundaries")
        expect(points.contains(2) && points.contains(4), "speech boundaries")
    }

    static func testIgnoresInvalidRanges() {
        let result = AudioDuckingPlanner.merge([
            .init(start: 4, end: 3),
            .init(start: .nan, end: 8),
            .init(start: 1, end: 2)
        ])
        expect(result == [.init(start: 1, end: 2)], "invalid range filtering")
    }

    static func expect(_ condition: Bool, _ name: String) {
        if !condition {
            fputs("FALHOU: \(name)\\n", stderr)
            exit(1)
        }
    }
}
