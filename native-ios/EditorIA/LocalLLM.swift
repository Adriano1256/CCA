import Foundation
#if canImport(LlamaSwift)
import LlamaSwift
#endif

enum LocalLLMError: LocalizedError {
    case modelLoadFailed
    case contextFailed
    case tokenizeFailed
    case promptTooLong
    case decodeFailed
    case grammarFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: return "Não foi possível abrir o modelo. Ele pode estar incompleto, ou o aparelho pode estar sem memória livre. Feche outros apps ou escolha um modelo menor."
        case .contextFailed: return "Sem memória para rodar a IA agora. Feche outros apps ou escolha um modelo menor."
        case .tokenizeFailed: return "Não foi possível preparar o pedido para a IA."
        case .promptTooLong: return "O projeto é grande demais para a memória da IA. Selecione menos conteúdo."
        case .decodeFailed: return "A IA parou no meio do processamento."
        case .grammarFailed: return "Não foi possível preparar o formato de resposta da IA."
        }
    }
}

#if canImport(LlamaSwift)
/// Roda um modelo GGUF no aparelho com llama.cpp. Nada sai do dispositivo.
/// Use sempre a partir de uma única fila ou tarefa de cada vez.
final class LlamaEngine: @unchecked Sendable {
    private static let backend: Void = { llama_backend_init() }()

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    let contextSize: Int

    init(path: String, contextSize: Int, gpuLayers: Int32 = 99, vocabOnly: Bool = false, threads: Int32 = 4) throws {
        _ = Self.backend
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = gpuLayers
        modelParams.vocab_only = vocabOnly
        guard let loaded = llama_model_load_from_file(path, modelParams) else { throw LocalLLMError.modelLoadFailed }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = 512
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        guard let created = llama_init_from_model(loaded, contextParams) else {
            llama_model_free(loaded)
            throw LocalLLMError.contextFailed
        }
        guard let loadedVocab = llama_model_get_vocab(loaded) else {
            llama_free(created)
            llama_model_free(loaded)
            throw LocalLLMError.modelLoadFailed
        }
        model = loaded
        context = created
        vocab = loadedVocab
        self.contextSize = contextSize
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    func tokenize(_ text: String, addSpecial: Bool = true) throws -> [llama_token] {
        let length = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 8)
        var count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), addSpecial, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), addSpecial, true)
        }
        guard count >= 0 else { throw LocalLLMError.tokenizeFailed }
        return Array(tokens.prefix(Int(count)))
    }

    private func bytes(of token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var written = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if written < 0 {
            buffer = [CChar](repeating: 0, count: Int(-written))
            written = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        guard written > 0 else { return [] }
        return buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }
    }

    private func allows(_ rules: UnsafeMutablePointer<llama_sampler>, _ token: llama_token) -> Bool {
        var single = llama_token_data(id: token, logit: 1, p: 0)
        return withUnsafeMutablePointer(to: &single) { pointer -> Bool in
            var array = llama_token_data_array(data: pointer, size: 1, selected: -1, sorted: false)
            llama_sampler_apply(rules, &array)
            return pointer.pointee.logit.isFinite
        }
    }

    /// A palavra mais provável que a gramática permite, olhando o vocabulário todo.
    private func bestAllowed(_ rules: UnsafeMutablePointer<llama_sampler>) -> llama_token {
        let count = Int(llama_vocab_n_tokens(vocab))
        guard let logits = llama_get_logits_ith(context, -1) else { return 0 }
        var candidates = (0..<count).map { llama_token_data(id: llama_token($0), logit: logits[$0], p: 0) }
        return candidates.withUnsafeMutableBufferPointer { buffer -> llama_token in
            var array = llama_token_data_array(data: buffer.baseAddress, size: buffer.count, selected: -1, sorted: false)
            llama_sampler_apply(rules, &array)
            guard let data = array.data, array.size > 0 else { return 0 }
            var best = 0
            for index in 1..<Int(array.size) where data[index].logit > data[best].logit { best = index }
            return data[best].id
        }
    }

    /// Confere se a gramática é aceita pelo vocabulário e devolve o amostrador pronto.
    func makeGrammarSampler(_ grammar: String) throws -> UnsafeMutablePointer<llama_sampler> {
        guard let sampler = llama_sampler_init_grammar(vocab, grammar, "root") else { throw LocalLLMError.grammarFailed }
        return sampler
    }

    /// Gera a resposta. `grammar` força o formato; `shouldStop` permite cancelar.
    func generate(prompt: String, grammar: String?, maximumTokens: Int = 700, temperature: Float = 0.2, shouldStop: () -> Bool = { false }, onProgress: (Int) -> Void = { _ in }) throws -> String {
        llama_memory_clear(llama_get_memory(context), true)
        var tokens = try tokenize(prompt)
        guard tokens.count + 32 < contextSize else { throw LocalLLMError.promptTooLong }

        // Sorteia entre as 40 melhores palavras e só confere a gramática na escolhida.
        // Conferir a gramática no vocabulário inteiro a cada palavra deixava a IA muito lenta.
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(chain) }
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32(truncatingIfNeeded: Date().hashValue)))
        let rules = try grammar.map { try makeGrammarSampler($0) }
        defer { if let rules { llama_sampler_free(rules) } }

        // O pedido entra em blocos que cabem no tamanho de lote.
        var position = 0
        while position < tokens.count {
            let end = min(position + 512, tokens.count)
            let status = tokens[position..<end].withUnsafeBufferPointer { part -> Int32 in
                let pointer = UnsafeMutablePointer(mutating: part.baseAddress)
                return llama_decode(context, llama_batch_get_one(pointer, Int32(part.count)))
            }
            guard status == 0 else { throw LocalLLMError.decodeFailed }
            position = end
        }
        tokens.removeAll()

        var output: [UInt8] = []
        var produced = 0
        let room = contextSize - position - 8
        while produced < min(maximumTokens, room) {
            if shouldStop() { break }
            var token = llama_sampler_sample(chain, context, -1)
            if let rules {
                if !allows(rules, token) { token = bestAllowed(rules) }
                llama_sampler_accept(rules, token)
            }
            if llama_vocab_is_eog(vocab, token) { break }
            output.append(contentsOf: bytes(of: token))
            produced += 1
            onProgress(produced)
            let status = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            guard status == 0 else { throw LocalLLMError.decodeFailed }
        }
        return String(decoding: output, as: UTF8.self)
    }
}
#else
/// O simulador do iOS não tem a biblioteca de IA; o resto do app funciona normalmente nele.
final class LlamaEngine: @unchecked Sendable {
    init(path: String, contextSize: Int, gpuLayers: Int32 = 99, vocabOnly: Bool = false, threads: Int32 = 4) throws {
        throw LocalLLMError.modelLoadFailed
    }

    func generate(prompt: String, grammar: String?, maximumTokens: Int = 700, temperature: Float = 0.2, shouldStop: () -> Bool = { false }, onProgress: (Int) -> Void = { _ in }) throws -> String {
        throw LocalLLMError.modelLoadFailed
    }
}
#endif
