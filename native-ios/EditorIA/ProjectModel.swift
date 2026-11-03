import Foundation

// Modelo do projeto. Usa somente Foundation para poder ser testado fora do iOS.

struct TranscriptWord: Codable, Hashable {
    var text: String
    var start: Double
    var end: Double
}

struct LocalMedia: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var relativePath: String
    var kind: String
    var byteCount: Int64
    var importOrder: Int
    var duration: Double?
    /// Marcado pelo usuário: este arquivo contém uma fala (sonora) que deve ser preservada.
    var isSonora: Bool = false
    /// Gerado pelo app (máscaras e recortes). Não é material de origem do Diretor IA.
    var isDerived: Bool = false
    /// Trechos com fala detectados no arquivo, em segundos da mídia original.
    var speechRanges: [AudioDuckingRange] = []
    /// Resumo da análise de som, ex.: "fala 72% · música 10%".
    var soundSummary: String?
    /// Batidas detectadas em músicas, em segundos.
    var beats: [Double] = []
    /// Fala transcrita em segundos da mídia original. As legendas da timeline são calculadas a partir daqui,
    /// então continuam certas depois de cortes, trocas de lugar e mudanças de velocidade.
    var transcript: [TranscriptWord] = []
    /// O que aparece nas imagens, detectado no aparelho.
    var visualTags: [String] = []
    /// Fração das amostras em que há rosto visível.
    var faceShare: Double?
    var soundAnalyzed = false

    enum CodingKeys: String, CodingKey { case id, name, relativePath, kind, byteCount, importOrder, duration, isSonora, isDerived, speechRanges, soundSummary, beats, transcript, visualTags, faceShare, soundAnalyzed }

    init(id: UUID = UUID(), name: String, relativePath: String, kind: String, byteCount: Int64, importOrder: Int, duration: Double?, isSonora: Bool = false, isDerived: Bool = false, beats: [Double] = []) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
        self.byteCount = byteCount
        self.importOrder = importOrder
        self.duration = duration
        self.isSonora = isSonora
        self.isDerived = isDerived
        self.beats = beats
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        relativePath = try values.decode(String.self, forKey: .relativePath)
        kind = try values.decode(String.self, forKey: .kind)
        byteCount = try values.decodeIfPresent(Int64.self, forKey: .byteCount) ?? 0
        importOrder = try values.decodeIfPresent(Int.self, forKey: .importOrder) ?? 0
        duration = try values.decodeIfPresent(Double.self, forKey: .duration)
        isSonora = try values.decodeIfPresent(Bool.self, forKey: .isSonora) ?? false
        isDerived = try values.decodeIfPresent(Bool.self, forKey: .isDerived) ?? false
        speechRanges = try values.decodeIfPresent([AudioDuckingRange].self, forKey: .speechRanges) ?? []
        soundSummary = try values.decodeIfPresent(String.self, forKey: .soundSummary)
        beats = try values.decodeIfPresent([Double].self, forKey: .beats) ?? []
        transcript = try values.decodeIfPresent([TranscriptWord].self, forKey: .transcript) ?? []
        visualTags = try values.decodeIfPresent([String].self, forKey: .visualTags) ?? []
        faceShare = try values.decodeIfPresent(Double.self, forKey: .faceShare)
        soundAnalyzed = try values.decodeIfPresent(Bool.self, forKey: .soundAnalyzed) ?? false
    }
}

struct ClipKeyframe: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var property: String
    var time: Double
    var value: Double
    var interpolation: String = "linear"
}

/// Aparência e comportamento do clipe. Todos os valores neutros deixam o clipe como veio da câmera.
struct ClipLook: Codable, Hashable {
    var speed: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
    var scale: Double = 1
    var rotation: Double = 0
    var exposure: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var temperature: Double = 6500
    var tint: Double = 0
    var shadows: Double = 0
    var highlights: Double = 1
    var lutRelativePath: String?
    var lutIntensity: Double = 1
    var chromaHex: String?
    var chromaTolerance: Double = 0.18
    var transitionKind: String?
    var transitionDuration: Double = 0
    var kenBurns: Bool = false

