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
        openingFollowsBeats(); modelRecommendation(); motionImportRewrite(); exportOptions()
        captionsFollowEdits(); captionGroups(); captionStyles(); cleanerDropsNoise(); reframeKeepsSubject(); ruleAgentUnderstands(); looksApply(); summaryKnowsImages()
        print("SceneAndAgent: 40 checks passed")
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
        precondition(AgentProtocol.formatPrompt(system: "s", user: "u", format: .gemma).hasSuffix("<|turn>user\nu<turn|>\n<|turn>model\n"), "Gemma no formato oficial, sem raciocínio")
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
        precondition(LocalModel.recommended(memoryGB: 11.5).id == "gemma4-12b", "iPhone de 12 GB usa o maior")
        precondition(AIStorageBudget.fits(adding: 6_000_000_000 + 626_000_000, installedBytes: 0), "Maior modelo e Whisper cabem nos 8 GB")
        precondition(!AIStorageBudget.fits(adding: 3_800_000_000, installedBytes: 6_626_000_000), "Passar de 8 GB é recusado")
        var crash = ModelCrashGuard(pending: "gemma4-12b")
        precondition(crash.recover() == "gemma4-12b" && crash.pending == nil && !crash.isBlocked("gemma4-12b"), "Primeira queda ainda tenta")
        precondition(crash.contextSize(for: LocalModel.catalog.last!) == 4096, "Depois da queda usa menos memória")
        crash.pending = "gemma4-12b"
        _ = crash.recover()
        precondition(crash.isBlocked("gemma4-12b"), "Segunda queda troca de modelo")
        precondition(crash.recover() == nil, "Sem queda não muda nada")
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
        precondition(MotionImport.isComposition("<script>window.seek = function(t){}</script>"), "Reconhece composição com window.seek")
        precondition(MotionImport.duration(in: "<script>const DURATION = 12.5; window.seek = f</script>") == 12.5, "Lê duração do prompt de texto animado")
        precondition(!MotionImport.isComposition("<p>oi</p>"), "HTML comum não vale")
    }

    static func exportOptions() {
        var options = ExportOptions()
        precondition(options.quality == .maximum, "A máxima é o padrão")
        precondition(options.bitrate(width: 1920, height: 1080, framesPerSecond: 30) == 31_104_000, "1080p30 máxima")
        options.quality = .good
        let low = options.bitrate(width: 1920, height: 1080, framesPerSecond: 30)
        options.quality = .high
        precondition(low < options.bitrate(width: 1920, height: 1080, framesPerSecond: 30), "Qualidade maior, mais dados")
        options.quality = .maximum
        options.codec = .hevc
        precondition(options.bitrate(width: 1920, height: 1080, framesPerSecond: 30) == 23_328_000, "HEVC usa menos dados")
        options.codec = .h264
        options.shortSide = 2160
        let vertical = options.dimensions(baseWidth: 1080, baseHeight: 1920)
        precondition(vertical.width == 2160 && vertical.height == 3840, "4K vertical")
        options.shortSide = 1080
        let feed = options.dimensions(baseWidth: 1080, baseHeight: 1350)
        precondition(feed.width == 1080 && feed.height == 1350, "4:5")
        options.shortSide = 720
        let wide = options.dimensions(baseWidth: 1920, baseHeight: 1080)
        precondition(wide.width == 1280 && wide.height == 720, "720p")
        precondition(options.dimensions(baseWidth: 1080, baseHeight: 1350).height % 2 == 0, "Sempre par")
        options.frameRate = 25
        precondition(options.timing(forNominalRates: [60]) == FrameTiming(value: 1, timescale: 25), "Escolha manual vence")
        precondition(ExportOptions().estimatedBytes(width: 1920, height: 1080, framesPerSecond: 30, duration: 60) > 200_000_000, "Estimativa")
    }

    static func captionsFollowEdits() {
        var project = sample()
        let index = project.media.firstIndex { $0.isSonora }!
        project.media[index].transcript = [TranscriptWord(text: "a", start: 1, end: 2), TranscriptWord(text: "rua", start: 5, end: 6), TranscriptWord(text: "nova", start: 25, end: 26)]
        var words = CaptionBuilder.timelineWords(project: project)
        precondition(words.map(\.text) == ["a", "rua"], "Fala fora do clipe não aparece: \(words.map(\.text))")
        let clipIndex = project.clips.firstIndex { $0.label == "fala" }!
        project.clips[clipIndex].start = 100
        project.clips[clipIndex].sourceIn = 4
        words = CaptionBuilder.timelineWords(project: project)
        precondition(words.first?.text == "rua" && close(words.first!.start, 101), "A legenda acompanha o corte e a posição: \(words)")
        project.clips[clipIndex].look.speed = 2
        words = CaptionBuilder.timelineWords(project: project)
        precondition(close(words.first!.start, 100.5), "A legenda acompanha a velocidade")
        project.captionsEnabled = false
        precondition(CaptionBuilder.timelineWords(project: project).isEmpty, "Desligada não aparece")
    }

    static func captionGroups() {
        let words = ["Olá", "gente.", "A", "rua", "nova", "chegou", "aqui", "hoje"].enumerated().map { CaptionWord(text: $0.element, start: Double($0.offset) * 0.3, duration: 0.25) }
        let groups = CaptionLayout.groups(words, maximumWords: 4)
        precondition(groups == [0..<2, 2..<6, 6..<8], "Quebra em frase e limite: \(groups)")
        var paused = words
        for index in 5..<8 { paused[index].start += 2 }
        precondition(CaptionLayout.groups(paused, maximumWords: 9).count == 3, "Quebra na pausa")
        precondition(CaptionLayout.phrase(in: words, at: 0.28)?.activeIndex == 0, "Entre palavras a frase continua")
        precondition(CaptionLayout.defaultVertical(width: 1080, height: 1920) < CaptionLayout.defaultVertical(width: 1920, height: 1080), "No vertical fica mais alta")
    }

    static func captionStyles() {
        let words = ["a", "rua", "nova"].enumerated().map { CaptionWord(text: $0.element, start: Double($0.offset), duration: 0.9) }
        for style in CaptionAnimator.styles {
            precondition(CaptionAnimator.frame(style: style.id, words: words, at: 1.5) != nil, "\(style.id) mostra algo")
            precondition(CaptionAnimator.frame(style: style.id, words: words, at: 9) == nil, "\(style.id) some sem fala")
        }
        let karaoke = CaptionAnimator.frame(style: "karaoke", words: words, at: 1.5)!
        precondition(karaoke.words.count == 3 && karaoke.words[1].isActive && !karaoke.words[0].isActive, "Karaokê destaca a palavra falada")
        precondition(CaptionAnimator.frame(style: "box", words: words, at: 1.5)!.words[1].hasBox, "Caixa na palavra")
        let reveal = CaptionAnimator.frame(style: "reveal", words: words, at: 0.5)!
        precondition(reveal.words[0].state.opacity > 0 && reveal.words[2].state.opacity == 0, "Aparece ao falar")
        let slam = CaptionAnimator.frame(style: "slam", words: words, at: 1.5)!
        precondition(slam.words.count == 1 && slam.words[0].text == "RUA", "Impacto: uma palavra em maiúsculas")
        precondition(CaptionAnimator.frame(style: "pop", words: words, at: 1.5)!.words[1].state.scale > 1.1, "Palavra salta")
        presetsAreSound()
    }

    static func presetsAreSound() {
        let all = CaptionPreset.all
        precondition(all.count >= 50, "Muitos estilos: \(all.count)")
        precondition(Set(all.map(\.id)).count == all.count, "Sem identificador repetido")
        precondition(all.allSatisfy { CaptionPreset.categories.contains($0.category) }, "Toda legenda tem categoria")
        let words = ["Agora", "a", "nossa", "rua", "tem", "asfalto", "novo", "em", "2026."].enumerated().map { CaptionWord(text: $0.element, start: Double($0.offset) * 0.4, duration: 0.36) }
        for preset in all {
            var time = 0.0
            while time < 4 {
                if let frame = CaptionAnimator.frame(style: preset.id, words: words, at: time) {
                    precondition(!frame.words.isEmpty, "\(preset.id) tem palavras")
                    for word in frame.words {
                        precondition(word.state.opacity >= 0 && word.state.opacity <= 1, "\(preset.id) opacidade")
                        precondition(word.state.scale.isFinite && word.state.offsetX.isFinite && word.state.rotation.isFinite, "\(preset.id) números válidos")
                        precondition(!word.text.isEmpty, "\(preset.id) texto")
                    }
                }
                time += 1.0 / 30
            }
            // Passada a entrada, a palavra fica visível e no lugar.
            if preset.scope != .single, let settled = CaptionAnimator.frame(style: preset.id, words: words, at: 0.35 + 0.0) {
                precondition(settled.words.contains { $0.state.opacity > 0 }, "\(preset.id) mostra a palavra")
            }
            // Igual a cada render: a exportação não pode variar.
            precondition(CaptionAnimator.frame(style: preset.id, words: words, at: 1.23) == CaptionAnimator.frame(style: preset.id, words: words, at: 1.23), "\(preset.id) repetível")
        }
        let hormozi = CaptionAnimator.frame(style: "hormozi", words: words, at: 2.05)!
        precondition(hormozi.words.allSatisfy { $0.text == $0.text.uppercased() }, "Hormozi em maiúsculas")
        precondition(hormozi.words.contains { $0.isKeyword }, "Palavra forte destacada")
        let beast = CaptionAnimator.frame(style: "mrbeast", words: words, at: 0.05)!
        precondition(beast.words.first?.color != nil, "MrBeast reveza cores")
        let fill = CaptionAnimator.frame(style: "karaoke-fill", words: words, at: 0.18)!
        precondition((fill.words[0].fill ?? 0) > 0.3 && (fill.words[0].fill ?? 1) < 0.7, "Preenche a palavra enquanto fala")
        let emoji = CaptionAnimator.frame(style: "emoji-viral", words: words, at: 2.1)!
        precondition(emoji.words.contains { $0.isEmoji }, "Emoji aparece em palavra conhecida")
        precondition(CaptionWords.isKeyword("2026") && CaptionWords.isKeyword("asfalto") && !CaptionWords.isKeyword("rua"), "Palavras fortes")
        precondition(CaptionPreset.match("quero legenda estilo MrBeast")?.id == "mrbeast", "Chat entende MrBeast")
        precondition(CaptionPreset.match("legenda neon")?.id == "neon", "Chat entende neon")
        precondition(CaptionPreset.match("legenda de prefeitura")?.category == "Institucional", "Chat entende prefeitura")
        precondition(CaptionPreset.find("nao existe") == nil, "Estilo desconhecido")
        var project = EditorProject()
        CaptionPreset.find("quadrinhos")!.apply(to: &project)
        precondition(project.captionStyle == "quadrinhos" && project.captionTextHex == "#FFEB3B" && project.captionFontStyle == "preset", "Preset vai para o projeto")
    }

    static func cleanerDropsNoise() {
        let words = [TranscriptWord(text: "[Música]", start: 0, end: 1), TranscriptWord(text: " olá ", start: 2, end: 3), TranscriptWord(text: "obrigado", start: 50, end: 51)]
        let clean = TranscriptCleaner.clean(words, speech: [AudioDuckingRange(start: 1.5, end: 4)])
        precondition(clean.map(\.text) == ["olá"], "Tira marcações e fala inventada no silêncio: \(clean)")
    }

    static func reframeKeepsSubject() {
        let left = Reframe.offset(imageWidth: 1920, imageHeight: 1080, frameWidth: 1080, frameHeight: 1920, interestX: 0.25, interestY: 0.5)
        precondition(left.x > 0 && close(left.y, 0), "Assunto à esquerda: o clipe anda para a direita")
        let extreme = Reframe.offset(imageWidth: 1920, imageHeight: 1080, frameWidth: 1080, frameHeight: 1920, interestX: 0, interestY: 0.5)
        let scaled = 1920.0 * (1920.0 / 1080.0)
        precondition(extreme.x <= (scaled - 1080) / 1080 / 2 + 0.001, "Sem borda preta")
    }

    static func ruleAgentUnderstands() {
        let project = sample()
        precondition(RuleAgent.plan(for: "Monta o vídeo institucional", project: project)?.actions.first?.kind == "institucional", "Montagem")
        precondition(RuleAgent.plan(for: "faz os stories", project: project)?.actions.first?.kind == "stories", "Stories")
        let caption = RuleAgent.plan(for: "coloca legenda animada com caixa", project: project)!
        precondition(caption.actions.first?.tool == "transcribe" && caption.actions.last?.kind == "box", "Transcreve e aplica o estilo")
        precondition(RuleAgent.plan(for: "abaixa a música para 10%", project: project)?.actions.first?.value == 0.1, "Volume")
        precondition(RuleAgent.plan(for: "tira o som do b-roll", project: project)?.actions.first?.track == "broll", "B-roll")
        precondition(RuleAgent.plan(for: "exporta", project: project)?.actions.first?.tool == "export", "Exportar")
        precondition(RuleAgent.plan(for: "qual o sentido da vida", project: project) == nil, "Não finge que entendeu")
        let trim = RuleAgent.plan(for: "Corta os 3 primeiros segundos do clipe 1", project: project)?.actions.first
        precondition(trim?.tool == "trim_start" && trim?.clip == 1 && trim?.value == 3, "Corte no início")
        let title = RuleAgent.plan(for: "Coloca o título Asfalto Novo no início com efeito de impacto", project: project)?.actions.first
        precondition(title?.tool == "add_text" && title?.text == "Asfalto Novo" && title?.time == 0 && title?.kind == "slam", "Título: \(String(describing: title))")
        let kinetic = RuleAgent.plan(for: "Faz um texto animado estilo katana escrito Asfalto novo", project: project)?.actions.first
        precondition(kinetic?.tool == "motion" && kinetic?.kind == "katana" && kinetic?.text == "Asfalto novo", "Texto animado: \(String(describing: kinetic))")
        let name = RuleAgent.plan(for: "Coloca uma tarja de nome da Maria Souza, moradora, em 10 segundos", project: project)?.actions.first
        precondition(name?.kind == "tarja-nome" && name?.text?.hasPrefix("Maria Souza") == true && name?.time == 10, "Tarja: \(String(describing: name))")
        precondition(RuleAgent.plan(for: "Deixa as imagens mais saturadas na trilha de vídeo", project: project)?.actions.first?.kind == "saturation", "Saturação")
        precondition(RuleAgent.plan(for: "Coloca um zoom lento no clipe 2", project: project)?.actions.first?.clip == 2, "Zoom lento")
        let both = RuleAgent.direct(for: "Tira o som do B-roll e depois coloca uma legenda neon", project: project)
        precondition(both?.actions.map(\.tool) == ["set_volume", "transcribe", "caption_style"], "Dois pedidos entendidos: \(String(describing: both?.actions.map(\.tool)))")
        let slowTitle = RuleAgent.direct(for: "Deixa o clipe 2 em câmera lenta pela metade da velocidade e coloca um título Obra Entregue aos 20 segundos", project: project)
        precondition(slowTitle?.actions.first?.tool == "set_speed" && slowTitle?.actions.first?.value == 0.5 && slowTitle?.actions.last?.text == "Obra Entregue" && slowTitle?.actions.last?.time == 20, "Câmera lenta e título: \(String(describing: slowTitle?.actions))")
        precondition(RuleAgent.clauses("coloca o título Arroz e Feijão no começo").count == 1, "Título com e não é dividido")
        precondition(RuleAgent.direct(for: "tira o som do b-roll e faz a imagem voar pela lua", project: project) == nil, "Parte que o app não entende vai para a IA")
        let breu = RuleAgent.direct(for: "Edite esse vídeo de acordo com o padrão do Breu Branco, mas deixa 15 segundos de imagem de apoio e aí entra a primeira fala", project: project)!
        precondition(breu.actions.first?.tool == "set_client" && breu.actions.first?.text == "Breu Branco", "Cliente pelo nome")
        precondition(breu.actions.last?.tool == "assemble" && breu.actions.last?.value == 15, "Abertura de 15 s: \(breu.actions)")
        precondition(AssemblyRequest.total(in: "monta um institucional de 1 minuto e meio") == 90, "Duração total")
        precondition(AssemblyRequest.total(in: "monta com 2 minutos e 10 segundos") == 130, "Minutos e segundos")
        precondition(AssemblyRequest.hold(in: "monta no padrão e o prefeito aparece 4 segundos") == 4, "Tempo da pessoa")
        var clientProject = project
        let clientList = ClientProfile.defaults
        let assembled = AgentExecutor.apply(breu, to: clientProject, playhead: 0, clients: clientList)
        precondition(assembled.project.clientID == clientList[0].id, "Projeto passa a ser do Breu Branco")
        precondition(assembled.done.contains { $0.contains("15 s de abertura") && $0.contains("Breu Branco") }, "Montagem com o ajuste: \(assembled.done)")
        clientProject.clientID = clientList[1].id
        let standard = AgentExecutor.apply(AgentPlan(reply: "", actions: [AgentAction(tool: "assemble", kind: "institucional")]), to: clientProject, playhead: 0, clients: clientList)
        precondition(standard.done.contains { $0.contains("8 s de abertura") && $0.contains("Tucuruí") }, "Sem ajuste usa o padrão do cliente: \(standard.done)")
        precondition(AgentExecutor.apply(AgentPlan(reply: "", actions: [AgentAction(tool: "set_client", text: "Marabá")]), to: project, playhead: 0, clients: clientList).blocked.count == 1, "Cliente inexistente é avisado")
        precondition(RuleAgent.direct(for: "legenda estilo MrBeast", project: project)?.actions.last?.kind == "mrbeast", "Pedido simples resolve na hora")
        let obra = project.clips.sorted { $0.start < $1.start }.firstIndex { $0.label == "obra" }! + 1
        let tolerant = AgentExecutor.apply(AgentPlan(reply: "", actions: [AgentAction(tool: "set_volume", track: "audio", value: 10), AgentAction(tool: "trim_start", clip: obra, time: 1)]), to: project, playhead: 0)
        precondition(tolerant.project.clips.filter { $0.track == "audio" }.allSatisfy { abs($0.volume - 0.1) < 0.001 }, "10 vira 10%")
        precondition(tolerant.done.contains { $0.contains("Início") }, "Corte aceita tempo no lugar de valor")
        precondition(AgentProtocol.parsePlan(#"{"reply":"ok","actions":[{"tool":"set_volume","track":"broll","value":0}]}"#) != nil, "Exemplo do prompt é válido")
    }

    static func looksApply() {
        let outcome = AgentExecutor.apply(AgentPlan(reply: "", actions: [AgentAction(tool: "look", track: "video", kind: "preto e branco"), AgentAction(tool: "caption_style", kind: "box"), AgentAction(tool: "fade", track: "audio", value: 2, kind: "out")]), to: sample(), playhead: 0)
        precondition(outcome.project.clips.filter { $0.track == "video" }.allSatisfy { $0.look.saturation == 0 }, "Visual")
        precondition(outcome.project.captionStyle == "box", "Legenda")
        precondition(outcome.project.clips.first { $0.track == "audio" }?.fadeOut == 2, "Fade")
    }

    static func summaryKnowsImages() {
        var project = sample()
        project.media[1].visualTags = ["road", "machine"]
        project.media[1].faceShare = 0.2
        project.media[0].transcript = [TranscriptWord(text: "asfalto", start: 1, end: 2)]
        let summary = AgentProtocol.projectSummary(project, playhead: 0, selectedClip: nil, libraryMoods: ["festa"])
        precondition(summary.contains("road") && summary.contains("asfalto") && summary.contains("festa"), "A IA sabe o que tem nas imagens, a fala e a biblioteca")
    }
}
