import Foundation

@main
enum SceneAndAgentTests {
    static func media(_ kind: String = "Vídeo", sonora: Bool = false, duration: Double = 60) -> LocalMedia {
        LocalMedia(name: "m", relativePath: "Media/m", kind: kind, byteCount: 1, importOrder: 1, duration: duration, isSonora: sonora)
    }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    static func main() {
        keyframesInterpolate(); clipStateAppliesLookAndTransition(); zOrderMatchesRule(); textAnimationsEnterAndExit()
        wordsEnterInSequence(); speedKeepsSameFootage(); splitRespectsSpeed(); transitionOverlapsAndRipples()
        approvedCutClosesGap(); cutPreviewShowsContext(); speechMapsToTimeline(); sonoraDetection(); beatsFoundInClickTrack()
        openingCutsAlignToBeats(); karaokePhrases(); lutParses(); lutRejectsBadFile(); chromaRemovesGreen()
        grammarHasAllTools(); promptFormats(); parsesPlanWithNoise(); agentNeverCutsSpeech(); agentEdits()
        agentGroupsByTrack(); agentReportsUnknownTool(); agentDoesNotChangeOriginal(); summaryHasNoPaths(); oldClipDecodes()
        openingFollowsBeats(); modelRecommendation(); motionImportRewrite()
        print("SceneAndAgent: 31 checks passed")
    }

    static func keyframesInterpolate() {
        let frames = [ClipKeyframe(property: "scale", time: 1, value: 1), ClipKeyframe(property: "scale", time: 3, value: 2)]
        precondition(close(KeyframeEvaluator.value(of: "scale", at: 2, in: frames, defaultValue: 9), 1.5), "Linear")
        precondition(close(KeyframeEvaluator.value(of: "scale", at: 0, in: frames, defaultValue: 9), 1), "Antes do primeiro")
        precondition(close(KeyframeEvaluator.value(of: "x", at: 2, in: frames, defaultValue: 9), 9), "Sem keyframes usa padrão")
    }

    static func clipStateAppliesLookAndTransition() {
        var clip = TimelineClip(mediaID: UUID(), track: "video", start: 10, duration: 4, label: "c")
        clip.look.transitionKind = "dissolve"
        clip.look.transitionDuration = 1
        precondition(close(SceneEvaluator.clipState(clip, at: 10.5).opacity, 0.5), "Dissolve no meio")
        precondition(close(SceneEvaluator.clipState(clip, at: 12).opacity, 1), "Depois da transição")
        clip.look.kenBurns = true
        precondition(close(SceneEvaluator.clipState(clip, at: 14).scale, 1.12), "Ken Burns no fim")
    }

    static func zOrderMatchesRule() {
        var project = EditorProject()
        project.clips = [
            TimelineClip(mediaID: UUID(), track: "subject", start: 0, duration: 5, label: "s"),
            TimelineClip(mediaID: UUID(), track: "broll", start: 0, duration: 5, label: "b"),
            TimelineClip(mediaID: UUID(), track: "video", start: 0, duration: 5, label: "v"),
            TimelineClip(mediaID: UUID(), track: "audio", start: 0, duration: 5, label: "a")
        ]
        project.overlays = [TextOverlay(text: "x", start: 0, duration: 5)]
        let items = SceneEvaluator.items(project: project, at: 2)
        precondition(items.count == 4, "Áudio não desenha")
        guard case .media(let first) = items[0], case .media(let second) = items[1], case .text = items[2], case .media(let last) = items[3] else { preconditionFailure("Ordem") }
        precondition(project.clips.first { $0.id == first.clipID }?.track == "video", "Vídeo embaixo")
        precondition(project.clips.first { $0.id == second.clipID }?.track == "broll", "B-roll cobre")
        precondition(project.clips.first { $0.id == last.clipID }?.track == "subject", "Pessoa acima do texto")
    }

