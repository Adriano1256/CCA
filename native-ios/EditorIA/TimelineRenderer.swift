import Foundation
import Combine
import AVFoundation
import CoreGraphics
import ImageIO
import QuartzCore
import UIKit

enum RenderError: LocalizedError {
    case noRenderableMedia
    case cannotCreateExportSession
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRenderableMedia: return "Não há mídia compatível para exportar. Verifique se os clipes da timeline ainda existem no aparelho."
        case .cannotCreateExportSession: return "Não foi possível iniciar o exportador de vídeo."
        case .exportFailed(let reason): return "Falha na exportação: \(reason)"
        }
    }
}

/// Composição pronta para tocar ou exportar. A prévia e o exportador usam o mesmo construtor e o
/// mesmo compositor, então cortes, cor, textos, ordem das trilhas e áudio são idênticos nos dois.
struct BuiltTimeline {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition?
    let audioMix: AVMutableAudioMix?
    let renderSize: CGSize
    let duration: Double
    let frameRateWarning: String?
}

/// Vídeo preto mínimo que garante a duração da composição (fotos e textos não ocupam faixa de vídeo).
@MainActor
enum BlankVideoFactory {
    static func url() async throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = caches.appendingPathComponent("EditorIA-blank-v1.mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let temporary = caches.appendingPathComponent("EditorIA-blank-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw RenderError.cannotCreateExportSession }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RenderError.cannotCreateExportSession }
        writer.startSession(atSourceTime: .zero)

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let pixelBuffer = buffer else { throw RenderError.cannotCreateExportSession }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 0, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        for second in 0..<10 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(second), timescale: 1)) else {
                throw writer.error ?? RenderError.cannotCreateExportSession
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 10, timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? RenderError.cannotCreateExportSession }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temporary, to: url)
        return url
    }
}

