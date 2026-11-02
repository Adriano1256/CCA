import Foundation

/// Frame rate da timeline expresso como fração exata (ex.: 1001/30000 = 29,97 fps).
struct FrameTiming: Equatable {
    var value: Int64
    var timescale: Int32
    var framesPerSecond: Double { Double(timescale) / Double(value) }

    static let standard = FrameTiming(value: 1, timescale: 30)
}

enum FrameRatePlanner {
    /// A timeline segue o material de maior frame rate, para não descartar quadros
    /// nem causar reprodução picotada. Sem vídeo, usa 30 fps.
    static func timing(forNominalRates rates: [Double]) -> FrameTiming {
        let valid = rates.filter { $0.isFinite && $0 > 1 }
        guard let highest = valid.max() else { return .standard }
        let capped = min(60, max(24, highest))
        for (rate, timing) in [
            (23.976, FrameTiming(value: 1001, timescale: 24000)),
            (29.97, FrameTiming(value: 1001, timescale: 30000)),
            (59.94, FrameTiming(value: 1001, timescale: 60000))
        ] where abs(capped - rate) < 0.02 {
            return timing
        }
        return FrameTiming(value: 1, timescale: Int32(capped.rounded()))
    }

    /// Aviso quando há materiais com frame rates diferentes na mesma timeline.
    static func mismatchWarning(forNominalRates rates: [Double]) -> String? {
        let valid = rates.filter { $0.isFinite && $0 > 1 }
        guard let low = valid.min(), let high = valid.max(), high - low > 0.05 else { return nil }
        let chosen = timing(forNominalRates: valid).framesPerSecond
        return String(format: "Material com frame rates diferentes (%.2f e %.2f fps). Timeline ajustada para %.2f fps.", low, high, chosen)
    }
}

enum LaneAllocator {
    /// Distribui intervalos em faixas sem sobreposição, reaproveitando faixas livres.
    /// Evita criar uma faixa de composição por clipe, o que esgota os decodificadores do aparelho.
    /// As entradas precisam estar ordenadas pelo início; devolve o índice da faixa de cada uma.
    static func assign(_ ranges: [(start: Double, end: Double)]) -> [Int] {
        var laneEnds: [Double] = []
        var result: [Int] = []
        for range in ranges {
            if let lane = laneEnds.firstIndex(where: { $0 <= range.start }) {
                laneEnds[lane] = range.end
                result.append(lane)
            } else {
                laneEnds.append(range.end)
                result.append(laneEnds.count - 1)
            }
        }
        return result
    }
}

struct StoryRange: Equatable {
    var index: Int
    var start: Double
    var duration: Double
    var fileName: String { String(format: "STORY_%03d.mp4", index) }
}

enum TimelineEditing {
    static func split(_ clip: TimelineClip, at playhead: Double, minimumPiece: Double = 0.1) -> (left: TimelineClip, right: TimelineClip)? {
        let offset = playhead - clip.start
        guard offset >= minimumPiece, offset <= clip.duration - minimumPiece else { return nil }
        var left = clip
        left.duration = offset
        left.keyframes = clip.keyframes.filter { $0.time <= offset }
        var right = clip
        right.id = UUID()
        right.start = playhead
        right.sourceIn = clip.sourceIn + offset * clip.look.speed
        right.look.transitionKind = nil
        right.look.transitionDuration = 0
        right.duration = clip.duration - offset
        right.keyframes = clip.keyframes.filter { $0.time >= offset }.map { frame in
            var adjusted = frame
            adjusted.time -= offset
            return adjusted
        }
        return (left, right)
    }

    /// Remove o clipe e puxa para trás o que vem depois nele, na mesma trilha.
    static func rippleDelete(_ id: UUID, in clips: [TimelineClip]) -> [TimelineClip] {
        guard let removed = clips.first(where: { $0.id == id }) else { return clips }
        return clips.compactMap { clip in
            if clip.id == id { return nil }
            var next = clip
            if next.track == removed.track, next.start >= removed.end - 0.0001 {
                next.start = max(0, next.start - removed.duration)
            }
            return next
        }
    }