    static func textAnimationsEnterAndExit() {
        for kind in TextMotion.entranceKinds {
            let middle = TextMotion.state(kind: kind, time: 1.5, duration: 3)
            precondition(close(middle.opacity, 1) && close(middle.scale, 1) && abs(middle.offsetY) < 0.001, "\(kind) deve assentar no meio")
            precondition(TextMotion.state(kind: kind, time: 3, duration: 3).opacity < 0.01, "\(kind) deve sumir no fim")
        }
        precondition(TextMotion.state(kind: "pop", time: 0, duration: 3).scale < 1, "Pop começa menor")
        precondition(close(TextMotion.state(kind: "typewriter", time: 0.9, duration: 3).reveal, 0.5), "Digita aos poucos")
        precondition(TextMotion.state(kind: "fade", time: -1, duration: 3).opacity == 0, "Fora do tempo não aparece")
    }

    static func wordsEnterInSequence() {
        let states = TextMotion.wordStates(kind: "wordPop", wordCount: 4, time: 0.1, duration: 4)
        precondition(states[0].opacity > 0 && states[3].opacity == 0, "Uma palavra de cada vez")
    }

    static func speedKeepsSameFootage() {
        let clip = TimelineClip(mediaID: UUID(), track: "video", start: 0, duration: 10, label: "c")
        let fast = TimelineEditing.setSpeed(clip, to: 2)
        precondition(fast.duration == 5 && fast.look.speed == 2, "2x dura metade")
        precondition(TimelineEditing.setSpeed(fast, to: 1).duration == 10, "Volta ao normal")
        precondition(TimelineEditing.trimEnd(fast, by: 100, sourceDuration: 10).duration == 5, "Limite considera a velocidade")
    }

    static func splitRespectsSpeed() {
        var clip = TimelineClip(mediaID: UUID(), track: "video", start: 0, duration: 10, label: "c")
        clip.look.speed = 2
        let parts = TimelineEditing.split(clip, at: 3)!
        precondition(parts.right.sourceIn == 6, "A fonte anda em dobro")
    }

    static func transitionOverlapsAndRipples() {
        let a = TimelineClip(mediaID: UUID(), track: "video", start: 0, duration: 5, label: "a")
        let b = TimelineClip(mediaID: UUID(), track: "video", start: 5, duration: 5, label: "b")
        let c = TimelineClip(mediaID: UUID(), track: "video", start: 10, duration: 5, label: "c")
        let result = TimelineEditing.addTransition(to: b.id, kind: "dissolve", duration: 1, in: [a, b, c])!
        precondition(result[1].start == 4 && result[1].look.transitionDuration == 1, "Segundo recua")
        precondition(result[2].start == 9, "Seguinte acompanha")
        let again = TimelineEditing.addTransition(to: b.id, kind: "wipe", duration: 1, in: result)!
        precondition(again[1].start == 4 && again[2].start == 9, "Refazer não recua de novo")
        precondition(TimelineEditing.addTransition(to: a.id, kind: "dissolve", duration: 1, in: [a, b, c]) == nil, "Primeiro não tem anterior")
    }

    static func approvedCutClosesGap() {
        let a = TimelineClip(mediaID: UUID(), track: "video", start: 0, duration: 10, sourceIn: 5, label: "a")
        let b = TimelineClip(mediaID: UUID(), track: "video", start: 10, duration: 5, label: "b")
        let result = TimelineEditing.cut(a.id, removing: AudioDuckingRange(start: 3, end: 6), in: [a, b])!
        precondition(result.count == 3, "Dois lados e o seguinte")
        precondition(result[0].duration == 3 && result[1].start == 3 && result[1].sourceIn == 11 && result[1].duration == 4, "Lados corretos")
        precondition(result[2].start == 7, "Espaço fechado")
        precondition(TimelineEditing.cut(a.id, removing: AudioDuckingRange(start: 20, end: 30), in: [a, b]) == nil, "Fora do clipe")
    }

    static func cutPreviewShowsContext() {
        let clip = TimelineClip(mediaID: UUID(), track: "video", start: 0, duration: 10, label: "a")
        let words = ["a", "rua", "foi", "ééé", "asfaltada"].enumerated().map { CaptionWord(text: $0.element, start: Double($0.offset), duration: 0.8) }
        let preview = SpeechCutPreview.make(words: words, clip: clip, removing: AudioDuckingRange(start: 3, end: 3.9))
        precondition(preview.before == "a rua foi" && preview.removed == "ééé" && preview.after == "asfaltada", "Contexto: \(preview)")
        precondition(close(preview.finalDuration, 9.1), "Duração final")
    }

