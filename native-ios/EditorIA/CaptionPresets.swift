import Foundation

/// Uma legenda animada descrita só com dados: fonte, cores, como as palavras entram e como a palavra falada se destaca.
/// O mesmo preset move a prévia, a exportação e a galeria.
struct CaptionPreset: Identifiable, Equatable {
    /// `group`: a frase aparece inteira. `spoken`: cada palavra aparece ao ser falada. `single`: uma palavra por vez.
    enum Scope: Equatable { case group, spoken, single }
    enum Entrance: Equatable { case none, fade, pop, slam, bounce, rise, fall, slide, rotate, flip, blur, stretch, type, glitch, swing, zoom }
    enum Active: Equatable { case none, color, scale, box, underline, lift, shake, glow, fill, dim }
    enum Idle: Equatable { case none, wave, float, tremble, pulse }
    enum Shadow: Equatable { case none, soft, hard, glow }

    var id: String
    var name: String
    var category: String
    var font = "Montserrat-Black"
    var upper = false
    var lower = false
    /// Tira vírgula e ponto, como nas legendas virais.
    var clean = false
    var text = "#FFFFFF"
    var highlight = "#FFD84D"
    var stroke: String?
    /// Espessura do contorno, em fração do tamanho da letra.
    var strokeWidth = 0.0
    var shadow = Shadow.soft
    var scope = Scope.group
    var maxWords = 4
    var entrance = Entrance.none
    var active = Active.color
    var idle = Idle.none
    var size = 1.0
    /// Caixa atrás de cada palavra.
    var wordBox: String?
    /// Faixa atrás de cada linha.
    var lineBox: String?
    /// Cor da palavra quando está sobre a caixa de destaque.
    var boxText = "#000000"
    /// Cores que se revezam na palavra falada.
    var cycle: [String] = []
    /// Inclinação máxima de cada palavra, em graus.
    var tilt = 0.0
    /// Palavras fortes ficam maiores e coloridas o tempo todo.
    var keywords = false
    var emoji = false
    /// De cima para baixo, no preenchimento da letra.
    var gradient: [String] = []
    var rgbSplit = false
    var stagger = 0.04

    static let categories = ["Virais", "Karaokê", "Impacto", "Divertidas", "Neon e tech", "Elegantes", "Institucional", "Meus estilos"]

    static func find(_ id: String) -> CaptionPreset? { all.first { $0.id == id } }

    /// Entende o jeito de pedir no chat: "legenda neon", "estilo MrBeast".
    static func match(_ request: String) -> CaptionPreset? {
        let text = request.lowercased()
        if let exact = all.first(where: { text.contains($0.id) || text.contains($0.name.lowercased()) }) { return exact }
        for (word, id) in aliases where text.contains(word) {
            return find(id)
        }
        return nil
    }

    /// Passa o visual para o projeto. As cores continuam editáveis depois.
    func apply(to project: inout EditorProject) {
        project.captionStyle = id
        project.captionTextHex = text
        project.captionHighlightHex = highlight
        project.captionFontStyle = "preset"
        project.captionsEnabled = true
    }

    private static let aliases: [(String, String)] = [
        ("hormozi", "hormozi"), ("mrbeast", "mrbeast"), ("beast", "mrbeast"), ("marca texto", "marca-texto"), ("marca-texto", "marca-texto"),
        ("viral", "hormozi"), ("tiktok", "tiktok-caixa"), ("reels", "reels-pop"), ("emoji", "emoji-viral"),
        ("gigante", "gigante"), ("neon", "neon"), ("glitch", "glitch"), ("retrô", "retro-game"), ("retro", "retro-game"), ("game", "retro-game"),
        ("quadrinho", "quadrinhos"), ("elegante", "elegante"), ("cinema", "cinema"), ("luxo", "luxo"),
        ("institucional", "inst-faixa"), ("prefeitura", "inst-faixa"), ("jornal", "inst-noticia"), ("notícia", "inst-noticia"),
        ("katana", "katana"), ("motion com ia", "motion-ia"), ("dois mundos", "dois-mundos"),
        ("escrever", "maquina"), ("digitando", "maquina"), ("máquina", "maquina"), ("gradiente", "fogo"), ("fogo", "fogo"),
        ("caixa", "box"), ("impacto", "slam"), ("uma palavra", "word"), ("salta", "pop"), ("pula", "pop"), ("aparec", "reveal"), ("simples", "phrase"), ("karaok", "karaoke")
    ]

