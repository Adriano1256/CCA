import Foundation
import AVFoundation
import Combine
import CoreMedia

struct AudioLevelSample: Identifiable, Codable, Sendable {
    var id = UUID()
    var time: Double
    var rms: Double
    var peak: Double
}

struct AudioSilenceRange: Identifiable, Codable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var duration: Double { max(0, end - start) }
}

struct AudioAnalysisReport: Codable, Sendable {
    var duration: Double
    var averageRMS: Double
    var peakLevel: Double
    var samples: [AudioLevelSample]
    var silenceRanges: [AudioSilenceRange]
    var thresholdDB: Double
}

@MainActor
final class LocalAudioAnalysisService: ObservableObject {
    @Published private(set) var report: AudioAnalysisReport?
    @Published private(set) var isAnalyzing = false
    @Published var status = "Pronto para analisar áudio localmente"
    @Published var errorMessage: String?

    func analyze(url: URL, thresholdDB: Double = -42, minimumSilence: Double = 0.45) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        report = nil
        errorMessage = nil
        status = "Analisando níveis e pausas no próprio aparelho…"
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await Self.performAnalysis(url: url, thresholdDB: thresholdDB, minimumSilence: minimumSilence)
            }.value
            report = result
            status = "Análise concluída · \(result.silenceRanges.count) pausa(s) candidata(s)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Não foi possível analisar este áudio"
        }
        isAnalyzing = false
    }

    nonisolated private static func performAnalysis(url: URL, thresholdDB: Double, minimumSilence: Double) async throws -> AudioAnalysisReport {
        let asset = AVURLAsset(url: url)
        let loadedTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = loadedTracks.first else { throw AudioAnalysisError.noAudioTrack }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioAnalysisError.cannotReadAudio }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? AudioAnalysisError.cannotStartReader }

        var samples: [AudioLevelSample] = []
        var totalSquares = 0.0
        var totalCount = 0
        var globalPeak = 0.0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount >= 2 else { continue }
            let count = byteCount / MemoryLayout<Int16>.size
            var pcm = [Int16](repeating: 0, count: count)
            let copyStatus = pcm.withUnsafeMutableBytes { rawBuffer in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: rawBuffer.baseAddress!)
            }
            guard copyStatus == kCMBlockBufferNoErr else { continue }

            var squares = 0.0
            var peak = 0.0
            for value in pcm {
                let normalized = Double(value) / Double(Int16.max)
                squares += normalized * normalized
                peak = max(peak, abs(normalized))
            }
            let rms = sqrt(squares / Double(max(1, count)))
            let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            let safeTime = timestamp.isFinite ? max(0, timestamp) : 0
            samples.append(AudioLevelSample(time: safeTime, rms: rms, peak: peak))
            totalSquares += squares
            totalCount += count
            globalPeak = max(globalPeak, peak)
        }
        guard reader.status == .completed || reader.status == .reading else {
            throw reader.error ?? AudioAnalysisError.readFailed
        }

        let threshold = pow(10.0, thresholdDB / 20.0)
        let sorted = samples.sorted { $0.time < $1.time }
        var ranges: [AudioSilenceRange] = []
        var silenceStart: Double?
        for index in sorted.indices {
            let current = sorted[index]
            let nextTime = index + 1 < sorted.count ? sorted[index + 1].time : current.time + 0.1
            let isQuiet = current.rms <= threshold
            if isQuiet {
                if silenceStart == nil { silenceStart = current.time }
            } else if let start = silenceStart {
                let end = current.time
                if end - start >= minimumSilence { ranges.append(AudioSilenceRange(start: start, end: end)) }
                silenceStart = nil
            }
            if index == sorted.count - 1, let start = silenceStart {
                let end = max(current.time, nextTime)
                if end - start >= minimumSilence { ranges.append(AudioSilenceRange(start: start, end: end)) }
            }
        }
        let duration = sorted.last.map { $0.time + 0.1 } ?? 0
        let average = totalCount > 0 ? sqrt(totalSquares / Double(totalCount)) : 0
        return AudioAnalysisReport(duration: duration, averageRMS: average, peakLevel: globalPeak, samples: sorted, silenceRanges: ranges, thresholdDB: thresholdDB)
    }
}

enum AudioAnalysisError: LocalizedError {
    case noAudioTrack
    case cannotReadAudio
    case cannotStartReader
    case readFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "O arquivo selecionado não contém uma faixa de áudio."
        case .cannotReadAudio: return "Não foi possível preparar a leitura do áudio."
        case .cannotStartReader: return "Não foi possível iniciar a análise local."
        case .readFailed: return "A leitura do áudio foi interrompida."
        }
    }
}
