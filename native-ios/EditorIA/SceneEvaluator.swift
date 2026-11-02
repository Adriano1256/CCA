import Foundation

/// Estado visual de uma camada em um instante. O compositor só desenha o que este cálculo manda,
/// então prévia e exportação são iguais, e toda a lógica pode ser testada fora do iPhone.
struct LayerState: Equatable {
    var opacity = 1.0
    var scale = 1.0
    /// Achatamento ou esticada na vertical, além da escala.
    var scaleY = 1.0
    /// Deslocamento em frações da largura e da altura do quadro.
    var offsetX = 0.0
    var offsetY = 0.0
    var rotation = 0.0
    /// Revelação da esquerda para a direita (1 = tudo visível).
    var wipe = 1.0
    /// Quantidade de branco por cima (flash).
    var flash = 0.0
    var blur = 0.0
    /// Fração dos caracteres visíveis (máquina de escrever).
    var reveal = 1.0
}

enum Easing {
    static func outCubic(_ t: Double) -> Double { 1 - pow(1 - clamp(t), 3) }
    static func inOutCubic(_ t: Double) -> Double {
        let x = clamp(t)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
    static func outBack(_ t: Double) -> Double {
        let x = clamp(t), c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
    static func outElastic(_ t: Double) -> Double {
        let x = clamp(t)
        if x == 0 || x == 1 { return x }
        return pow(2, -10 * x) * sin((x * 10 - 0.75) * (2 * .pi / 3)) + 1
    }
    static func outBounce(_ t: Double) -> Double {
        var x = clamp(t)
        let n1 = 7.5625, d1 = 2.75
        if x < 1 / d1 { return n1 * x * x }
        if x < 2 / d1 { x -= 1.5 / d1; return n1 * x * x + 0.75 }
        if x < 2.5 / d1 { x -= 2.25 / d1; return n1 * x * x + 0.9375 }
        x -= 2.625 / d1
        return n1 * x * x + 0.984375
    }
    static func clamp(_ t: Double) -> Double { min(1, max(0, t)) }
}

enum KeyframeEvaluator {
    /// Interpola os keyframes de uma propriedade. Sem keyframes, devolve o valor padrão.
    static func value(of property: String, at time: Double, in frames: [ClipKeyframe], defaultValue: Double) -> Double {
        let matching = frames.filter { $0.property == property }.sorted { $0.time < $1.time }
        guard let first = matching.first, let last = matching.last else { return defaultValue }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        for (a, b) in zip(matching, matching.dropFirst()) where time >= a.time && time <= b.time {
            let span = max(0.0001, b.time - a.time)
            let progress = (time - a.time) / span
            let eased = b.interpolation == "ease" ? Easing.inOutCubic(progress) : progress
            return a.value + (b.value - a.value) * eased
        }
        return last.value
    }
}

enum TextMotion {
    static let entranceKinds = ["fade", "pop", "slide", "slideDown", "slideLeft", "slideRight", "bounce", "zoom", "slam", "spring", "swing", "flip", "blur", "typewriter", "glitch", "shake"]

    /// Animação de entrada e saída de um texto. `time` é contado do início do texto.
    static func state(kind: String, time: Double, duration: Double, entrance: Double = 0.45, exit: Double = 0.25) -> LayerState {
        var state = LayerState()
        guard duration > 0, time >= 0, time <= duration else { state.opacity = 0; return state }
        let progress = Easing.clamp(time / max(0.01, min(entrance, duration * 0.5)))
        switch kind {
        case "pop":
            state.scale = 0.6 + 0.4 * Easing.outBack(progress)
            state.opacity = Easing.clamp(progress * 3)
        case "slide":
            state.offsetY = 0.08 * (1 - Easing.outCubic(progress))
            state.opacity = progress
        case "slideDown":
            state.offsetY = -0.08 * (1 - Easing.outCubic(progress))
            state.opacity = progress
        case "slideLeft":
            state.offsetX = 0.25 * (1 - Easing.outCubic(progress))
            state.opacity = progress
        case "slideRight":
            state.offsetX = -0.25 * (1 - Easing.outCubic(progress))
            state.opacity = progress
        case "bounce":
            state.offsetY = 0.18 * (1 - Easing.outBounce(progress))
            state.opacity = Easing.clamp(progress * 4)
        case "zoom":
            state.scale = 1.8 - 0.8 * Easing.outCubic(progress)
            state.opacity = progress
        case "slam":
            let fast = Easing.clamp(progress * 2)
            state.scale = 3 - 2 * Easing.outCubic(fast)
            state.opacity = Easing.clamp(fast * 4)
            state.flash = max(0, 0.35 * (1 - Easing.clamp((time - 0.12) / 0.15))) * (fast >= 1 ? 1 : 0)
        case "spring":
            state.scale = max(0.01, Easing.outElastic(progress))
            state.opacity = Easing.clamp(progress * 4)
        case "swing":
            state.rotation = -18 * (1 - Easing.outElastic(progress))
            state.opacity = Easing.clamp(progress * 4)
        case "flip":
            state.rotation = 90 * (1 - Easing.outCubic(progress))
            state.opacity = progress
        case "blur":
            state.blur = 30 * (1 - Easing.outCubic(progress))
            state.opacity = progress
        case "typewriter":
            state.reveal = Easing.clamp(time / max(0.1, duration * 0.6))
        case "glitch":
            let tick = Int(time * 24)
            state.offsetX = progress < 1 ? (tick % 2 == 0 ? 0.012 : -0.012) : 0
            state.opacity = progress < 1 ? (tick % 3 == 0 ? 0.4 : 1) : 1
        case "shake":
            let decay = 1 - progress
            state.offsetX = 0.015 * decay * sin(time * 60)
            state.offsetY = 0.01 * decay * cos(time * 70)
            state.opacity = Easing.clamp(progress * 5)
        default:
            state.opacity = progress
        }
        // Saída suave no fim do tempo do texto.
        let remaining = duration - time
        if remaining < exit { state.opacity *= Easing.clamp(remaining / max(0.01, exit)) }
        return state
    }

    /// Estado de cada palavra quando o texto entra palavra por palavra.
    static func wordStates(kind: String, wordCount: Int, time: Double, duration: Double) -> [LayerState] {
        guard wordCount > 0 else { return [] }
        let stagger = min(0.22, duration * 0.5 / Double(max(1, wordCount)))
        return (0..<wordCount).map { index in
            let local = time - Double(index) * stagger
            guard local >= 0 else {
                var hidden = LayerState()
                hidden.opacity = 0
                return hidden
            }
            return state(kind: kind == "wordSlam" ? "slam" : kind == "wordSlide" ? "slide" : "pop",
                         time: local, duration: max(0.01, duration - Double(index) * stagger), entrance: 0.3)
        }
    }
}

enum TransitionMotion {
    static let kinds = ["dissolve", "slideLeft", "slideUp", "zoom", "wipe", "flash"]

    static func apply(kind: String, progress: Double, to state: inout LayerState) {
        let p = Easing.clamp(progress)
        switch kind {
        case "slideLeft": state.offsetX += 1 - Easing.inOutCubic(p)
        case "slideUp": state.offsetY += 1 - Easing.inOutCubic(p)
        case "zoom":
            state.scale *= 1.3 - 0.3 * Easing.outCubic(p)
            state.opacity *= p
        case "wipe": state.wipe = Easing.inOutCubic(p)
        case "flash":
            state.flash = max(state.flash, 1 - abs(p * 2 - 1))
            state.opacity *= p < 0.5 ? 0 : 1
        default: state.opacity *= p
        }
    }
}

enum SceneEvaluator {
    /// Ordem de empilhamento, de baixo para cima. É a mesma regra na prévia e na exportação.
    static let trackOrder = ["video", "broll", "#text", "subject", "motion", "#captions"]

    struct MediaLayer: Equatable {
        var clipID: UUID
        var state: LayerState
    }

    enum Item: Equatable {
        case media(MediaLayer)
        case text(UUID, LayerState)
    }

    static func clipState(_ clip: TimelineClip, at time: Double) -> LayerState {
        var state = LayerState()
        let local = time - clip.start
        let look = clip.look
        state.opacity = KeyframeEvaluator.value(of: "opacity", at: local, in: clip.keyframes, defaultValue: 1)
        state.scale = look.scale * KeyframeEvaluator.value(of: "scale", at: local, in: clip.keyframes, defaultValue: 1)
        state.offsetX = look.offsetX + KeyframeEvaluator.value(of: "x", at: local, in: clip.keyframes, defaultValue: 0)
        state.offsetY = look.offsetY + KeyframeEvaluator.value(of: "y", at: local, in: clip.keyframes, defaultValue: 0)
        state.rotation = look.rotation + KeyframeEvaluator.value(of: "rotation", at: local, in: clip.keyframes, defaultValue: 0)
        if look.kenBurns {
            state.scale *= 1 + 0.12 * Easing.clamp(local / max(0.01, clip.duration))
        }
        if let kind = look.transitionKind, look.transitionDuration > 0, local < look.transitionDuration {
            TransitionMotion.apply(kind: kind, progress: local / look.transitionDuration, to: &state)
        }
        return state
    }

    /// Tudo que aparece em um instante, de baixo para cima (a legenda é desenhada à parte, no topo).
    static func items(project: EditorProject, at time: Double) -> [Item] {
        var result: [Item] = []
        for track in trackOrder {
            if track == "#text" {
                for overlay in project.overlays where time >= overlay.start && time <= overlay.start + overlay.duration {
                    result.append(.text(overlay.id, TextMotion.state(kind: overlay.animation, time: time - overlay.start, duration: overlay.duration)))
                }
            } else if track != "#captions" {
                let active = project.clips
                    .filter { $0.track == track && time >= $0.start && time < $0.end }
                    .sorted { $0.start < $1.start }
                for clip in active {
                    result.append(.media(MediaLayer(clipID: clip.id, state: clipState(clip, at: time))))
                }
            }
        }
        return result
    }
}