    static let all: [CaptionPreset] = [
        // Virais
        CaptionPreset(id: "hormozi", name: "Estilo Hormozi", category: "Virais", font: "Anton-Regular", upper: true, clean: true, highlight: "#FFD400", stroke: "#000000", strokeWidth: 0.07, shadow: .hard, maxWords: 3, entrance: .rise, active: .scale, keywords: true),
        CaptionPreset(id: "hormozi-classico", name: "Hormozi clássico", category: "Virais", font: "Montserrat-Black", upper: true, clean: true, highlight: "#39E75F", shadow: .hard, maxWords: 3, entrance: .pop, active: .color, size: 0.92),
        CaptionPreset(id: "mrbeast", name: "Estilo MrBeast", category: "Virais", font: "LuckiestGuy-Regular", upper: true, clean: true, stroke: "#000000", strokeWidth: 0.11, shadow: .hard, scope: .spoken, maxWords: 3, entrance: .pop, active: .scale, size: 1.12, cycle: ["#FFD400", "#3DFF6E", "#FF3B4E", "#35D6FF"], tilt: 3),
        CaptionPreset(id: "podcast", name: "Corte de podcast", category: "Virais", font: "Inter-Black", clean: true, shadow: .soft, maxWords: 5, entrance: .fade, active: .box, size: 0.84),
        CaptionPreset(id: "tiktok-caixa", name: "TikTok caixa preta", category: "Virais", font: "Montserrat-ExtraBold", clean: true, shadow: .none, scope: .spoken, maxWords: 4, entrance: .pop, active: .color, size: 0.82, wordBox: "#000000"),
        CaptionPreset(id: "tiktok-branca", name: "TikTok caixa branca", category: "Virais", font: "Montserrat-ExtraBold", clean: true, text: "#000000", highlight: "#E4183C", shadow: .none, scope: .spoken, maxWords: 4, entrance: .pop, active: .color, size: 0.82, wordBox: "#FFFFFF"),
        CaptionPreset(id: "reels-pop", name: "Reels pop", category: "Virais", font: "Poppins-Black", clean: true, highlight: "#FF4FA3", stroke: "#000000", strokeWidth: 0.05, scope: .spoken, maxWords: 3, entrance: .pop, active: .scale),
        CaptionPreset(id: "verde-viral", name: "Caixa verde", category: "Virais", font: "Poppins-Black", upper: true, clean: true, highlight: "#22E55B", shadow: .soft, maxWords: 3, entrance: .pop, active: .box, size: 0.9),
        CaptionPreset(id: "roxo-viral", name: "Caixa roxa", category: "Virais", font: "Poppins-Black", upper: true, clean: true, highlight: "#8B5CFF", shadow: .soft, maxWords: 3, entrance: .pop, active: .box, size: 0.9, boxText: "#FFFFFF"),
        CaptionPreset(id: "marca-texto", name: "Marca-texto", category: "Virais", font: "Montserrat-Black", clean: true, highlight: "#FFEB3B", shadow: .soft, maxWords: 4, entrance: .fade, active: .box, size: 0.86),
        CaptionPreset(id: "emoji-viral", name: "Com emoji", category: "Virais", font: "Poppins-Black", upper: true, clean: true, highlight: "#FFD400", stroke: "#000000", strokeWidth: 0.06, scope: .spoken, maxWords: 3, entrance: .pop, active: .color, keywords: true, emoji: true),
        CaptionPreset(id: "palavra-forte", name: "Palavra forte", category: "Virais", font: "Oswald-Bold", upper: true, clean: true, highlight: "#FF5A1F", stroke: "#000000", strokeWidth: 0.05, shadow: .hard, maxWords: 4, entrance: .rise, active: .none, keywords: true),
        CaptionPreset(id: "foco", name: "Foco na palavra", category: "Virais", font: "Inter-Black", clean: true, highlight: "#FFFFFF", maxWords: 5, entrance: .fade, active: .dim, size: 0.9),
        CaptionPreset(id: "sublinhado", name: "Sublinhado", category: "Virais", font: "Montserrat-ExtraBold", clean: true, highlight: "#FFD400", maxWords: 4, entrance: .rise, active: .underline, size: 0.88),

        // Karaokê
        CaptionPreset(id: "karaoke", name: "Karaokê", category: "Karaokê", font: "Montserrat-Black", maxWords: 4),
        CaptionPreset(id: "karaoke-fill", name: "Preenchendo", category: "Karaokê", font: "Anton-Regular", upper: true, clean: true, highlight: "#FFD400", stroke: "#000000", strokeWidth: 0.05, maxWords: 4, active: .fill),
        CaptionPreset(id: "karaoke-azul", name: "Preenchendo azul", category: "Karaokê", font: "Poppins-Black", clean: true, highlight: "#35D6FF", stroke: "#001A33", strokeWidth: 0.06, maxWords: 4, active: .fill, size: 0.88),
        CaptionPreset(id: "box", name: "Caixa na palavra", category: "Karaokê", font: "Montserrat-Black", maxWords: 4, active: .box),
        CaptionPreset(id: "reveal", name: "Aparece ao falar", category: "Karaokê", font: "Montserrat-Black", scope: .spoken, maxWords: 6, entrance: .rise),
        CaptionPreset(id: "phrase", name: "Frase simples", category: "Karaokê", font: "Inter-Black", maxWords: 7, entrance: .fade, active: .none, size: 0.82),
        CaptionPreset(id: "onda", name: "Onda", category: "Karaokê", font: "Fredoka-Bold", clean: true, highlight: "#FFD84D", stroke: "#000000", strokeWidth: 0.05, maxWords: 4, active: .lift, idle: .wave),
        CaptionPreset(id: "balanco", name: "Balanço", category: "Karaokê", font: "Fredoka-Bold", clean: true, highlight: "#FF7AB6", scope: .spoken, maxWords: 4, entrance: .swing, active: .color),

        // Impacto
        CaptionPreset(id: "slam", name: "Impacto, uma palavra", category: "Impacto", font: "Anton-Regular", upper: true, clean: true, stroke: "#000000", strokeWidth: 0.04, scope: .single, entrance: .slam, active: .color, size: 1.5),
        CaptionPreset(id: "word", name: "Uma palavra", category: "Impacto", font: "Montserrat-Black", clean: true, scope: .single, entrance: .pop, active: .none, size: 1.2),
        CaptionPreset(id: "pop", name: "Palavra salta", category: "Impacto", font: "Montserrat-Black", maxWords: 4, active: .scale),
        CaptionPreset(id: "gigante", name: "Gigante", category: "Impacto", font: "Anton-Regular", upper: true, clean: true, highlight: "#FFFFFF", scope: .single, entrance: .slam, active: .none, size: 2.1),
        CaptionPreset(id: "corte-seco", name: "Corte seco", category: "Impacto", font: "BarlowCondensed-Black", upper: true, clean: true, scope: .single, active: .none, size: 1.7),
        CaptionPreset(id: "tremor", name: "Tremor", category: "Impacto", font: "ArchivoBlack-Regular", upper: true, clean: true, highlight: "#FF3B30", stroke: "#000000", strokeWidth: 0.05, scope: .single, entrance: .slam, active: .shake, idle: .tremble, size: 1.3),
        CaptionPreset(id: "sombra-dura", name: "Sombra dura", category: "Impacto", font: "ArchivoBlack-Regular", upper: true, clean: true, highlight: "#FFD400", shadow: .hard, maxWords: 3, entrance: .zoom, active: .color),
        CaptionPreset(id: "fogo", name: "Fogo", category: "Impacto", font: "Anton-Regular", upper: true, clean: true, highlight: "#FFFFFF", stroke: "#2A0A00", strokeWidth: 0.05, scope: .spoken, maxWords: 3, entrance: .pop, active: .none, size: 1.1, gradient: ["#FFE14D", "#FF3D00"]),
        CaptionPreset(id: "militar", name: "Carimbo", category: "Impacto", font: "BlackOpsOne-Regular", upper: true, clean: true, highlight: "#FFB000", maxWords: 3, entrance: .slam, active: .color, size: 0.9, tilt: 2),
        CaptionPreset(id: "giro", name: "Giro", category: "Impacto", font: "RussoOne-Regular", upper: true, clean: true, highlight: "#35D6FF", stroke: "#000000", strokeWidth: 0.05, scope: .spoken, maxWords: 3, entrance: .rotate, active: .color),
        CaptionPreset(id: "esticado", name: "Esticado", category: "Impacto", font: "BebasNeue-Regular", upper: true, clean: true, highlight: "#FFD400", stroke: "#000000", strokeWidth: 0.04, scope: .spoken, maxWords: 3, entrance: .stretch, active: .color, size: 1.2),

        // Divertidas
        CaptionPreset(id: "quadrinhos", name: "Quadrinhos", category: "Divertidas", font: "Bangers-Regular", upper: true, clean: true, text: "#FFEB3B", highlight: "#FF3B30", stroke: "#000000", strokeWidth: 0.09, shadow: .hard, scope: .spoken, maxWords: 3, entrance: .pop, active: .scale, size: 1.15, tilt: 4),
        CaptionPreset(id: "desenho", name: "Desenho animado", category: "Divertidas", font: "LilitaOne", clean: true, highlight: "#FFD84D", stroke: "#3A1D00", strokeWidth: 0.09, shadow: .hard, scope: .spoken, maxWords: 3, entrance: .bounce, active: .scale, tilt: 2.5),
        CaptionPreset(id: "bolha", name: "Bolha", category: "Divertidas", font: "TitanOne", clean: true, text: "#FFFFFF", highlight: "#FF7AB6", stroke: "#7A1FA2", strokeWidth: 0.08, scope: .spoken, maxWords: 3, entrance: .bounce, active: .lift, idle: .float),
        CaptionPreset(id: "caneta", name: "Caneta", category: "Divertidas", font: "PermanentMarker-Regular", clean: true, highlight: "#FFD84D", scope: .spoken, maxWords: 4, entrance: .fade, active: .color, tilt: 2),
        CaptionPreset(id: "caderno", name: "Caderno", category: "Divertidas", font: "Caveat-Bold", clean: true, highlight: "#FFD84D", maxWords: 5, entrance: .fade, active: .underline, size: 1.15),
        CaptionPreset(id: "recadinho", name: "Recadinho", category: "Divertidas", font: "Kalam-Bold", clean: true, text: "#222222", highlight: "#E4183C", shadow: .none, scope: .spoken, maxWords: 3, entrance: .pop, active: .color, size: 0.9, wordBox: "#FFF59D", tilt: 2.5),
        CaptionPreset(id: "praia", name: "Verão", category: "Divertidas", font: "Pacifico-Regular", clean: true, highlight: "#FFD84D", maxWords: 4, entrance: .rise, active: .color),

        // Neon e tech
        CaptionPreset(id: "neon", name: "Neon", category: "Neon e tech", font: "Righteous-Regular", clean: true, text: "#FFFFFF", highlight: "#00F0FF", shadow: .glow, scope: .spoken, maxWords: 4, entrance: .fade, active: .glow),
        CaptionPreset(id: "neon-rosa", name: "Neon rosa", category: "Neon e tech", font: "Righteous-Regular", upper: true, clean: true, text: "#FFD9EE", highlight: "#FF2BD6", shadow: .glow, maxWords: 3, entrance: .blur, active: .glow),
        CaptionPreset(id: "glitch", name: "Glitch", category: "Neon e tech", font: "SpaceGrotesk-Bold", upper: true, clean: true, highlight: "#00F0FF", scope: .spoken, maxWords: 3, entrance: .glitch, active: .color, rgbSplit: true),
        CaptionPreset(id: "maquina", name: "Digitando", category: "Neon e tech", font: "SpaceGrotesk-Bold", highlight: "#39FF88", shadow: .none, scope: .spoken, maxWords: 5, entrance: .type, active: .color, size: 0.86, lineBox: "#000000CC"),
        CaptionPreset(id: "retro-game", name: "Videogame", category: "Neon e tech", font: "PressStart2P-Regular", upper: true, clean: true, text: "#FFFFFF", highlight: "#FFD400", stroke: "#000000", strokeWidth: 0.08, shadow: .hard, scope: .spoken, maxWords: 2, entrance: .none, active: .color, size: 0.56),
        CaptionPreset(id: "bloco", name: "Blocos", category: "Neon e tech", font: "RubikMonoOne-Regular", upper: true, clean: true, highlight: "#8BFF3A", maxWords: 2, entrance: .flip, active: .color, size: 0.72),
        CaptionPreset(id: "placar", name: "Placar", category: "Neon e tech", font: "Bungee-Regular", upper: true, clean: true, highlight: "#FF5A1F", scope: .spoken, maxWords: 3, entrance: .flip, active: .color, size: 0.82, wordBox: "#111111"),

        // Elegantes
        CaptionPreset(id: "elegante", name: "Elegante", category: "Elegantes", font: "InstrumentSerif-Italic", highlight: "#FFE9A8", scope: .spoken, maxWords: 6, entrance: .blur, active: .none, size: 1.2),
        CaptionPreset(id: "cinema", name: "Cinema", category: "Elegantes", font: "DMSerifDisplay-Regular", highlight: "#FFFFFF", maxWords: 7, entrance: .fade, active: .none, size: 0.9),
        CaptionPreset(id: "luxo", name: "Luxo", category: "Elegantes", font: "PlayfairDisplay-BlackItalic", text: "#FFFFFF", highlight: "#E5C07B", scope: .spoken, maxWords: 4, entrance: .blur, active: .color, gradient: []),
        CaptionPreset(id: "ouro", name: "Ouro", category: "Elegantes", font: "PlayfairDisplay-BlackItalic", highlight: "#FFF4C2", scope: .group, maxWords: 4, entrance: .fade, active: .none, gradient: ["#FFF0B3", "#B8862B"]),
        CaptionPreset(id: "minimalista", name: "Minimalista", category: "Elegantes", font: "Inter-Black", lower: true, clean: true, shadow: .soft, maxWords: 5, entrance: .fade, active: .dim, size: 0.72),
        CaptionPreset(id: "editorial", name: "Editorial", category: "Elegantes", font: "Sora-Bold", highlight: "#FFD84D", maxWords: 5, entrance: .rise, active: .color, size: 0.8),

        // Institucional
        CaptionPreset(id: "inst-limpa", name: "Limpa", category: "Institucional", font: "Montserrat-ExtraBold", shadow: .soft, maxWords: 6, entrance: .fade, active: .none, size: 0.76),
        CaptionPreset(id: "inst-faixa", name: "Faixa escura", category: "Institucional", font: "Montserrat-ExtraBold", highlight: "#FFD84D", shadow: .none, maxWords: 6, entrance: .fade, active: .color, size: 0.72, lineBox: "#000000B3"),
        CaptionPreset(id: "inst-cor", name: "Cor do cliente", category: "Institucional", font: "Poppins-Bold", highlight: "#0B6E4F", maxWords: 5, entrance: .fade, active: .box, size: 0.76, boxText: "#FFFFFF"),
        CaptionPreset(id: "inst-noticia", name: "Noticiário", category: "Institucional", font: "Oswald-Bold", upper: true, highlight: "#FFD84D", shadow: .none, maxWords: 6, entrance: .rise, active: .none, size: 0.8, lineBox: "#0A2A5CE6"),
        CaptionPreset(id: "inst-sublinhado", name: "Sublinhado discreto", category: "Institucional", font: "Montserrat-ExtraBold", highlight: "#FFD84D", maxWords: 6, entrance: .fade, active: .underline, size: 0.74),

        // Meus estilos
        CaptionPreset(id: "katana", name: "Katana", category: "Meus estilos", font: "ArchivoBlack-Regular", upper: true, clean: true, text: "#EAF6FF", highlight: "#E4183C", shadow: .none, scope: .single, entrance: .slam, active: .color, size: 1.45),
        CaptionPreset(id: "motion-ia", name: "Motion com IA", category: "Meus estilos", font: "Anton-Regular", upper: true, clean: true, highlight: "#C6FF34", scope: .spoken, maxWords: 3, entrance: .rise, active: .underline, size: 1.1),
        CaptionPreset(id: "dois-mundos", name: "Dois mundos", category: "Meus estilos", font: "InstrumentSerif-Italic", clean: true, highlight: "#FFD84D", scope: .spoken, maxWords: 4, entrance: .rise, active: .color, size: 1.25)
    ]
}

