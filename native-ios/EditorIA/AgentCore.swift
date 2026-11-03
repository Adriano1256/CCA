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
    case exportVideo
    case prepare
    case addMusic(mood: String)
    case addSound(kind: String, time: Double)
    case reframe
    case undo
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
        "add_text", "delete_text", "set_color", "transition", "ken_burns", "zoom", "mark_sonora", "assemble", "set_client",
        "caption_style", "caption_color", "caption_size", "captions_off", "ducking", "seek", "transcribe", "analyze_sound", "export",
        "fade", "look", "music", "sound", "reframe", "prepare", "undo"
    ]

    /// Gramática que obriga o modelo a responder sempre com um JSON válido neste formato.
    static var grammar: String {
        let toolNames = tools.map { "\"\\\"\($0)\\\"\"" }.joined(separator: " | ")
        return #"""
        root ::= "{" ws "\"reply\"" ws ":" ws string ws "," ws "\"actions\"" ws ":" ws "[" ws (action (ws "," ws action)*)? ws "]" ws "}"
        action ::= "{" ws "\"tool\"" ws ":" ws tool (ws "," ws "\"clip\"" ws ":" ws integer)? (ws "," ws "\"track\"" ws ":" ws string)? (ws "," ws "\"time\"" ws ":" ws number)? (ws "," ws "\"value\"" ws ":" ws number)? (ws "," ws "\"duration\"" ws ":" ws number)? (ws "," ws "\"text\"" ws ":" ws string)? (ws "," ws "\"kind\"" ws ":" ws string)? ws "}"
        integer ::= "-"? [0-9]{1,6}
        number ::= "-"? [0-9]{1,6} ("." [0-9]{1,4})?
        string ::= "\"" ([^"\\\x7F\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})){0,220} "\""
        ws ::= [ \t\n]{0,4}
        """# + "\ntool ::= " + toolNames + "\n"
    }

    static let systemPrompt = """
    Você é o assistente de edição do Editor IA, em um iPhone, sem internet. Fala português do Brasil.
    Responda SEMPRE em JSON: {"reply":"frase curta para o editor","actions":[...]}.
    Cada ação tem "tool" e os campos necessários, nesta ordem: tool, clip, track, time, value, duration, text, kind. Tempos em segundos. "clip" é o número do clipe na lista do projeto. Volume e velocidade: 1 é normal, 0.1 é 10%.

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
    mark_sonora(clip) marca que o clipe tem fala; set_client(text) escolhe o cliente pelo nome, como "Breu Branco" ou "Tucuruí"; assemble(time,value,duration,kind) kind: institucional ou stories, monta a timeline no padrão do cliente; value muda os segundos de imagem de apoio antes da primeira fala; duration muda a duração total desejada; time muda quantos segundos a pessoa aparece antes do B-roll cobrir
    caption_style(kind) legenda animada, kind: hormozi hormozi-classico mrbeast podcast tiktok-caixa tiktok-branca reels-pop verde-viral roxo-viral marca-texto emoji-viral palavra-forte foco sublinhado karaoke karaoke-fill karaoke-azul box reveal phrase onda balanco slam word pop gigante corte-seco tremor sombra-dura fogo militar giro esticado quadrinhos desenho bolha caneta caderno recadinho praia neon neon-rosa glitch maquina retro-game bloco placar elegante cinema luxo ouro minimalista editorial inst-limpa inst-faixa inst-cor inst-noticia inst-sublinhado katana motion-ia dois-mundos. Em vídeo de prefeitura prefira os inst-; caption_color(text) cor em hex como #FFD84D; caption_size(value) 40 a 140; captions_off() tira as legendas
    ducking(value) volume da música sob a fala, 0.05 a 0.8; fade(clip ou track,kind,value) kind: in ou out, value em segundos
    look(clip ou track,kind) kind: natural quente frio vibrante cinema "preto e branco"
    music(kind) coloca música da biblioteca pelo clima: emocionante inspirador "obra e trabalho" festa corporativo suave impacto
    sound(kind,time) efeito sonoro da biblioteca: transição impacto subida clique ambiente aplauso
    reframe() ajusta os clipes à proporção mantendo o assunto no quadro; prepare() analisa fala, música e imagens; undo() desfaz a última edição
    seek(time) move o cursor; transcribe() cria legendas; analyze_sound() detecta fala e música
    export() exporta o vídeo

    Trilhas: video, broll, voice, audio (música), sfx, subject.

    Regras:
    - Nunca invente falas, nomes, dados ou acontecimentos.
    - Clipes marcados [SONORA] têm fala: não os corte. Se pedirem corte em sonora, explique que é preciso abrir a revisão da fala, e não inclua a ação.
    - Respeite a ordem de importação.
    - Mexa só no que foi pedido.
    - Se não souber, se faltar informação ou se o app não tiver a ferramenta, diga isso em "reply" e use "actions":[].
    - Pergunta sem pedido de edição: responda em "reply" com "actions":[].

    Exemplos:
    Pedido: tira o som do b-roll
    {"reply":"B-roll sem som.","actions":[{"tool":"set_volume","track":"broll","value":0}]}
    Pedido: abaixa a música para 20%
    {"reply":"Música em 20%.","actions":[{"tool":"set_volume","track":"audio","value":0.2}]}
    Pedido: corta 2 segundos do começo do clipe 3
    {"reply":"Cortei 2 s do início do clipe 3.","actions":[{"tool":"trim_start","clip":3,"value":2}]}
    Pedido: coloca o título Bem-vindos no começo com impacto
    {"reply":"Título no início.","actions":[{"tool":"add_text","time":0,"duration":3,"text":"Bem-vindos","kind":"slam"}]}
    Pedido: legenda estilo neon
    {"reply":"Legenda neon.","actions":[{"tool":"caption_style","kind":"neon"}]}
    Pedido: edita no padrão do Breu Branco, mas abre com 15 segundos de B-roll antes da primeira fala
    {"reply":"Montando no padrão do Breu Branco, com 15 s de abertura.","actions":[{"tool":"set_client","text":"Breu Branco"},{"tool":"assemble","value":15,"kind":"institucional"}]}
    Pedido: quanto dura o vídeo?
    {"reply":"O vídeo tem 1 minuto e 32 segundos.","actions":[]}
    """

    static func formatPrompt(system: String, user: String, format: ChatFormat) -> String {
        switch format {
        case .gemma:
            return "<|turn>system\n\(system)<turn|>\n<|turn>user\n\(user)<turn|>\n<|turn>model\n"
        case .qwen:
            return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        }
    }

    /// Resumo do projeto para a IA. Sem caminhos de arquivo e limitado para caber no contexto.
    static func projectSummary(_ project: EditorProject, playhead: Double, selectedClip: UUID?, libraryMoods: [String] = [], maximumClips: Int = 40) -> String {
        var lines: [String] = []
        lines.append(String(format: "Projeto \"%@\", perfil %@, duração %.1f s, cursor em %.1f s.", project.name, project.profile, project.contentEnd, playhead))
        let clips = project.clips.filter { $0.track != "subject" }.sorted { $0.start < $1.start }
        lines.append("Clipes:")
        for (index, clip) in clips.prefix(maximumClips).enumerated() {
            let media = project.media.first { $0.id == clip.mediaID }
            let tags = (isSpeech(clip, media: media) ? " [SONORA]" : "") + (clip.id == selectedClip ? " [SELECIONADO]" : "")
            lines.append(String(format: "%d. %@ %.1f-%.1f s, volume %.2f, %@%@", index + 1, clip.track, clip.start, clip.end, clip.volume, media?.kind ?? "?", tags))
            if let media {
                var facts: [String] = []
                if !media.visualTags.isEmpty { facts.append("imagem: " + media.visualTags.prefix(5).joined(separator: ", ")) }
                if let share = media.faceShare { facts.append(String(format: "rostos %.0f%%", share * 100)) }
                if let sound = media.soundSummary { facts.append("som: " + sound) }
                if !media.transcript.isEmpty {
                    let speed = max(0.01, clip.look.speed)
                    let sourceEnd = clip.sourceIn + clip.duration * speed
                    let spoken = media.transcript.filter { $0.start >= clip.sourceIn && $0.start < sourceEnd }.prefix(40).map(\.text).joined(separator: " ")
                    if !spoken.isEmpty { facts.append("fala: " + spoken) }
                }
                if !facts.isEmpty { lines.append("   " + facts.joined(separator: " | ")) }
            }
        }
        if clips.count > maximumClips { lines.append("... mais \(clips.count - maximumClips) clipes") }
        if !project.overlays.isEmpty {
            lines.append("Textos:")
            for (index, overlay) in project.overlays.prefix(20).enumerated() {
                lines.append(String(format: "%d. \"%@\" em %.1f s por %.1f s", index + 1, String(overlay.text.prefix(40)), overlay.start, overlay.duration))
            }
        }
        lines.append(libraryMoods.isEmpty ? "Biblioteca de sons: vazia." : "Biblioteca de sons: \(libraryMoods.joined(separator: ", ")).")
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
    static func apply(_ plan: AgentPlan, to source: EditorProject, playhead: Double, clients: [ClientProfile] = []) -> AgentOutcome {
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
                    outcome.project.clips[index] = TimelineEditing.trimStart(clip, by: action.value ?? action.duration ?? action.time ?? 0, isStill: stillFlag(index))
                    outcome.done.append("Início do clipe \(action.clip ?? 0) aparado")
                case "trim_end":
                    let media = outcome.project.media.first { $0.id == clip.mediaID }
                    outcome.project.clips[index] = TimelineEditing.trimEnd(clip, by: -(action.value ?? action.duration ?? action.time ?? 0), sourceDuration: media?.kind == "Imagem" ? nil : media?.duration)
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
                guard !list.isEmpty, var value = action.value else { outcome.blocked.append("set_volume: faltou alvo ou valor"); continue }
                // "10" quer dizer 10%.
                if value > 2 { value /= 100 }
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
            case "set_client":
                let wanted = AssemblyRequest.fold(action.text ?? "")
                guard !wanted.isEmpty, let client = clients.first(where: { AssemblyRequest.fold($0.name).contains(wanted) || wanted.contains(AssemblyRequest.fold($0.name).replacingOccurrences(of: "prefeitura de ", with: "")) }) else {
                    outcome.blocked.append("Cliente \"\(action.text ?? "")\" não encontrado nos perfis")
                    continue
                }
                outcome.project.clientID = client.id
                outcome.done.append("Cliente: \(client.name)")
            case "assemble":
                // O padrão vem do perfil do cliente; o pedido pode mudar só um pedaço dele.
                let client = clients.first { $0.id == outcome.project.clientID }
                let opening = min(60, max(0, action.value ?? client?.openingDuration ?? 8))
                let target = action.duration.map { min(600, max(10, $0)) }
                let hold = min(10, max(0.5, action.time ?? 2.5))
                let draft = action.kind == "stories"
                    ? DirectorPlanningCore.buildStoriesDraft(media: outcome.project.directorMedia)
                    : DirectorPlanningCore.buildInstitutionalDraft(
                        media: outcome.project.directorMedia,
                        openingDuration: opening,
                        personHold: hold,
                        targetMinimum: target.map { max(5, $0 - 10) } ?? client?.targetMinimum ?? 90,
                        targetMaximum: target.map { $0 + 10 } ?? client?.targetMaximum ?? 120
                    )
                let instructions = DirectorTimelineMaterializer.makeInstructions(draft: draft, media: outcome.project.directorMedia, appendAt: 0)
                guard !instructions.isEmpty else { outcome.blocked.append("Stories com vídeo precisam da sua aprovação na aba Diretor IA"); continue }
                outcome.project.clips = outcome.project.clips.filter { $0.track == "audio" || $0.track == "sfx" || $0.track == "motion" }
                for item in instructions {
                    guard let mediaID = UUID(uuidString: item.mediaID) else { continue }
                    outcome.project.clips.append(TimelineClip(mediaID: mediaID, track: item.track, start: item.timelineStart, duration: item.duration, sourceIn: item.sourceIn, volume: item.volume, label: item.label))
                }
                outcome.project.profile = draft.profile
                var details = ["falas inteiras"]
                if action.kind != "stories" {
                    details.insert(String(format: "%.0f s de abertura", opening), at: 0)
                    if let target { details.append(String(format: "cerca de %.0f s no total", target)) }
                    if action.time != nil { details.append(String(format: "pessoa aparece %.1f s antes do B-roll", hold)) }
                }
                outcome.done.append("Montagem \(draft.profile)\(client.map { " (\($0.name))" } ?? ""): " + details.joined(separator: ", "))
            case "caption_style":
                if let kind = action.kind, let preset = CaptionPreset.find(kind) ?? CaptionPreset.match(kind) {
                    preset.apply(to: &outcome.project)
                    outcome.done.append("Legenda: \(preset.name)")
                } else {
                    outcome.blocked.append("Estilo de legenda desconhecido")
                }
            case "caption_color":
                if let text = action.text, text.hasPrefix("#"), text.count == 7 {
                    outcome.project.captionHighlightHex = text
                    outcome.done.append("Cor de destaque da legenda alterada")
                } else {
                    outcome.blocked.append("caption_color: use uma cor como #FFD84D")
                }
            case "caption_size":
                if let value = action.value {
                    outcome.project.captionFontSize = min(140, max(40, value))
                    outcome.done.append("Tamanho da legenda alterado")
                }
            case "captions_off":
                outcome.project.captionsEnabled = false
                outcome.done.append("Legendas desligadas; a transcrição continua guardada")
            case "fade":
                let list = targets(action)
                guard !list.isEmpty else { outcome.blocked.append("fade: faltou o alvo"); continue }
                for index in list {
                    let duration = outcome.project.clips[index].duration / 2
                    if action.kind == "in" {
                        outcome.project.clips[index].fadeIn = min(duration, max(0, action.value ?? 1))
                    } else {
                        outcome.project.clips[index].fadeOut = min(duration, max(0, action.value ?? 1))
                    }
                }
                outcome.done.append("Fade em \(list.count) clipe(s)")
            case "look":
                let list = targets(action)
                guard !list.isEmpty, let kind = action.kind, ColorLooks.names.contains(kind) else { outcome.blocked.append("look: faltou o alvo ou o visual"); continue }
                for index in list { ColorLooks.apply(kind, to: &outcome.project.clips[index].look) }
                outcome.done.append("Visual \(kind) em \(list.count) clipe(s)")
            case "music":
                outcome.requests.append(.addMusic(mood: action.kind ?? ""))
            case "sound":
                outcome.requests.append(.addSound(kind: action.kind ?? "", time: action.time ?? playhead))
            case "reframe":
                outcome.requests.append(.reframe)
            case "prepare":
                outcome.requests.append(.prepare)
            case "undo":
                outcome.requests.append(.undo)
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
        ),
        LocalModel(
            id: "gemma4-12b",
            name: "Gemma 4 12B",
            detail: "O maior que cabe em um iPhone de 12 GB. Entende melhor pedidos difíceis e responde mais devagar. Licença Apache 2.0.",
            url: "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/main/gemma-4-12b-it-UD-Q3_K_XL.gguf",
            fileName: "gemma-4-12b-it-UD-Q3_K_XL.gguf",
            approximateBytes: 6_000_000_000,
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



/// Entende pedidos comuns sem modelo de IA, para o chat funcionar desde a primeira abertura.
/// Lê do pedido as mudanças no padrão de montagem: "abre com 15 segundos de B-roll", "1 minuto e meio", "padrão do Breu".
enum AssemblyRequest {
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).trimmingCharacters(in: .whitespaces)
    }

    private static func number(_ pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    static func isAssembly(_ request: String) -> Bool {
        let text = fold(request)
        let verb = ["mont", "edit", "faz o video", "faca o video", "faz um video", "faz esse video"].contains { text.contains($0) }
        let pattern = ["padrao", "institucional", "prefeitura", "breu", "tucurui"].contains { text.contains($0) }
        return verb && pattern
    }

    static func client(in request: String) -> String? {
        let text = fold(request)
        if text.contains("breu") { return "Breu Branco" }
        if text.contains("tucurui") { return "Tucuruí" }
        return nil
    }

    /// Segundos de imagem de apoio antes da primeira fala.
    static func opening(in request: String) -> Double? {
        let text = fold(request)
        return number(#"(\d+(?:[.,]\d+)?)\s*(?:s|seg|segundos?)\s+(?:de\s+)?(?:b-?\s?roll|imagens?|imagem de apoio|apoio|abertura|musica)"#, in: text)
            ?? number(#"abertura\s+(?:de|com)\s+(\d+(?:[.,]\d+)?)"#, in: text)
    }

    /// Duração total desejada.
    static func total(in request: String) -> Double? {
        let text = fold(request)
        if text.contains("minuto e meio") || text.contains("1m30") || text.contains("1:30") { return 90 }
        if let minutes = number(#"(\d+(?:[.,]\d+)?)\s*minutos?"#, in: text) {
            let seconds = number(#"minutos?\s+e\s+(\d+)\s*(?:s|seg|segundos?)"#, in: text) ?? 0
            return minutes * 60 + seconds
        }
        return number(#"(?:total|video)\s+de\s+(\d+)\s*(?:s|seg|segundos?)"#, in: text)
    }

    /// Quanto a pessoa aparece antes de o B-roll cobrir.
    static func hold(in request: String) -> Double? {
        number(#"(?:pessoa|prefeito|entrevistado|ela|ele)\s+aparece\w*\s+(?:por\s+)?(\d+(?:[.,]\d+)?)\s*(?:s|seg|segundos?)"#, in: fold(request))
    }

    static func plan(for request: String) -> AgentPlan {
        var actions: [AgentAction] = []
        var notes: [String] = []
        if let client = client(in: request) {
            actions.append(AgentAction(tool: "set_client", text: client))
            notes.append("no padrão de \(client)")
        } else {
            notes.append("no padrão do cliente do projeto")
        }
        let opening = opening(in: request), total = total(in: request), hold = hold(in: request)
        if let opening { notes.append(String(format: "com %.0f s de abertura antes da primeira fala", opening)) }
        if let total { notes.append(String(format: "cerca de %.0f s no total", total)) }
        if let hold { notes.append(String(format: "pessoa aparecendo %.0f s antes do B-roll", hold)) }
        actions.append(AgentAction(tool: "assemble", time: hold, value: opening, duration: total, kind: "institucional"))
        return AgentPlan(reply: "Montando " + notes.joined(separator: ", ") + ". As falas ficam inteiras.", actions: actions)
    }
}

enum RuleAgent {
    private static let verbs = ["coloca", "bota", "poe", "tira", "corta", "deixa", "faz", "muda", "aumenta", "abaixa", "adiciona", "remove", "aplica", "troca", "monta", "exporta", "acelera"]

    /// Pedido simples, de uma coisa só: o app resolve na hora, sem esperar a IA.
    static func direct(for request: String, project: EditorProject) -> AgentPlan? {
        // Montagem no padrão, mesmo com ajustes no meio do pedido, é resolvida na hora.
        if AssemblyRequest.isAssembly(request), !fold(request).contains("stories") { return AssemblyRequest.plan(for: request) }
        // Vários pedidos numa frase: se o app entende cada parte, faz tudo na hora; senão, vai para a IA.
        let parts = clauses(request)
        if parts.count > 1 {
            var actions: [AgentAction] = []
            var replies: [String] = []
            for part in parts {
                guard let plan = plan(for: part, project: project), !plan.actions.isEmpty else { return nil }
                actions += plan.actions
                replies.append(plan.reply)
            }
            return AgentPlan(reply: replies.joined(separator: " "), actions: actions)
        }
        let text = fold(request)
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," })
        let actions = words.filter { word in verbs.contains { word.hasPrefix($0) } }.count
        guard actions <= 1, words.count <= 16 else { return nil }
        return plan(for: request, project: project)
    }

    /// Separa "faz isso e depois coloca aquilo" em pedidos de uma coisa só.
    static func clauses(_ request: String) -> [String] {
        let pattern = #"(?:\s*[,;]\s*(?:e\s+)?(?:depois|tambem|também|ai|aí)?\s*|\s+e\s+(?:depois\s+|tambem\s+|também\s+|ai\s+|aí\s+)?)(?=(?:coloca|coloque|bota|tira|tire|corta|corte|deixa|deixe|faz|faça|faca|muda|mude|aumenta|abaixa|adiciona|remove|aplica|troca|poe|põe|acelera|exporta)\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [request] }
        let marker = "\u{1F}"
        let marked = regex.stringByReplacingMatches(in: request, range: NSRange(request.startIndex..., in: request), withTemplate: marker)
        return marked.components(separatedBy: marker).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    /// Primeiro trecho que casa com o padrão, procurando no texto original (com acentos).
    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”'.,")))
        return value.isEmpty ? nil : value
    }

    private static func number(_ pattern: String, in text: String) -> Double? {
        capture(pattern, in: text).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    static func plan(for request: String, project: EditorProject) -> AgentPlan? {
        let text = fold(request)
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        let percent = text.split(whereSeparator: { !$0.isNumber }).first.flatMap { Double($0) }
        let clipNumber = number(#"clipe\s+(\d+)"#, in: text).map { Int($0) }
        let atSeconds = number(#"(?:em|aos|no segundo|nos)\s+(\d+(?:[.,]\d+)?)\s*(?:s\b|seg)"#, in: text)
        let quoted = capture(#"["“]([^"”]+)["”]"#, in: request)
        let written = quoted ?? capture(#"(?:escrito|dizendo|escrevendo|com o texto|t[íi]tulo)\s+(.+?)(?:\s+(?:no|na|em|aos|com|logo|para)\s|,|$)"#, in: request)

        if has("desfaz", "desfazer", "volta como") { return AgentPlan(reply: "Desfazendo.", actions: [AgentAction(tool: "undo")]) }
        if has("exporta", "exportar") { return AgentPlan(reply: "Exportando na qualidade escolhida.", actions: [AgentAction(tool: "export")]) }
        if has("prepara", "analisa", "analise") { return AgentPlan(reply: "Vou analisar fala, música e imagens.", actions: [AgentAction(tool: "prepare")]) }
        if has("transcrev") { return AgentPlan(reply: "Transcrevendo as sonoras.", actions: [AgentAction(tool: "transcribe")]) }
        if has("story", "stories") && has("mont", "faz", "cria") { return AgentPlan(reply: "Montando a sequência de Stories.", actions: [AgentAction(tool: "assemble", kind: "stories")]) }
        if AssemblyRequest.isAssembly(request) || has("institucional", "prefeitura") && has("mont", "faz", "cria", "edita") || has("monta o video", "monta esse video", "monta o videos", "edita o video") {
            return AssemblyRequest.plan(for: request)
        }
        if has("legenda") {
            if has("tira", "remove", "desliga", "sem legenda") { return AgentPlan(reply: "Legendas desligadas.", actions: [AgentAction(tool: "captions_off")]) }
            let preset = CaptionPreset.match(text) ?? CaptionPreset.find("karaoke")!
            var actions = [AgentAction(tool: "caption_style", kind: preset.id)]
            if !project.media.contains(where: { !$0.transcript.isEmpty }) { actions.insert(AgentAction(tool: "transcribe"), at: 0) }
            return AgentPlan(reply: "Legenda \(preset.name) aplicada.", actions: actions)
        }
        if has("tarja", "nome na tela", "lower third"), let name = quoted ?? capture(#"nome d[aoe]s?\s+(.+?)(?:\s+(?:em|aos|no|na)\s+\d|$)"#, in: request) ?? capture(#"tarja (?:d[aoe]s?|com)\s+(.+?)(?:\s+(?:em|aos|no|na)\s+\d|$)"#, in: request) {
            return AgentPlan(reply: "Nome na tela adicionado.", actions: [AgentAction(tool: "add_text", time: atSeconds, duration: 4, text: name, kind: "slide")])
        }
        if has("titulo", "texto animado") || (has("escrito", "texto") && has("coloca", "bota", "poe", "adiciona")), let written {
            let kind = has("impacto", "forte") ? "slam" : has("pula", "salta") ? "pop" : "fade"
            return AgentPlan(reply: "Título adicionado.", actions: [AgentAction(tool: "add_text", time: atSeconds ?? (has("inicio", "comeco") ? 0 : nil), duration: 3, text: written, kind: kind)])
        }
        if has("corta", "tira", "remove", "apara"), has("segundo"), let clipNumber, let seconds = number(#"(\d+(?:[.,]\d+)?)\s*(?:primeiros\s+|ultimos\s+)?seg"#, in: text) {
            let fromEnd = has("ultimos", "final", "fim")
            return AgentPlan(reply: "Cortei \(Int(seconds)) s do \(fromEnd ? "fim" : "início") do clipe \(clipNumber).", actions: [AgentAction(tool: fromEnd ? "trim_end" : "trim_start", clip: clipNumber, value: seconds)])
        }
        if has("broll", "b-roll", "b roll", "imagens de apoio") && has("tira o som", "sem som", "muda", "mudo") {
            return AgentPlan(reply: "B-roll sem som.", actions: [AgentAction(tool: "set_volume", track: "broll", value: 0)])
        }
        if has("musica", "trilha") {
            if has("abaixa", "mais baixo", "diminui", "volume") {
                let value = percent.map { $0 / 100 } ?? 0.15
                return AgentPlan(reply: "Volume da música ajustado.", actions: [AgentAction(tool: "set_volume", track: "audio", value: value)])
            }
            if has("coloca", "bota", "adiciona", "poe", "põe") {
                let mood = LibraryItem.musicMoods.first { text.contains($0.folding(options: .diacriticInsensitive, locale: nil)) } ?? ""
                return AgentPlan(reply: "Colocando música da biblioteca.", actions: [AgentAction(tool: "music", kind: mood)])
            }
        }
        if has("camera lenta", "camara lenta", "metade da velocidade", "acelera", "mais rapido", "velocidade", "slow") {
            var value: Double? = number(#"(\d+(?:[.,]\d+)?)\s*x\b"#, in: text)
            if value == nil { value = has("metade", "camera lenta", "camara lenta", "slow") ? 0.5 : has("dobro", "acelera", "mais rapido") ? 2 : nil }
            if let value {
                return AgentPlan(reply: value < 1 ? "Câmera lenta aplicada." : "Clipe acelerado.", actions: [AgentAction(tool: "set_speed", clip: clipNumber, track: clipNumber == nil ? "broll" : nil, value: value)])
            }
        }
        if has("saturad", "mais cor", "cores mais vivas") {
            let value = has("menos", "dessatur") ? 0.7 : 1.3
            return AgentPlan(reply: "Saturação ajustada.", actions: [AgentAction(tool: "set_color", clip: clipNumber, track: clipNumber == nil ? "video" : nil, value: value, kind: "saturation")])
        }
        if has("zoom lento", "zoom suave", "aproximando devagar") {
            return AgentPlan(reply: "Zoom lento aplicado.", actions: [AgentAction(tool: "ken_burns", clip: clipNumber, track: clipNumber == nil ? "video" : nil)])
        }
        if has("reenquadr", "reframe", "enquadr") { return AgentPlan(reply: "Reenquadrando.", actions: [AgentAction(tool: "reframe")]) }
        for look in ColorLooks.names where text.contains(look) && has("cor", "visual", "look", "deixa") {
            return AgentPlan(reply: "Aplicando o visual \(look).", actions: [AgentAction(tool: "look", track: "video", kind: look)])
        }
        return nil
    }
}



/// O app e tudo que ele baixa para a IA não passam de 8 GB. Vídeos do usuário não entram nesta conta.
enum AIStorageBudget {
    static let limitBytes: Int64 = 8_000_000_000
    /// Tamanho aproximado do app instalado.
    static let appBytes: Int64 = 300_000_000

    static func used(installedBytes: Int64) -> Int64 { appBytes + installedBytes }

    static func fits(adding bytes: Int64, installedBytes: Int64) -> Bool {
        used(installedBytes: installedBytes) + bytes <= limitBytes
    }

    static func summary(installedBytes: Int64) -> String {
        String(format: "App e IA: %.1f de 8 GB", Double(used(installedBytes: installedBytes)) / 1_000_000_000)
    }
}

/// Se o app fechar sozinho durante a IA, foi falta de memória. Na volta, reduz o contexto ou troca de modelo.
struct ModelCrashGuard {
    var pending: String?
    var crashes: [String: Int] = [:]

    /// Chamado ao abrir o app. Devolve o modelo que derrubou o app na última vez.
    mutating func recover() -> String? {
        guard let model = pending else { return nil }
        pending = nil
        crashes[model, default: 0] += 1
        return model
    }

    func isBlocked(_ id: String) -> Bool { (crashes[id] ?? 0) >= 2 }
    func contextSize(for model: LocalModel) -> Int { (crashes[model.id] ?? 0) >= 1 ? min(4096, model.contextSize) : model.contextSize }
}
