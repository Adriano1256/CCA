import Foundation

@main
enum DirectorPlanningCoreTests {
    static func main() {
        testInstitutionalPreservesImportOrderAndApproval()
        testInstitutionalCoverageRunsUnderSonora()
        testStoriesVisualSegmentsNeverExceedFifteenSeconds()
        testStoriesAudioCanExceedFifteenSeconds()
        testMaterializerAppendsToEndAndKeepsFullSonora()
        testMaterializerSkipsUnreviewedStoryVideoCuts()
        testMaterializerPreventsDuplicateApplication()
        testVideoSonoraStaysWholeWithPersonVisibleAndMutedBroll()
        testOpeningUsesSeveralFilesInOrder()
        testCoverageNeverRepeatsSourceFootage()
        testApprovedStorySegmentsAreApplied()
        testNothingCutsSonoraWhenOverTarget()
        print("DirectorPlanningCore: 12 checks passed")
    }

    static func testInstitutionalPreservesImportOrderAndApproval() {
        let media = [
            DirectorMediaDescriptor(id: "b", name: "B.mp4", kind: .video, importOrder: 2, duration: 20),
            DirectorMediaDescriptor(id: "a", name: "A.mp4", kind: .video, importOrder: 1, duration: 20),
            DirectorMediaDescriptor(id: "v", name: "sonora.wav", kind: .audio, importOrder: 3, duration: 24)
        ]
        let draft = DirectorPlanningCore.buildInstitutionalDraft(media: media)
        let opening = draft.segments.filter { $0.role == .openingVisual }
        precondition(opening.first?.mediaID == "a", "Abertura deve respeitar a ordem de importação")
        precondition(abs(opening.reduce(0) { $0 + $1.duration } - 8) < 0.001, "Abertura deve somar oito segundos")
        let sonora = draft.segments.first { $0.role == .sonoraCandidate }
        precondition(sonora?.requiresReview == true, "Sonora exige aprovação")
        precondition(draft.isNonDestructive, "Rascunho não pode ser destrutivo")
    }

    static func testInstitutionalCoverageRunsUnderSonora() {
        let media = [
            DirectorMediaDescriptor(id: "opening", name: "abertura.mp4", kind: .video, importOrder: 1, duration: 8),
            DirectorMediaDescriptor(id: "coverage", name: "obra.mp4", kind: .video, importOrder: 2, duration: 16),
            DirectorMediaDescriptor(id: "speech", name: "morador.wav", kind: .audio, importOrder: 3, duration: 22)
        ]
        let draft = DirectorPlanningCore.buildInstitutionalDraft(media: media)
        let speech = draft.segments.first { $0.role == .sonoraCandidate }!
        let coverage = draft.segments.first { $0.role == .visualCoverage }!
        precondition(abs(speech.timelineStart - coverage.timelineStart) < 0.001, "B-roll deve começar junto da sonora")
        precondition(coverage.duration <= speech.duration, "Cobertura não deve exceder a sonora")
    }

    static func testStoriesVisualSegmentsNeverExceedFifteenSeconds() {
        let media = [DirectorMediaDescriptor(id: "v", name: "evento.mp4", kind: .video, importOrder: 1, duration: 37)]
        let draft = DirectorPlanningCore.buildStoriesDraft(media: media)
        let visuals = draft.segments.filter { $0.role == .storyVisual }
        precondition(visuals.count == 3, "Vídeo de 37 s deve gerar três segmentos visuais")
        precondition(visuals.allSatisfy { $0.duration <= 15 }, "Nenhum segmento visual pode ultrapassar 15 s")
        precondition(abs(visuals.reduce(0) { $0 + $1.duration } - 37) < 0.001, "Duração total precisa ser preservada")
    }

    static func testStoriesAudioCanExceedFifteenSeconds() {
        let media = [DirectorMediaDescriptor(id: "a", name: "fala.wav", kind: .audio, importOrder: 1, duration: 23)]
        let draft = DirectorPlanningCore.buildStoriesDraft(media: media)
        let audio = draft.segments.first { $0.role == .storyAudio }
        precondition(audio?.duration == 23, "Sonora pode ultrapassar quinze segundos")
        precondition(audio?.requiresReview == true, "Sonora exige revisão")
    }

    static func testMaterializerAppendsToEndAndKeepsFullSonora() {
        let media = [
            DirectorMediaDescriptor(id: "v1", name: "abertura.mp4", kind: .video, importOrder: 1, duration: 8),
            DirectorMediaDescriptor(id: "v2", name: "cobertura.mp4", kind: .video, importOrder: 2, duration: 12),
            DirectorMediaDescriptor(id: "a", name: "fala.wav", kind: .audio, importOrder: 3, duration: 23)
        ]
        let draft = DirectorPlanningCore.buildInstitutionalDraft(media: media)
        let instructions = DirectorTimelineMaterializer.makeInstructions(draft: draft, media: media, appendAt: 42)
        let audio = instructions.first { $0.mediaID == "a" }
        precondition(audio?.track == "voice", "Sonora em áudio deve ir para a trilha de voz, fora do ducking")
        precondition(audio?.duration == 23, "Sonora deve entrar inteira, sem corte automático")
        precondition((audio?.timelineStart ?? 0) >= 42, "Montagem deve ser acrescentada depois da timeline existente")
        precondition(instructions.contains { $0.track == "broll" }, "Cobertura deve usar trilha B-roll")
    }

    static func testMaterializerSkipsUnreviewedStoryVideoCuts() {
        let media = [DirectorMediaDescriptor(id: "v", name: "evento.mp4", kind: .video, importOrder: 1, duration: 37)]
        let draft = DirectorPlanningCore.buildStoriesDraft(media: media)
        let instructions = DirectorTimelineMaterializer.makeInstructions(draft: draft, media: media, appendAt: 0)
        precondition(instructions.isEmpty, "Trechos de vídeo com possível fala precisam de revisão antes de aplicar cortes")
    }