/// Palavras que merecem destaque e emoji, em português.
enum CaptionWords {
    private static let weak: Set<String> = ["porque", "quando", "depois", "também", "ainda", "sempre", "muito", "muita", "muitos", "muitas", "aquele", "aquela", "estamos", "estava", "foram", "nosso", "nossa", "nossos", "nossas", "outros", "outras", "então", "agora", "pessoas", "gente", "sobre", "entre", "desde", "tinha", "tenho", "fazer", "vamos", "isso", "essa", "esse"]

    private static let emojis: [(String, String)] = [
        ("asfalt", "🛣️"), ("estrada", "🛣️"), ("rua", "🛣️"), ("obra", "🏗️"), ("constru", "🏗️"), ("saúde", "🏥"), ("hospital", "🏥"), ("médic", "🩺"),
        ("escola", "🏫"), ("educa", "📚"), ("aluno", "🎒"), ("criança", "👧"), ("família", "👨‍👩‍👧"), ("água", "💧"), ("rio", "🌊"), ("energia", "⚡️"), ("luz", "💡"),
        ("dinheiro", "💰"), ("real", "💰"), ("reais", "💰"), ("milh", "💰"), ("emprego", "💼"), ("trabalh", "💪"), ("força", "💪"), ("obrigad", "🙏"), ("deus", "🙏"),
        ("amor", "❤️"), ("coração", "❤️"), ("feliz", "😄"), ("alegria", "😄"), ("festa", "🎉"), ("parabéns", "🎉"), ("música", "🎵"), ("segur", "🛡️"), ("polícia", "🚓"),
        ("carro", "🚗"), ("ônibus", "🚌"), ("casa", "🏠"), ("morad", "🏠"), ("cidade", "🏙️"), ("sol", "☀️"), ("árvore", "🌳"), ("verde", "🌳"), ("meio ambiente", "🌳"),
        ("novo", "✨"), ("nova", "✨"), ("melhor", "🚀"), ("cresc", "📈"), ("hoje", "📅"), ("tempo", "⏰"), ("atenção", "⚠️"), ("cuidado", "⚠️"), ("segredo", "🤫")
    ]

