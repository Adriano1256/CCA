import Foundation

/// Platform-independent planning primitives. This file deliberately uses Foundation only
/// so the rules can be tested on Linux/macOS without an iOS SDK.
struct DirectorMediaDescriptor: Codable, Hashable {
    enum Kind: String, Codable { case video = "Vídeo", image = "Imagem", audio = "Áudio", unknown = "Desconhecido" }
    var id: String
    var name: String
    var kind: Kind
    var importOrder: Int
    var duration: Double?
    var isSonora: Bool = false
}

struct DirectorDraftSegment: Codable, Hashable, Identifiable {
    enum Role: String, Codable {
        case openingVisual
        case visualCoverage
        case visualSequence
        case sonoraCandidate
        case storyVisual
        case storyAudio
        case institutionalClosingPlaceholder
    }
    var id: String
    var mediaID: String?
    var mediaName: String
    var role: Role
    var sourceIn: Double
    var duration: Double
    var timelineStart: Double
    var preservesOriginalOrder: Bool
    var requiresReview: Bool
    var note: String
}

struct DirectorTimelineDraft: Codable, Hashable {
    var profile: String
    var targetMinimum: Double
    var targetMaximum: Double
    var segments: [DirectorDraftSegment]
    var warnings: [String]
    var isNonDestructive: Bool { true }
}

enum DirectorPlanningCore {
    /// Monta o padrão institucional: abertura de cerca de 8 s, sonoras inteiras com B-roll por cima
    /// (a pessoa aparece 2 a 3 s, a imagem cobre e ela volta em pontos regulares) e fechamento.
    static func buildInstitutionalDraft(
        media: [DirectorMediaDescriptor],
        openingDuration: Double = 8,
        personHold: Double = 2.5,
        coverageShot: Double = 4,
        returnEvery: Double = 12,
        targetMinimum: Double = 90,
        targetMaximum: Double = 120,
        openingCuts: [Double] = []
    ) -> DirectorTimelineDraft {
        let ordered = media.sorted { lhs, rhs in
            lhs.importOrder == rhs.importOrder ? lhs.id < rhs.id : lhs.importOrder < rhs.importOrder
        }
        let visuals = ordered.filter { $0.kind == .image || ($0.kind == .video && !$0.isSonora) }
        let sonoras = ordered.filter { $0.kind == .audio || ($0.kind == .video && $0.isSonora) }
        var segments: [DirectorDraftSegment] = []
        var used: [String: Double] = [:]
        var cursor = 0.0
        var serial = 0

        func available(_ item: DirectorMediaDescriptor) -> Double {
            max(0, (item.duration ?? 5) - (used[item.id] ?? 0))
        }

        func take(_ item: DirectorMediaDescriptor, seconds: Double, at start: Double, role: DirectorDraftSegment.Role, idPrefix: String, note: String) {
            serial += 1
            let sourceIn = used[item.id] ?? 0
            used[item.id] = sourceIn + seconds
            segments.append(DirectorDraftSegment(
                id: "\(idPrefix)-\(item.id)-\(serial)", mediaID: item.id, mediaName: item.name,
                role: role, sourceIn: sourceIn, duration: seconds, timelineStart: start,
                preservesOriginalOrder: true, requiresReview: false, note: note
            ))
        }

        // Abertura: planos curtos em ordem de importação, sem esgotar um único arquivo.
        var openingRemaining = max(0, openingDuration)
        let openingShot = visuals.isEmpty ? 0 : min(openingDuration, max(1.5, openingDuration / Double(visuals.count)))
        var madeProgress = true
        // Com música analisada, os cortes da abertura caem nas batidas.
        var plannedShots: [Double] = []
        var previousCut = 0.0
        for cut in openingCuts where cut > previousCut && cut < openingDuration {
            plannedShots.append(cut - previousCut)
            previousCut = cut
        }
        if !plannedShots.isEmpty { plannedShots.append(openingDuration - previousCut) }
        var shotIndex = 0
        while openingRemaining > 0.01 && madeProgress {
            madeProgress = false
            for item in visuals where openingRemaining > 0.01 {
                let free = available(item)
                guard free > 0.05 else { continue }
                let wanted = shotIndex < plannedShots.count ? plannedShots[shotIndex] : openingShot
                shotIndex += 1
                let seconds = min(openingRemaining, min(wanted, free))
                take(item, seconds: seconds, at: cursor, role: .openingVisual, idPrefix: "opening",
                     note: "Abertura visual em ordem de importação. O plano continua editável.")
                cursor += seconds
                openingRemaining -= seconds
                madeProgress = true
            }
        }

        // Cobertura percorre os visuais em ordem, sempre continuando de onde o arquivo parou.
        var coverageIndex = 0
        func nextCoverage() -> DirectorMediaDescriptor? {
            guard !visuals.isEmpty else { return nil }
            for _ in 0..<visuals.count {
                let candidate = visuals[coverageIndex % visuals.count]
                coverageIndex += 1
                if available(candidate) > 0.5 { return candidate }
            }
            return nil
        }

        var ranOutOfCoverage = false
        for item in sonoras {
            let duration = max(0.1, item.duration ?? 0.1)
            segments.append(DirectorDraftSegment(
                id: "sonora-\(item.id)", mediaID: item.id, mediaName: item.name,
                role: .sonoraCandidate, sourceIn: 0, duration: duration, timelineStart: cursor,
                preservesOriginalOrder: true, requiresReview: true,
                note: "Sonora preservada inteira. Qualquer corte só depois de transcrever, mostrar o trecho e aprovar."
            ))

            // Em vídeo a pessoa aparece no início e no fim; em áudio separado não há imagem dela.
            let hold = item.kind == .video ? max(0, personHold) : 0
            var time = cursor + hold
            let coverageEnd = cursor + duration - hold
            var coveredSinceReturn = 0.0
            while coverageEnd - time >= 0.5 {
                guard let candidate = nextCoverage() else { ranOutOfCoverage = true; break }
                let seconds = min(coverageShot, min(available(candidate), coverageEnd - time))
                take(candidate, seconds: seconds, at: time, role: .visualCoverage, idPrefix: "coverage",
                     note: "Imagem de apoio sobre a fala, em ordem de importação. O áudio da pessoa continua. Confirme se a imagem combina com o assunto.")
                time += seconds
                coveredSinceReturn += seconds
                if hold > 0 && coveredSinceReturn >= returnEvery {
                    time += hold
                    coveredSinceReturn = 0
                }
            }
            cursor += duration
        }

        // Sem sonoras suficientes, completa a trilha principal até a duração mínima.
        while cursor < targetMinimum, let candidate = nextCoverage() {
            let seconds = min(coverageShot, min(available(candidate), targetMinimum - cursor))
            guard seconds > 0.05 else { break }
            take(candidate, seconds: seconds, at: cursor, role: .visualSequence, idPrefix: "sequence",
                 note: "Sequência visual em ordem de importação.")
            cursor += seconds
        }

        segments.append(DirectorDraftSegment(
            id: "institutional-closing", mediaID: nil, mediaName: "Encerramento institucional",
            role: .institutionalClosingPlaceholder, sourceIn: 0, duration: 3, timelineStart: cursor,
            preservesOriginalOrder: true, requiresReview: true,
            note: "Reservar 2 a 3 segundos da autoridade ou do prefeito em quadro. Não inventar nem selecionar uma fala sem identificação."
        ))

        var warnings: [String] = []
        if visuals.isEmpty { warnings.append("Não há vídeos ou imagens de apoio para construir a abertura visual.") }
        if sonoras.isEmpty { warnings.append("Nenhuma sonora marcada. Na aba Mídia, marque os vídeos ou áudios que têm fala para eles entrarem inteiros.") }
        if ranOutOfCoverage { warnings.append("As imagens de apoio acabaram antes do fim das sonoras. Parte da fala fica sem cobertura.") }
        if cursor > targetMaximum {
            warnings.append(String(format: "A montagem tem %.0f s, acima dos %.0f s desejados. Nenhuma sonora foi cortada; decida na timeline o que encurtar.", cursor, targetMaximum))
        } else if cursor < targetMinimum {
            warnings.append(String(format: "A montagem tem %.0f s, abaixo dos %.0f s desejados. Faltou material.", cursor, targetMinimum))
        }
        warnings.append("A ordem de importação é preservada. Este rascunho não corta nem altera arquivos originais.")

        return DirectorTimelineDraft(profile: "Institucional", targetMinimum: targetMinimum, targetMaximum: targetMaximum, segments: segments, warnings: warnings)
    }

