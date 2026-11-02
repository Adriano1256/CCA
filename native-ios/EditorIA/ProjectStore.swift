import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ProjectSummary: Identifiable, Hashable {
    var id: UUID
    var name: String
    var updatedAt: Date
    var clipCount: Int
}

@MainActor
final class ProjectStore: ObservableObject {
    static let maximumMaskFrames = 360

    @Published var project = EditorProject()
    @Published var selectedMediaID: UUID?
    @Published var selectedClipID: UUID?
    @Published var playhead: Double = 0
    @Published var status = "Projeto armazenado no dispositivo"
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var projects: [ProjectSummary] = []
    @Published private(set) var isImporting = false

    private var undoStack: [EditorProject] = []
    private var redoStack: [EditorProject] = []
    private let historyLimit = 40
    private let fileManager = FileManager.default
    private var lastUndoKey: String?
    private var lastUndoDate = Date.distantPast
    private let currentProjectDefaultsKey = "EditorIA.currentProjectID"

    var selectedMedia: LocalMedia? {
        project.media.first(where: { $0.id == selectedMediaID })
    }

    func urlForMedia(_ item: LocalMedia) -> URL {
        projectDirectory.appendingPathComponent(item.relativePath)
    }

    var selectedClip: TimelineClip? {
        project.clips.first(where: { $0.id == selectedClipID })
    }

    var timelineDuration: Double { max(30, project.contentEnd) }

    /// Pasta base; `LocalMedia.relativePath` é relativo a ela ("Media/arquivo.mov").
    var baseDirectoryURL: URL { projectDirectory }
    var mediaDirectoryURL: URL { mediaDirectory }