    static func isKeyword(_ raw: String) -> Bool {
        let word = cleaned(raw).lowercased()
        if word.contains(where: \.isNumber) { return true }
        return word.count >= 6 && !weak.contains(word)
    }

    static func emoji(for raw: String) -> String? {
        let word = cleaned(raw).lowercased()
        guard word.count >= 3 else { return nil }
        return emojis.first { word.hasPrefix($0.0) }?.1
    }

    static func cleaned(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }
}

enum CaptionAnimator {
    struct WordVisual: Equatable {
        var text: String
        var state: LayerState
        var isActive = false
        var hasBox = false
        /// Cor própria, quando as cores se revezam.
        var color: String?
        var isKeyword = false
        var isEmoji = false
        /// Quanto da palavra já foi preenchido com a cor de destaque (nil = sem preenchimento).
        var fill: Double?
        var underline = false
        var glow = false
        var split = 0.0
    }

    struct Frame: Equatable {
        var preset: CaptionPreset
        var words: [WordVisual]
        var sizeFactor: Double
    }

    static var styles: [(id: String, name: String)] { CaptionPreset.all.map { ($0.id, $0.name) } }

    static func frame(style: String, words: [CaptionWord], at time: Double) -> Frame? {
        let preset = CaptionPreset.find(style) ?? CaptionPreset.all.first { $0.id == "karaoke" }!
        guard !words.isEmpty else { return nil }
        if preset.scope == .single {
            // Mantém a palavra em pausas curtas, para a legenda não piscar.
            guard let index = words.lastIndex(where: { $0.start <= time }) else { return nil }
            let word = words[index]
            let limit = word.start + word.duration + 0.25
            let next = index + 1 < words.count ? words[index + 1].start : limit
            guard time < min(limit, next) else { return nil }
            return Frame(preset: preset, words: visuals(preset: preset, words: words, indices: index..<(index + 1), active: index, time: time), sizeFactor: preset.size)
        }
        for group in CaptionLayout.groups(words, maximumWords: preset.maxWords) {
            let first = words[group.lowerBound], last = words[group.upperBound - 1]
            guard time >= first.start, time < last.start + last.duration else { continue }
            let active = group.last { words[$0].start <= time } ?? group.lowerBound
            return Frame(preset: preset, words: visuals(preset: preset, words: words, indices: group, active: active, time: time), sizeFactor: preset.size)
        }
        return nil
    }