    /// Aparar o início mantém o fim do clipe parado na timeline.
    static func trimStart(_ clip: TimelineClip, by seconds: Double, minimumDuration: Double = 0.1, isStill: Bool = false) -> TimelineClip {
        let speed = max(0.01, clip.look.speed)
        let lowerBound = isStill ? -clip.start : max(-clip.sourceIn / speed, -clip.start)
        let delta = max(lowerBound, min(seconds, clip.duration - minimumDuration))
        var next = clip
        next.start = clip.start + delta
        next.duration = clip.duration - delta
        if !isStill { next.sourceIn = max(0, clip.sourceIn + delta * speed) }
        let duration = next.duration
        next.keyframes = clip.keyframes.compactMap { frame in
            var adjusted = frame
            adjusted.time -= delta
            return adjusted.time >= 0 && adjusted.time <= duration ? adjusted : nil
        }
        return next
    }

    /// Aparar o fim respeita a duração da mídia; fotos podem durar o quanto o usuário quiser.
    static func trimEnd(_ clip: TimelineClip, by seconds: Double, sourceDuration: Double?, minimumDuration: Double = 0.1) -> TimelineClip {
        let speed = max(0.01, clip.look.speed)
        let available = sourceDuration.map { max(minimumDuration, ($0 - clip.sourceIn) / speed) } ?? .greatestFiniteMagnitude
        var next = clip
        let duration = min(available, max(minimumDuration, clip.duration + seconds))
        next.duration = duration
        next.keyframes.removeAll { $0.time > duration }
        return next
    }

    /// Encaixa o valor no candidato mais próximo dentro da tolerância.
    static func snap(_ value: Double, to candidates: [Double], tolerance: Double) -> Double {
        var best = value
        var bestDistance = tolerance
        for candidate in candidates {
            let distance = abs(candidate - value)
            if distance <= bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return max(0, best)
    }

    /// Cada clipe da trilha principal vira um arquivo de Stories, em ordem de timeline.
    static func storyRanges(from clips: [TimelineClip]) -> [StoryRange] {
        clips.filter { $0.track == "video" }
            .sorted { $0.start < $1.start }
            .enumerated()
            .map { StoryRange(index: $0.offset + 1, start: $0.element.start, duration: $0.element.duration) }
    }

    /// Muda a velocidade mantendo o mesmo trecho da mídia: 2x dura metade na timeline.
    static func setSpeed(_ clip: TimelineClip, to speed: Double) -> TimelineClip {
        let safe = min(8, max(0.1, speed))
        var next = clip
        next.duration = clip.duration * max(0.01, clip.look.speed) / safe
        next.look.speed = safe
        let factor = next.duration / max(0.0001, clip.duration)
        next.keyframes = clip.keyframes.map { frame in
            var adjusted = frame
            adjusted.time *= factor
            return adjusted
        }
        return next
    }

    /// Transição entre dois clipes vizinhos da mesma trilha: o segundo recua e sobrepõe o primeiro,
    /// e o que vem depois acompanha. Devolve nil se não houver um clipe logo antes.
    static func addTransition(to id: UUID, kind: String, duration: Double, in clips: [TimelineClip]) -> [TimelineClip]? {
        guard let target = clips.first(where: { $0.id == id }) else { return nil }
        let previous = clips.filter { $0.track == target.track && $0.id != id && $0.start < target.start && $0.end >= target.start - 0.05 }
            .max { $0.end < $1.end }
        guard let previous else { return nil }
        let oldOverlap = target.look.transitionKind == nil ? 0 : target.look.transitionDuration
        let safe = min(duration, min(previous.duration, target.duration) * 0.9)
        guard safe > 0.02 else { return nil }
        let shift = safe - oldOverlap
        return clips.map { clip in
            var next = clip
            if clip.id == id {
                next.start = max(0, clip.start - shift)
                next.look.transitionKind = kind
                next.look.transitionDuration = safe
            } else if clip.track == target.track && clip.start > target.start {
                next.start = max(0, clip.start - shift)
            }
            return next
        }
    }

    /// Corte aprovado em uma fala: tira o intervalo (em tempo de timeline), mantém os dois lados
    /// como clipes independentes e fecha o espaço. Nada é apagado do arquivo original.
    static func cut(_ id: UUID, removing range: AudioDuckingRange, in clips: [TimelineClip]) -> [TimelineClip]? {
        guard let clip = clips.first(where: { $0.id == id }) else { return nil }
        let from = max(clip.start, range.start)
        let to = min(clip.end, range.end)
        guard to - from > 0.02 else { return nil }
        let removed = to - from
        let speed = max(0.01, clip.look.speed)
        var result: [TimelineClip] = []
        for item in clips {
            if item.id == id {
                if from - clip.start > 0.02 {
                    var left = clip
                    left.duration = from - clip.start
                    result.append(left)
                }
                if clip.end - to > 0.02 {
                    var right = clip
                    right.id = UUID()
                    right.start = from
                    right.sourceIn = clip.sourceIn + (to - clip.start) * speed
                    right.duration = clip.end - to
                    right.look.transitionKind = nil
                    right.look.transitionDuration = 0
                    right.keyframes = []
                    result.append(right)
                }
            } else {
                var next = item
                if item.start >= to - 0.0001 { next.start = max(0, item.start - removed) }
                result.append(next)
            }
        }
        return result
    }
}

enum SpeechCutPreview {
    struct Result: Equatable {
        var before: String
        var removed: String
        var after: String
        var originalDuration: Double
        var finalDuration: Double
    }