    static func speechMapsToTimeline() {
        var project = EditorProject()
        var item = media(sonora: true)
        item.speechRanges = [AudioDuckingRange(start: 10, end: 20)]
        project.media = [item]
        project.clips = [TimelineClip(mediaID: item.id, track: "video", start: 100, duration: 5, sourceIn: 12, label: "c")]
        let ranges = SpeechMapper.timelineRanges(project: project)
        precondition(ranges == [AudioDuckingRange(start: 100, end: 105)], "Fala em tempo de timeline: \(ranges)")
    }

    static func sonoraDetection() {
        let ranges = AudioContentAnalysis.mergeWindows([(0, 1, 0.9), (1, 2, 0.8), (2, 3, 0.1), (3, 4, 0.9)], maximumGap: 0.5)
        precondition(ranges.count == 2 && close(AudioContentAnalysis.coverage(ranges, duration: 4), 0.75), "Junta janelas")
        precondition(AudioContentAnalysis.looksLikeSonora(speechCoverage: 0.7, duration: 30), "Fala domina")
        precondition(!AudioContentAnalysis.looksLikeSonora(speechCoverage: 0.1, duration: 30), "Pouca fala")
        precondition(!AudioContentAnalysis.looksLikeSonora(speechCoverage: 0.9, duration: 2), "Curto demais")
    }

    static func beatsFoundInClickTrack() {
        let hop = 0.02
        var envelope = [Double](repeating: 0.01, count: 500)
        for beat in stride(from: 25, to: 500, by: 25) {
            envelope[beat] = 1
            envelope[beat + 1] = 0.5
        }
        let beats = BeatDetector.beats(envelope: envelope, hop: hop)
        precondition(beats.count >= 15 && beats.count <= 20, "Batidas: \(beats.count)")
        for (a, b) in zip(beats, beats.dropFirst()) { precondition(abs(b - a - 0.5) < 0.05, "Intervalo regular") }
        precondition(BeatDetector.beats(envelope: [], hop: hop).isEmpty, "Vazio")
    }

    static func openingCutsAlignToBeats() {
        let cuts = BeatDetector.alignedCuts(start: 0, duration: 8, beats: stride(from: 0.5, to: 8, by: 0.5).map { $0 }, minimumShot: 1)
        precondition(cuts.first == 1 && cuts.allSatisfy { $0 < 8 }, "Cortes: \(cuts)")
        let none = BeatDetector.alignedCuts(start: 0, duration: 8, beats: [], maximumShot: 3)
        precondition(none == [3, 6], "Sem música corta em tempo regular: \(none)")
    }

    static func karaokePhrases() {
        let words = (0..<8).map { CaptionWord(text: "w\($0)", start: Double($0), duration: 0.9) }
        let phrase = CaptionLayout.phrase(in: words, at: 6.5)!
        precondition(phrase.words == ["w5", "w6", "w7"] && phrase.activeIndex == 1, "Frase: \(phrase)")
        precondition(CaptionLayout.phrase(in: words, at: 100) == nil, "Sem fala não mostra")
    }

    static func lutParses() {
        let text = """
        TITLE "x"
        # comentário
        LUT_3D_SIZE 2
        0 0 0
        1 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
        """
        let lut = try! CubeLUT.parse(text)
        precondition(lut.dimension == 2 && lut.values.count == 32 && lut.values[4] == 1, "LUT lido")
    }

    static func lutRejectsBadFile() {
        precondition((try? CubeLUT.parse("LUT_3D_SIZE 2\n0 0 0")) == nil, "Faltam linhas")
        precondition((try? CubeLUT.parse("LUT_1D_SIZE 2\n0 0 0\n1 1 1")) == nil, "1D recusado")
    }