    enum CodingKeys: String, CodingKey {
        case speed, offsetX, offsetY, scale, rotation, exposure, contrast, saturation, temperature, tint, shadows, highlights
        case lutRelativePath, lutIntensity, chromaHex, chromaTolerance, transitionKind, transitionDuration, kenBurns
    }

    init() {}

    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        speed = try v.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        offsetX = try v.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try v.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
        scale = try v.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        rotation = try v.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        exposure = try v.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try v.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try v.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        temperature = try v.decodeIfPresent(Double.self, forKey: .temperature) ?? 6500
        tint = try v.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        shadows = try v.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        highlights = try v.decodeIfPresent(Double.self, forKey: .highlights) ?? 1
        lutRelativePath = try v.decodeIfPresent(String.self, forKey: .lutRelativePath)
        lutIntensity = try v.decodeIfPresent(Double.self, forKey: .lutIntensity) ?? 1
        chromaHex = try v.decodeIfPresent(String.self, forKey: .chromaHex)
        chromaTolerance = try v.decodeIfPresent(Double.self, forKey: .chromaTolerance) ?? 0.18
        transitionKind = try v.decodeIfPresent(String.self, forKey: .transitionKind)
        transitionDuration = try v.decodeIfPresent(Double.self, forKey: .transitionDuration) ?? 0
        kenBurns = try v.decodeIfPresent(Bool.self, forKey: .kenBurns) ?? false
    }

    var hasColorChanges: Bool {
        exposure != 0 || contrast != 1 || saturation != 1 || temperature != 6500 || tint != 0 || shadows != 0 || highlights != 1 || lutRelativePath != nil
    }
}

struct TimelineClip: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var mediaID: UUID
    var track: String
    var start: Double
    var duration: Double
    var sourceIn: Double = 0
    var volume: Double = 1
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var keyframes: [ClipKeyframe] = []
    var label: String
    var look: ClipLook = ClipLook()

    var end: Double { start + duration }

    enum CodingKeys: String, CodingKey { case id, mediaID, track, start, duration, sourceIn, volume, fadeIn, fadeOut, keyframes, label, look }

    init(id: UUID = UUID(), mediaID: UUID, track: String, start: Double, duration: Double, sourceIn: Double = 0, volume: Double = 1, fadeIn: Double = 0, fadeOut: Double = 0, keyframes: [ClipKeyframe] = [], label: String, look: ClipLook = ClipLook()) {
        self.id = id
        self.mediaID = mediaID
        self.track = track
        self.start = start
        self.duration = duration
        self.sourceIn = sourceIn
        self.volume = volume
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.keyframes = keyframes
        self.label = label
        self.look = look
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mediaID = try values.decode(UUID.self, forKey: .mediaID)
        track = try values.decode(String.self, forKey: .track)
        start = try values.decode(Double.self, forKey: .start)
        duration = try values.decode(Double.self, forKey: .duration)
        sourceIn = try values.decodeIfPresent(Double.self, forKey: .sourceIn) ?? 0
        volume = try values.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        fadeIn = try values.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 0
        fadeOut = try values.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 0
        keyframes = try values.decodeIfPresent([ClipKeyframe].self, forKey: .keyframes) ?? []
        label = try values.decode(String.self, forKey: .label)
        look = try values.decodeIfPresent(ClipLook.self, forKey: .look) ?? ClipLook()
    }
}

