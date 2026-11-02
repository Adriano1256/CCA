import Foundation

@main
enum TimelineCoreTests {
    static func clip(_ track: String = "video", start: Double, duration: Double, sourceIn: Double = 0) -> TimelineClip {
        TimelineClip(mediaID: UUID(), track: track, start: start, duration: duration, sourceIn: sourceIn, label: "c")
    }

    static func main() {
        frameRateFollowsMaterial()
        lanesReuseFreeTracks()
        splitPreservesSourceAndKeyframes()
        rippleDeleteClosesGapOnlyOnSameTrack()
        trimStartKeepsEndFixed()
        trimEndRespectsSourceButNotPhotos()
        snapPicksClosest()
        storiesAreNumberedInTimelineOrder()
        oldProjectFilesStillOpen()
        projectRoundTripKeepsEverything()
        derivedMediaIsHiddenFromDirector()
        print("TimelineCore: 11 checks passed")
    }

    static func frameRateFollowsMaterial() {
        precondition(FrameRatePlanner.timing(forNominalRates: []) == .standard, "Sem vídeo usa 30 fps")
        precondition(FrameRatePlanner.timing(forNominalRates: [29.97]) == FrameTiming(value: 1001, timescale: 30000), "29,97 exato")
        precondition(FrameRatePlanner.timing(forNominalRates: [29.97, 59.94]) == FrameTiming(value: 1001, timescale: 60000), "Segue o maior")
        precondition(FrameRatePlanner.timing(forNominalRates: [120]) == FrameTiming(value: 1, timescale: 60), "Limita em 60")
        precondition(FrameRatePlanner.timing(forNominalRates: [25]) == FrameTiming(value: 1, timescale: 25), "25 exato")
        precondition(FrameRatePlanner.mismatchWarning(forNominalRates: [29.97, 59.94]) != nil, "Avisa quando são diferentes")
        precondition(FrameRatePlanner.mismatchWarning(forNominalRates: [30, 30]) == nil, "Não avisa quando são iguais")
    }

    static func lanesReuseFreeTracks() {
        let lanes = LaneAllocator.assign([(0, 5), (5, 8), (6, 7), (8, 10), (7, 9)])
        precondition(lanes == [0, 0, 1, 0, 1], "Reaproveita faixas livres: \(lanes)")
    }

    static func splitPreservesSourceAndKeyframes() {
        var original = clip(start: 10, duration: 8, sourceIn: 2)
        original.keyframes = [ClipKeyframe(property: "scale", time: 1, value: 1), ClipKeyframe(property: "scale", time: 6, value: 2)]
        let parts = TimelineEditing.split(original, at: 13)!
        precondition(parts.left.duration == 3 && parts.right.start == 13, "Ponto de corte")
        precondition(parts.right.sourceIn == 5 && parts.right.duration == 5, "Fonte continua de onde parou")
        precondition(parts.left.keyframes.count == 1 && parts.right.keyframes.first?.time == 3, "Keyframes divididos")
        precondition(TimelineEditing.split(original, at: 10.01) == nil, "Não divide na extremidade")
    }

    static func rippleDeleteClosesGapOnlyOnSameTrack() {
        let a = clip(start: 0, duration: 5)
        let b = clip(start: 5, duration: 3)
        let c = clip(start: 8, duration: 2)
        let music = clip("audio", start: 8, duration: 2)
        let result = TimelineEditing.rippleDelete(b.id, in: [a, b, c, music])
        precondition(result.count == 3, "Remove um")
        precondition(result.first { $0.id == c.id }?.start == 5, "Puxa o seguinte")
        precondition(result.first { $0.id == music.id }?.start == 8, "Outra trilha não muda")
    }

    static func trimStartKeepsEndFixed() {
        let original = clip(start: 10, duration: 8, sourceIn: 2)
        let trimmed = TimelineEditing.trimStart(original, by: 3)
        precondition(trimmed.start == 13 && trimmed.end == original.end && trimmed.sourceIn == 5, "Fim fica parado")
        let extended = TimelineEditing.trimStart(original, by: -5)
        precondition(extended.sourceIn == 0 && extended.start == 8, "Não passa do início da mídia")
    }

    static func trimEndRespectsSourceButNotPhotos() {
        let original = clip(start: 0, duration: 8, sourceIn: 2)
        precondition(TimelineEditing.trimEnd(original, by: 100, sourceDuration: 12).duration == 10, "Limite da mídia")
        precondition(TimelineEditing.trimEnd(original, by: 100, sourceDuration: nil).duration == 108, "Foto não tem limite")
    }

    static func snapPicksClosest() {
        precondition(TimelineEditing.snap(5.1, to: [0, 5, 10], tolerance: 0.2) == 5, "Encaixa")
        precondition(TimelineEditing.snap(5.5, to: [0, 5, 10], tolerance: 0.2) == 5.5, "Fora da tolerância")
    }

    static func storiesAreNumberedInTimelineOrder() {
        let ranges = TimelineEditing.storyRanges(from: [clip(start: 5, duration: 2), clip("broll", start: 0, duration: 1), clip(start: 0, duration: 5)])
        precondition(ranges.count == 2 && ranges[0].start == 0 && ranges[1].fileName == "STORY_002.mp4", "Numeração em ordem")
    }

    static func oldProjectFilesStillOpen() {
        let json = #"{"schemaVersion":7,"name":"Antigo","media":[{"name":"a.mov","relativePath":"Media/a.mov","kind":"Vídeo","byteCount":1,"importOrder":1}],"clips":[]}"#
        let project = try! JSONDecoder().decode(EditorProject.self, from: Data(json.utf8))
        precondition(project.name == "Antigo" && project.media[0].isSonora == false && project.media[0].isDerived == false, "Projeto antigo abre com valores padrão")
    }

    static func projectRoundTripKeepsEverything() {
        var project = EditorProject()
        project.media = [LocalMedia(name: "a", relativePath: "Media/a", kind: "Vídeo", byteCount: 9, importOrder: 1, duration: 3, isSonora: true)]
        project.clips = [TimelineClip(mediaID: project.media[0].id, track: "video", start: 1, duration: 2, label: "x")]
        project.overlays = [TextOverlay(text: "Oi", start: 0, duration: 1)]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let copy = try! decoder.decode(EditorProject.self, from: encoder.encode(project))
        precondition(copy.id == project.id && copy.media == project.media && copy.clips == project.clips && copy.overlays == project.overlays, "Salvar e reabrir sem perda")
    }

    static func derivedMediaIsHiddenFromDirector() {
        var project = EditorProject()
        project.media = [
            LocalMedia(name: "a", relativePath: "a", kind: "Vídeo", byteCount: 1, importOrder: 1, duration: 3, isSonora: true),
            LocalMedia(name: "máscara", relativePath: "m", kind: "Imagem", byteCount: 1, importOrder: 2, duration: 1, isDerived: true)
        ]
        precondition(project.directorMedia.count == 1 && project.directorMedia[0].isSonora, "Máscaras não entram na montagem")
    }
}
