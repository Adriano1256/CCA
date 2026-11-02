import Foundation

/// Converts a reviewed, non-destructive Director draft into clip instructions.
/// It never modifies source media and keeps speech candidates at their full source duration.
struct DirectorClipInstruction: Codable, Hashable {
    var segmentID: String
    var mediaID: String
    var track: String
    var timelineStart: Double
    var sourceIn: Double
    var duration: Double
    var volume: Double
    var label: String
}

enum DirectorTimelineMaterializer {
    static func makeInstructions(
        draft: DirectorTimelineDraft,
        media: [DirectorMediaDescriptor],
        appendAt timelineOffset: Double,
        alreadyApplied: Set<String> = [],
        approvedSegmentIDs: Set<String> = []
    ) -> [DirectorClipInstruction] {
        let mediaByID = Dictionary(uniqueKeysWithValues: media.map { ($0.id, $0) })
        return draft.segments.compactMap { segment in
            guard let mediaID = segment.mediaID,
                  let source = mediaByID[mediaID],
                  !alreadyApplied.contains(segment.id),
                  segment.duration.isFinite, segment.duration > 0,
                  segment.sourceIn.isFinite, segment.sourceIn >= 0 else { return nil }

            // A Story video segment may contain an unreviewed spoken statement.
            // Keep it in the draft for approval, but do not commit that trim automatically.
            if segment.role == .storyVisual && segment.requiresReview && !approvedSegmentIDs.contains(segment.id) { return nil }

            let available = max(0, (source.duration ?? segment.sourceIn + segment.duration) - segment.sourceIn)
            let safeDuration = min(segment.duration, available)
            guard safeDuration > 0.05 else { return nil }

            let track: String
            let volume: Double
            switch segment.role {
            case .sonoraCandidate, .storyAudio:
                // Fala em vídeo fica na trilha principal; em áudio separado, na trilha de voz.
                // Ela nunca vai para a trilha musical, que sofre ducking.
                track = source.kind == .video ? "video" : "voice"
                volume = 1.0
            case .visualCoverage:
                // O B-roll entra mudo para não competir com a fala que continua por baixo.
                track = "broll"
                volume = 0
            case .openingVisual, .visualSequence:
                track = "video"
                volume = 0.4
            case .storyVisual:
                track = "video"
                volume = 1.0
            case .institutionalClosingPlaceholder:
                return nil
            }

            let marker = "[IASEG:\(segment.id)]"
            return DirectorClipInstruction(
                segmentID: segment.id,
                mediaID: mediaID,
                track: track,
                timelineStart: max(0, timelineOffset) + segment.timelineStart,
                sourceIn: segment.sourceIn,
                duration: safeDuration,
                volume: volume,
                label: "IA · \(segment.mediaName) \(marker)"
            )
        }
    }
}