    static func chromaRemovesGreen() {
        let n = 16
        let cube = CubeLUT.chromaCube(keyRed: 0, keyGreen: 1, keyBlue: 0, tolerance: 0.2, dimension: n)
        precondition(cube.count == n * n * n * 4, "Tamanho")
        func alpha(_ r: Int, _ g: Int, _ b: Int) -> Float { cube[(b * n * n + g * n + r) * 4 + 3] }
        precondition(alpha(0, n - 1, 0) == 0, "Verde some")
        precondition(alpha(n - 1, 0, 0) == 1, "Vermelho fica")
        precondition(alpha(n - 1, n - 1, n - 1) == 1, "Branco fica")
    }

    static func grammarHasAllTools() {
        for tool in AgentProtocol.tools { precondition(AgentProtocol.grammar.contains(tool), tool) }
        precondition(AgentProtocol.grammar.contains("root ::="), "Tem raiz")
    }

    static func promptFormats() {
        precondition(AgentProtocol.formatPrompt(system: "s", user: "u", format: .gemma).hasSuffix("<|turn>model\n<|channel>thought\n<channel|>"), "Gemma sem raciocínio")
        precondition(AgentProtocol.formatPrompt(system: "s", user: "u", format: .qwen).hasSuffix("<think>\n\n</think>\n\n"), "Qwen sem raciocínio")
    }

    static func parsesPlanWithNoise() {
        let plan = AgentProtocol.parsePlan("claro! {\"reply\":\"ok\",\"actions\":[{\"tool\":\"seek\",\"time\":2}]} fim")
        precondition(plan?.actions.first?.time == 2, "Lê JSON com texto em volta")
        precondition(AgentProtocol.parsePlan("sem json") == nil, "Resposta inválida")
    }

    static func sample() -> EditorProject {
        var project = EditorProject()
        let speech = media(sonora: true), broll = media(), music = media("Áudio")
        project.media = [speech, broll, music]
        project.clips = [
            TimelineClip(mediaID: speech.id, track: "video", start: 0, duration: 20, label: "fala"),
            TimelineClip(mediaID: broll.id, track: "video", start: 20, duration: 10, label: "obra"),
            TimelineClip(mediaID: music.id, track: "audio", start: 0, duration: 30, label: "música")
        ]
        return project
    }

    static func agentNeverCutsSpeech() {
        let project = sample()
        for tool in ["delete", "ripple_delete", "trim_start", "trim_end", "split", "set_speed"] {
            // A lista enviada à IA vem ordenada; a fala é um dos clipes em 0 s.
            let numbers = project.clips.sorted { $0.start < $1.start }
            let speechNumber = numbers.firstIndex { $0.label == "fala" }! + 1
            let plan = AgentPlan(reply: "", actions: [AgentAction(tool: tool, clip: speechNumber, time: 5, value: 1)])
            let outcome = AgentExecutor.apply(plan, to: project, playhead: 0)
            precondition(outcome.project.clips == project.clips, "\(tool) não pode mexer em fala")
            precondition(outcome.blocked.count == 1, "\(tool) deve avisar")
        }
    }

    static func agentEdits() {
        let project = sample()
        let sorted = project.clips.sorted { $0.start < $1.start }
        let brollNumber = sorted.firstIndex { $0.label == "obra" }! + 1
        let plan = AgentPlan(reply: "", actions: [
            AgentAction(tool: "trim_start", clip: brollNumber, value: 2),
            AgentAction(tool: "add_text", time: 1, duration: 2, text: "Asfalto novo", kind: "pop"),
            AgentAction(tool: "zoom", clip: brollNumber, value: 1.3)
        ])
        let outcome = AgentExecutor.apply(plan, to: project, playhead: 0)
        let edited = outcome.project.clips.first { $0.label == "obra" }!
        precondition(edited.start == 22 && edited.duration == 8, "Aparado")
        precondition(outcome.project.overlays.first?.text == "Asfalto novo", "Texto")
        precondition(edited.keyframes.count == 2, "Zoom")
        precondition(outcome.blocked.isEmpty && outcome.done.count == 3, "Tudo feito")
    }