    static func testMaterializerPreventsDuplicateApplication() {
        let media = [DirectorMediaDescriptor(id: "v", name: "foto.jpg", kind: .image, importOrder: 1, duration: 5)]
        let draft = DirectorPlanningCore.buildInstitutionalDraft(media: media)
        let appliedID = draft.segments.first!.id
        let instructions = DirectorTimelineMaterializer.makeInstructions(draft: draft, media: media, appendAt: 0, alreadyApplied: [appliedID])
        precondition(!instructions.contains { $0.segmentID == appliedID }, "Segmento já aplicado não pode ser duplicado")
    }

    static func testVideoSonoraStaysWholeWithPersonVisibleAndMutedBroll() {
        let media = [
            DirectorMediaDescriptor(id: "b1", name: "obra.mp4", kind: .video, importOrder: 1, duration: 60),
            DirectorMediaDescriptor(id: "s", name: "morador.mp4", kind: .video, importOrder: 2, duration: 40, isSonora: true)
        ]
        let draft = DirectorPlanningCore.buildInstitutionalDraft(media: media)
        let sonora = draft.segments.first { $0.role == .sonoraCandidate }!
        precondition(sonora.duration == 40 && sonora.sourceIn == 0, "Sonora em vídeo entra inteira")
        let coverage = draft.segments.filter { $0.role == .visualCoverage }
        precondition(!coverage.isEmpty, "Deve haver B-roll sobre a sonora")
        let first = coverage.map(\.timelineStart).min()!
        precondition(abs(first - (sonora.timelineStart + 2.5)) < 0.001, "A pessoa aparece 2,5 s antes do B-roll")
        let last = coverage.map { $0.timelineStart + $0.duration }.max()!
        precondition(last <= sonora.timelineStart + sonora.duration - 2.5 + 0.001, "A pessoa aparece nos últimos 2,5 s")
        precondition(coverage.allSatisfy { $0.mediaID == "b1" }, "A própria sonora não vira B-roll")
        let sorted = coverage.sorted { $0.timelineStart < $1.timelineStart }
        let hasReturn = zip(sorted, sorted.dropFirst()).contains { $1.timelineStart - ($0.timelineStart + $0.duration) >= 2.4 }
        precondition(hasReturn, "A pessoa volta ao quadro no meio da fala")
        let instructions = DirectorTimelineMaterializer.makeInstructions(draft: draft, media: media, appendAt: 0)
        let speech = instructions.first { $0.mediaID == "s" }!
        precondition(speech.track == "video" && speech.volume == 1 && speech.duration == 40, "Sonora na trilha principal com áudio")
        precondition(instructions.filter { $0.track == "broll" }.allSatisfy { $0.volume == 0 }, "B-roll deve entrar mudo")
    }

    static func testOpeningUsesSeveralFilesInOrder() {
        let media = (1...4).map { DirectorMediaDescriptor(id: "v\($0)", name: "v\($0).mp4", kind: .video, importOrder: $0, duration: 30) }
        let draft = DirectorPlanningCore.buildInstitutionalDraft(media: media)
        let opening = draft.segments.filter { $0.role == .openingVisual }
        precondition(opening.map { $0.mediaID! } == ["v1", "v2", "v3", "v4"], "Abertura percorre os arquivos em ordem")
        precondition(abs(opening.reduce(0) { $0 + $1.duration } - 8) < 0.001, "Abertura soma oito segundos")
    }

    static func testCoverageNeverRepeatsSourceFootage() {
        let media = [
            DirectorMediaDescriptor(id: "b", name: "obra.mp4", kind: .video, importOrder: 1, duration: 30),
            DirectorMediaDescriptor(id: "s", name: "fala.wav", kind: .audio, importOrder: 2, duration: 60)
        ]
        let draft = DirectorPlanningCore.buildInstitutionalDraft(media: media)
        let uses = draft.segments.filter { $0.mediaID == "b" }.sorted { $0.sourceIn < $1.sourceIn }
        for (a, b) in zip(uses, uses.dropFirst()) {
            precondition(a.sourceIn + a.duration <= b.sourceIn + 0.001, "O mesmo trecho não pode se repetir")
        }
        precondition(draft.warnings.contains { $0.contains("acabaram") }, "Deve avisar quando as imagens acabam")
    }

    static func testApprovedStorySegmentsAreApplied() {
        let media = [DirectorMediaDescriptor(id: "v", name: "evento.mp4", kind: .video, importOrder: 1, duration: 37)]
        let draft = DirectorPlanningCore.buildStoriesDraft(media: media)
        let approved = Set(draft.segments.map(\.id))
        let instructions = DirectorTimelineMaterializer.makeInstructions(draft: draft, media: media, appendAt: 0, approvedSegmentIDs: approved)
        precondition(instructions.count == 3 && instructions.allSatisfy { $0.duration <= 15 }, "Trechos aprovados entram com no máximo 15 s")
    }

    static func testNothingCutsSonoraWhenOverTarget() {
        let media = [DirectorMediaDescriptor(id: "s", name: "longa.mp4", kind: .video, importOrder: 1, duration: 300, isSonora: true)]
        let draft = DirectorPlanningCore.buildInstitutionalDraft(media: media)
        precondition(draft.segments.first { $0.role == .sonoraCandidate }?.duration == 300, "Sonora longa não é cortada")
        precondition(draft.warnings.contains { $0.contains("acima") }, "Deve avisar que passou da duração")
    }
}