@MainActor
enum TimelineCompositionBuilder {
    private typealias Lane = (track: AVMutableCompositionTrack, end: Double)

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 60000)
    }

    static func build(project: EditorProject, baseDirectory: URL, width: Int, height: Int) async throws -> BuiltTimeline {
        let composition = AVMutableComposition()
        let renderSize = CGSize(width: width, height: height)
        var visualClips: [TimelineClip] = []
        var trackForClip: [UUID: CMPersistentTrackID] = [:]
        var orientationForClip: [UUID: CGImagePropertyOrientation] = [:]
        var hasStillClips = false
        var parameters: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]
        var videoLanes: [Lane] = []
        var audioLanes: [Lane] = []
        var nominalRates: [Double] = []
        var maxEnd = 0.0

        for overlay in project.overlays { maxEnd = max(maxEnd, overlay.start + overlay.duration) }
        for caption in project.captionWords { maxEnd = max(maxEnd, caption.start + caption.duration) }
        let speechRanges = project.automaticDucking ? SpeechMapper.timelineRanges(project: project).map { (start: $0.start, end: $0.end) } : []

        let sortedClips = project.clips.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.track < rhs.track : lhs.start < rhs.start
        }

        for clip in sortedClips {
            guard let media = project.media.first(where: { $0.id == clip.mediaID }) else { continue }
            let sourceURL = baseDirectory.appendingPathComponent(media.relativePath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }

            if media.kind == "Imagem" {
                hasStillClips = true
                maxEnd = max(maxEnd, clip.end)
                continue
            }

            let asset = AVURLAsset(url: sourceURL)
            let speed = max(0.01, clip.look.speed)
            let sourceStart = time(max(0, clip.sourceIn))
            let assetDuration = try await asset.load(.duration)
            let sourceDuration = CMTimeMinimum(time(max(0.1, clip.duration * speed)), CMTimeSubtract(assetDuration, sourceStart))
            guard sourceDuration.seconds > 0 else { continue }
            let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)
            let timelineStart = time(max(0, clip.start))
            let timelineDuration = sourceDuration.seconds / speed
            let clipEnd = clip.start + timelineDuration
            maxEnd = max(maxEnd, clipEnd)

            func insert(_ source: AVAssetTrack, into destination: AVMutableCompositionTrack) throws {
                try destination.insertTimeRange(sourceRange, of: source, at: timelineStart)
                if abs(speed - 1) > 0.001 {
                    destination.scaleTimeRange(CMTimeRange(start: timelineStart, duration: sourceDuration), toDuration: time(timelineDuration))
                }
            }

            var usesAudio = true
            if media.kind == "Vídeo" {
                let sourceTracks = try await asset.loadTracks(withMediaType: .video)
                guard let sourceVideo = sourceTracks.first,
                      let destination = laneTrack(&videoLanes, mediaType: .video, start: clip.start, end: clipEnd, composition: composition) else { continue }
                try insert(sourceVideo, into: destination)
                let preferredTransform = try await sourceVideo.load(.preferredTransform)
                let nominalRate = try await sourceVideo.load(.nominalFrameRate)
                nominalRates.append(Double(nominalRate))
                var effective = clip
                effective.duration = timelineDuration
                visualClips.append(effective)
                trackForClip[clip.id] = destination.trackID
                orientationForClip[clip.id] = CGImagePropertyOrientation(videoTransform: preferredTransform)
                usesAudio = clip.volume > 0.001 || clip.keyframes.contains { $0.property == "volume" }
            }

            guard usesAudio else { continue }
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let sourceAudio = audioTracks.first,
                  let destinationAudio = laneTrack(&audioLanes, mediaType: .audio, start: clip.start, end: clipEnd, composition: composition) else { continue }
            try insert(sourceAudio, into: destinationAudio)
            let mixParameters = parameters[destinationAudio.trackID] ?? AVMutableAudioMixInputParameters(track: destinationAudio)
            parameters[destinationAudio.trackID] = mixParameters
            // Só a trilha musical abaixa durante a fala.
            let ducking = (media.kind == "Áudio" && clip.track == "audio") ? speechRanges : []
            applyVolumeEnvelope(mixParameters, volume: Float(clip.volume), clip: clip, duration: timelineDuration, duckingRanges: ducking, duckingLevel: project.duckingLevel)
        }

        let hasVisual = !visualClips.isEmpty || hasStillClips || !project.overlays.isEmpty || !project.captionWords.isEmpty
        guard hasVisual || !parameters.isEmpty, maxEnd > 0 else { throw RenderError.noRenderableMedia }

        let audioMix: AVMutableAudioMix?
        if parameters.isEmpty {
            audioMix = nil
        } else {
            let mix = AVMutableAudioMix()
            mix.inputParameters = Array(parameters.values)
            audioMix = mix
        }

        guard hasVisual else {
            return BuiltTimeline(composition: composition, videoComposition: nil, audioMix: audioMix, renderSize: renderSize, duration: maxEnd, frameRateWarning: nil)
        }

        // A faixa preta define a duração total; sem ela, fotos e textos depois do último vídeo seriam perdidos.
        let blankAsset = AVURLAsset(url: try await BlankVideoFactory.url())
        let blankDuration = try await blankAsset.load(.duration)
        let blankSources = try await blankAsset.loadTracks(withMediaType: .video)
        guard let blankSource = blankSources.first,
              let blankTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RenderError.cannotCreateExportSession
        }
        let blankRange = CMTimeRange(start: .zero, duration: blankDuration)
        try blankTrack.insertTimeRange(blankRange, of: blankSource, at: .zero)
        blankTrack.scaleTimeRange(blankRange, toDuration: time(maxEnd))

        let timing = FrameRatePlanner.timing(forNominalRates: nominalRates)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = TimelineCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: timing.value, timescale: timing.timescale)
        // Vídeo HDR do iPhone é convertido para SDR (Rec. 709), o padrão de redes sociais.
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        // As instruções precisam ser contíguas e cobrir tudo: cada uma termina exatamente onde a próxima começa.
        var cuts: Set<Double> = [0, maxEnd]
        for clip in visualClips {
            cuts.insert(clip.start)
            cuts.insert(clip.end)
        }
        var boundaries: [CMTime] = []
        for second in cuts.sorted() {
            let boundary = time(second)
            if boundaries.last.map({ CMTimeCompare($0, boundary) < 0 }) ?? true { boundaries.append(boundary) }
        }
        if let last = boundaries.last { boundaries[boundaries.count - 1] = CMTimeMaximum(last, composition.duration) }

        let scene = CompositionScene(project: project, renderSize: renderSize, baseDirectory: baseDirectory, trackForClip: trackForClip, orientationForClip: orientationForClip)
        var instructions: [AVVideoCompositionInstructionProtocol] = []
        for (startTime, endTime) in zip(boundaries, boundaries.dropFirst()) {
            let start = startTime.seconds
            let end = endTime.seconds
            let active = visualClips.filter { $0.start < end - 0.0001 && $0.end > start + 0.0001 && SceneEvaluator.trackOrder.contains($0.track) }
            let trackIDs = Array(Set(active.compactMap { trackForClip[$0.id] }))
            instructions.append(TimelineInstruction(timeRange: CMTimeRange(start: startTime, end: endTime), trackIDs: trackIDs, scene: scene))
        }
        videoComposition.instructions = instructions

        return BuiltTimeline(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            renderSize: renderSize,
            duration: maxEnd,
            frameRateWarning: FrameRatePlanner.mismatchWarning(forNominalRates: nominalRates)
        )
    }

    private static func laneTrack(_ lanes: inout [Lane], mediaType: AVMediaType, start: Double, end: Double, composition: AVMutableComposition) -> AVMutableCompositionTrack? {
        if let index = lanes.firstIndex(where: { $0.end <= start }) {
            lanes[index].end = end
            return lanes[index].track
        }
        guard let track = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        lanes.append((track, end))
        return track
    }

    /// Carrega a foto já reduzida e em pé, para muitas imagens não esgotarem a memória.
    nonisolated static func loadStill(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func applyVolumeEnvelope(
        _ parameters: AVMutableAudioMixInputParameters,
        volume: Float,
        clip: TimelineClip,
        duration: Double,
        duckingRanges: [(start: Double, end: Double)],
        duckingLevel: Double
    ) {
        guard duration > 0 else { return }
        let safeDuckLevel = min(0.8, max(0.05, duckingLevel))
        let attack = 0.12
        let release = 0.24
        let localSpeech = AudioDuckingPlanner.localize(
            duckingRanges.map { AudioDuckingRange(start: $0.start, end: $0.end) },
            clipStart: clip.start,
            clipDuration: duration
        )

        var points: Set<Double> = Set(AudioDuckingPlanner.automationPoints(
            ranges: localSpeech,
            duration: duration,
            attack: attack,
            release: release
        ))
        let fadeIn = min(clip.fadeIn, duration)
        let fadeOut = min(clip.fadeOut, max(0, duration - fadeIn))
        if fadeIn > 0 { points.insert(fadeIn) }
        if fadeOut > 0 { points.insert(duration - fadeOut) }
        for frame in clip.keyframes where frame.property == "volume" {
            points.insert(min(duration, max(0, frame.time)))
        }

        let keyframes = clip.keyframes.filter { $0.property == "volume" }.sorted { $0.time < $1.time }
        var basePoints: [(time: Double, value: Double)] = [(0, Double(volume))]
        for frame in keyframes {
            let time = min(duration, max(0, frame.time))
            let value = min(2, max(0, frame.value))
            if let index = basePoints.firstIndex(where: { abs($0.time - time) < 0.001 }) {
                basePoints[index].value = value
            } else {
                basePoints.append((time, value))
            }
        }
        basePoints.sort { $0.time < $1.time }

        func baseVolume(at time: Double) -> Double {
            guard let first = basePoints.first else { return Double(volume) }
            if time <= first.time { return first.value }
            guard let last = basePoints.last, time < last.time else { return basePoints.last?.value ?? Double(volume) }
            for pair in zip(basePoints, basePoints.dropFirst()) where time >= pair.0.time && time <= pair.1.time {
                let span = max(0.0001, pair.1.time - pair.0.time)
                let progress = (time - pair.0.time) / span
                return pair.0.value + (pair.1.value - pair.0.value) * progress
            }
            return first.value
        }

        func duckFactor(at time: Double) -> Double {
            AudioDuckingPlanner.factor(
                at: time,
                ranges: localSpeech,
                duckLevel: safeDuckLevel,
                attack: attack,
                release: release
            )
        }

        func finalVolume(at time: Double) -> Float {
            var fade = 1.0
            if fadeIn > 0 && time < fadeIn { fade = min(fade, max(0, time / fadeIn)) }
            if fadeOut > 0 && time > duration - fadeOut { fade = min(fade, max(0, (duration - time) / fadeOut)) }
            let value = baseVolume(at: time) * fade * duckFactor(at: time)
            return Float(min(2, max(0, value)))
        }

        let sortedPoints = points.filter { $0.isFinite && $0 >= 0 && $0 <= duration }.sorted()
        guard let first = sortedPoints.first else { return }
        parameters.setVolume(finalVolume(at: first), at: CMTime(seconds: clip.start + first, preferredTimescale: 60000))
        for pair in zip(sortedPoints, sortedPoints.dropFirst()) where pair.1 - pair.0 > 0.001 {
            let startTime = CMTime(seconds: clip.start + pair.0, preferredTimescale: 60000)
            let range = CMTimeRange(start: startTime, duration: CMTime(seconds: pair.1 - pair.0, preferredTimescale: 60000))
            parameters.setVolumeRamp(fromStartVolume: finalVolume(at: pair.0), toEndVolume: finalVolume(at: pair.1), timeRange: range)
        }
    }

}

