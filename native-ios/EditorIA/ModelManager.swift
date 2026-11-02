import Foundation
import Combine
import UIKit

/// Baixa, confere e guarda os modelos de IA. O download só começa quando o usuário pede,
/// e depois disso a IA funciona em modo avião.
@MainActor
final class ModelManager: NSObject, ObservableObject {
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var downloadingID: String?
    @Published private(set) var progress: Double = 0
    @Published var message: String?
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "EditorIA.selectedModel") }
    }

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EditorIA/Models", isDirectory: true)
    }

    let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    private var session: URLSession!
    private var task: URLSessionDownloadTask?

    override init() {
        let recommended = LocalModel.recommended(memoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824)
        selectedID = UserDefaults.standard.string(forKey: "EditorIA.selectedModel") ?? recommended.id
        super.init()
        var folder = Self.directory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.criativar.editoria.models")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        refresh()
        var guardState = ModelGuardStore.load()
        if let crashed = guardState.recover() {
            ModelGuardStore.save(guardState)
            let name = LocalModel.catalog.first { $0.id == crashed }?.name ?? "O modelo"
            if guardState.isBlocked(crashed) {
                message = "\(name) não coube na memória deste aparelho. Passei para outro modelo instalado. Toque em Usar este para tentar de novo."
            } else {
                message = "\(name) fechou o app por falta de memória. Vou tentar de novo usando menos memória."
            }
        }
    }

    /// Usuário escolheu este modelo: ele merece nova tentativa.
    func select(_ model: LocalModel) {
        var guardState = ModelGuardStore.load()
        guardState.crashes[model.id] = nil
        ModelGuardStore.save(guardState)
        selectedID = model.id
    }

    nonisolated static func installedBytesOnDisk() -> Int64 {
        func size(_ folder: URL) -> Int64 {
            guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var total: Int64 = 0
            for case let file as URL in files {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total
        }
        return size(directory) + size(WhisperService.directory)
    }

    func installedBytes() -> Int64 { Self.installedBytesOnDisk() }

    var recommended: LocalModel { LocalModel.recommended(memoryGB: memoryGB) }
    var selected: LocalModel? { LocalModel.catalog.first { $0.id == selectedID } }
    var activeModel: LocalModel? {
        let guardState = ModelGuardStore.load()
        if let selected, installed.contains(selected.id), !guardState.isBlocked(selected.id) { return selected }
        return LocalModel.catalog.last { installed.contains($0.id) && !guardState.isBlocked($0.id) }
    }

    func url(for model: LocalModel) -> URL {
        Self.directory.appendingPathComponent(model.fileName)
    }

    func refresh() {
        installed = Set(LocalModel.catalog.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }.map(\.id))
    }

    func freeSpaceBytes() -> Int64 {
        let values = try? Self.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    func download(_ model: LocalModel) {
        guard downloadingID == nil else { message = "Aguarde o download em andamento."; return }
        guard freeSpaceBytes() > model.approximateBytes + 500_000_000 else {
            message = "Falta espaço no aparelho para este modelo."
            return
        }
        guard AIStorageBudget.fits(adding: model.approximateBytes, installedBytes: installedBytes()) else {
            message = "Este modelo passaria do limite de 8 GB do app. Apague outro modelo primeiro."
            return
        }
        guard let url = URL(string: model.url) else { return }
        let next = session.downloadTask(with: url)
        next.taskDescription = model.id
        task = next
        downloadingID = model.id
        progress = 0
        message = "Baixando \(model.name). Mantenha o Wi-Fi ligado."
        next.resume()
    }

    func cancelDownload() {
        task?.cancel()
        task = nil
        downloadingID = nil
        message = "Download cancelado."
    }

    func delete(_ model: LocalModel) {
        try? FileManager.default.removeItem(at: url(for: model))
        refresh()
    }

    fileprivate func finish(modelID: String, error: String?) {
        downloadingID = nil
        task = nil
        refresh()
        if let error {
            message = error
        } else if let model = LocalModel.catalog.first(where: { $0.id == modelID }) {
            selectedID = model.id
            message = "\(model.name) instalado. A IA já funciona sem internet."
        }
    }

    fileprivate func update(progress value: Double) { progress = value }
}