    /// O que o usuário vê antes de aprovar um corte: contexto anterior, trecho cortado e contexto posterior.
    static func make(words: [CaptionWord], clip: TimelineClip, removing range: AudioDuckingRange, contextWords: Int = 8) -> Result {
        let inClip = words.filter { $0.start >= clip.start - 0.01 && $0.start < clip.end }.sorted { $0.start < $1.start }
        func center(_ word: CaptionWord) -> Double { word.start + word.duration / 2 }
        let before = inClip.filter { center($0) < range.start }.suffix(contextWords).map(\.text).joined(separator: " ")
        let removed = inClip.filter { center($0) >= range.start && center($0) <= range.end }.map(\.text).joined(separator: " ")
        let after = inClip.filter { center($0) > range.end }.prefix(contextWords).map(\.text).joined(separator: " ")
        let cut = max(0, min(clip.end, range.end) - max(clip.start, range.start))
        return Result(before: before, removed: removed, after: after, originalDuration: clip.duration, finalDuration: clip.duration - cut)
    }
}

enum SpeechMapper {
    /// Converte trechos de fala da mídia em tempo de timeline, respeitando corte e velocidade.
    static func timelineRanges(project: EditorProject) -> [AudioDuckingRange] {
        var result: [AudioDuckingRange] = []
        for clip in project.clips where clip.track != "audio" && clip.track != "sfx" && clip.track != "broll" && clip.volume > 0.05 {
            guard let media = project.media.first(where: { $0.id == clip.mediaID }) else { continue }
            let speed = max(0.01, clip.look.speed)
            for range in media.speechRanges {
                let start = clip.start + (range.start - clip.sourceIn) / speed
                let end = clip.start + (range.end - clip.sourceIn) / speed
                let clampedStart = max(clip.start, start)
                let clampedEnd = min(clip.end, end)
                if clampedEnd > clampedStart { result.append(AudioDuckingRange(start: clampedStart, end: clampedEnd)) }
            }
        }
        result.append(contentsOf: project.captionWords.map { AudioDuckingRange(start: $0.start, end: $0.start + $0.duration) })
        return AudioDuckingPlanner.merge(result)
    }
}

enum AudioContentAnalysis {
    /// Une janelas de classificação vizinhas em trechos contínuos.
    static func mergeWindows(_ windows: [(start: Double, end: Double, confidence: Double)], threshold: Double = 0.5, maximumGap: Double = 0.8) -> [AudioDuckingRange] {
        AudioDuckingPlanner.merge(
            windows.filter { $0.confidence >= threshold }.map { AudioDuckingRange(start: $0.start, end: $0.end) },
            maximumGap: maximumGap
        )
    }

    static func coverage(_ ranges: [AudioDuckingRange], duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, ranges.reduce(0) { $0 + $1.duration } / duration)
    }

    /// Só sugere sonora quando a fala domina um arquivo com duração suficiente.
    static func looksLikeSonora(speechCoverage: Double, duration: Double) -> Bool {
        speechCoverage >= 0.45 && duration >= 6
    }
}

