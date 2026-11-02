import Foundation

/// Pure, deterministic audio-ducking math shared by the renderer and tests.
/// All input ranges are expressed in timeline seconds; localized ranges are clip-relative.
struct AudioDuckingRange: Equatable, Hashable, Codable {
    var start: Double
    var end: Double

    var duration: Double { max(0, end - start) }
}

enum AudioDuckingPlanner {
    static func merge(_ ranges: [AudioDuckingRange], maximumGap: Double = 0.42) -> [AudioDuckingRange] {
        let valid = ranges
            .filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard var current = valid.first.map({ [$0] }) else { return [] }
        for range in valid.dropFirst() {
            let lastIndex = current.count - 1
            if range.start - current[lastIndex].end <= max(0, maximumGap) {
                current[lastIndex].end = max(current[lastIndex].end, range.end)
            } else {
                current.append(range)
            }
        }
        return current
    }

    static func localize(_ ranges: [AudioDuckingRange], clipStart: Double, clipDuration: Double) -> [AudioDuckingRange] {
        guard clipStart.isFinite, clipDuration.isFinite, clipDuration > 0 else { return [] }
        let clipEnd = clipStart + clipDuration
        return ranges.compactMap { range in
            let start = max(clipStart, range.start)
            let end = min(clipEnd, range.end)
            guard end > start else { return nil }
            return AudioDuckingRange(start: start - clipStart, end: end - clipStart)
        }
    }

    static func factor(
        at time: Double,
        ranges: [AudioDuckingRange],
        duckLevel: Double,
        attack: Double = 0.12,
        release: Double = 0.24
    ) -> Double {
        guard time.isFinite else { return 1 }
        let safeLevel = min(0.8, max(0.05, duckLevel))
        let safeAttack = max(0.001, attack)
        let safeRelease = max(0.001, release)
        var result = 1.0
        for range in ranges where range.end > range.start {
            let duckStart = max(0, range.start - safeAttack)
            let duckEnd = max(duckStart, range.end + safeRelease)
            guard time >= duckStart && time <= duckEnd else { continue }
            let attackProgress = min(1, max(0, (time - duckStart) / safeAttack))
            let releaseProgress = min(1, max(0, (duckEnd - time) / safeRelease))
            let envelope = min(attackProgress, releaseProgress)
            result = min(result, 1 - (1 - safeLevel) * envelope)
        }
        return result
    }

    static func automationPoints(
        ranges: [AudioDuckingRange],
        duration: Double,
        attack: Double = 0.12,
        release: Double = 0.24
    ) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        var points: Set<Double> = [0, duration]
        for range in ranges {
            let start = max(0, range.start)
            let end = min(duration, range.end)
            guard end > start else { continue }
            points.insert(max(0, start - attack))
            points.insert(start)
            points.insert(min(duration, start + attack))
            points.insert(max(0, end - release))
            points.insert(end)
            points.insert(min(duration, end + release))
        }
        return points.filter { $0.isFinite && $0 >= 0 && $0 <= duration }.sorted()
    }
}
