import Foundation
#if canImport(WhisperKit)
import WhisperKit
#endif

/// Transcrição com Whisper no próprio aparelho. É mais confiável em português que o reconhecedor do iOS,
/// mas precisa de um modelo baixado uma vez. Sem ele, o app usa o reconhecedor do sistema.
enum WhisperService {
    struct Option: Identifiable, Hashable {
        var id: String
        var name: String
        var detail: String
        var bytes: Int64 { id.hasPrefix("large") ? 626_000_000 : 216_000_000 }
    }

    static let options = [
        Option(id: "small_216MB", name: "Whisper Small", detail: "216 MB. Rápido, bom para a maioria das falas."),
        Option(id: "large-v3-v20240930_626MB", name: "Whisper Large v3", detail: "626 MB. O mais preciso, recomendado para sonoras.")
    ]

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EditorIA/Whisper", isDirectory: true)
    }

    private static func recordFile() -> URL { directory.appendingPathComponent("instalado.txt") }

    /// Pasta do modelo já baixado, se houver.
    static var installedFolder: String? {
        get { try? String(contentsOf: recordFile(), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
        set {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let newValue { try? newValue.write(to: recordFile(), atomically: true, encoding: .utf8) } else { try? FileManager.default.removeItem(at: recordFile()) }
        }
    }

    static var isInstalled: Bool {
        guard let folder = installedFolder else { return false }
        return FileManager.default.fileExists(atPath: folder)
    }

    static func download(_ option: Option, progress: @escaping @Sendable (Double) -> Void) async throws {
        #if canImport(WhisperKit)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var base = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
        let folder = try await WhisperKit.download(variant: option.id, downloadBase: directory) { value in
            progress(value.fractionCompleted)
        }
        installedFolder = folder.path
        #else
        throw LocalTranscriptionError.recognizerUnavailable
        #endif
    }

    static func remove() {
        if let folder = installedFolder { try? FileManager.default.removeItem(atPath: folder) }
        installedFolder = nil
    }

    static func transcribe(url: URL) async throws -> [TranscriptWord] {
        #if canImport(WhisperKit)
        guard let folder = installedFolder else { throw LocalTranscriptionError.recognizerUnavailable }
        let audioURL = try await AudioExtractor.audioFile(from: url)
        defer { if audioURL != url { try? FileManager.default.removeItem(at: audioURL) } }
        let config = WhisperKitConfig(modelFolder: folder, verbose: false, logLevel: .error, load: true, download: false)
        let kit = try await WhisperKit(config)
        let options = DecodingOptions(language: "pt", wordTimestamps: true)
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        var words: [TranscriptWord] = []
        for result in results {
            for segment in result.segments {
                for word in segment.words ?? [] {
                    words.append(TranscriptWord(text: word.word.trimmingCharacters(in: .whitespacesAndNewlines), start: Double(word.start), end: Double(word.end)))
                }
            }
        }
        return words
        #else
        throw LocalTranscriptionError.recognizerUnavailable
        #endif
    }
}