enum BeatDetector {
    /// Acha batidas a partir da energia de um sinal mono. `hop` é o tempo entre as amostras do envelope.
    static func beats(envelope: [Double], hop: Double, minimumInterval: Double = 0.25) -> [Double] {
        guard envelope.count > 8, hop > 0 else { return [] }
        var flux = [Double](repeating: 0, count: envelope.count)
        for index in 1..<envelope.count { flux[index] = max(0, envelope[index] - envelope[index - 1]) }
        let window = max(4, Int(0.5 / hop))
        var result: [Double] = []
        var last = -Double.greatestFiniteMagnitude
        for index in 1..<(flux.count - 1) {
            let low = max(0, index - window)
            let high = min(flux.count - 1, index + window)
            let slice = flux[low...high]
            let mean = slice.reduce(0, +) / Double(slice.count)
            let time = Double(index) * hop
            if flux[index] > mean * 1.6, flux[index] >= flux[index - 1], flux[index] >= flux[index + 1], flux[index] > 0.001, time - last >= minimumInterval {
                result.append(time)
                last = time
            }
        }
        return result
    }

    /// Encaixa os cortes da abertura nas batidas, sem deixar plano curto demais.
    static func alignedCuts(start: Double, duration: Double, beats: [Double], minimumShot: Double = 0.8, maximumShot: Double = 3) -> [Double] {
        var cuts: [Double] = []
        var last = start
        let end = start + duration
        for beat in beats where beat > start && beat < end - minimumShot {
            if beat - last >= minimumShot {
                cuts.append(beat)
                last = beat
            }
        }
        var filled: [Double] = []
        var cursor = start
        for cut in cuts + [end] {
            while cut - cursor > maximumShot {
                cursor += maximumShot
                filled.append(cursor)
            }
            if cut < end { filled.append(cut) }
            cursor = cut
        }
        return filled
    }
}

enum CaptionLayout {
    struct Phrase: Equatable {
        var words: [String]
        var activeIndex: Int
        var key: String
    }

    /// Agrupa as palavras em frases curtas e indica a palavra falada agora (estilo karaokê).
    static func phrase(in words: [CaptionWord], at time: Double, maximumWords: Int = 5, maximumGap: Double = 0.7) -> Phrase? {
        guard let index = words.firstIndex(where: { time >= $0.start && time < $0.start + $0.duration }) else { return nil }
        var groupStart = 0
        var cursor = 0
        while cursor <= index {
            var end = cursor
            while end + 1 < words.count, end + 1 - cursor < maximumWords,
                  words[end + 1].start - (words[end].start + words[end].duration) <= maximumGap {
                end += 1
            }
            if index <= end {
                groupStart = cursor
                let group = words[cursor...end].map(\.text)
                return Phrase(words: group, activeIndex: index - groupStart, key: "\(cursor)-\(index)")
            }
            cursor = end + 1
        }
        return nil
    }
}

/// Lê arquivos de LUT `.cube` (3D). Devolve dados RGBA em ponto flutuante, prontos para o filtro de cor.
enum CubeLUT {
    struct Parsed: Equatable {
        var dimension: Int
        var values: [Float]
    }