@MainActor
final class TimelineRenderer: ObservableObject {
    @Published private(set) var isExporting = false
    @Published private(set) var progress: Float = 0
    @Published private(set) var status = "Pronto para exportar"

    private var activeSession: AVAssetExportSession?
    private var cancelRequested = false

    func cancel() {
        cancelRequested = true
        activeSession?.cancelExport()
        status = "Cancelando exportação…"
    }

    private func beginExport() throws {
        guard !isExporting else { throw RenderError.exportFailed("Já existe uma exportação em andamento.") }
        isExporting = true
        cancelRequested = false
        progress = 0
        status = "Preparando composição local"
        // A exportação usa a GPU e para se a tela apagar.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func endExport() {
        isExporting = false
        activeSession = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func export(project: EditorProject, baseDirectory: URL, width: Int = 1920, height: Int = 1080) async throws -> URL {
        try beginExport()
        defer { endExport() }

        let built = try await TimelineCompositionBuilder.build(project: project, baseDirectory: baseDirectory, width: width, height: height)
        guard let videoComposition = built.videoComposition else {
            guard let session = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetAppleM4A) else { throw RenderError.cannotCreateExportSession }
            session.audioMix = built.audioMix
            let destination = try outputURL(fileName: "\(safeName(project.name))-\(Int(Date().timeIntervalSince1970)).m4a")
            return try await run(session: session, to: destination, fileType: .m4a, progressBase: 0, progressSpan: 1)
        }

        guard let session = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else { throw RenderError.cannotCreateExportSession }
        session.videoComposition = videoComposition
        session.audioMix = built.audioMix
        let destination = try outputURL(fileName: "\(safeName(project.name))-\(Int(Date().timeIntervalSince1970)).mp4")
        let result = try await run(session: session, to: destination, fileType: .mp4, progressBase: 0, progressSpan: 1)
        status = built.frameRateWarning ?? "Vídeo exportado localmente"
        return result
    }