    private static func visuals(preset: CaptionPreset, words: [CaptionWord], indices: Range<Int>, active: Int, time: Double) -> [WordVisual] {
        var result: [WordVisual] = []
        let groupStart = words[indices.lowerBound].start
        for index in indices {
            let word = words[index]
            let position = index - indices.lowerBound
            let isActive = index == active
            let anchor = preset.scope == .group ? groupStart + Double(position) * preset.stagger : word.start
            var state = entrance(preset.entrance, local: time - anchor, seed: index)
            if preset.scope == .spoken, time < word.start { state.opacity = 0 }
            state.rotation += preset.tilt * signedNoise(index)
            applyIdle(preset.idle, state: &state, time: time, position: position, seed: index)

            var visual = WordVisual(text: display(word.text, preset: preset), state: state)
            visual.isKeyword = preset.keywords && CaptionWords.isKeyword(word.text)
            if preset.entrance == .glitch, preset.rgbSplit { visual.split = time - anchor < 0.22 ? 1 : 0.35 }
            if preset.entrance == .type, isActive {
                let visible = Int((Easing.clamp((time - word.start) / max(0.05, min(word.duration, 0.3))) * Double(visual.text.count)).rounded(.up))
                visual.text = String(visual.text.prefix(max(1, visible)))
            }

            let local = time - word.start
            let progress = Easing.clamp(local / 0.14)
            switch preset.active {
            case .none:
                break
            case .color:
                visual.isActive = isActive
            case .scale:
                visual.isActive = isActive
                if isActive { visual.state.scale *= 1 + 0.22 * Easing.outBack(progress) }
            case .box:
                visual.isActive = isActive
                visual.hasBox = isActive
            case .underline:
                visual.isActive = isActive
                visual.underline = isActive
            case .lift:
                visual.isActive = isActive
                if isActive { visual.state.offsetY -= 0.009 * Easing.outBack(progress) }
            case .shake:
                visual.isActive = isActive
                if isActive { visual.state.offsetX += sin(local * 70) * 0.004 * max(0, 1 - local / 0.3) }
            case .glow:
                visual.isActive = isActive
                visual.glow = isActive
            case .fill:
                visual.fill = time >= word.start + word.duration ? 1 : (local <= 0 ? 0 : local / max(0.05, word.duration))
            case .dim:
                visual.isActive = isActive
                if !isActive { visual.state.opacity *= 0.42 }
            }
            if isActive, !preset.cycle.isEmpty {
                visual.color = preset.cycle[index % preset.cycle.count]
            }
            result.append(visual)

            if preset.emoji, time >= word.start, let emoji = CaptionWords.emoji(for: word.text) {
                var mark = WordVisual(text: emoji, state: entrance(.pop, local: time - word.start, seed: index))
                mark.isEmoji = true
                result.append(mark)
            }
        }
        return result
    }