    static func agentGroupsByTrack() {
        let plan = AgentPlan(reply: "", actions: [AgentAction(tool: "set_volume", track: "audio", value: 0.2), AgentAction(tool: "set_color", track: "video", value: 1.2, kind: "saturation")])
        let outcome = AgentExecutor.apply(plan, to: sample(), playhead: 0)
        precondition(outcome.project.clips.first { $0.label == "música" }?.volume == 0.2, "Volume da trilha")
        precondition(outcome.project.clips.filter { $0.track == "video" }.allSatisfy { $0.look.saturation == 1.2 }, "Cor da trilha")
    }

    static func agentReportsUnknownTool() {
        let outcome = AgentExecutor.apply(AgentPlan(reply: "", actions: [AgentAction(tool: "voar")]), to: sample(), playhead: 0)
        precondition(outcome.blocked.count == 1, "Avisa em vez de fingir")
    }

    static func agentDoesNotChangeOriginal() {
        let project = sample()
        _ = AgentExecutor.apply(AgentPlan(reply: "", actions: [AgentAction(tool: "assemble", kind: "institucional")]), to: project, playhead: 0)
        precondition(project.clips.count == 3, "Trabalha em cópia, para o preview e o desfazer")
    }

    static func summaryHasNoPaths() {
        let summary = AgentProtocol.projectSummary(sample(), playhead: 1, selectedClip: nil)
        precondition(summary.contains("[SONORA]") && !summary.contains("Media/"), "Resumo marca fala e não expõe caminhos")
    }

    static func oldClipDecodes() {
        let id = UUID().uuidString
        let json = "{\"mediaID\":\"\(id)\",\"track\":\"video\",\"start\":0,\"duration\":1,\"label\":\"x\"}"
        let clip = try! JSONDecoder().decode(TimelineClip.self, from: Data(json.utf8))
        precondition(clip.look.speed == 1 && !clip.look.hasColorChanges, "Projeto antigo abre com aparência neutra")
    }

    static func openingFollowsBeats() {
        let items = (1...5).map { DirectorMediaDescriptor(id: "v\($0)", name: "v", kind: .video, importOrder: $0, duration: 30) }
        let draft = DirectorPlanningCore.buildInstitutionalDraft(media: items, openingCuts: [1.5, 3, 5, 6.5])
        let opening = draft.segments.filter { $0.role == .openingVisual }
        precondition(opening.map(\.duration) == [1.5, 1.5, 2, 1.5, 1.5], "Cortes nas batidas: \(opening.map(\.duration))")
    }

    static func modelRecommendation() {
        precondition(LocalModel.recommended(memoryGB: 6).id == "qwen35-2b-q4", "iPhone de 6 GB")
        precondition(LocalModel.recommended(memoryGB: 8).id == "gemma4-e2b-qat", "iPhone de 8 GB")
        precondition(LocalModel.recommended(memoryGB: 12).id == "gemma4-e4b", "iPhone de 12 GB")
        precondition(LocalModel.recommended(memoryGB: 4).id == "qwen35-2b-q4", "Menor opção")
        precondition(LocalModel.looksValid(header: Array("GGUFxx".utf8), fileSize: 100, expected: 100), "Arquivo válido")
        precondition(!LocalModel.looksValid(header: Array("<html".utf8), fileSize: 100, expected: 100), "Página de erro não vale")
    }

    static func motionImportRewrite() {
        let html = "<script src=\"https://cdn.jsdelivr.net/npm/gsap@3.14/dist/gsap.min.js\"></script><img src=\"a.png\">"
        let result = MotionImport.prepare(html: html, libraryPath: "../lib")
        precondition(result.html.contains("../lib/gsap.min.js") && !result.html.contains("jsdelivr"), "GSAP local")
        precondition(result.html.contains("../lib/runtime.js"), "Runtime incluído")
        precondition(MotionImport.prepare(html: "<script src=\"https://x.com/a.js\"></script>", libraryPath: "../lib").warnings.count == 1, "Avisa sobre o que depende de internet")
        precondition(MotionImport.isComposition("<div data-composition-id=\"a\" data-duration=\"3\">"), "Reconhece composição")
        precondition(MotionImport.duration(in: "<div data-composition-id=\"a\" data-duration=\"3.5\">") == 3.5, "Lê duração")
        precondition(!MotionImport.isComposition("<p>oi</p>"), "HTML comum não vale")
    }
}
