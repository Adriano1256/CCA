import Foundation

/// Uma ação que a IA local pede. Os campos valem conforme a ferramenta; o que faltar é ignorado.
struct AgentAction: Codable, Equatable {
    var tool: String
    var clip: Int?
    var track: String?
    var time: Double?
    var value: Double?
    var duration: Double?
    var text: String?
    var kind: String?
}

struct AgentPlan: Codable, Equatable {
    var reply: String
    var actions: [AgentAction]
}

/// Tarefas que precisam do aparelho e não só de mexer no projeto.
enum AgentRequest: Equatable {
    case transcribeAll
    case analyzeSound
    case motion(template: String, text: String, start: Double, duration: Double)
    case exportVideo
}

struct AgentOutcome {
    var project: EditorProject
    var done: [String] = []
    /// Ações recusadas, com o motivo, para mostrar ao usuário.
    var blocked: [String] = []
    var requests: [AgentRequest] = []
    var seek: Double?
}

enum ChatFormat: String, Codable {
    case gemma, qwen
}

enum AgentProtocol {
    static let tools: [String] = [
        "split", "delete", "ripple_delete", "move", "trim_start", "trim_end", "set_volume", "set_speed", "set_track",
        "add_text", "delete_text", "set_color", "transition", "ken_burns", "zoom", "mark_sonora", "assemble",
        "caption_style", "ducking", "seek", "transcribe", "analyze_sound", "motion", "export"
    ]