extension ModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.update(progress: value) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskDescription ?? ""
        guard let model = LocalModel.catalog.first(where: { $0.id == id }) else { return }
        // O arquivo temporário some ao sair deste método; precisa ser movido agora.
        var problem: String?
        let size = ((try? FileManager.default.attributesOfItem(atPath: location.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let handle = try? FileHandle(forReadingFrom: location)
        let header = (try? handle?.read(upToCount: 4)).flatMap { $0 }.map { [UInt8]($0) } ?? []
        try? handle?.close()
        if LocalModel.looksValid(header: header, fileSize: size, expected: model.approximateBytes) {
            let destination = Self.directory.appendingPathComponent(model.fileName)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                problem = "Não foi possível salvar o modelo: \(error.localizedDescription)"
            }
        } else {
            problem = "O download veio incompleto ou inválido. Tente de novo."
        }
        Task { @MainActor in self.finish(modelID: id, error: problem) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        let id = task.taskDescription ?? ""
        let text = error.localizedDescription
        Task { @MainActor in self.finish(modelID: id, error: "Falha no download: \(text)") }
    }
}

/// Conversa com a IA local. O plano dela entra direto na timeline e pode ser desfeito; fala nunca é cortada por ela.
@MainActor
final class AgentController: ObservableObject {
    struct Message: Identifiable {
        let id = UUID()
        let fromUser: Bool
        var text: String
        var plan: AgentPlan?
        var applied = false
        var done: [String] = []
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isThinking = false
    @Published private(set) var tokens = 0
    /// Muda quando chega um plano novo, para o editor aplicar na timeline.
    @Published private(set) var pendingPlanCount = 0

    private var engine: LlamaEngine?
    private var engineModelID: String?
    private let stopFlag = StopFlag()
    private var memoryObserver: NSObjectProtocol?

    final class StopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    init() {
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isThinking else { return }
                self.engine = nil
                self.engineModelID = nil
            }
        }
    }

    /// Libera a memória da IA, por exemplo antes de exportar um vídeo.
    func unload() {
        guard !isThinking else { return }
        engine = nil
        engineModelID = nil
    }

    func stop() { stopFlag.isSet = true }

    func markApplied(_ id: UUID, outcome: [String]) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].applied = true
        messages[index].done = outcome
    }

    /// Resposta que não precisou do modelo.
    func addExchange(request: String, plan: AgentPlan) {
        messages.append(Message(fromUser: true, text: request))
        receive(plan)
    }

    private func receive(_ plan: AgentPlan) {
        messages.append(Message(fromUser: false, text: plan.reply, plan: plan.actions.isEmpty ? nil : plan))
        if !plan.actions.isEmpty { pendingPlanCount += 1 }
    }

    func addNote(_ text: String) {
        messages.append(Message(fromUser: false, text: text))
    }

    func ask(_ text: String, model: LocalModel, modelURL: URL, summary: String, fallback: AgentPlan? = nil) {
        guard !isThinking else { return }
        messages.append(Message(fromUser: true, text: text))
        isThinking = true
        tokens = 0
        stopFlag.isSet = false
        let previous = messages.dropLast().last { !$0.fromUser }?.text
        let context = (previous.map { "Sua resposta anterior: \($0)\n" } ?? "")
        let prompt = AgentProtocol.formatPrompt(system: AgentProtocol.systemPrompt, user: "\(summary)\n\n\(context)Pedido do editor: \(text)", format: model.format)
        let flag = stopFlag
        let grammar = AgentProtocol.grammar
        let existing = engineModelID == model.id ? engine : nil
        var guardState = ModelGuardStore.load()
        let contextSize = guardState.contextSize(for: model)
        guardState.pending = model.id
        ModelGuardStore.save(guardState)

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { () throws -> (LlamaEngine, String) in
                    let active = try existing ?? LlamaEngine(path: modelURL.path, contextSize: contextSize)
                    let raw = try active.generate(prompt: prompt, grammar: grammar, shouldStop: { flag.isSet }, onProgress: { count in
                        Task { @MainActor [weak self] in self?.tokens = count }
                    })
                    return (active, raw)
                }.value
                engine = result.0
                engineModelID = model.id
                if let plan = AgentProtocol.parsePlan(result.1) {
                    receive(plan)
                } else if flag.isSet {
                    messages.append(Message(fromUser: false, text: "Parado."))
                } else {
                    if let fallback {
                        receive(fallback)
                    } else {
                        messages.append(Message(fromUser: false, text: "Não consegui montar uma resposta válida. Tente pedir de outro jeito."))
                    }
                }
            } catch {
                engine = nil
                engineModelID = nil
                if let fallback {
                    receive(fallback)
                } else {
                    messages.append(Message(fromUser: false, text: error.localizedDescription))
                }
            }
            var finished = ModelGuardStore.load()
            finished.pending = nil
            ModelGuardStore.save(finished)
            isThinking = false
        }
    }
}

/// Guarda em disco o que a IA estava fazendo, para saber na próxima abertura se o app caiu por falta de memória.
enum ModelGuardStore {
    private static let pendingKey = "EditorIA.modelPending"
    private static let crashesKey = "EditorIA.modelCrashes"

    static func load() -> ModelCrashGuard {
        let defaults = UserDefaults.standard
        return ModelCrashGuard(pending: defaults.string(forKey: pendingKey), crashes: defaults.dictionary(forKey: crashesKey) as? [String: Int] ?? [:])
    }

    static func save(_ state: ModelCrashGuard) {
        let defaults = UserDefaults.standard
        defaults.set(state.pending, forKey: pendingKey)
        defaults.set(state.crashes, forKey: crashesKey)
    }
}