    private static func display(_ raw: String, preset: CaptionPreset) -> String {
        var text = preset.clean ? CaptionWords.cleaned(raw) : raw
        if text.isEmpty { text = raw }
        if preset.upper { text = text.uppercased() }
        if preset.lower { text = text.lowercased() }
        return text
    }

    private static func entrance(_ kind: CaptionPreset.Entrance, local: Double, seed: Int) -> LayerState {
        var state = LayerState()
        guard local >= 0 else {
            if kind != .none { state.opacity = 0 }
            return state
        }
        switch kind {
        case .none, .type:
            break
        case .fade:
            state.opacity = Easing.clamp(local / 0.14)
        case .pop:
            let p = Easing.clamp(local / 0.16)
            state.scale = 0.72 + 0.28 * Easing.outBack(p)
            state.opacity = Easing.clamp(p * 3)
        case .slam:
            let p = Easing.clamp(local / 0.12)
            state.scale = 1.9 - 0.9 * Easing.outCubic(p)
            state.opacity = Easing.clamp(p * 3)
        case .bounce:
            state.offsetY = 0.035 * (1 - Easing.outBounce(local / 0.42))
            state.opacity = Easing.clamp(local / 0.08)
        case .rise:
            let p = Easing.clamp(local / 0.16)
            state.offsetY = 0.016 * (1 - Easing.outCubic(p))
            state.opacity = p
        case .fall:
            let p = Easing.clamp(local / 0.2)
            state.offsetY = -0.03 * (1 - Easing.outBack(p))
            state.opacity = Easing.clamp(p * 3)
        case .slide:
            let p = Easing.clamp(local / 0.2)
            state.offsetX = 0.05 * (1 - Easing.outCubic(p))
            state.opacity = p
        case .rotate:
            let p = Easing.clamp(local / 0.24)
            state.rotation = -16 * (1 - Easing.outBack(p))
            state.scale = 0.84 + 0.16 * Easing.outCubic(p)
            state.opacity = Easing.clamp(p * 3)
        case .flip:
            let p = Easing.clamp(local / 0.2)
            state.scaleY = max(0.02, Easing.outBack(p))
            state.opacity = Easing.clamp(p * 4)
        case .blur:
            let p = Easing.clamp(local / 0.28)
            state.blur = 14 * (1 - Easing.outCubic(p))
            state.opacity = p
        case .stretch:
            let p = Easing.clamp(local / 0.2)
            state.scaleY = 1.7 - 0.7 * Easing.outBack(p)
            state.scale = 0.82 + 0.18 * Easing.outCubic(p)
            state.opacity = Easing.clamp(p * 4)
        case .glitch:
            guard local < 0.22 else { break }
            let beat = Int(local * 30)
            state.offsetX = signedNoise(seed &* 31 &+ beat) * 0.012
            state.offsetY = signedNoise(seed &* 17 &+ beat) * 0.004
            state.opacity = beat % 3 == 1 ? 0.35 : 1
        case .swing:
            state.rotation = 20 * exp(-6 * local) * cos(15 * local)
            state.opacity = Easing.clamp(local / 0.08)
        case .zoom:
            let p = Easing.clamp(local / 0.18)
            state.scale = 0.25 + 0.75 * Easing.outBack(p)
            state.opacity = Easing.clamp(p * 3)
        }
        return state
    }

    private static func applyIdle(_ idle: CaptionPreset.Idle, state: inout LayerState, time: Double, position: Int, seed: Int) {
        switch idle {
        case .none:
            break
        case .wave:
            state.offsetY += sin(time * 5 + Double(position) * 0.9) * 0.004
        case .float:
            state.offsetY += sin(time * 2.4) * 0.004
        case .tremble:
            let beat = Int(time * 15)
            state.offsetX += signedNoise(seed &* 13 &+ beat) * 0.002
            state.offsetY += signedNoise(seed &* 7 &+ beat) * 0.0015
        case .pulse:
            state.scale *= 1 + 0.03 * sin(time * 6)
        }
    }

    /// Valor de -1 a 1 que depende só da semente, para o mesmo quadro sair sempre igual.
    private static func signedNoise(_ seed: Int) -> Double {
        var value = UInt32(truncatingIfNeeded: seed &* 2654435761 &+ 1013904223)
        value ^= value >> 15
        value = value &* 2246822519
        value ^= value >> 13
        return Double(value % 2000) / 1000 - 1
    }
}
