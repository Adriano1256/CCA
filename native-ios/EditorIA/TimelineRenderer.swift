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
    var framesPerSecond: Double = 30
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

    static func build(project: EditorProject, baseDirectory: URL, width: Int, height: Int, frameRate: Int? = nil) async throws -> BuiltTimeline {
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

        let timing = frameRate.map { FrameTiming(value: 1, timescale: Int32($0)) } ?? FrameRatePlanner.timing(forNominalRates: nominalRates)
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
            framesPerSecond: timing.framesPerSecond,
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

/// Sinaliza o cancelamento entre as filas de gravação.
private final class ExportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelledValue = false
    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return cancelledValue }
        set { lock.lock(); cancelledValue = newValue; lock.unlock() }
    }
}

@MainActor
final class TimelineRenderer: ObservableObject {
    @Published private(set) var isExporting = false
    @Published private(set) var progress: Float = 0
    @Published private(set) var status = "Pronto para exportar"

    private var control = ExportControl()
    private var activeReader: AVAssetReader?
    private var activeSession: AVAssetExportSession?

    func cancel() {
        control.cancelled = true
        activeReader?.cancelReading()
        activeSession?.cancelExport()
        status = "Cancelando exportação…"
    }

    private func beginExport() throws {
        guard !isExporting else { throw RenderError.exportFailed("Já existe uma exportação em andamento.") }
        isExporting = true
        control = ExportControl()
        progress = 0
        status = "Preparando composição local"
        // A exportação usa a GPU e para se a tela apagar.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func endExport() {
        isExporting = false
        activeReader = nil
        activeSession = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func export(project: EditorProject, baseDirectory: URL, width: Int = 1920, height: Int = 1080, options: ExportOptions = .maximum) async throws -> URL {
        try beginExport()
        defer { endExport() }

        let built = try await TimelineCompositionBuilder.build(project: project, baseDirectory: baseDirectory, width: width, height: height, frameRate: options.frameRate)
        guard built.videoComposition != nil else {
            guard let session = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetAppleM4A) else { throw RenderError.cannotCreateExportSession }
            session.audioMix = built.audioMix
            let destination = try outputURL(fileName: "\(safeName(project.name))-\(Int(Date().timeIntervalSince1970)).m4a")
            return try await runAudioOnly(session: session, to: destination)
        }
        let destination = try outputURL(fileName: "\(safeName(project.name))-\(Int(Date().timeIntervalSince1970)).mp4")
        try await write(built: built, to: destination, options: options, timeRange: nil, progressBase: 0, progressSpan: 1)
        status = built.frameRateWarning ?? "Vídeo exportado localmente"
        return destination
    }

    /// Exporta um arquivo por clipe da trilha principal: STORY_001.mp4, STORY_002.mp4…
    func exportStories(project: EditorProject, baseDirectory: URL, width: Int = 1080, height: Int = 1920, options: ExportOptions = .maximum) async throws -> [URL] {
        try beginExport()
        defer { endExport() }

        let ranges = TimelineEditing.storyRanges(from: project.clips)
        guard !ranges.isEmpty else { throw RenderError.noRenderableMedia }
        let folder = "Stories-\(safeName(project.name))-\(Int(Date().timeIntervalSince1970))"
        var results: [URL] = []
        for range in ranges {
            if control.cancelled { throw RenderError.exportFailed("Exportação cancelada.") }
            let span = 1 / Float(ranges.count)
            status = "Exportando \(range.fileName)"
            let built = try await TimelineCompositionBuilder.build(project: project, baseDirectory: baseDirectory, width: width, height: height, frameRate: options.frameRate)
            let destination = try outputURL(fileName: "\(folder)/\(range.fileName)")
            let timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 60000), duration: CMTime(seconds: range.duration, preferredTimescale: 60000))
            try await write(built: built, to: destination, options: options, timeRange: timeRange, progressBase: Float(range.index - 1) * span, progressSpan: span)
            results.append(destination)
        }
        status = "\(results.count) Stories exportados localmente"
        return results
    }

    /// Grava com codec e bitrate escolhidos, em vez de deixar o sistema decidir a qualidade.
    private func write(built: BuiltTimeline, to destination: URL, options: ExportOptions, timeRange: CMTimeRange?, progressBase: Float, progressSpan: Float) async throws {
        guard let videoComposition = built.videoComposition else { throw RenderError.noRenderableMedia }
        let composition = built.composition
        let reader = try AVAssetReader(asset: composition)
        if let timeRange { reader.timeRange = timeRange }

        let videoTracks = composition.tracks(withMediaType: .video)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw RenderError.cannotCreateExportSession }
        reader.add(videoOutput)

        let audioTracks = composition.tracks(withMediaType: .audio)
        var audioOutput: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            output.audioMix = built.audioMix
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let width = Int(built.renderSize.width), height = Int(built.renderSize.height)
        let bitrate = options.bitrate(width: width, height: height, framesPerSecond: built.framesPerSecond)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: built.framesPerSecond,
            AVVideoMaxKeyFrameIntervalKey: max(1, Int(built.framesPerSecond))
        ]
        if options.codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: options.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw RenderError.exportFailed("O aparelho não aceita este codec nesta resolução.") }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: options.audioBitrate
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else { throw reader.error ?? RenderError.cannotCreateExportSession }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? RenderError.cannotCreateExportSession
        }
        let start = timeRange?.start ?? .zero
        writer.startSession(atSourceTime: start)
        activeReader = reader
        status = "Renderizando no dispositivo"

        let total = max(0.01, timeRange?.duration.seconds ?? built.duration)
        let startSeconds = start.seconds
        let control = self.control
        let report: @Sendable (Double) -> Void = { [weak self] seconds in
            let fraction = Float(min(1, max(0, (seconds - startSeconds) / total)))
            Task { @MainActor in self?.progress = progressBase + fraction * progressSpan }
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await Self.pump(input: videoInput, output: videoOutput, label: "video", control: control, report: report) }
            if let audioInput, let audioOutput {
                group.addTask { await Self.pump(input: audioInput, output: audioOutput, label: "audio", control: control, report: nil) }
            }
        }

        if control.cancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            status = "Exportação cancelada"
            throw RenderError.exportFailed("Exportação cancelada.")
        }
        guard reader.status != .failed else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw RenderError.exportFailed(reader.error?.localizedDescription ?? "Falha na leitura do vídeo")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw RenderError.exportFailed(writer.error?.localizedDescription ?? "Falha na gravação do arquivo")
        }
        progress = progressBase + progressSpan
    }

    /// Passa as amostras do leitor para o gravador, no ritmo que o gravador aguenta.
    nonisolated private static func pump(input: AVAssetWriterInput, output: AVAssetReaderOutput, label: String, control: ExportControl, report: (@Sendable (Double) -> Void)?) async {
        let queue = DispatchQueue(label: "editoria.export.\(label)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            input.requestMediaDataWhenReady(on: queue) {
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    if !control.cancelled, let sample = output.copyNextSampleBuffer() {
                        report?(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                        if !input.append(sample) {
                            finished = true
                            input.markAsFinished()
                            continuation.resume()
                            return
                        }
                    } else {
                        finished = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

    private func runAudioOnly(session: AVAssetExportSession, to destination: URL) async throws -> URL {
        session.outputURL = destination
        session.outputFileType = .m4a
        activeSession = session
        status = "Renderizando áudio no dispositivo"
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw RenderError.exportFailed(session.error?.localizedDescription ?? "Falha ao gravar o áudio")
        }
        progress = 1
        status = "Áudio exportado localmente"
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