    /// Gramática que obriga o modelo a responder sempre com um JSON válido neste formato.
    static var grammar: String {
        let toolNames = tools.map { "\"\\\"\($0)\\\"\"" }.joined(separator: " | ")
        return #"""
        root ::= "{" ws "\"reply\"" ws ":" ws string ws "," ws "\"actions\"" ws ":" ws "[" ws (action (ws "," ws action)*)? ws "]" ws "}"
        action ::= "{" ws "\"tool\"" ws ":" ws tool (ws "," ws field)* ws "}"
        field ::= intfield | numfield | strfield
        intfield ::= "\"clip\"" ws ":" ws integer
        numfield ::= ("\"time\"" | "\"value\"" | "\"duration\"") ws ":" ws number
        strfield ::= ("\"track\"" | "\"text\"" | "\"kind\"") ws ":" ws string
        integer ::= "-"? [0-9]{1,6}
        number ::= "-"? [0-9]{1,6} ("." [0-9]{1,4})?
        string ::= "\"" ([^"\\\x7F\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\""
        ws ::= [ \t\n]{0,4}
        """# + "\ntool ::= " + toolNames + "\n"
    }

    static let systemPrompt = """
    Você é o assistente de edição do Editor IA, em um iPhone, sem internet. Fala português do Brasil.
    Responda SEMPRE em JSON: {"reply":"frase curta para o editor","actions":[...]}.
    Cada ação tem "tool" e os campos necessários. Tempos em segundos. "clip" é o número do clipe na lista do projeto.

    Ferramentas:
    split(clip,time) divide o clipe no tempo da timeline
    delete(clip) apaga e mantém o espaço; ripple_delete(clip) apaga e fecha o espaço
    move(clip,time) coloca o início do clipe no tempo
    trim_start(clip,value) corta value segundos do início; trim_end(clip,value) corta do fim
    set_volume(clip ou track,value) 0 a 2; set_speed(clip,value) 0.1 a 8; set_track(clip,track)
    add_text(text,time,duration,kind) kind: fade pop slide bounce zoom slam spring typewriter glitch; delete_text(clip) usa o número do texto
    set_color(clip ou track,kind,value) kind: exposure(-2 a 2) contrast(0.5 a 1.5) saturation(0 a 2) temperature(3000 a 10000) shadows(-1 a 1) highlights(0 a 1)
    transition(clip ou track,kind,value) kind: dissolve slideLeft slideUp zoom wipe flash; value é a duração
    ken_burns(clip ou track) zoom lento em foto; zoom(clip,value) zoom até value ao longo do clipe
    mark_sonora(clip) marca que o clipe tem fala; assemble(kind) kind: institucional ou stories, monta a timeline
    caption_style(kind) kind: word phrase karaoke; ducking(value) volume da música sob a fala, 0.05 a 0.8
    seek(time) move o cursor; transcribe() cria legendas; analyze_sound() detecta fala e música
    motion(kind,text,time,duration) kind é o id do modelo de motion; export() exporta o vídeo

    Trilhas: video, broll, voice, audio (música), sfx, motion, subject.

    Regras:
    - Nunca invente falas, nomes, dados ou acontecimentos.
    - Clipes marcados [SONORA] têm fala: não os corte. Se pedirem corte em sonora, explique que é preciso abrir a revisão da fala, e não inclua a ação.
    - Respeite a ordem de importação.
    - Mexa só no que foi pedido.
    - Se não souber, se faltar informação ou se o app não tiver a ferramenta, diga isso em "reply" e use "actions":[].
    - Pergunta sem pedido de edição: responda em "reply" com "actions":[].
    """

    static func formatPrompt(system: String, user: String, format: ChatFormat) -> String {
        switch format {
        case .gemma:
            return "<|turn>system\n\(system)<turn|>\n<|turn>user\n\(user)<turn|>\n<|turn>model\n<|channel>thought\n<channel|>"
        case .qwen:
            return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        }
    }

    /// Resumo do projeto para a IA. Sem caminhos de arquivo e limitado para caber no contexto.
    static func projectSummary(_ project: EditorProject, playhead: Double, selectedClip: UUID?, motionTemplates: [String] = [], maximumClips: Int = 60) -> String {
        var lines: [String] = []
        lines.append(String(format: "Projeto \"%@\", perfil %@, duração %.1f s, cursor em %.1f s.", project.name, project.profile, project.contentEnd, playhead))
        let clips = project.clips.filter { $0.track != "subject" }.sorted { $0.start < $1.start }
        lines.append("Clipes:")
        for (index, clip) in clips.prefix(maximumClips).enumerated() {
            let media = project.media.first { $0.id == clip.mediaID }
            let tags = (isSpeech(clip, media: media) ? " [SONORA]" : "") + (clip.id == selectedClip ? " [SELECIONADO]" : "")
            lines.append(String(format: "%d. %@ %.1f-%.1f s, volume %.2f, %@%@", index + 1, clip.track, clip.start, clip.end, clip.volume, media?.kind ?? "?", tags))
        }
        if clips.count > maximumClips { lines.append("... mais \(clips.count - maximumClips) clipes") }
        if !project.overlays.isEmpty {
            lines.append("Textos:")
            for (index, overlay) in project.overlays.prefix(20).enumerated() {
                lines.append(String(format: "%d. \"%@\" em %.1f s por %.1f s", index + 1, String(overlay.text.prefix(40)), overlay.start, overlay.duration))
            }
        }
        if !project.captionWords.isEmpty {
            let speech = project.captionWords.prefix(120).map(\.text).joined(separator: " ")
            lines.append("Fala transcrita: \(speech)")
        }
        if !motionTemplates.isEmpty { lines.append("Modelos de motion: \(motionTemplates.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }

    static func isSpeech(_ clip: TimelineClip, media: LocalMedia?) -> Bool {
        clip.track == "voice" || (media?.isSonora ?? false)
    }

    /// Aceita JSON puro ou com texto em volta, para não perder uma resposta por causa de um detalhe.
    static func parsePlan(_ text: String) -> AgentPlan? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AgentPlan.self, from: data)
    }
}

enum AgentExecutor {
    /// Aplica as ações em uma cópia do projeto. Fala nunca é cortada aqui, mesmo que a IA peça.
    static func apply(_ plan: AgentPlan, to source: EditorProject, playhead: Double) -> AgentOutcome {
        var outcome = AgentOutcome(project: source)
        // A numeração é a da lista enviada à IA; não muda enquanto o plano é aplicado.
        let numbered = source.clips.filter { $0.track != "subject" }.sorted { $0.start < $1.start }.map(\.id)

        func clipIndex(_ number: Int?) -> Int? {
            guard let number, number >= 1, number <= numbered.count else { return nil }
            return outcome.project.clips.firstIndex { $0.id == numbered[number - 1] }
        }

        func targets(_ action: AgentAction) -> [Int] {
            if let index = clipIndex(action.clip) { return [index] }
            if let track = action.track { return outcome.project.clips.indices.filter { outcome.project.clips[$0].track == track } }
            return []
        }

        func isProtected(_ index: Int) -> Bool {
            let clip = outcome.project.clips[index]
            return AgentProtocol.isSpeech(clip, media: outcome.project.media.first { $0.id == clip.mediaID })
        }

        func stillFlag(_ index: Int) -> Bool {
            outcome.project.media.first { $0.id == outcome.project.clips[index].mediaID }?.kind == "Imagem"
        }

        for action in plan.actions {
            switch action.tool {
            case "split", "delete", "ripple_delete", "trim_start", "trim_end", "set_speed":
                guard let index = clipIndex(action.clip) else {
                    outcome.blocked.append("\(action.tool): clipe \(action.clip.map(String.init) ?? "?") não existe")
                    continue
                }
                if isProtected(index) {
                    outcome.blocked.append("Clipe \(action.clip ?? 0) tem fala. Abra a revisão da sonora para aprovar qualquer corte.")
                    continue
                }
                let clip = outcome.project.clips[index]
                switch action.tool {
                case "split":
                    guard let time = action.time, let parts = TimelineEditing.split(clip, at: time) else {
                        outcome.blocked.append("Não deu para dividir o clipe \(action.clip ?? 0) nesse tempo")
                        continue
                    }
                    outcome.project.clips[index] = parts.left
                    outcome.project.clips.append(parts.right)
                    outcome.done.append("Clipe \(action.clip ?? 0) dividido")
                case "delete":
                    outcome.project.clips.remove(at: index)
                    outcome.done.append("Clipe \(action.clip ?? 0) apagado")
                case "ripple_delete":
                    outcome.project.clips = TimelineEditing.rippleDelete(clip.id, in: outcome.project.clips)
                    outcome.done.append("Clipe \(action.clip ?? 0) apagado e espaço fechado")
                case "trim_start":
                    outcome.project.clips[index] = TimelineEditing.trimStart(clip, by: action.value ?? 0, isStill: stillFlag(index))
                    outcome.done.append("Início do clipe \(action.clip ?? 0) aparado")
                case "trim_end":
                    let media = outcome.project.media.first { $0.id == clip.mediaID }
                    outcome.project.clips[index] = TimelineEditing.trimEnd(clip, by: -(action.value ?? 0), sourceDuration: media?.kind == "Imagem" ? nil : media?.duration)
                    outcome.done.append("Fim do clipe \(action.clip ?? 0) aparado")
                default:
                    outcome.project.clips[index] = TimelineEditing.setSpeed(clip, to: action.value ?? 1)
                    outcome.done.append("Velocidade do clipe \(action.clip ?? 0) ajustada")
                }
            case "move":
                guard let index = clipIndex(action.clip), let time = action.time else { outcome.blocked.append("move: faltou clipe ou tempo"); continue }
                outcome.project.clips[index].start = max(0, time)
                outcome.done.append("Clipe \(action.clip ?? 0) movido")
            case "set_track":
                guard let index = clipIndex(action.clip), let track = action.track else { outcome.blocked.append("set_track: faltou clipe ou trilha"); continue }
                outcome.project.clips[index].track = track
                outcome.done.append("Clipe \(action.clip ?? 0) movido para a trilha \(track)")
            case "set_volume":
                let list = targets(action)
                guard !list.isEmpty, let value = action.value else { outcome.blocked.append("set_volume: faltou alvo ou valor"); continue }
                for index in list { outcome.project.clips[index].volume = min(2, max(0, value)) }
                outcome.done.append("Volume ajustado em \(list.count) clipe(s)")
            case "add_text":
                guard let text = action.text, !text.isEmpty else { outcome.blocked.append("add_text: faltou o texto"); continue }
                outcome.project.overlays.append(TextOverlay(text: text, start: action.time ?? playhead, duration: max(0.5, action.duration ?? 3), animation: action.kind ?? "fade"))
                outcome.done.append("Texto adicionado")
            case "delete_text":
                guard let number = action.clip, number >= 1, number <= outcome.project.overlays.count else { outcome.blocked.append("delete_text: texto não existe"); continue }
                outcome.project.overlays.remove(at: number - 1)
                outcome.done.append("Texto removido")
            case "set_color":
                let list = targets(action)
                guard !list.isEmpty, let kind = action.kind, let value = action.value else { outcome.blocked.append("set_color: faltou alvo, ajuste ou valor"); continue }
                for index in list {
                    switch kind {
                    case "exposure": outcome.project.clips[index].look.exposure = min(2, max(-2, value))
                    case "contrast": outcome.project.clips[index].look.contrast = min(1.5, max(0.5, value))
                    case "saturation": outcome.project.clips[index].look.saturation = min(2, max(0, value))
                    case "temperature": outcome.project.clips[index].look.temperature = min(10000, max(3000, value))
                    case "shadows": outcome.project.clips[index].look.shadows = min(1, max(-1, value))
                    case "highlights": outcome.project.clips[index].look.highlights = min(1, max(0, value))
                    default: break
                    }
                }
                outcome.done.append("Cor ajustada em \(list.count) clipe(s)")
            case "transition":
                let kind = TransitionMotion.kinds.contains(action.kind ?? "") ? action.kind! : "dissolve"
                let ids = targets(action).map { outcome.project.clips[$0].id }
                guard !ids.isEmpty else { outcome.blocked.append("transition: faltou o alvo"); continue }
                var count = 0
                for id in ids {
                    if let next = TimelineEditing.addTransition(to: id, kind: kind, duration: action.value ?? 0.5, in: outcome.project.clips) {
                        outcome.project.clips = next
                        count += 1
                    }
                }
                outcome.done.append("Transição em \(count) clipe(s)")
            case "ken_burns":
                let list = targets(action)
                for index in list { outcome.project.clips[index].look.kenBurns = true }
                outcome.done.append("Zoom lento em \(list.count) clipe(s)")
            case "zoom":
                guard let index = clipIndex(action.clip), let value = action.value else { outcome.blocked.append("zoom: faltou clipe ou valor"); continue }
                let duration = outcome.project.clips[index].duration
                outcome.project.clips[index].keyframes.removeAll { $0.property == "scale" }
                outcome.project.clips[index].keyframes.append(ClipKeyframe(property: "scale", time: 0, value: 1, interpolation: "ease"))
                outcome.project.clips[index].keyframes.append(ClipKeyframe(property: "scale", time: duration, value: min(4, max(0.1, value)), interpolation: "ease"))
                outcome.done.append("Zoom no clipe \(action.clip ?? 0)")
            case "mark_sonora":
                guard let index = clipIndex(action.clip), let mediaIndex = outcome.project.media.firstIndex(where: { $0.id == outcome.project.clips[index].mediaID }) else {
                    outcome.blocked.append("mark_sonora: clipe não existe")
                    continue
                }
                outcome.project.media[mediaIndex].isSonora = true
                outcome.done.append("Clipe \(action.clip ?? 0) marcado como sonora")
            case "assemble":
                let draft = action.kind == "stories"
                    ? DirectorPlanningCore.buildStoriesDraft(media: outcome.project.directorMedia)
                    : DirectorPlanningCore.buildInstitutionalDraft(media: outcome.project.directorMedia)
                let instructions = DirectorTimelineMaterializer.makeInstructions(draft: draft, media: outcome.project.directorMedia, appendAt: 0)
                guard !instructions.isEmpty else { outcome.blocked.append("Stories com vídeo precisam da sua aprovação na aba Diretor IA"); continue }
                outcome.project.clips = outcome.project.clips.filter { $0.track == "audio" || $0.track == "sfx" || $0.track == "motion" }
                for item in instructions {
                    guard let mediaID = UUID(uuidString: item.mediaID) else { continue }
                    outcome.project.clips.append(TimelineClip(mediaID: mediaID, track: item.track, start: item.timelineStart, duration: item.duration, sourceIn: item.sourceIn, volume: item.volume, label: item.label))
                }
                outcome.project.profile = draft.profile
                outcome.done.append("Montagem \(draft.profile) aplicada; falas inteiras")
            case "caption_style":
                if let kind = action.kind, ["word", "phrase", "karaoke"].contains(kind) {
                    outcome.project.captionStyle = kind
                    outcome.done.append("Estilo de legenda: \(kind)")
                }
            case "ducking":
                if let value = action.value {
                    outcome.project.automaticDucking = true
                    outcome.project.duckingLevel = min(0.8, max(0.05, value))
                    outcome.done.append("Música abaixa durante a fala")
                }
            case "seek":
                outcome.seek = action.time
            case "transcribe":
                outcome.requests.append(.transcribeAll)
            case "analyze_sound":
                outcome.requests.append(.analyzeSound)
            case "motion":
                outcome.requests.append(.motion(template: action.kind ?? "", text: action.text ?? "", start: action.time ?? playhead, duration: action.duration ?? 3))
            case "export":
                outcome.requests.append(.exportVideo)
            default:
                outcome.blocked.append("Ferramenta desconhecida: \(action.tool)")
            }
        }
        return outcome
    }
}

/// Modelos oferecidos no app. São baixados uma vez, com sua autorização, e depois rodam sem internet.
struct LocalModel: Identifiable, Equatable {
    var id: String
    var name: String
    var detail: String
    var url: String
    var fileName: String
    var approximateBytes: Int64
    var format: ChatFormat
    /// Memória mínima do aparelho para rodar com folga.
    var minimumMemoryGB: Double
    var contextSize: Int

    static let catalog: [LocalModel] = [
        LocalModel(
            id: "qwen35-2b-q4",
            name: "Qwen 3.5 2B",
            detail: "Leve e rápido. Licença Apache 2.0.",
            url: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf",
            fileName: "Qwen3.5-2B-Q4_K_M.gguf",
            approximateBytes: 1_300_000_000,
            format: .qwen,
            minimumMemoryGB: 5.5,
            contextSize: 4096
        ),
        LocalModel(
            id: "gemma4-e2b-qat",
            name: "Gemma 4 E2B",
            detail: "Otimizado para celular, bom em vários idiomas. Licença Apache 2.0.",
            url: "https://huggingface.co/unsloth/gemma-4-E2B-it-qat-mobile-GGUF/resolve/main/gemma-4-E2B-it-qat-UD-Q2_K_XL.gguf",
            fileName: "gemma-4-E2B-it-qat-UD-Q2_K_XL.gguf",
            approximateBytes: 2_200_000_000,
            format: .gemma,
            minimumMemoryGB: 7.5,
            contextSize: 4096
        ),
        LocalModel(
            id: "gemma4-e4b",
            name: "Gemma 4 E4B",
            detail: "Mais capaz e mais pesado. Licença Apache 2.0.",
            url: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-UD-Q2_K_XL.gguf",
            fileName: "gemma-4-E4B-it-UD-Q2_K_XL.gguf",
            approximateBytes: 3_800_000_000,
            format: .gemma,
            minimumMemoryGB: 11,
            contextSize: 8192
        )
    ]

    /// O melhor modelo que cabe na memória do aparelho.
    static func recommended(memoryGB: Double) -> LocalModel {
        catalog.filter { memoryGB >= $0.minimumMemoryGB }.last ?? catalog[0]
    }

    /// Todo arquivo GGUF começa com estas quatro letras; detecta download corrompido ou página de erro.
    static func looksValid(header: [UInt8], fileSize: Int64, expected: Int64) -> Bool {
        header.count >= 4 && Array(header.prefix(4)) == Array("GGUF".utf8) && fileSize > expected / 2
    }
}

/// Prepara uma composição HTML vinda de fora (por exemplo, feita por mim no HyperFrames) para rodar sem internet.
enum MotionImport {
    struct Prepared {
        var html: String
        /// Endereços externos que continuam no arquivo e não vão carregar offline.
        var warnings: [String]
    }

    private static let localLibraries = ["gsap", "SplitText", "CustomEase", "lottie"]

    static func prepare(html: String, libraryPath: String) -> Prepared {
        var result = html
        var warnings: [String] = []
        let pattern = #"(?:src|href)\s*=\s*["'](https?://[^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                guard let range = Range(match.range(at: 1), in: html) else { continue }
                let url = String(html[range])
                if let library = localLibraries.first(where: { url.lowercased().contains($0.lowercased()) }) {
                    result = result.replacingOccurrences(of: url, with: "\(libraryPath)/\(library).min.js")
                } else {
                    warnings.append(url)
                }
            }
        }
        let runtime = "<script src=\"\(libraryPath)/runtime.js\"></script>"
        if let head = result.range(of: "</head>", options: .caseInsensitive) {
            result.insert(contentsOf: runtime, at: head.lowerBound)
        } else {
            result = runtime + result
        }
        return Prepared(html: result, warnings: warnings)
    }

    static func isComposition(_ html: String) -> Bool {
        html.contains("data-composition-id")
    }

    static func duration(in html: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"data-duration\s*=\s*["']([0-9.]+)["']"#),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return Double(html[range])
    }
}
