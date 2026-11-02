import Foundation

/// Deterministic, fully local planning layer for the Director IA.
/// This is intentionally a rule-based foundation, not a claim that an on-device LLM is integrated.
struct LocalDirectorStep: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var requiresApproval: Bool = false
}

struct LocalDirectorPlan: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var originalCommand: String
    var profile: String
    var targetDuration: String
    var steps: [LocalDirectorStep]
    var warnings: [String]
    var timelineDraft: DirectorTimelineDraft? = nil
    var generatedAt: Date = .now

    var approvalCount: Int { steps.filter(\.requiresApproval).count }
}

enum LocalDirectorService {
    static func makePlan(command: String, project: EditorProject) -> LocalDirectorPlan {
        let normalized = command.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let isStories = normalized.contains("story") || normalized.contains("stories") || normalized.contains("reels")
        let isInstitutional = ["prefeitura", "institucional", "obra", "asfalto", "entrega", "evento", "acao", "saude", "educacao"]
            .contains(where: { normalized.contains($0) }) || project.profile.localizedCaseInsensitiveContains("institucional")
        let profile = isStories ? "Stories" : (isInstitutional ? "Institucional" : project.profile)
        let duration = isStories ? "Sequência de Stories: imagens até 15 s; sonoras relevantes podem ultrapassar" : (isInstitutional ? "1min30s a 2min" : "Definida pela narrativa")

        var steps: [LocalDirectorStep] = []
        var warnings: [String] = []

        if isStories {
            steps.append(.init(title: "Preservar a ordem de importação", detail: "Usar a sequência original como referência cronológica e intercalar apenas quando isso não alterar a continuidade."))
            steps.append(.init(title: "Montar sequência vertical", detail: "Preparar Stories em 9:16, com clipes visuais de até 15 segundos e exceção para sonoras que precisem manter o contexto."))
        } else if isInstitutional {
            steps.append(.init(title: "Abertura de aproximadamente 8 segundos", detail: "Apresentar imagens do evento em ordem de envio, combinando estrutura/ação, população e autoridades conforme o material disponível."))
            steps.append(.init(title: "Construir a narrativa com sonoras", detail: "Priorizar falas que expliquem a pauta. Intercalar 2 a 3 segundos de pessoa em quadro com imagens de cobertura, preservando o áudio."))
            steps.append(.init(title: "Encerramento institucional", detail: "Reservar a fala final da autoridade ou do prefeito quando fizer sentido, mantendo 2 a 3 segundos de presença em quadro no fechamento."))
        } else {
            steps.append(.init(title: "Analisar a mídia importada", detail: "Inventariar vídeos, imagens e áudios, mantendo a ordem de importação como referência inicial."))
            steps.append(.init(title: "Propor estrutura narrativa", detail: "Separar abertura, desenvolvimento e encerramento antes de alterar a timeline."))
        }

        steps.append(.init(title: "Preservar a ordem original", detail: "Os arquivos permanecem na ordem de importação. Reordenações narrativas são apenas sugestões até aprovação."))
        steps.append(.init(title: "Analisar falas e transcrições", detail: "Usar transcrições disponíveis no projeto; quando ainda não houver transcrição, sinalizar que a análise de conteúdo depende dessa etapa."))
        steps.append(.init(title: "Prévia obrigatória de cortes de fala", detail: "Mostrar texto, timecodes, contexto anterior/posterior e trecho proposto. Não executar cortes de sonora sem aprovação explícita.", requiresApproval: true))
        steps.append(.init(title: "Desenho sonoro", detail: "Propor trilha, efeitos e ducking depois de entender a pauta e as falas. Não inserir efeitos automaticamente em todos os cortes.", requiresApproval: true))

        if project.media.allSatisfy(\.isDerived) {
            warnings.append("Nenhuma mídia foi importada. O plano é apenas uma estrutura inicial.")
        } else {
            let source = project.media.filter { !$0.isDerived }
            let videoCount = source.filter { $0.kind == "Vídeo" }.count
            let audioCount = source.filter { $0.kind == "Áudio" }.count
            let sonoraCount = source.filter(\.isSonora).count
            warnings.append("Mídia disponível: \(source.count) arquivos, \(videoCount) vídeos, \(audioCount) áudios e \(sonoraCount) sonoras marcadas. A análise audiovisual profunda ainda depende dos modelos locais especializados.")
        }
        warnings.append("Este planejador é uma primeira camada determinística local. Um modelo de linguagem local ainda precisa ser integrado para compreensão livre e comandos complexos.")

        let descriptors = project.directorMedia
        let timelineDraft = isStories
            ? DirectorPlanningCore.buildStoriesDraft(media: descriptors)
            : (isInstitutional ? DirectorPlanningCore.buildInstitutionalDraft(media: descriptors) : nil)

        return LocalDirectorPlan(
            originalCommand: command.trimmingCharacters(in: .whitespacesAndNewlines),
            profile: profile,
            targetDuration: duration,
            steps: steps,
            warnings: warnings,
            timelineDraft: timelineDraft
        )
    }
}