    private var projectDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EditorIA", isDirectory: true)
    }

    private var mediaDirectory: URL {
        projectDirectory.appendingPathComponent("Media", isDirectory: true)
    }

    private var projectsDirectory: URL {
        projectDirectory.appendingPathComponent("Projects", isDirectory: true)
    }

    private var legacyProjectFile: URL {
        projectDirectory.appendingPathComponent("project.json")
    }

    private func projectFile(for id: UUID) -> URL {
        projectsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    init() {
        do {
            try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            excludeFromBackup(projectDirectory)
            loadClients()
            loadInitialProject()
        } catch {
            status = "Não foi possível preparar o armazenamento local"
        }
    }

    /// Vídeos ficam só no aparelho: nada de mídia indo para o backup do iCloud.
    private func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    // MARK: - Projetos

    func refreshProjects() {
        let files = (try? fileManager.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)) ?? []
        let decoder = makeDecoder()
        projects = files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let item = try? decoder.decode(EditorProject.self, from: data) else { return nil }
            return ProjectSummary(id: item.id, name: item.name, updatedAt: item.updatedAt, clipCount: item.clips.count)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func createProject(named name: String) {
        saveProject()
        var next = EditorProject()
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { next.name = cleaned }
        activate(next)
        saveProject()
        refreshProjects()
        status = "Projeto criado"
    }

    func openProject(_ id: UUID) {
        guard id != project.id else { return }
        saveProject()
        do {
            let data = try Data(contentsOf: projectFile(for: id))
            activate(try makeDecoder().decode(EditorProject.self, from: data))
            status = "Projeto aberto"
        } catch {
            status = "Não foi possível abrir o projeto: \(error.localizedDescription)"
        }
        refreshProjects()
    }

    func renameCurrentProject(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != project.name else { return }
        project.name = cleaned
        saveProject()
        refreshProjects()
    }

    /// Apaga o projeto e os arquivos de mídia que nenhum outro projeto usa.
    func deleteProject(_ id: UUID) {
        let decoder = makeDecoder()
        guard let data = try? Data(contentsOf: projectFile(for: id)),
              let doomed = try? decoder.decode(EditorProject.self, from: data) else { return }
        try? fileManager.removeItem(at: projectFile(for: id))
        let files = (try? fileManager.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)) ?? []
        var stillUsed = Set<String>()
        for file in files where file.pathExtension == "json" {
            if let content = try? Data(contentsOf: file), let other = try? decoder.decode(EditorProject.self, from: content) {
                stillUsed.formUnion(other.media.map(\.relativePath))
            }
        }
        for item in doomed.media where !stillUsed.contains(item.relativePath) {
            try? fileManager.removeItem(at: urlForMedia(item))
        }
        if id == project.id {
            refreshProjects()
            if let newest = projects.first, let content = try? Data(contentsOf: projectFile(for: newest.id)),
               let next = try? decoder.decode(EditorProject.self, from: content) {
                activate(next)
            } else {
                activate(EditorProject())
                saveProject()
            }
        }
        refreshProjects()
        status = "Projeto apagado"
    }

    private func activate(_ next: EditorProject) {
        project = next
        selectedMediaID = nil
        selectedClipID = nil
        playhead = 0
        undoStack.removeAll()
        redoStack.removeAll()
        lastUndoKey = nil
        refreshHistoryAvailability()
        UserDefaults.standard.set(next.id.uuidString, forKey: currentProjectDefaultsKey)
    }

    private func loadInitialProject() {
        // O formato antigo guardava um único project.json; ele vira um projeto da lista.
        if fileManager.fileExists(atPath: legacyProjectFile.path),
           let data = try? Data(contentsOf: legacyProjectFile),
           let legacy = try? makeDecoder().decode(EditorProject.self, from: data) {
            project = legacy
            saveProject()
            try? fileManager.removeItem(at: legacyProjectFile)
        }
        refreshProjects()
        let saved = UserDefaults.standard.string(forKey: currentProjectDefaultsKey).flatMap(UUID.init(uuidString:))
        let target = projects.first(where: { $0.id == saved })?.id ?? projects.first?.id
        if let target, let data = try? Data(contentsOf: projectFile(for: target)),
           let loaded = try? makeDecoder().decode(EditorProject.self, from: data) {
            activate(loaded)
            status = "Projeto local recuperado"
        } else {
            activate(EditorProject())
            saveProject()
            refreshProjects()
        }
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Importação

    /// Copia os arquivos na ordem recebida. `moveFiles` move em vez de copiar (arquivos temporários da Fototeca).
    func importFiles(_ urls: [URL], moveFiles: Bool = false) async {
        guard !isImporting else { status = "Aguarde a importação em andamento"; return }
        isImporting = true
        defer { isImporting = false }
        recordUndo()
        var imported = 0
        for (position, sourceURL) in urls.enumerated() {
            status = "Importando \(position + 1) de \(urls.count)…"
            let hasAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }

            do {
                let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
                let destination = mediaDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
                // Arquivos de vários GB não podem travar a interface.
                try await Task.detached(priority: .userInitiated) {
                    if moveFiles {
                        try FileManager.default.moveItem(at: sourceURL, to: destination)
                    } else {
                        try FileManager.default.copyItem(at: sourceURL, to: destination)
                    }
                }.value

                let contentType = values.contentType
                let kind: String
                if contentType?.conforms(to: .movie) == true || contentType?.conforms(to: .video) == true {
                    kind = "Vídeo"
                } else if contentType?.conforms(to: .audio) == true {
                    kind = "Áudio"
                } else {
                    kind = "Imagem"
                }

                let duration: Double
                if kind == "Imagem" {
                    duration = 5
                } else {
                    let asset = AVURLAsset(url: destination)
                    let loadedDuration = try? await asset.load(.duration)
                    duration = max(0.5, loadedDuration?.seconds ?? 10)
                }
                let item = LocalMedia(
                    name: sourceURL.lastPathComponent,
                    relativePath: "Media/\(destination.lastPathComponent)",
                    kind: kind,
                    byteCount: Int64(values.fileSize ?? 0),
                    importOrder: project.media.count + 1,
                    duration: duration
                )
                project.media.append(item)
                let track = kind == "Áudio" ? "audio" : "video"
                let timelineStart = project.clips.filter { $0.track == track }.map(\.end).max() ?? 0
                let initialVolume = track == "audio" ? 0.28 : 1.0
                let clip = TimelineClip(mediaID: item.id, track: track, start: timelineStart, duration: duration, volume: initialVolume, label: item.name)
                project.clips.append(clip)
                selectedMediaID = item.id
                selectedClipID = clip.id
                imported += 1
            } catch {
                status = "Falha ao importar \(sourceURL.lastPathComponent): \(error.localizedDescription)"
            }
        }
        saveProject()
        refreshProjects()
        if imported > 0 { status = "\(imported) arquivo(s) no armazenamento local" }
    }

    /// Marca um arquivo como sonora. Áudio marcado sai da trilha musical e deixa de sofrer ducking.
    func setSonora(_ mediaID: UUID, _ isSonora: Bool) {
        guard let index = project.media.firstIndex(where: { $0.id == mediaID }) else { return }
        recordUndo()
        project.media[index].isSonora = isSonora
        if project.media[index].kind == "Áudio" {
            for clipIndex in project.clips.indices where project.clips[clipIndex].mediaID == mediaID {
                project.clips[clipIndex].track = isSonora ? "voice" : "audio"
                project.clips[clipIndex].volume = isSonora ? 1.0 : 0.28
            }
        }
        status = isSonora ? "Marcado como sonora. A fala será preservada inteira." : "Marcação de sonora removida"
        saveProject()
    }

    func setCaptionStyle(_ style: String) {
        guard project.captionStyle != style else { return }
        recordUndo()
        project.captionStyle = style
        saveProject()
    }

    func setProfile(_ profile: String) {
        guard project.profile != profile else { return }
        recordUndo()
        project.profile = profile
        saveProject()
    }

    private func mediaDuration(for clip: TimelineClip) -> Double? {
        guard let media = project.media.first(where: { $0.id == clip.mediaID }), media.kind != "Imagem" else { return nil }
        return media.duration
    }

    private func isStill(_ clip: TimelineClip) -> Bool {
        project.media.first(where: { $0.id == clip.mediaID })?.kind == "Imagem"
    }

    func selectClip(_ clip: TimelineClip) {
        selectedClipID = clip.id
        selectedMediaID = clip.mediaID
        // Mantém o cursor se ele já está dentro do clipe, para poder dividir ali.
        if playhead < clip.start || playhead > clip.end { playhead = clip.start }
    }

    func splitSelectedClip() {
        guard let clip = selectedClip else { status = "Selecione um clipe primeiro"; return }
        guard let parts = TimelineEditing.split(clip, at: playhead),
              let index = project.clips.firstIndex(where: { $0.id == clip.id }) else {
            status = "Posicione o cursor dentro do clipe, longe das extremidades"
            return
        }
        recordUndo()
        project.clips[index] = parts.left
        project.clips.insert(parts.right, at: index + 1)
        selectedClipID = parts.right.id
        status = "Clipe dividido no ponto \(timecode(playhead))"
        saveProject()
    }

    /// Remove o clipe e fecha o buraco na mesma trilha.
    func rippleDeleteSelectedClip() {
        guard let id = selectedClipID else { status = "Selecione um clipe primeiro"; return }
        recordUndo()
        project.clips = TimelineEditing.rippleDelete(id, in: project.clips)
        selectedClipID = nil
        status = "Clipe removido e espaço fechado. Arquivo original preservado."
        saveProject()
    }

    func deleteSelectedClip() {
        guard let id = selectedClipID else { status = "Selecione um clipe primeiro"; return }
        recordUndo()
        project.clips.removeAll { $0.id == id }
        selectedClipID = nil
        status = "Clipe removido da timeline. Arquivo original preservado."
        saveProject()
    }

    func duplicateSelectedClip() {
        guard let clip = selectedClip else { status = "Selecione um clipe primeiro"; return }
        recordUndo()
        var copy = clip
        copy.id = UUID()
        copy.start = clip.end
        copy.label += " cópia"
        project.clips.append(copy)
        selectedClipID = copy.id
        status = "Clipe duplicado"
        saveProject()
    }

    func trimSelectedStart(by seconds: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = project.clips[index]
        let next = TimelineEditing.trimStart(clip, by: seconds, isStill: isStill(clip))
        guard abs(next.duration - clip.duration) > 0.001 else { return }
        recordUndo()
        project.clips[index] = next
        status = "Ponto de entrada ajustado"
        saveProject()
    }

    func trimSelectedEnd(by seconds: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = project.clips[index]
        let next = TimelineEditing.trimEnd(clip, by: seconds, sourceDuration: mediaDuration(for: clip))
        guard abs(next.duration - clip.duration) > 0.001 else { return }
        recordUndo()
        project.clips[index] = next
        status = "Ponto de saída ajustado"
        saveProject()
    }

    /// Move o clipe arrastado, encaixando no cursor e nas pontas dos outros clipes.
    func moveSelectedClip(toStart proposed: Double, snapTolerance: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        let others = project.clips.filter { $0.id != id }
        let candidates: [Double] = [0, playhead] + others.flatMap { [$0.start, $0.end] }
        let duration = project.clips[index].duration
        let snappedStart = TimelineEditing.snap(proposed, to: candidates, tolerance: snapTolerance)
        let snappedEnd = TimelineEditing.snap(proposed + duration, to: candidates, tolerance: snapTolerance) - duration
        let next = max(0, abs(snappedStart - proposed) <= abs(snappedEnd - proposed) && snappedStart != proposed ? snappedStart : snappedEnd)
        guard abs(next - project.clips[index].start) > 0.001 else { return }
        recordUndo()
        project.clips[index].start = next
        status = "Clipe movido"
        saveProject()
    }

    func setSelectedClipVolume(_ value: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        let next = min(2, max(0, value))
        guard abs(project.clips[index].volume - next) > 0.001 else { return }
        recordUndo(coalescing: "volume-\(id)")
        project.clips[index].volume = next
        status = "Volume do clipe ajustado"
        saveProject()
    }

    func adjustSelectedFadeIn(by seconds: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        let clip = project.clips[index]
        project.clips[index].fadeIn = min(max(0, clip.duration / 2), max(0, clip.fadeIn + seconds))
        status = "Fade in ajustado"
        saveProject()
    }

    func adjustSelectedFadeOut(by seconds: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        let clip = project.clips[index]
        project.clips[index].fadeOut = min(max(0, clip.duration / 2), max(0, clip.fadeOut + seconds))
        status = "Fade out ajustado"
        saveProject()
    }

    func addKeyframe(property: String, value: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = project.clips[index]
        let localTime = min(clip.duration, max(0, playhead - clip.start))
        recordUndo()
        if let existing = project.clips[index].keyframes.firstIndex(where: { $0.property == property && abs($0.time - localTime) < 0.02 }) {
            project.clips[index].keyframes[existing].value = value
        } else {
            project.clips[index].keyframes.append(ClipKeyframe(property: property, time: localTime, value: value))
        }
        project.clips[index].keyframes.sort { $0.time < $1.time }
        status = "Keyframe de \(property) adicionado em \(timecode(localTime))"
        saveProject()
    }

    func removeKeyframes(property: String) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        project.clips[index].keyframes.removeAll { $0.property == property }
        status = "Keyframes de \(property) removidos"
        saveProject()
    }

    func moveSelectedClip(by seconds: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        project.clips[index].start = max(0, project.clips[index].start + seconds)
        status = "Posição do clipe ajustada"
        saveProject()
    }

    func adjustSelectedDuration(by seconds: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        let clip = project.clips[index]
        let sourceDuration = mediaDuration(for: clip) ?? .greatestFiniteMagnitude
        let nextDuration = min(max(0.5, sourceDuration - clip.sourceIn), max(0.5, clip.duration + seconds))
        project.clips[index].duration = nextDuration
        project.clips[index].keyframes.removeAll { $0.time > nextDuration }
        status = "Duração do clipe ajustada"
        saveProject()
    }

    func changeSelectedTrack(_ track: String) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        project.clips[index].track = track
        status = "Trilha do clipe alterada"
        saveProject()
    }

    func renameSelectedClip(_ name: String) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(coalescing: "rename-\(id)")
        project.clips[index].label = name
        saveProject()
    }

    /// Aplica o rascunho do Diretor como clipes editáveis. Com `replaceExisting` a montagem substitui
    /// a timeline (reversível com Desfazer); caso contrário entra depois do conteúdo atual.
    /// Sonoras entram inteiras: esta operação não corta nenhuma fala.
    @discardableResult
    func applyDirectorDraft(_ draft: DirectorTimelineDraft, replaceExisting: Bool = false, approvedSegmentIDs: Set<String> = []) -> Int {
        let alreadyApplied: Set<String> = replaceExisting ? [] : Set(project.clips.compactMap { clip -> String? in
            guard let start = clip.label.range(of: "[IASEG:"),
                  let end = clip.label.range(of: "]", range: start.upperBound..<clip.label.endIndex) else { return nil }
            return String(clip.label[start.upperBound..<end.lowerBound])
        })
        let existingEnd = replaceExisting ? 0 : project.contentEnd
        let instructions = DirectorTimelineMaterializer.makeInstructions(
            draft: draft,
            media: project.directorMedia,
            appendAt: existingEnd,
            alreadyApplied: alreadyApplied,
            approvedSegmentIDs: approvedSegmentIDs
        )
        guard !instructions.isEmpty else {
            status = "Nenhum trecho para aplicar. Trechos de vídeo que exigem revisão precisam da sua aprovação."
            return 0
        }

        recordUndo()
        if replaceExisting {
            let manualMusic = project.clips.filter { $0.track == "audio" || $0.track == "sfx" }
            project.clips = manualMusic
        }
        for instruction in instructions {
            guard let mediaID = UUID(uuidString: instruction.mediaID) else { continue }
            let clip = TimelineClip(
                mediaID: mediaID,
                track: instruction.track,
                start: instruction.timelineStart,
                duration: instruction.duration,
                sourceIn: instruction.sourceIn,
                volume: instruction.volume,
                label: instruction.label
            )
            project.clips.append(clip)
        }
        project.profile = draft.profile
        selectedClipID = nil
        playhead = existingEnd
        status = "\(instructions.count) trecho(s) do Diretor IA na timeline, editáveis. Falas preservadas."
        saveProject()
        return instructions.count
    }

    func transcribeSelectedClip() async {
        guard let clip = selectedClip,
              let media = project.media.first(where: { $0.id == clip.mediaID }) else {
            status = "Selecione um clipe de vídeo ou áudio para transcrever"
            return
        }
        guard media.kind == "Vídeo" || media.kind == "Áudio" else {
            status = "Selecione um vídeo ou áudio, não uma imagem"
            return
        }
        let url = urlForMedia(media)
        status = "Transcrevendo localmente em português..."
        do {
            let segments = try await LocalTranscriptionService.transcribe(url: url, localeIdentifier: "pt-BR")
            let lowerBound = clip.sourceIn
            let upperBound = clip.sourceIn + clip.duration
            let words = segments.compactMap { segment -> CaptionWord? in
                let segmentStart = segment.start
                let segmentEnd = segment.start + segment.duration
                guard segmentEnd > lowerBound, segmentStart < upperBound else { return nil }
                let clippedStart = max(segmentStart, lowerBound)
                let clippedEnd = min(segmentEnd, upperBound)
                let timelineStart = clip.start + (clippedStart - lowerBound)
                let wordText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !wordText.isEmpty, clippedEnd > clippedStart else { return nil }
                return CaptionWord(text: wordText, start: timelineStart, duration: max(0.12, clippedEnd - clippedStart))
            }
            guard !words.isEmpty else {
                status = "Nenhuma fala foi identificada no trecho selecionado"
                return
            }
            recordUndo()
            project.captionWords.removeAll { $0.start >= clip.start && $0.start < clip.end }
            project.captionWords.append(contentsOf: words)
            project.captionWords.sort { $0.start < $1.start }
            status = "Transcrição local concluída: \(words.count) palavras/trechos sincronizados"
            saveProject()
        } catch {
            status = error.localizedDescription
        }
    }

    func setAutomaticDucking(_ enabled: Bool) {
        guard project.automaticDucking != enabled else { return }
        recordUndo()
        project.automaticDucking = enabled
        status = enabled ? "Redução automática da música ativada" : "Redução automática da música desativada"
        saveProject()
    }

    func setDuckingLevel(_ level: Double) {
        let next = min(0.8, max(0.05, level))
        guard abs(project.duckingLevel - next) > 0.005 else { return }
        recordUndo(coalescing: "ducking")
        project.duckingLevel = next
        status = "Intensidade do ducking atualizada"
        saveProject()
    }

    func clearCaptionWords() {
        guard !project.captionWords.isEmpty else { return }
        recordUndo()
        project.captionWords.removeAll()
        status = "Legendas removidas do projeto"
        saveProject()
    }

    /// Aplica as máscaras amostradas de um vídeo como uma sequência de camadas transparentes.
    /// Cada PNG ocupa o intervalo até a próxima amostra. É uma composição inicial offline;
    /// a qualidade temporal depende da taxa de amostragem usada na segmentação.
    func addVideoPersonSequence(manifestURL: URL, basedOn sourceClip: TimelineClip) throws -> Int {
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(VideoPersonSegmentationService.Manifest.self, from: data)
        let sourceEnd = sourceClip.sourceIn + sourceClip.duration
        let frames = manifest.frames
            .filter { $0.time >= sourceClip.sourceIn && $0.time < sourceEnd }
            .sorted { $0.time < $1.time }
        guard !frames.isEmpty else {
            throw NSError(domain: "EditorIA.Segmentation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Não há máscaras dentro do trecho selecionado."])
        }
        // Cada máscara é uma imagem carregada na exportação; acima disso o aparelho fica sem memória.
        guard frames.count <= Self.maximumMaskFrames else {
            throw NSError(domain: "EditorIA.Segmentation", code: 4, userInfo: [NSLocalizedDescriptionKey: "Trecho longo demais para o recorte: \(frames.count) máscaras (limite de \(Self.maximumMaskFrames)). Divida o clipe e use um trecho de até 1 minuto."])
        }

        recordUndo()
        let folderName = "SubjectFrames-\(UUID().uuidString)"
        let destinationFolder = mediaDirectory.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        var inserted = 0

        for (index, frame) in frames.enumerated() {
            let sourceFrameURL = manifestURL.deletingLastPathComponent().appendingPathComponent(frame.file)
            guard FileManager.default.fileExists(atPath: sourceFrameURL.path) else { continue }
            let nextTime = index + 1 < frames.count ? frames[index + 1].time : frame.time + (1.0 / max(1, manifest.sampleRate))
            let frameDuration = min(max(0.04, nextTime - frame.time), max(0.04, sourceEnd - frame.time))
            guard frameDuration > 0 else { continue }

            let filename = String(format: "subject-%06d-\(UUID().uuidString.prefix(8)).png", index + 1)
            let destinationURL = destinationFolder.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: sourceFrameURL, to: destinationURL)
            let relativePath = "Media/\(folderName)/\(filename)"
            let byteCount = ((try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
            let media = LocalMedia(
                name: "Máscara de pessoa \(index + 1)",
                relativePath: relativePath,
                kind: "Imagem",
                byteCount: byteCount,
                importOrder: project.media.count + 1,
                duration: frameDuration,
                isDerived: true
            )
            project.media.append(media)
            let timelineClip = TimelineClip(
                mediaID: media.id,
                track: "subject",
                start: sourceClip.start + (frame.time - sourceClip.sourceIn),
                duration: frameDuration,
                label: "Pessoa • quadro \(index + 1)"
            )
            project.clips.append(timelineClip)
            inserted += 1
        }

        guard inserted > 0 else {
            throw NSError(domain: "EditorIA.Segmentation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Nenhuma máscara pôde ser adicionada à timeline."])
        }
        status = "Sequência de pessoa aplicada à timeline: \(inserted) quadros. A suavidade depende da amostragem."
        try? FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent())
        saveProject()
        return inserted
    }

    func addPersonCutout(data: Data, basedOn sourceClip: TimelineClip, originalName: String) throws {
        guard let image = UIImage(data: data), let png = image.pngData() else {
            throw NSError(domain: "EditorIA.Segmentation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Imagem recortada inválida."])
        }
        recordUndo()
        let filename = "subject-\(UUID().uuidString).png"
        let destination = mediaDirectory.appendingPathComponent(filename)
        try png.write(to: destination, options: .atomic)
        let item = LocalMedia(
            name: "Pessoa recortada • \(originalName)",
            relativePath: "Media/\(filename)",
            kind: "Imagem",
            byteCount: Int64(png.count),
            importOrder: project.media.count + 1,
            duration: sourceClip.duration,
            isDerived: true
        )
        project.media.append(item)
        let cutoutClip = TimelineClip(
            mediaID: item.id,
            track: "subject",
            start: sourceClip.start,
            duration: sourceClip.duration,
            label: "Pessoa recortada"
        )
        project.clips.append(cutoutClip)
        selectedMediaID = item.id
        selectedClipID = cutoutClip.id
        status = "Pessoa recortada localmente. A camada foi colocada acima dos textos."
        saveProject()
    }

    func addTextOverlay(_ text: String, duration: Double = 3, animation: String = "fade") {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { status = "Digite um texto antes de adicionar"; return }
        recordUndo()
        let overlay = TextOverlay(text: cleaned, start: playhead, duration: max(0.5, duration), animation: animation)
        project.overlays.append(overlay)
        project.overlays.sort { $0.start < $1.start }
        status = "Texto adicionado à composição"
        saveProject()
    }

    func beginTextOverlayEdit() {
        recordUndo()
    }

    func updateTextOverlay(_ overlay: TextOverlay, registerUndo: Bool = true) {
        guard let index = project.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        if registerUndo { recordUndo() }
        project.overlays[index] = overlay
        project.overlays.sort { $0.start < $1.start }
        status = "Texto atualizado"
        saveProject()
    }

    func deleteTextOverlay(_ id: UUID) {
        guard project.overlays.contains(where: { $0.id == id }) else { return }
        recordUndo()
        project.overlays.removeAll { $0.id == id }
        status = "Texto removido da composição"
        saveProject()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        lastUndoKey = nil
        redoStack.append(project)
        project = previous
        refreshHistoryAvailability()
        status = "Última alteração desfeita"
        saveProject()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        project = next
        refreshHistoryAvailability()
        status = "Alteração refeita"
        saveProject()
    }

    /// `coalescing` junta ajustes contínuos (como um slider) em um único passo de desfazer.
    private func recordUndo(coalescing key: String? = nil) {
        if let key, key == lastUndoKey, Date().timeIntervalSince(lastUndoDate) < 1.5 {
            lastUndoDate = Date()
            return
        }
        lastUndoKey = key
        lastUndoDate = Date()
        undoStack.append(project)
        if undoStack.count > historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        refreshHistoryAvailability()
    }

    private func refreshHistoryAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// Salva sem trocar a mensagem de status, para não apagar o resultado da última ação.
    func saveProject() {
        do {
            project.updatedAt = .now
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(project)
            try data.write(to: projectFile(for: project.id), options: .atomic)
        } catch {
            status = "Erro ao salvar projeto: \(error.localizedDescription)"
        }
    }

    // MARK: - Aparência do clipe

    /// Ajusta a aparência do clipe selecionado. Vários ajustes seguidos viram um só passo de desfazer.
    func updateSelectedLook(_ key: String, _ change: (inout ClipLook) -> Void) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(coalescing: "look-\(key)-\(id)")
        change(&project.clips[index].look)
        saveProject()
    }

    func copySelectedColorToTrack() {
        guard let clip = selectedClip else { return }
        recordUndo()
        for index in project.clips.indices where project.clips[index].track == clip.track {
            let source = clip.look
            project.clips[index].look.exposure = source.exposure
            project.clips[index].look.contrast = source.contrast
            project.clips[index].look.saturation = source.saturation
            project.clips[index].look.temperature = source.temperature
            project.clips[index].look.tint = source.tint
            project.clips[index].look.shadows = source.shadows
            project.clips[index].look.highlights = source.highlights
            project.clips[index].look.lutRelativePath = source.lutRelativePath
            project.clips[index].look.lutIntensity = source.lutIntensity
        }
        status = "Cor aplicada a toda a trilha"
        saveProject()
    }

    func setSelectedSpeed(_ speed: Double) {
        guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(coalescing: "speed-\(id)")
        project.clips[index] = TimelineEditing.setSpeed(project.clips[index], to: speed)
        saveProject()
    }

    func addTransitionToSelected(kind: String, duration: Double) {
        guard let id = selectedClipID else { return }
        guard let next = TimelineEditing.addTransition(to: id, kind: kind, duration: duration, in: project.clips) else {
            status = "Transição precisa de um clipe logo antes, na mesma trilha"
            return
        }
        recordUndo()
        project.clips = next
        status = "Transição aplicada"
        saveProject()
    }

    /// Guarda o LUT junto da mídia e aplica ao clipe selecionado.
    func importLUT(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            _ = try CubeLUT.parse(text)
            let folder = projectDirectory.appendingPathComponent("LUTs", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            try? fileManager.removeItem(at: destination)
            try text.write(to: destination, atomically: true, encoding: .utf8)
            updateSelectedLook("lut") { $0.lutRelativePath = "LUTs/\(url.lastPathComponent)" }
            status = "LUT \(url.lastPathComponent) aplicado"
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: - Corte de fala aprovado

    /// Só é chamado depois de o usuário ver a transcrição e aprovar.
    func applyApprovedSpeechCut(clipID: UUID, range: AudioDuckingRange) {
        guard let next = TimelineEditing.cut(clipID, removing: range, in: project.clips) else {
            status = "Trecho fora do clipe"
            return
        }
        recordUndo()
        project.clips = next
        let removed = range.end - range.start
        project.captionWords = project.captionWords.compactMap { word in
            let center = word.start + word.duration / 2
            if center >= range.start && center <= range.end { return nil }
            var moved = word
            if word.start >= range.end { moved.start = max(0, word.start - removed) }
            return moved
        }
        selectedClipID = nil
        status = "Corte de fala aprovado aplicado. Desfazer traz de volta."
        saveProject()
    }

    // MARK: - IA local

    func applyAgentPlan(_ plan: AgentPlan) -> AgentOutcome {
        recordUndo()
        let outcome = AgentExecutor.apply(plan, to: project, playhead: playhead)
        project = outcome.project
        project.overlays.sort { $0.start < $1.start }
        if let seek = outcome.seek { playhead = max(0, seek) }
        selectedClipID = nil
        status = outcome.done.isEmpty ? "Nenhuma alteração feita" : outcome.done.joined(separator: " · ")
        saveProject()
        return outcome
    }

    // MARK: - Análise automática

    /// Analisa o som de todo o material, sugere o que é sonora e acha as batidas das músicas.
    func analyzeAllSound(onProgress: (String) -> Void) async {
        let targets = project.media.filter { !$0.isDerived && $0.kind != "Imagem" }
        guard !targets.isEmpty else { status = "Nenhum vídeo ou áudio para analisar"; return }
        recordUndo()
        var marked = 0
        for (position, item) in targets.enumerated() {
            onProgress("Ouvindo \(position + 1) de \(targets.count): \(item.name)")
            let url = urlForMedia(item)
            let duration = item.duration ?? 0
            guard let report = try? await SoundDirectorService.analyze(url: url, duration: duration),
                  let index = project.media.firstIndex(where: { $0.id == item.id }) else { continue }
            project.media[index].speechRanges = report.speechRanges
            project.media[index].soundSummary = report.summary
            if AudioContentAnalysis.looksLikeSonora(speechCoverage: report.speechShare, duration: duration), !project.media[index].isSonora, report.musicShare < 0.6 {
                project.media[index].isSonora = true
                marked += 1
                if project.media[index].kind == "Áudio" {
                    for clipIndex in project.clips.indices where project.clips[clipIndex].mediaID == item.id {
                        project.clips[clipIndex].track = "voice"
                        project.clips[clipIndex].volume = 1
                    }
                }
            }
            if item.kind == "Áudio", report.musicShare >= 0.4, let beats = try? await SoundDirectorService.beats(url: url) {
                project.media[index].beats = beats
            }
        }
        status = "Som analisado. \(marked) arquivo(s) marcados como sonora; confira na aba Mídia."
        saveProject()
    }

    /// Transcreve cada sonora da timeline em ordem.
    func transcribeAllSonoras(onProgress: (String) -> Void) async {
        let targets = project.clips
            .filter { clip in clip.track == "voice" || (project.media.first { $0.id == clip.mediaID }?.isSonora ?? false) }
            .sorted { $0.start < $1.start }
        guard !targets.isEmpty else { status = "Marque as sonoras na aba Mídia primeiro"; return }
        for (position, clip) in targets.enumerated() {
            onProgress("Transcrevendo \(position + 1) de \(targets.count)")
            selectedClipID = clip.id
            selectedMediaID = clip.mediaID
            await transcribeSelectedClip()
        }
    }

    /// Batidas da primeira música da timeline, em tempo de timeline.
    var musicBeats: [Double] {
        guard let clip = project.clips.filter({ $0.track == "audio" }).min(by: { $0.start < $1.start }),
              let media = project.media.first(where: { $0.id == clip.mediaID }) else { return [] }
        let speed = max(0.01, clip.look.speed)
        return media.beats.map { clip.start + ($0 - clip.sourceIn) / speed }.filter { $0 >= clip.start && $0 <= clip.end }
    }

    // MARK: - Motion

    var motionDirectoryURL: URL {
        let folder = mediaDirectory.appendingPathComponent("Motion", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func newMotionURL() -> URL {
        motionDirectoryURL.appendingPathComponent("motion-\(UUID().uuidString).mov")
    }

    /// O motion renderizado entra na timeline como um clipe editável.
    func addMotionClip(file: URL, name: String, start: Double, duration: Double, opaque: Bool) {
        recordUndo()
        let item = LocalMedia(
            name: name,
            relativePath: "Media/Motion/\(file.lastPathComponent)",
            kind: "Vídeo",
            byteCount: ((try? fileManager.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? 0,
            importOrder: project.media.count + 1,
            duration: duration,
            isDerived: true
        )
        project.media.append(item)
        let clip = TimelineClip(mediaID: item.id, track: "motion", start: start, duration: duration, volume: 0, label: name)
        project.clips.append(clip)
        selectedClipID = clip.id
        selectedMediaID = item.id
        status = "Motion \"\(name)\" na timeline"
        saveProject()
    }

    // MARK: - Clientes

    @Published private(set) var clients: [ClientProfile] = []

    private var clientsFile: URL { projectDirectory.appendingPathComponent("clients.json") }

    func loadClients() {
        if let data = try? Data(contentsOf: clientsFile), let loaded = try? JSONDecoder().decode([ClientProfile].self, from: data), !loaded.isEmpty {
            clients = loaded
        } else {
            clients = ClientProfile.defaults
            saveClients()
        }
    }

    private func saveClients() {
        if let data = try? JSONEncoder().encode(clients) { try? data.write(to: clientsFile, options: .atomic) }
    }

    var currentClient: ClientProfile? { clients.first { $0.id == project.clientID } }

    func setClient(_ id: UUID?) {
        guard project.clientID != id else { return }
        recordUndo()
        project.clientID = id
        saveProject()
    }

    func updateClient(_ client: ClientProfile) {
        guard let index = clients.firstIndex(where: { $0.id == client.id }) else { return }
        clients[index] = client
        saveClients()
    }

    func addClient(named name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        clients.append(ClientProfile(name: cleaned))
        saveClients()
    }

    func deleteClient(_ id: UUID) {
        clients.removeAll { $0.id == id }
        saveClients()
    }

    func importClientLogo(from url: URL, clientID: UUID) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let index = clients.firstIndex(where: { $0.id == clientID }) else { return }
        let folder = projectDirectory.appendingPathComponent("Logos", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let destination = folder.appendingPathComponent("\(clientID.uuidString).\(ext)")
        try? fileManager.removeItem(at: destination)
        do {
            try fileManager.copyItem(at: url, to: destination)
            clients[index].logoRelativePath = "Logos/\(destination.lastPathComponent)"
            saveClients()
            status = "Logo salvo"
        } catch {
            status = "Não foi possível salvar o logo: \(error.localizedDescription)"
        }
    }

    /// Logo como endereço embutido, para os modelos de motion funcionarem sem acesso a outros arquivos.
    func logoDataURI(for client: ClientProfile?) -> String {
        guard let path = client?.logoRelativePath,
              let data = try? Data(contentsOf: projectDirectory.appendingPathComponent(path)) else { return "" }
        let mime = path.lowercased().hasSuffix("png") ? "image/png" : "image/jpeg"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private func timecode(_ value: Double) -> String {
        let total = Int(value)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
