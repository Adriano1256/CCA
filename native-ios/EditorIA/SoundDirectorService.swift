import Foundation
import AVFoundation
import SoundAnalysis

/// Análise real do som no aparelho, com o classificador embutido do iOS (sem internet e sem baixar nada).
enum SoundDirectorService {
    struct Report {
        var speechRanges: [AudioDuckingRange]
        var speechShare: Double
        var musicShare: Double
        var topSounds: [String]
        var summary: String { 
            var parts = [String(format: "fala %.0f%%", speechShare * 100), String(format: "música %.0f%%", musicShare * 100)]
            if !topSounds.isEmpty { parts.append(topSounds.joined(separator: ", ")) }
            return parts.joined(separator: " · ")
        }
    }

    private final class Observer: NSObject, SNResultsObserving, @unchecked Sendable {
        var speech: [(start: Double, end: Double, confidence: Double)] = []
        var music: [(start: Double, end: Double, confidence: Double)] = []
        var other: [String: Double] = [:]
        let speechIDs: [String]
        let musicIDs: [String]
        var failure: Error?

        init(speechIDs: [String], musicIDs: [String]) {
            self.speechIDs = speechIDs
            self.musicIDs = musicIDs
        }

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            let start = result.timeRange.start.seconds
            let end = start + result.timeRange.duration.seconds
            let speechConfidence = speechIDs.compactMap { result.classification(forIdentifier: $0)?.confidence }.max() ?? 0
            let musicConfidence = musicIDs.compactMap { result.classification(forIdentifier: $0)?.confidence }.max() ?? 0
            speech.append((start, end, speechConfidence))
            music.append((start, end, musicConfidence))
            if let top = result.classifications.first, top.confidence > 0.6, !speechIDs.contains(top.identifier), !musicIDs.contains(top.identifier) {
                other[top.identifier, default: 0] += end - start
            }
        }

        func request(_ request: SNRequest, didFailWithError error: Error) { failure = error }
    }

    static func analyze(url: URL, duration: Double) async throws -> Report {
        let audioURL = try await AudioExtractor.audioFile(from: url)
        defer { if audioURL != url { try? FileManager.default.removeItem(at: audioURL) } }
        return try await Task.detached(priority: .userInitiated) { () throws -> Report in
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let known = Set(request.knownClassifications)
            let speechIDs = ["speech", "conversation", "narration", "shout", "yell"].filter { known.contains($0) }
            let musicIDs = ["music", "singing"].filter { known.contains($0) }
            let observer = Observer(speechIDs: speechIDs, musicIDs: musicIDs)
            let analyzer = try SNAudioFileAnalyzer(url: audioURL)
            try analyzer.add(request, withObserver: observer)
            analyzer.analyze()
            if let failure = observer.failure { throw failure }
            let speech = AudioContentAnalysis.mergeWindows(observer.speech, threshold: 0.5)
            let music = AudioContentAnalysis.mergeWindows(observer.music, threshold: 0.5)
            let top = observer.other.sorted { $0.value > $1.value }.prefix(3).map(\.key)
            return Report(
                speechRanges: speech,
                speechShare: AudioContentAnalysis.coverage(speech, duration: duration),
                musicShare: AudioContentAnalysis.coverage(music, duration: duration),
                topSounds: Array(top)
            )
        }.value
    }

    /// Lê o som como energia ao longo do tempo e acha as batidas.
    static func beats(url: URL) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { return [] }
        return try await Task.detached(priority: .userInitiated) { () throws -> [Double] in
            let reader = try AVAssetReader(asset: asset)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 11_025,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            guard reader.canAdd(output) else { return [] }
            reader.add(output)
            guard reader.startReading() else { return [] }
            let hopSamples = 220
            var envelope: [Double] = []
            var accumulator = 0.0
            var count = 0
            while let buffer = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let bytes = CMBlockBufferGetDataLength(block)
                guard bytes >= 2 else { continue }
                let sampleCount = bytes / 2
                var pcm = [Int16](repeating: 0, count: sampleCount)
                let status = pcm.withUnsafeMutableBytes { raw in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: sampleCount * 2, destination: raw.baseAddress!)
                }
                guard status == kCMBlockBufferNoErr else { continue }
                for value in pcm {
                    let sample = Double(value) / 32768
                    accumulator += sample * sample
                    count += 1
                    if count == hopSamples {
                        envelope.append((accumulator / Double(hopSamples)).squareRoot())
                        accumulator = 0
                        count = 0
                    }
                }
            }
            return BeatDetector.beats(envelope: envelope, hop: Double(hopSamples) / 11_025)
        }.value
    }
}

enum AudioExtractor {
    /// Vídeo vira um arquivo só de áudio; áudio é devolvido como está.
    static func audioFile(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { return url }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw LocalTranscriptionError.noResult }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw LocalTranscriptionError.noResult }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("EditorIA-Audio-\(UUID().uuidString).m4a")
        session.outputURL = output
        session.outputFileType = .m4a
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw session.error ?? LocalTranscriptionError.noResult
        }
        return output
    }
}