    static func buildStoriesDraft(media: [DirectorMediaDescriptor], maximumVisualDuration: Double = 15) -> DirectorTimelineDraft {
        let ordered = media.sorted { lhs, rhs in
            lhs.importOrder == rhs.importOrder ? lhs.id < rhs.id : lhs.importOrder < rhs.importOrder
        }
        let cap = max(1, maximumVisualDuration)
        var segments: [DirectorDraftSegment] = []
        var cursor = 0.0

        for item in ordered {
            let duration = max(0.1, item.duration ?? (item.kind == .image ? 5 : 15))
            if item.kind == .audio || (item.kind == .video && item.isSonora) {
                segments.append(DirectorDraftSegment(
                    id: "story-audio-\(item.id)", mediaID: item.id, mediaName: item.name,
                    role: .storyAudio, sourceIn: 0, duration: duration, timelineStart: cursor,
                    preservesOriginalOrder: true, requiresReview: true,
                    note: "Preservar a sonora e seu contexto. A duração pode ultrapassar 15 segundos quando a fala relevante exigir."
                ))
                cursor += duration
                continue
            }

            var source = 0.0
            var part = 1
            while source < duration - 0.0001 {
                let chunk = min(cap, duration - source)
                segments.append(DirectorDraftSegment(
                    id: "story-\(item.id)-\(part)", mediaID: item.id, mediaName: item.name,
                    role: .storyVisual, sourceIn: source, duration: chunk, timelineStart: cursor,
                    preservesOriginalOrder: true, requiresReview: item.kind == .video,
                    note: item.kind == .video
                        ? "Trecho visual limitado a 15 segundos. Verificar fala relevante antes de fechar; se houver sonora que precise de contexto, preservar a fala mesmo que ultrapasse o limite."
                        : "Imagem estática limitada a 15 segundos."
                ))
                source += chunk
                cursor += chunk
                part += 1
            }
        }

        var warnings: [String] = []
        if ordered.isEmpty { warnings.append("Nenhuma mídia foi importada para a sequência de Stories.") }
        warnings.append("A sequência respeita a ordem de importação. Vídeos precisam de análise de fala antes de confirmar a duração final.")
        warnings.append("Este é um rascunho não destrutivo: nenhum arquivo original foi cortado ou alterado.")
        return DirectorTimelineDraft(profile: "Stories", targetMinimum: cursor, targetMaximum: cursor, segments: segments, warnings: warnings)
    }
}