struct TextOverlay: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var start: Double
    var duration: Double
    var fontSize: Double = 64
    var colorHex: String = "#FFFFFF"
    var backgroundHex: String = "#00000000"
    var horizontalPosition: Double = 0.5
    var verticalPosition: Double = 0.78
    var scale: Double = 1.0
    var rotationDegrees: Double = 0
    var outlineHex: String = "#000000"
    var outlineWidth: Double = 0
    var animation: String = "fade"
    var wordAnimation: String = "none"
    var fontStyle: String = "heavy"

    enum CodingKeys: String, CodingKey {
        case id, text, start, duration, fontSize, colorHex, backgroundHex
        case horizontalPosition, verticalPosition, scale, rotationDegrees
        case outlineHex, outlineWidth, animation, wordAnimation, fontStyle
    }

    init(id: UUID = UUID(), text: String, start: Double, duration: Double,
         fontSize: Double = 64, colorHex: String = "#FFFFFF", backgroundHex: String = "#00000000",
         horizontalPosition: Double = 0.5, verticalPosition: Double = 0.78,
         scale: Double = 1.0, rotationDegrees: Double = 0,
         outlineHex: String = "#000000", outlineWidth: Double = 0, animation: String = "fade", wordAnimation: String = "none", fontStyle: String = "heavy") {
        self.id = id
        self.text = text
        self.start = start
        self.duration = duration
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.backgroundHex = backgroundHex
        self.horizontalPosition = horizontalPosition
        self.verticalPosition = verticalPosition
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.outlineHex = outlineHex
        self.outlineWidth = outlineWidth
        self.animation = animation
        self.wordAnimation = wordAnimation
        self.fontStyle = fontStyle
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try values.decode(String.self, forKey: .text)
        start = try values.decode(Double.self, forKey: .start)
        duration = try values.decode(Double.self, forKey: .duration)
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 64
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex) ?? "#FFFFFF"
        backgroundHex = try values.decodeIfPresent(String.self, forKey: .backgroundHex) ?? "#00000000"
        horizontalPosition = try values.decodeIfPresent(Double.self, forKey: .horizontalPosition) ?? 0.5
        verticalPosition = try values.decodeIfPresent(Double.self, forKey: .verticalPosition) ?? 0.78
        scale = try values.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        rotationDegrees = try values.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        outlineHex = try values.decodeIfPresent(String.self, forKey: .outlineHex) ?? "#000000"
        outlineWidth = try values.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? 0
        animation = try values.decodeIfPresent(String.self, forKey: .animation) ?? "fade"
        wordAnimation = try values.decodeIfPresent(String.self, forKey: .wordAnimation) ?? "none"
        fontStyle = try values.decodeIfPresent(String.self, forKey: .fontStyle) ?? "heavy"
    }
}

struct CaptionWord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var start: Double
    var duration: Double
    var fontSize: Double = 58
    var colorHex: String = "#FFFFFF"
    var verticalPosition: Double = 0.84
    var animation: String = "pop"
}

struct EditorProject: Codable {
    var id: UUID = UUID()
    var schemaVersion: Int = 9
    var clientID: UUID?
    var captionStyle: String = "karaoke"
    var captionHighlightHex: String = "#FFD84D"
    var captionTextHex: String = "#FFFFFF"
    var captionFontSize: Double = 88
    var captionFontStyle: String = "preset"
    /// Altura da legenda (0 = topo, 1 = base). Sem valor, usa a posição segura da proporção.
    var captionVertical: Double?
    /// Falso quando o usuário apaga as legendas; a transcrição continua guardada.
    var captionsEnabled: Bool = true
    var name: String = "Projeto sem título"
    var profile: String = "Institucional"
    var media: [LocalMedia] = []
    var clips: [TimelineClip] = []
    var overlays: [TextOverlay] = []
    var captionWords: [CaptionWord] = []
    var automaticDucking: Bool = true
    var duckingLevel: Double = 0.24
    var updatedAt: Date = .now