    enum ParseError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let reason): return "LUT inválido: \(reason)" }
        }
    }

    static func parse(_ text: String) throws -> Parsed {
        var dimension = 0
        var rows: [Float] = []
        var minValue: [Float] = [0, 0, 0]
        var maxValue: [Float] = [1, 1, 1]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts[0] == "LUT_1D_SIZE" { throw ParseError.invalid("só LUT 3D é aceito") }
            if parts[0] == "LUT_3D_SIZE", parts.count > 1 { dimension = Int(parts[1]) ?? 0; continue }
            if parts[0] == "DOMAIN_MIN", parts.count > 3 { minValue = parts[1...3].compactMap { Float($0) }; continue }
            if parts[0] == "DOMAIN_MAX", parts.count > 3 { maxValue = parts[1...3].compactMap { Float($0) }; continue }
            if parts.count >= 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) {
                rows.append(contentsOf: [r, g, b, 1])
            }
        }
        guard dimension >= 2, dimension <= 129 else { throw ParseError.invalid("tamanho ausente") }
        guard rows.count == dimension * dimension * dimension * 4 else {
            throw ParseError.invalid("esperava \(dimension * dimension * dimension) linhas de cor")
        }
        if minValue != [0, 0, 0] || maxValue != [1, 1, 1] {
            guard minValue.count == 3, maxValue.count == 3 else { throw ParseError.invalid("domínio") }
            for index in 0..<(rows.count / 4) {
                for channel in 0..<3 {
                    let span = max(0.0001, maxValue[channel] - minValue[channel])
                    rows[index * 4 + channel] = (rows[index * 4 + channel] - minValue[channel]) / span
                }
            }
        }
        return Parsed(dimension: dimension, values: rows)
    }

    /// Cubo que torna transparente a cor escolhida, para chroma key.
    static func chromaCube(keyRed: Double, keyGreen: Double, keyBlue: Double, tolerance: Double, softness: Double = 0.08, dimension: Int = 32) -> [Float] {
        var data = [Float]()
        data.reserveCapacity(dimension * dimension * dimension * 4)
        let scale = Double(dimension - 1)
        let keyVector = chromaVector(keyRed, keyGreen, keyBlue)
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let red = Double(r) / scale, green = Double(g) / scale, blue = Double(b) / scale
                    let vector = chromaVector(red, green, blue)
                    let distance = ((vector.0 - keyVector.0) * (vector.0 - keyVector.0) + (vector.1 - keyVector.1) * (vector.1 - keyVector.1)).squareRoot()
                    let alpha = min(1, max(0, (distance - tolerance) / max(0.001, softness)))
                    data.append(contentsOf: [Float(red * alpha), Float(green * alpha), Float(blue * alpha), Float(alpha)])
                }
            }
        }
        return data
    }

    private static func chromaVector(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double) {
        (-0.169 * r - 0.331 * g + 0.5 * b, 0.5 * r - 0.419 * g - 0.081 * b)
    }
}

/// O que o usuário escolhe ao exportar.
struct ExportOptions: Equatable {
    enum Quality: String, CaseIterable {
        case good = "Boa"
        case high = "Alta"
        case maximum = "Máxima"

        var bitsPerPixel: Double {
            switch self {
            case .good: return 0.12
            case .high: return 0.25
            case .maximum: return 0.5
            }
        }
    }

    enum Codec: String, CaseIterable {
        case h264 = "H.264"
        case hevc = "HEVC"
    }

    var quality: Quality = .maximum
    var codec: Codec = .h264
    /// Lado menor do vídeo: 720, 1080, 1440 ou 2160.
    var shortSide: Int = 1080
    /// Nil segue o material.
    var frameRate: Int?

    static let maximum = ExportOptions()

    /// HEVC comprime melhor, então chega à mesma imagem com menos dados.
    func bitrate(width: Int, height: Int, framesPerSecond: Double) -> Int {
        let factor = codec == .hevc ? 0.75 : 1
        let value = Double(width) * Double(height) * framesPerSecond * quality.bitsPerPixel * factor
        return Int(min(240_000_000, max(2_000_000, value)))
    }

    var audioBitrate: Int { quality == .good ? 192_000 : 320_000 }

    /// Tamanho final, mantendo a proporção. Sempre em números pares, como os codecs exigem.
    func dimensions(baseWidth: Int, baseHeight: Int) -> (width: Int, height: Int) {
        let scale = Double(shortSide) / Double(max(1, min(baseWidth, baseHeight)))
        func even(_ value: Double) -> Int { Int((value / 2).rounded()) * 2 }
        return (even(Double(baseWidth) * scale), even(Double(baseHeight) * scale))
    }

    func estimatedBytes(width: Int, height: Int, framesPerSecond: Double, duration: Double) -> Int64 {
        Int64(Double(bitrate(width: width, height: height, framesPerSecond: framesPerSecond) + audioBitrate) * duration / 8)
    }

    func timing(forNominalRates rates: [Double]) -> FrameTiming {
        if let frameRate { return FrameTiming(value: 1, timescale: Int32(frameRate)) }
        return FrameRatePlanner.timing(forNominalRates: rates)
    }
}