    /// Exporta um arquivo por clipe da trilha principal: STORY_001.mp4, STORY_002.mp4…
    func exportStories(project: EditorProject, baseDirectory: URL, width: Int = 1080, height: Int = 1920) async throws -> [URL] {
        try beginExport()
        defer { endExport() }

        let ranges = TimelineEditing.storyRanges(from: project.clips)
        guard !ranges.isEmpty else { throw RenderError.noRenderableMedia }
        let folder = "Stories-\(safeName(project.name))-\(Int(Date().timeIntervalSince1970))"
        var results: [URL] = []
        for range in ranges {
            if cancelRequested { throw RenderError.exportFailed("Exportação cancelada.") }
            let span = 1 / Float(ranges.count)
            status = "Exportando \(range.fileName)"
            // A ferramenta de animação não pode ser reutilizada: cada arquivo tem sua composição.
            let built = try await TimelineCompositionBuilder.build(project: project, baseDirectory: baseDirectory, width: width, height: height)
            guard let videoComposition = built.videoComposition else { throw RenderError.noRenderableMedia }
                guard let session = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else { throw RenderError.cannotCreateExportSession }
            session.videoComposition = videoComposition
            session.audioMix = built.audioMix
            session.timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 60000), duration: CMTime(seconds: range.duration, preferredTimescale: 60000))
            let destination = try outputURL(fileName: "\(folder)/\(range.fileName)")
            results.append(try await run(session: session, to: destination, fileType: .mp4, progressBase: Float(range.index - 1) * span, progressSpan: span))
        }
        status = "\(results.count) Stories exportados localmente"
        return results
    }

    private func run(session: AVAssetExportSession, to destination: URL, fileType: AVFileType, progressBase: Float, progressSpan: Float) async throws -> URL {
        session.outputURL = destination
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = false
        activeSession = session
        status = "Renderizando no dispositivo"
        let monitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.progress = progressBase + session.progress * progressSpan
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        monitor.cancel()
        progress = progressBase + progressSpan
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            if session.status == .cancelled {
                status = "Exportação cancelada"
                throw RenderError.exportFailed("Exportação cancelada.")
            }
            throw RenderError.exportFailed(session.error?.localizedDescription ?? "Erro desconhecido")
        }
        status = "Exportado localmente"
        return destination
    }

    private func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
    }

    private func outputURL(fileName: String) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = documents.appendingPathComponent("EditorIA/Exports", isDirectory: true).appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        return url
    }
}