    enum CodingKeys: String, CodingKey { case id, schemaVersion, clientID, captionStyle, captionHighlightHex, captionTextHex, captionFontSize, captionFontStyle, captionVertical, captionsEnabled, name, profile, media, clips, overlays, captionWords, automaticDucking, duckingLevel, updatedAt }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        clientID = try values.decodeIfPresent(UUID.self, forKey: .clientID)
        captionStyle = try values.decodeIfPresent(String.self, forKey: .captionStyle) ?? "karaoke"
        captionHighlightHex = try values.decodeIfPresent(String.self, forKey: .captionHighlightHex) ?? "#FFD84D"
        captionTextHex = try values.decodeIfPresent(String.self, forKey: .captionTextHex) ?? "#FFFFFF"
        captionFontSize = try values.decodeIfPresent(Double.self, forKey: .captionFontSize) ?? 78
        captionFontStyle = try values.decodeIfPresent(String.self, forKey: .captionFontStyle) ?? "preset"
        captionVertical = try values.decodeIfPresent(Double.self, forKey: .captionVertical)
        captionsEnabled = try values.decodeIfPresent(Bool.self, forKey: .captionsEnabled) ?? true
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Projeto sem título"
        profile = try values.decodeIfPresent(String.self, forKey: .profile) ?? "Institucional"
        media = try values.decodeIfPresent([LocalMedia].self, forKey: .media) ?? []
        clips = try values.decodeIfPresent([TimelineClip].self, forKey: .clips) ?? []
        overlays = try values.decodeIfPresent([TextOverlay].self, forKey: .overlays) ?? []
        captionWords = try values.decodeIfPresent([CaptionWord].self, forKey: .captionWords) ?? []
        automaticDucking = try values.decodeIfPresent(Bool.self, forKey: .automaticDucking) ?? true
        duckingLevel = try values.decodeIfPresent(Double.self, forKey: .duckingLevel) ?? 0.24
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}

extension EditorProject {
    /// Material de origem visível para o Diretor IA, na ordem de importação.
    var directorMedia: [DirectorMediaDescriptor] {
        media.filter { !$0.isDerived }.map { item in
            DirectorMediaDescriptor(
                id: item.id.uuidString,
                name: item.name,
                kind: DirectorMediaDescriptor.Kind(rawValue: item.kind) ?? .unknown,
                importOrder: item.importOrder,
                duration: item.duration,
                isSonora: item.isSonora
            )
        }
    }

    /// Fim do conteúdo da timeline, sem o mínimo visual usado pela interface.
    var contentEnd: Double {
        let clipEnd = clips.map(\.end).max() ?? 0
        let overlayEnd = overlays.map { $0.start + $0.duration }.max() ?? 0
        let captionEnd = captionWords.map { $0.start + $0.duration }.max() ?? 0
        return max(clipEnd, max(overlayEnd, captionEnd))
    }

    /// Cópia com textos e legendas ajustados à resolução de saída.
    func scalingText(by factor: Double) -> EditorProject {
        guard factor.isFinite, factor > 0, abs(factor - 1) > 0.001 else { return self }
        var copy = self
        for index in copy.overlays.indices {
            copy.overlays[index].fontSize *= factor
            copy.overlays[index].outlineWidth *= factor
        }
        for index in copy.captionWords.indices {
            copy.captionWords[index].fontSize *= factor
        }
        copy.captionFontSize *= factor
        return copy
    }
}

/// Identidade de um cliente. Cada projeto usa um perfil, para nunca misturar logos e cores entre clientes.
struct ClientProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var primaryHex: String = "#1F6FEB"
    var secondaryHex: String = "#FFFFFF"
    var logoRelativePath: String?
    var targetMinimum: Double = 90
    var targetMaximum: Double = 120
    var openingDuration: Double = 8
    var notes: String = ""

    static let defaults: [ClientProfile] = [
        ClientProfile(name: "Prefeitura de Breu Branco"),
        ClientProfile(name: "Prefeitura de Tucuruí"),
        ClientProfile(name: "Outros clientes", targetMinimum: 15, targetMaximum: 180, openingDuration: 3)
    ]
}

/// Música ou efeito guardado no aparelho, usado em qualquer projeto.
struct LibraryItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var relativePath: String
    /// "music" ou "sfx".
    var kind: String
    /// Clima da música ou tipo do efeito, usado para procurar e pela IA.
    var mood: String
    var duration: Double
    var beats: [Double] = []
    var source: String = ""

    static let musicMoods = ["emocionante", "inspirador", "obra e trabalho", "festa", "corporativo", "suave", "impacto"]
    static let sfxKinds = ["transição", "impacto", "subida", "clique", "ambiente", "aplauso"]
}
