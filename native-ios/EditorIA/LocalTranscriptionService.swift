import Foundation
import Speech
import AVFoundation

struct LocalSpeechSegment {
    let text: String
    let start: Double
    let duration: Double
}

enum LocalTranscriptionError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case onDeviceNotSupported
    case noResult

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permissão de reconhecimento de fala não concedida."
        case .recognizerUnavailable:
            return "Reconhecimento de fala em português indisponível neste aparelho."
        case .onDeviceNotSupported:
            return "Este aparelho não oferece reconhecimento offline para o idioma selecionado. Nenhum áudio foi enviado para a nuvem."
        case .noResult:
            return "Não foi possível reconhecer uma fala neste arquivo."
        }
    }
}

private final class SpeechCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func runOnce(_ body: () -> Void) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        lock.unlock()
        body()
    }
}

private final class SpeechTaskRetention: @unchecked Sendable {
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?

    func retain(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func release() {
        lock.lock()
        task = nil
        lock.unlock()
    }
}

enum LocalTranscriptionService {
    static func transcribe(url: URL, localeIdentifier: String) async throws -> [LocalSpeechSegment] {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else { throw LocalTranscriptionError.permissionDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            throw LocalTranscriptionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw LocalTranscriptionError.onDeviceNotSupported
        }

        // O reconhecedor trabalha melhor com áudio puro: extrai a faixa de som de vídeos antes.
        let audioURL = try await AudioExtractor.audioFile(from: url)
        defer { if audioURL != url { try? FileManager.default.removeItem(at: audioURL) } }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.addsPunctuation = true
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            request.taskHint = .dictation

            let gate = SpeechCompletionGate()
            let retention = SpeechTaskRetention()
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    gate.runOnce {
                        retention.release()
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                let segments = result.bestTranscription.segments.map {
                    LocalSpeechSegment(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                }
                gate.runOnce {
                    retention.release()
                    if segments.isEmpty {
                        continuation.resume(throwing: LocalTranscriptionError.noResult)
                    } else {
                        continuation.resume(returning: segments)
                    }
                }
            }
            retention.retain(task)
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
