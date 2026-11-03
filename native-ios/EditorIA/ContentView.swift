import SwiftUI
import AVKit
import UIKit
import UniformTypeIdentifiers
import PhotosUI
import Photos

private enum EditorSection: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case director = "Montagem"
    case clip = "Clipe"
    case media = "Mídia"
    case captions = "Legendas"
    case audio = "Áudio"
    case color = "Cor"
    case styles = "Perfis"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right.fill"
        case .director: return "sparkles"
        case .clip: return "slider.horizontal.3"
        case .media: return "square.stack.3d.up"
        case .captions: return "captions.bubble"
        case .audio: return "waveform"
        case .color: return "circle.lefthalf.filled"
        case .styles: return "square.grid.2x2"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: EditorSection? = .chat
    @State private var sheetSection: EditorSection?
    @State private var showProjects = false
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var command = ""
    @State private var directorPlan: LocalDirectorPlan?
    @State private var approveStoryCuts = false
    @State private var showApproval = false
    @StateObject private var models = ModelManager()
    @StateObject private var agent = AgentController()
    @State private var showLUTImporter = false
    @State private var showVoiceRecorder = false
    @State private var sonoraCutClipID: UUID?
    @State private var analysisMessage: String?
    @StateObject private var playback = TimelinePlayback()
    @StateObject private var renderer = TimelineRenderer()
    @StateObject private var audioAnalyzer = LocalAudioAnalysisService()
    @State private var exportedURL: URL?
    @State private var exportedStories: [URL] = []
    @State private var exportError: String?
    @State private var exportAspect = "16:9"
    @AppStorage("export.quality") private var exportQuality = ExportOptions.Quality.maximum.rawValue
    @AppStorage("export.codec") private var exportCodec = ExportOptions.Codec.h264.rawValue
    @AppStorage("export.shortSide") private var exportShortSide = 1080
    @AppStorage("export.frameRate") private var exportFrameRate = 0
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var motionOpacity = 1.0
    @State private var motionScale = 1.0
    @State private var overlayText = ""
    @State private var overlayAnimation = "fade"
    @State private var selectedMotionOverlayID: UUID?
    @State private var motionDraftFontSize = 64.0
    @State private var motionDraftX = 0.5
    @State private var motionDraftY = 0.78
    @State private var motionDraftScale = 1.0
    @State private var motionDraftRotation = 0.0
    @State private var motionDraftOutline = 0.0
    @State private var motionDraftColor = "#FFFFFF"
    @State private var motionDraftOutlineColor = "#000000"
    @State private var motionDraftAnimation = "fade"
    @State private var motionDraftWordAnimation = "none"
    @State private var isTranscribing = false
    @State private var audioSilenceThreshold = -42.0
    @State private var audioMinimumSilence = 0.45
    @State private var isSegmentingPerson = false
    @State private var segmentationError: String?
    @State private var isAnalyzingVideoPerson = false
    @State private var videoSegmentationSummary: String?
    @State private var videoSegmentationManifestURL: URL?
    @State private var videoMaskFeatherRadius = 2.0

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .image, .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                // Nomes de câmera em ordem correspondem à ordem cronológica.
                let ordered = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                Task {
                    await store.importFiles(ordered)
                    await store.prepareMaterial { store.status = $0 }
                }
            case .failure(let error): store.status = error.localizedDescription
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoSelection,
            maxSelectionCount: 100,
            selectionBehavior: .ordered,
            matching: .any(of: [.videos, .images]),
            preferredItemEncoding: .current
        )
        .sheet(isPresented: $showProjects) { ProjectsSheet() }
        .sheet(isPresented: $showVoiceRecorder) { VoiceRecorderSheet() }
        .sheet(item: Binding(get: { sonoraCutClipID.map { IdentifiedUUID(id: $0) } }, set: { sonoraCutClipID = $0?.id })) { item in
            SonoraCutSheet(clipID: item.id)
        }
        .fileImporter(isPresented: $showLUTImporter, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data]) { result in
            if case .success(let url) = result { store.importLUT(from: url) }
        }
        .sheet(item: $sheetSection) { section in
            NavigationStack {
                Group {
                    if section == .chat {
                        sectionContent(section).padding(.horizontal)
                    } else {
                        ScrollView {
                            sectionContent(section).padding()
                        }
                    }
                }
                .navigationTitle(section.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fechar") { sheetSection = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .onAppear {
            let projectStore = store
            playback.onTimeChange = { projectStore.playhead = $0 }
            rebuildPreview()
            if let first = store.project.overlays.first { loadMotionDraft(first) }
            #if DEBUG
            // Só nos testes automáticos: abre um painel para a captura de tela.
            if let name = ProcessInfo.processInfo.environment["EDITORIA_OPEN"], let section = EditorSection(rawValue: name) {
                selection = section
                if horizontalSizeClass == .compact { sheetSection = section }
            }
            #endif
        }
        .onChange(of: store.project.updatedAt) { _, _ in rebuildPreview() }
        .onChange(of: agent.pendingPlanCount) { _, _ in applyPendingPlans() }
        .onChange(of: store.project.id) { _, _ in
            exportedURL = nil
            exportedStories = []
            directorPlan = nil
            rebuildPreview()
        }
        .onChange(of: exportAspect) { _, _ in rebuildPreview() }
        .onChange(of: selectedMotionOverlayID) { _, newID in
            guard let newID, let overlay = store.project.overlays.first(where: { $0.id == newID }) else { return }
            loadMotionDraft(overlay)
        }
        .onChange(of: photoSelection) { _, items in importFromPhotos(items) }
        .alert("Exportação", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "") }
        .alert("Recorte de pessoa", isPresented: Binding(get: { segmentationError != nil }, set: { if !$0 { segmentationError = nil } })) {
            Button("OK", role: .cancel) { segmentationError = nil }
        } message: { Text(segmentationError ?? "") }
        .alert("Aprovação necessária", isPresented: $showApproval) {
            Button("Entendi", role: .cancel) { }
        } message: {
            Text("Antes de cortar uma sonora, o Diretor IA deverá apresentar a transcrição e o trecho sugerido para sua aprovação.")
        }
    }

    // MARK: - Layouts

    /// iPhone: prévia em cima, timeline no meio, ferramentas em painéis que sobem de baixo.
    private var compactLayout: some View {
        VStack(spacing: 0) {
            compactHeader
            exportProgress
            previewSurface
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 280)
                .padding(.horizontal, 8)
            transportBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            ScrollView(.vertical) {
                EditorTimeline(isPlaying: playback.isPlaying, onSeek: seek)
                    .padding(.horizontal, 8)
            }
            if store.selectedClip != nil { quickClipActions }
            sectionBar
        }
        .background(Color(uiColor: .systemBackground))
    }

    /// iPad: barra lateral e painéis lado a lado.
    private var regularLayout: some View {
        NavigationSplitView {
            List(EditorSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section as EditorSection?)
            }
            .navigationTitle("Editor IA")
            .safeAreaInset(edge: .bottom) {
                Label("Modo local", systemImage: "airplane")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding()
            }
        } detail: {
            VStack(spacing: 0) {
                compactHeader
                exportProgress
                ScrollView {
                    VStack(spacing: 16) {
                        previewSurface.frame(maxHeight: 420)
                        transportBar
                        EditorTimeline(isPlaying: playback.isPlaying, onSeek: seek)
                        if store.selectedClip != nil { quickClipActions }
                        sectionContent(selection ?? .chat)
                    }
                    .padding()
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            Button { showProjects = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(store.project.name).font(.headline).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    Text(store.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Projetos: \(store.project.name)")

            Menu {
                Button { showPhotoPicker = true } label: { Label("Da Fototeca", systemImage: "photo.on.rectangle") }
                Button { showFileImporter = true } label: { Label("De Arquivos", systemImage: "folder") }
            } label: {
                Image(systemName: store.isImporting ? "hourglass" : "plus")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .disabled(store.isImporting)
            .accessibilityLabel("Importar mídia")

            exportMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var exportMenu: some View {
        Menu {
            Picker("Proporção", selection: $exportAspect) {
                Text("16:9 · Horizontal").tag("16:9")
                Text("9:16 · Stories/Reels").tag("9:16")
                Text("4:5 · Feed").tag("4:5")
                Text("1:1 · Quadrado").tag("1:1")
            }
            Picker("Qualidade", selection: $exportQuality) {
                ForEach(ExportOptions.Quality.allCases, id: \.rawValue) { Text("Qualidade \($0.rawValue)").tag($0.rawValue) }
            }
            Menu("Resolução: \(resolutionName(exportShortSide))") {
                Picker("Resolução", selection: $exportShortSide) {
                    ForEach([720, 1080, 1440, 2160], id: \.self) { Text(resolutionName($0)).tag($0) }
                }
            }
            Menu("Formato: \(exportCodec)") {
                Picker("Formato", selection: $exportCodec) {
                    Text("H.264 (funciona em tudo)").tag(ExportOptions.Codec.h264.rawValue)
                    Text("HEVC (arquivo menor)").tag(ExportOptions.Codec.hevc.rawValue)
                }
            }
            Menu("Quadros: \(exportFrameRate == 0 ? "igual ao material" : "\(exportFrameRate) fps")") {
                Picker("Quadros por segundo", selection: $exportFrameRate) {
                    Text("Igual ao material").tag(0)
                    ForEach([24, 25, 30, 50, 60], id: \.self) { Text("\($0) fps").tag($0) }
                }
            }
            Text(estimateText)
            Divider()
            Button { startExport() } label: { Label("Exportar vídeo", systemImage: "film") }
                .disabled(renderer.isExporting || store.project.clips.isEmpty)
            Button { startStoriesExport() } label: { Label("Exportar Stories em arquivos", systemImage: "square.stack") }
                .disabled(renderer.isExporting || store.project.clips.isEmpty)
            if let exportedURL {
                Divider()
                ShareLink(item: exportedURL) { Label("Compartilhar vídeo", systemImage: "square.and.arrow.up") }
                Button { saveToPhotos([exportedURL]) } label: { Label("Salvar vídeo na Fototeca", systemImage: "photo.badge.arrow.down") }
            }
            if !exportedStories.isEmpty {
                Divider()
                ShareLink(items: exportedStories) { Label("Compartilhar \(exportedStories.count) Stories", systemImage: "square.and.arrow.up") }
                Button { saveToPhotos(exportedStories) } label: { Label("Salvar Stories na Fototeca", systemImage: "photo.badge.arrow.down") }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.headline)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Exportar")
    }

    @ViewBuilder
    private var exportProgress: some View {
        if renderer.isExporting {
            HStack(spacing: 10) {
                ProgressView(value: renderer.progress).tint(.blue)
                Text("\(Int(renderer.progress * 100))%").font(.caption2.monospacedDigit())
                Button("Cancelar", role: .cancel) { renderer.cancel() }.font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    private var previewSurface: some View {
        ZStack {
            PlayerSurface(player: playback.player)
            if store.project.clips.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack").font(.system(size: 34)).foregroundStyle(.white.opacity(0.55))
                    Text("Toque em + para importar").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                }
            } else if playback.isBuilding {
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(CGFloat(baseDimensions.width) / CGFloat(baseDimensions.height), contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { playback.togglePlay(from: store.playhead, timelineEnd: store.project.contentEnd) }
    }

    private var transportBar: some View {
        HStack(spacing: 8) {
            Button { playback.togglePlay(from: store.playhead, timelineEnd: store.project.contentEnd) } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .disabled(store.project.clips.isEmpty)
            .accessibilityLabel(playback.isPlaying ? "Pausar" : "Reproduzir")
            VStack(alignment: .leading, spacing: 1) {
                Text("\(timecode(store.playhead)) / \(timecode(store.project.contentEnd))")
                    .font(.system(.footnote, design: .monospaced))
                if let warning = playback.frameRateWarning {
                    Text(warning).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 44) }
                .disabled(!store.canUndo)
                .accessibilityLabel("Desfazer")
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 44) }
                .disabled(!store.canRedo)
                .accessibilityLabel("Refazer")
        }
    }

    private var quickClipActions: some View {
        HStack(spacing: 8) {
            Button { store.splitSelectedClip(); seek(store.playhead) } label: { Label("Dividir", systemImage: "scissors") }
            Button { store.duplicateSelectedClip() } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
            Menu {
                Button(role: .destructive) { store.rippleDeleteSelectedClip() } label: { Label("Apagar e fechar o espaço", systemImage: "arrow.left.to.line") }
                Button(role: .destructive) { store.deleteSelectedClip() } label: { Label("Apagar e manter o espaço", systemImage: "trash") }
            } label: { Label("Apagar", systemImage: "trash") }
            Spacer(minLength: 0)
            Button { sheetSection = .clip; selection = .clip } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Ajustes do clipe")
        }
        .font(.footnote)
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var sectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(EditorSection.allCases) { section in
                    Button { sheetSection = section } label: {
                        VStack(spacing: 3) {
                            Image(systemName: section.symbol).font(.body)
                            Text(section.rawValue).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        .frame(minWidth: 62, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
        .background(.bar)
    }

    /// Aplica direto na timeline o que a IA decidiu, mesmo com o chat fechado. Tudo pode ser desfeito.
    private func applyPendingPlans() {
        for message in agent.messages where message.plan != nil && !message.applied {
            guard let plan = message.plan else { continue }
            let outcome = store.applyAgentPlan(plan)
            agent.markApplied(message.id, outcome: outcome.done)
            if !outcome.blocked.isEmpty { agent.addNote(outcome.blocked.joined(separator: "\n")) }
            handleAgentRequests(outcome.requests)
        }
    }

    /// Pedidos da IA que precisam do aparelho, um de cada vez e na ordem pedida.
    private func handleAgentRequests(_ requests: [AgentRequest]) {
        guard !requests.isEmpty else { return }
        Task {
            for request in requests {
                await perform(request)
            }
            seek(store.playhead)
        }
    }

    private func perform(_ request: AgentRequest) async {
        switch request {
        case .transcribeAll:
            await store.transcribeAllSonoras { store.status = $0 }
            agent.addNote(store.status)
        case .analyzeSound, .prepare:
            await store.prepareMaterial { store.status = $0 }
            agent.addNote(store.status)
        case .exportVideo:
            startExport()
        case .undo:
            store.undo()
        case .reframe:
            let size = baseDimensions
            await store.autoReframe(frameWidth: size.width, frameHeight: size.height) { store.status = $0 }
            agent.addNote(store.status)
        case .addMusic(let mood):
            if let item = store.libraryItem(kind: "music", mood: mood) {
                store.addFromLibrary(item)
                agent.addNote("Coloquei \"\(item.name)\". A música abaixa sozinha durante as falas.")
            } else {
                agent.addNote(mood.isEmpty ? "Sua biblioteca de música está vazia. Importe músicas na aba Áudio." : "Não há música com o clima \"\(mood)\" na biblioteca. Importe na aba Áudio.")
            }
        case .addSound(let kind, let time):
            if let item = store.libraryItem(kind: "sfx", mood: kind) {
                store.addFromLibrary(item, at: time)
            } else {
                agent.addNote("Não há efeito do tipo \"\(kind)\" na biblioteca. Importe na aba Áudio.")
            }
        }
    }

    private func seek(_ seconds: Double) {
        playback.pause()
        store.playhead = max(0, seconds)
        playback.seek(to: store.playhead)
    }

    private func rebuildPreview() {
        let size = baseDimensions
        playback.scheduleRebuild(project: store.project, baseDirectory: store.baseDirectoryURL, width: (size.width / 2) & ~1, height: (size.height / 2) & ~1, playhead: store.playhead)
    }

    private func startExport() {
        playback.pause()
        agent.unload()
        Task {
            do {
                let size = exportDimensions
                exportedURL = try await renderer.export(project: store.project, baseDirectory: store.baseDirectoryURL, width: size.width, height: size.height, options: exportOptions)
                store.status = renderer.status
            } catch {
                exportError = error.localizedDescription
                store.status = error.localizedDescription
            }
        }
    }

    private func startStoriesExport() {
        playback.pause()
        agent.unload()
        Task {
            do {
                let size = exportOptions.dimensions(baseWidth: 1080, baseHeight: 1920)
                exportedStories = try await renderer.exportStories(project: store.project, baseDirectory: store.baseDirectoryURL, width: size.width, height: size.height, options: exportOptions)
                store.status = renderer.status
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func saveToPhotos(_ urls: [URL]) {
        Task {
            do {
                for url in urls { try await saveExportToPhotos(url) }
                store.status = urls.count == 1 ? "Vídeo salvo na Fototeca" : "\(urls.count) vídeos salvos na Fototeca"
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func saveExportToPhotos(_ url: URL) async throws {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw NSError(domain: "EditorIA.Photos", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permissão para adicionar vídeos à Fototeca não concedida."])
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    private func importFromPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var stagedURLs: [URL] = []
            for item in items {
                do {
                    if let picked = try await item.loadTransferable(type: PickedMediaFile.self) {
                        stagedURLs.append(picked.url)
                    }
                } catch {
                    store.status = "Não foi possível carregar um item da Fototeca: \(error.localizedDescription)"
                }
            }
            if !stagedURLs.isEmpty {
                await store.importFiles(stagedURLs, moveFiles: true)
                await store.prepareMaterial { store.status = $0 }
                stagedURLs.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) }
            } else {
                store.status = "Nenhum arquivo compatível foi recebido da Fototeca"
            }
            photoSelection = []
        }
    }

    /// Tamanho de referência da proporção; textos e legendas são medidos nele.
    private var baseDimensions: (width: Int, height: Int) {
        switch exportAspect {
        case "9:16": return (1080, 1920)
        case "4:5": return (1080, 1350)
        case "1:1": return (1080, 1080)
        default: return (1920, 1080)
        }
    }

    private var exportOptions: ExportOptions {
        ExportOptions(
            quality: ExportOptions.Quality(rawValue: exportQuality) ?? .maximum,
            codec: ExportOptions.Codec(rawValue: exportCodec) ?? .h264,
            shortSide: exportShortSide,
            frameRate: exportFrameRate == 0 ? nil : exportFrameRate
        )
    }

    private var exportDimensions: (width: Int, height: Int) {
        exportOptions.dimensions(baseWidth: baseDimensions.width, baseHeight: baseDimensions.height)
    }

    private func resolutionName(_ side: Int) -> String {
        switch side {
        case 720: return "HD 720p"
        case 1440: return "2K 1440p"
        case 2160: return "4K 2160p"
        default: return "Full HD 1080p"
        }
    }

    /// Tamanho aproximado do arquivo final, com a escolha atual.
    private var estimateText: String {
        let size = exportDimensions
        let bytes = exportOptions.estimatedBytes(width: size.width, height: size.height, framesPerSecond: Double(exportFrameRate == 0 ? 30 : exportFrameRate), duration: store.project.contentEnd)
        return "Arquivo de aproximadamente \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    @ViewBuilder
    private func sectionContent(_ section: EditorSection) -> some View {
        switch section {
        case .clip:
            if let clip = store.selectedClip {
                selectedClipInspector(clip)
            } else {
                ContentUnavailableView("Nenhum clipe selecionado", systemImage: "cursorarrow.click", description: Text("Toque em um clipe na timeline."))
            }
        case .chat:
            AIAssistantPanel(models: models, agent: agent, fillsHeight: sheetSection == .chat)
        case .director:
            VStack(alignment: .leading, spacing: 12) {
                Label("Montagem automática", systemImage: "sparkles")
                    .font(.title3.bold())
                Text("Marque as sonoras na aba Mídia e peça a montagem. Estas são as regras fixas do padrão institucional e de Stories, e funcionam mesmo sem modelo de IA instalado.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Ex.: monte um vídeo institucional respeitando a ordem dos arquivos", text: $command, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button {
                        directorPlan = LocalDirectorService.makePlan(command: command, project: store.project, client: store.currentClient, beats: store.musicBeats)
                        store.status = "Plano local preparado. Nenhum corte foi executado."
                    } label: { Label("Analisar comando", systemImage: "list.clipboard") }
                        .buttonStyle(.borderedProminent)
                        .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Regras de sonoras") { showApproval = true }
                        .buttonStyle(.bordered)
                }
                if let plan = directorPlan {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Plano de montagem", systemImage: "checklist")
                                .font(.headline)
                            Spacer()
                            Text("LOCAL")
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                        }
                        LabeledContent("Perfil", value: plan.profile)
                        LabeledContent("Duração", value: plan.targetDuration)
                        ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(step.title).font(.subheadline.weight(.semibold))
                                        if step.requiresApproval {
                                            Text("APROVAÇÃO")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5).padding(.vertical, 3)
                                                .background(.orange.opacity(0.18), in: Capsule())
                                        }
                                    }
                                    Text(step.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        ForEach(plan.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let draft = plan.timelineDraft {
                            Divider()
                            Label("Rascunho de sequência", systemImage: "timeline.selection")
                                .font(.subheadline.weight(.semibold))
                            ForEach(draft.segments) { segment in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(segment.mediaName).font(.caption.weight(.semibold)).lineLimit(1)
                                        Spacer()
                                        Text("\(segment.timelineStart, specifier: "%.1f")s · \(segment.duration, specifier: "%.1f")s")
                                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    Text(segment.note).font(.caption2).foregroundStyle(.secondary)
                                    if segment.requiresReview {
                                        Label("Revisão obrigatória", systemImage: "hand.raised")
                                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            let reviewIDs = Set(draft.segments.filter { $0.role == .storyVisual && $0.requiresReview }.map(\.id))
                            if !reviewIDs.isEmpty {
                                Toggle("Aprovo estes \(reviewIDs.count) cortes visuais. Confirmei que não interrompem falas importantes.", isOn: $approveStoryCuts)
                                    .font(.caption)
                            }
                            let approved = approveStoryCuts ? reviewIDs : []
                            Button {
                                store.applyDirectorDraft(draft, replaceExisting: true, approvedSegmentIDs: approved)
                                seek(store.playhead)
                            } label: {
                                Label("Montar na timeline (substitui)", systemImage: "rectangle.stack.badge.play")
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 6)
                            Button {
                                store.applyDirectorDraft(draft, replaceExisting: false, approvedSegmentIDs: approved)
                                seek(store.playhead)
                            } label: {
                                Label("Adicionar ao final da timeline", systemImage: "plus.rectangle.on.rectangle")
                            }
                            .buttonStyle(.bordered)
                            Text("Substituir troca os clipes de vídeo e voz pela montagem e mantém sua música e seus efeitos; Desfazer traz tudo de volta. Os arquivos originais não mudam. Sonoras entram inteiras.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("O rascunho é não destrutivo. Nenhuma fala é cortada automaticamente; decisões de sonora e desenho sonoro continuam sujeitas à revisão.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        case .media:
            VStack(alignment: .leading, spacing: 10) {
                Text("Mídia do projeto").font(.title3.bold())
                if store.project.media.isEmpty {
                    ContentUnavailableView("Nenhuma mídia", systemImage: "square.stack", description: Text("Importe vídeos, imagens e áudios armazenados no aparelho."))
                } else {
                    Text("Ative Sonora nos arquivos com fala: eles entram inteiros, e o Diretor coloca imagens de apoio por cima.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(store.project.media.filter { !$0.isDerived }) { item in
                        HStack {
                            Image(systemName: item.kind == "Vídeo" ? "video" : item.kind == "Áudio" ? "waveform" : "photo")
                            VStack(alignment: .leading) {
                                Text("\(item.importOrder). \(item.name)").lineLimit(1)
                                Text(item.kind).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.kind != "Imagem" {
                                Toggle("Sonora", isOn: Binding(
                                    get: { item.isSonora },
                                    set: { store.setSonora(item.id, $0) }
                                ))
                                .labelsHidden()
                                .accessibilityLabel("Sonora: \(item.name)")
                                Text("Sonora").font(.caption2).foregroundStyle(item.isSonora ? .green : .secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                Button("Importar arquivos") { showFileImporter = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        case .captions:
            VStack(alignment: .leading, spacing: 12) {
                Label("Textos e legendas", systemImage: "captions.bubble").font(.title3.bold())
                Text("Adicione títulos e textos à composição. Eles serão renderizados no vídeo exportado, com animações de entrada.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Digite o texto que aparecerá no vídeo", text: $overlayText, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                Picker("Animação de entrada", selection: $overlayAnimation) {
                    Text("Fade").tag("fade")
                    Text("Pop").tag("pop")
                    Text("Deslizar").tag("slide")
                }
                .pickerStyle(.segmented)
                Button {
                    store.addTextOverlay(overlayText, animation: overlayAnimation)
                    overlayText = ""
                } label: { Label("Adicionar no cursor", systemImage: "plus.circle.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(overlayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    isTranscribing = true
                    Task {
                        await store.transcribeSelectedClip()
                        isTranscribing = false
                    }
                } label: {
                    if isTranscribing {
                        Label("Transcrevendo no aparelho...", systemImage: "waveform")
                    } else {
                        Label("Transcrever fala localmente", systemImage: "text.quote")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTranscribing || store.selectedClip == nil)
                Button {
                    isTranscribing = true
                    Task {
                        await store.transcribeAllSonoras { analysisMessage = $0 }
                        analysisMessage = nil
                        isTranscribing = false
                    }
                } label: { Label(analysisMessage ?? "Transcrever todas as sonoras", systemImage: "text.badge.checkmark") }
                .buttonStyle(.bordered)
                .disabled(isTranscribing)
                CaptionStylePanel()
                Text("A fala é transcrita no próprio aparelho, sem enviar nada. As legendas acompanham qualquer corte ou mudança de lugar do clipe.")
                    .font(.caption).foregroundStyle(.secondary)

                if !store.project.captionWords.isEmpty {
                    HStack {
                        Text("Legendas sincronizadas (\(store.project.captionWords.count))").font(.subheadline.bold())
                        Spacer()
                        Button("Limpar") { store.clearCaptionWords() }.foregroundStyle(.red)
                    }
                    ForEach(store.project.captionWords.prefix(12)) { word in
                        HStack {
                            Text(word.text).font(.subheadline)
                            Spacer()
                            Text("\(timecode(word.start)) · \(word.duration, specifier: "%.2f")s")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                if !store.project.overlays.isEmpty {
                    Divider()
                    Text("Elementos de texto no projeto").font(.subheadline.bold())
                    ForEach(store.project.overlays) { overlay in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(overlay.text).font(.subheadline).lineLimit(2)
                                Text("\(timecode(overlay.start)) · \(overlay.duration, specifier: "%.1f")s · \(overlay.animation)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { store.deleteTextOverlay(overlay.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }
                Text("Para melhor precisão em português, instale o Whisper em Chat, no botão Modelos.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            titleEditorSection
        case .audio:
            audioAnalysisSection
        case .color:
            ColorPanel(showLUTImporter: $showLUTImporter)
        case .styles:
            ClientProfilesPanel()
        }
    }

    private var titleEditorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Editar títulos", systemImage: "textformat")
                .font(.title3.bold())
            Text("Edite posição, tamanho, rotação, contorno e animação dos textos. As alterações são aplicadas à composição e salvas no projeto local.")
                .font(.subheadline).foregroundStyle(.secondary)

            GroupBox("Adicionar elemento") {
                VStack(alignment: .leading, spacing: 9) {
                    TextField("Texto para animar", text: $overlayText, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.roundedBorder)
                    Picker("Animação", selection: $overlayAnimation) {
                        Text("Fade").tag("fade")
                        Text("Pop").tag("pop")
                        Text("Deslizar").tag("slide")
                        Text("Bounce").tag("bounce")
                        Text("Slam").tag("slam")
                    }
                    .pickerStyle(.segmented)
                    Button {
                        store.addTextOverlay(overlayText, animation: overlayAnimation)
                        if let created = store.project.overlays.last {
                            selectedMotionOverlayID = created.id
                            loadMotionDraft(created)
                        }
                        overlayText = ""
                    } label: { Label("Adicionar texto na timeline", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(overlayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let selectedMedia = store.selectedMedia,
               selectedMedia.kind == "Imagem",
               let sourceClip = store.project.clips.first(where: { $0.mediaID == selectedMedia.id }) {
                GroupBox("Recorte inteligente de pessoa") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A segmentação usa o Vision no próprio aparelho. Nesta etapa, o recorte funciona em fotografias e cria uma camada transparente acima dos textos, permitindo composições com tipografia atrás da pessoa.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            Task {
                                isSegmentingPerson = true
                                defer { isSegmentingPerson = false }
                                do {
                                    let sourceURL = store.urlForMedia(selectedMedia)
                                    let png = try await PersonSegmentationService.createTransparentPersonPNG(from: sourceURL)
                                    try store.addPersonCutout(data: png, basedOn: sourceClip, originalName: selectedMedia.name)
                                } catch {
                                    segmentationError = error.localizedDescription
                                }
                            }
                        } label: {
                            if isSegmentingPerson {
                                Label("Recortando pessoa…", systemImage: "person.crop.rectangle")
                            } else {
                                Label("Recortar pessoa da fotografia", systemImage: "person.crop.rectangle")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSegmentingPerson)
                    }
                }
            }

            if let selectedMedia = store.selectedMedia,
               selectedMedia.kind == "Vídeo" {
                GroupBox("Segmentação de pessoa em vídeo") {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Analisa o vídeo quadro a quadro em amostragem local e gera PNGs transparentes com marcação de tempo. Esta etapa prepara as máscaras para o tracking e a composição contínua nas próximas versões; ainda não substitui automaticamente o clipe original na timeline.")
                            .font(.caption).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Suavização das bordas")
                                Spacer()
                                Text("\(videoMaskFeatherRadius, specifier: "%.1f") px")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $videoMaskFeatherRadius, in: 0...8, step: 0.5)
                            Text("Valores maiores suavizam a borda do recorte, mas podem criar halos. Ajuste conforme o vídeo.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task {
                                isAnalyzingVideoPerson = true
                                videoSegmentationSummary = nil
                                defer { isAnalyzingVideoPerson = false }
                                do {
                                    let sourceURL = store.urlForMedia(selectedMedia)
                                    let folder = store.mediaDirectoryURL
                                        .appendingPathComponent("PersonMasks", isDirectory: true)
                                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                                    let result = try await VideoPersonSegmentationService.generateMaskFrames(
                                        from: sourceURL,
                                        outputDirectory: folder,
                                        sampleRate: 5,
                                        maskFeatherRadius: videoMaskFeatherRadius
                                    )
                                    videoSegmentationManifestURL = result.manifestURL
                                    videoSegmentationSummary = String(format: "%d máscaras geradas a 5 quadros por segundo, suavização de %.1f px.", result.frameCount, videoMaskFeatherRadius)
                                    store.status = "Análise de pessoa concluída: \(result.frameCount) quadros"
                                } catch {
                                    segmentationError = error.localizedDescription
                                }
                            }
                        } label: {
                            if isAnalyzingVideoPerson {
                                Label("Analisando vídeo no aparelho…", systemImage: "person.crop.rectangle")
                            } else {
                                Label("Gerar máscaras do vídeo", systemImage: "person.crop.rectangle")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAnalyzingVideoPerson)
                        if let videoSegmentationSummary {
                            Text(videoSegmentationSummary)
                                .font(.caption)
                                .foregroundStyle(.green)
                                .textSelection(.enabled)
                        }
                        if let manifestURL = videoSegmentationManifestURL,
                           let sourceClip = store.project.clips.first(where: { $0.mediaID == selectedMedia.id && $0.track != "subject" }) {
                            Button {
                                do {
                                    let count = try store.addVideoPersonSequence(manifestURL: manifestURL, basedOn: sourceClip)
                                    videoSegmentationSummary = "\(count) camadas transparentes adicionadas à trilha de pessoa. A amostragem atual é de até 5 quadros por segundo."
                                    videoSegmentationManifestURL = nil
                                } catch {
                                    segmentationError = error.localizedDescription
                                }
                            } label: {
                                Label("Aplicar máscaras na timeline", systemImage: "square.stack.3d.up.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if store.project.overlays.isEmpty {
                ContentUnavailableView("Nenhum elemento de texto", systemImage: "textformat", description: Text("Adicione um texto para começar a compor animações."))
            } else {
                GroupBox("Elementos da composição") {
                    VStack(spacing: 8) {
                        ForEach(store.project.overlays) { overlay in
                            Button {
                                selectedMotionOverlayID = overlay.id
                                loadMotionDraft(overlay)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(overlay.text).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text("\(timecode(overlay.start)) · \(overlay.duration, specifier: "%.1f")s · \(overlay.animation)")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedMotionOverlayID == overlay.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                    }
                                }
                                .padding(8)
                                .background(selectedMotionOverlayID == overlay.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let overlay = activeMotionOverlay {
                    GroupBox("Transformação e estilo") {
                        VStack(alignment: .leading, spacing: 12) {
                            motionSlider("Tamanho", value: $motionDraftFontSize, range: 18...180, suffix: " pt")
                            motionSlider("Posição horizontal", value: $motionDraftX, range: 0.05...0.95, suffix: "")
                            motionSlider("Posição vertical", value: $motionDraftY, range: 0.05...0.95, suffix: "")
                            motionSlider("Escala", value: $motionDraftScale, range: 0.2...3, suffix: "×")
                            motionSlider("Rotação", value: $motionDraftRotation, range: -180...180, suffix: "°")
                            motionSlider("Contorno", value: $motionDraftOutline, range: 0...12, suffix: " px")
                            Picker("Animação de entrada", selection: $motionDraftAnimation) {
                                ForEach(TextMotion.entranceKinds, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            Picker("Animação por palavra", selection: $motionDraftWordAnimation) {
                                Text("Desativada").tag("none")
                                Text("Palavra aparecendo").tag("wordPop")
                                Text("Palavra com impacto").tag("wordSlam")
                                Text("Palavra subindo").tag("wordSlide")
                            }
                            .pickerStyle(.menu)
                            HStack {
                                Button("Branco") { motionDraftColor = "#FFFFFF" }.buttonStyle(.bordered)
                                Button("Amarelo") { motionDraftColor = "#FFD84D" }.buttonStyle(.bordered)
                                Button("Ciano") { motionDraftColor = "#55DFFF" }.buttonStyle(.bordered)
                                Button("Preto") { motionDraftOutlineColor = "#000000" }.buttonStyle(.bordered)
                            }
                            Button {
                                var updated = overlay
                                updated.fontSize = motionDraftFontSize
                                updated.horizontalPosition = motionDraftX
                                updated.verticalPosition = motionDraftY
                                updated.scale = motionDraftScale
                                updated.rotationDegrees = motionDraftRotation
                                updated.outlineWidth = motionDraftOutline
                                updated.colorHex = motionDraftColor
                                updated.outlineHex = motionDraftOutlineColor
                                updated.animation = motionDraftAnimation
                                updated.wordAnimation = motionDraftWordAnimation
                                store.updateTextOverlay(updated)
                            } label: {
                                Label("Aplicar alterações ao texto", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            Text("A animação por palavra cria entradas sequenciais. Para fotografias, use o recorte inteligente acima: a pessoa fica em uma camada superior e o texto pode aparecer atrás dela. O recorte contínuo de pessoas em vídeos, com tracking quadro a quadro, será uma etapa posterior.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var activeMotionOverlay: TextOverlay? {
        if let selectedMotionOverlayID,
           let selected = store.project.overlays.first(where: { $0.id == selectedMotionOverlayID }) { return selected }
        return store.project.overlays.first
    }

    private func loadMotionDraft(_ overlay: TextOverlay) {
        motionDraftFontSize = overlay.fontSize
        motionDraftX = overlay.horizontalPosition
        motionDraftY = overlay.verticalPosition
        motionDraftScale = overlay.scale
        motionDraftRotation = overlay.rotationDegrees
        motionDraftOutline = overlay.outlineWidth
        motionDraftColor = overlay.colorHex
        motionDraftOutlineColor = overlay.outlineHex
        motionDraftAnimation = overlay.animation
        motionDraftWordAnimation = overlay.wordAnimation
    }

    private func motionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.1f")\(suffix)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var audioAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sound Director IA", systemImage: "waveform")
                .font(.title3.bold())
            Button {
                Task {
                    await store.prepareMaterial { analysisMessage = $0 }
                    analysisMessage = nil
                }
            } label: { Label(analysisMessage ?? "Analisar o material de novo", systemImage: "ear") }
                .buttonStyle(.bordered)
                .disabled(analysisMessage != nil || store.isPreparing)
            Text("Ao importar, o app ouve e olha cada arquivo no próprio aparelho: detecta fala e música, marca as sonoras, acha as batidas e transcreve. A música abaixa sozinha quando há fala.")
                .font(.caption).foregroundStyle(.secondary)
            SoundLibraryPanel()
            Button { showVoiceRecorder = true } label: { Label("Gravar narração", systemImage: "mic.fill") }
                .buttonStyle(.bordered)
            Text("Análise acústica local para identificar níveis de áudio e pausas. Nenhum arquivo é enviado para a nuvem.")
                .font(.subheadline).foregroundStyle(.secondary)

            if let media = store.selectedMedia {
                HStack(spacing: 8) {
                    Image(systemName: media.kind == "Áudio" ? "waveform" : "video")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text("Arquivo selecionado para análise").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    let url = store.urlForMedia(media)
                    Task { await audioAnalyzer.analyze(url: url, thresholdDB: audioSilenceThreshold, minimumSilence: audioMinimumSilence) }
                } label: {
                    if audioAnalyzer.isAnalyzing {
                        Label("Analisando áudio…", systemImage: "waveform")
                    } else {
                        Label("Analisar áudio localmente", systemImage: "waveform.badge.magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(audioAnalyzer.isAnalyzing)
            } else {
                ContentUnavailableView("Selecione uma mídia", systemImage: "waveform", description: Text("Importe um vídeo ou áudio e selecione-o para analisar o som."))
            }

            GroupBox("Mixagem inteligente") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Reduzir música durante as falas", isOn: Binding(
                        get: { store.project.automaticDucking },
                        set: { store.setAutomaticDucking($0) }
                    ))
                    Text("Usa a fala detectada e os trechos transcritos para baixar a trilha musical. Não altera o áudio original da fala.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Volume da música durante a fala")
                        Spacer()
                        Text("\(Int(store.project.duckingLevel * 100))%")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { store.project.duckingLevel },
                        set: { store.setDuckingLevel($0) }
                    ), in: 0.05 ... 0.8, step: 0.05)
                    Text("O ducking usa a fala detectada na análise do material.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Limite de silêncio")
                    Spacer()
                    Text("\(audioSilenceThreshold, specifier: "%.0f") dB")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $audioSilenceThreshold, in: -60 ... -25, step: 1)
                HStack {
                    Text("Pausa mínima")
                    Spacer()
                    Text("\(audioMinimumSilence, specifier: "%.2f") s")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $audioMinimumSilence, in: 0.2 ... 2.0, step: 0.05)
            }
            .font(.caption)

            Text(audioAnalyzer.status)
                .font(.caption).foregroundStyle(.secondary)

            if let error = audioAnalyzer.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }

            if let report = audioAnalyzer.report {
                let strideValue = max(1, report.samples.count / 120)
                let displaySamples = report.samples.enumerated().filter { $0.offset % strideValue == 0 }.prefix(120).map { $0.element }
                Divider()
                Text("Resumo acústico").font(.headline)
                HStack(spacing: 10) {
                    metricCard("Duração", value: timecode(report.duration))
                    metricCard("Pico", value: String(format: "%.0f%%", report.peakLevel * 100))
                    metricCard("Pausas", value: "\(report.silenceRanges.count)")
                }
                Text("Forma de onda aproximada").font(.subheadline.weight(.semibold))
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(displaySamples.enumerated()), id: \.offset) { _, sample in
                        Capsule()
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(3, min(46, sample.rms * 150)))
                    }
                }
                .frame(height: 50)
                .padding(.vertical, 4)

                if report.silenceRanges.isEmpty {
                    Text("Nenhuma pausa acima do limite foi detectada.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Pausas candidatas. Nenhuma será removida automaticamente.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(report.silenceRanges) { range in
                        HStack {
                            Image(systemName: "pause.circle")
                            Text("\(timecode(range.start)) até \(timecode(range.end))")
                            Spacer()
                            Text("\(range.duration, specifier: "%.1f")s")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.vertical, 3)
                    }
                }
                Text("Esta medida mostra volume e pausas do arquivo selecionado.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func featureCard(_ title: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            Text("Ainda não disponível nesta versão.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func selectedClipInspector(_ clip: TimelineClip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Inspetor de clipe", systemImage: "slider.horizontal.3")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(timecode(clip.start)) · \(clip.duration, specifier: "%.1f")s")
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            TextField("Nome do clipe", text: Binding(
                get: { store.selectedClip?.label ?? clip.label },
                set: { store.renameSelectedClip($0) }
            ))
            .textFieldStyle(.roundedBorder)
            Picker("Trilha", selection: Binding(
                get: { store.selectedClip?.track ?? clip.track },
                set: { store.changeSelectedTrack($0) }
            )) {
                Text("Vídeo principal").tag("video")
                Text("B-roll").tag("broll")
                Text("Legendas").tag("captions")
                Text("Voz / sonora").tag("voice")
                Text("Trilha musical").tag("audio")
                Text("Efeitos sonoros").tag("sfx")
            }
            .pickerStyle(.menu)
            HStack(spacing: 8) {
                Button { store.splitSelectedClip() } label: { Label("Dividir no cursor", systemImage: "scissors") }
                    .buttonStyle(.borderedProminent)
                Button { store.duplicateSelectedClip() } label: { Image(systemName: "plus.square.on.square") }
                    .buttonStyle(.bordered)
                Button { store.deleteSelectedClip() } label: { Image(systemName: "trash") }
                    .buttonStyle(.bordered).tint(.red)
                    .accessibilityLabel("Apagar clipe")
            }
            HStack {
                Button { store.trimSelectedStart(by: 0.5) } label: { Label("Aparar início", systemImage: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left") }
                    .buttonStyle(.bordered)
                Button { store.trimSelectedEnd(by: -0.5) } label: { Label("Aparar final", systemImage: "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right") }
                    .buttonStyle(.bordered)
            }
            HStack {
                Button { store.moveSelectedClip(by: -1) } label: { Label("−1s", systemImage: "arrow.left") }
                    .buttonStyle(.bordered)
                Button { store.moveSelectedClip(by: 1) } label: { Label("+1s", systemImage: "arrow.right") }
                    .buttonStyle(.bordered)
                Spacer()
                Button { store.adjustSelectedDuration(by: -1) } label: { Text("− Duração") }
                    .buttonStyle(.bordered)
                Button { store.adjustSelectedDuration(by: 1) } label: { Text("+ Duração") }
                    .buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text("\(Int(clip.volume * 100))%")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { store.selectedClip?.volume ?? clip.volume }, set: { store.setSelectedClipVolume($0) }), in: 0...2)
                HStack {
                    Button { store.adjustSelectedFadeIn(by: 0.25) } label: { Label("Fade in +0,25s", systemImage: "waveform.path") }
                        .buttonStyle(.bordered)
                    Button { store.adjustSelectedFadeOut(by: 0.25) } label: { Label("Fade out +0,25s", systemImage: "waveform.path") }
                        .buttonStyle(.bordered)
                }
                Text("Fade in: \(clip.fadeIn, specifier: "%.2f")s · Fade out: \(clip.fadeOut, specifier: "%.2f")s")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text("Opacidade")
                    Slider(value: $motionOpacity, in: 0...1)
                    Text("\(Int(motionOpacity * 100))%")
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                HStack {
                    Text("Escala")
                    Slider(value: $motionScale, in: 0.1...3)
                    Text("\(motionScale, specifier: "%.1f")×")
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                HStack {
                    Button { store.addKeyframe(property: "opacity", value: motionOpacity) } label: { Label("Gravar opacidade", systemImage: "circle.lefthalf.filled") }
                    Button { store.addKeyframe(property: "scale", value: motionScale) } label: { Label("Gravar escala", systemImage: "arrow.up.left.and.arrow.down.right") }
                    Button { store.addKeyframe(property: "volume", value: clip.volume) } label: { Label("Gravar volume", systemImage: "waveform") }
                }
                .buttonStyle(.bordered)
                Text("\(clip.keyframes.count) keyframe(s)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ClipEffectsPanel(clip: clip, onReviewSpeech: { sonoraCutClipID = clip.id })
            Text("Dividir exige posicionar o cursor dentro do clipe. Mover e ajustar duração não alteram o arquivo original.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func timecode(_ value: Double) -> String {
        let total = max(0, Int(value))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

}

/// Timeline única: todas as trilhas rolam juntas, com régua, cursor, zoom de pinça,
/// arrasto do clipe selecionado e alças para aparar.
private struct EditorTimeline: View {
    @EnvironmentObject private var store: ProjectStore
    let isPlaying: Bool
    let onSeek: (Double) -> Void

    @State private var pointsPerSecond = 14.0
    @State private var zoomStart: Double?
    @State private var dragSeconds = 0.0
    @State private var trimStartSeconds = 0.0
    @State private var trimEndSeconds = 0.0

    private let laneHeight: CGFloat = 44
    private let laneSpacing: CGFloat = 4
    private let rulerHeight: CGFloat = 22

    private struct Lane: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let tint: Color
    }

    private var lanes: [Lane] {
        var result = [
            Lane(id: "video", title: "Vídeo principal", symbol: "film", tint: .blue),
            Lane(id: "broll", title: "B-roll", symbol: "photo.stack", tint: .teal)
        ]
        if store.project.clips.contains(where: { $0.track == "subject" }) {
            result.append(Lane(id: "subject", title: "Pessoa recortada", symbol: "person.crop.rectangle", tint: .indigo))
        }
        if store.project.clips.contains(where: { $0.track == "motion" }) {
            result.append(Lane(id: "motion", title: "Motion", symbol: "wand.and.stars", tint: .yellow))
        }
        if !store.project.overlays.isEmpty { result.append(Lane(id: "#text", title: "Textos", symbol: "textformat", tint: .purple)) }
        if !store.project.captionWords.isEmpty { result.append(Lane(id: "#captions", title: "Legendas", symbol: "captions.bubble", tint: .purple)) }
        result.append(Lane(id: "voice", title: "Voz e sonoras", symbol: "mic", tint: .green))
        result.append(Lane(id: "audio", title: "Trilha musical", symbol: "music.note", tint: .orange))
        if store.project.clips.contains(where: { $0.track == "sfx" }) {
            result.append(Lane(id: "sfx", title: "Efeitos sonoros", symbol: "speaker.wave.2", tint: .pink))
        }
        if store.project.clips.contains(where: { $0.track == "captions" }) {
            result.append(Lane(id: "captions", title: "Clipes em legendas", symbol: "text.bubble", tint: .purple))
        }
        return result
    }

    private var contentWidth: CGFloat {
        CGFloat((store.timelineDuration + 10) * pointsPerSecond)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(spacing: laneSpacing) {
                Color.clear.frame(height: rulerHeight)
                ForEach(lanes) { lane in
                    Image(systemName: lane.symbol)
                        .font(.caption2)
                        .foregroundStyle(lane.tint)
                        .frame(width: 24, height: laneHeight)
                        .accessibilityLabel(lane.title)
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(0...Int(store.timelineDuration / 5) + 2, id: \.self) { index in
                                Color.clear.frame(width: CGFloat(5 * pointsPerSecond), height: 1).id(index)
                            }
                        }
                        VStack(alignment: .leading, spacing: laneSpacing) {
                            ruler
                            ForEach(lanes) { lane in laneView(lane) }
                        }
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: rulerHeight + CGFloat(lanes.count) * (laneHeight + laneSpacing))
                            .offset(x: CGFloat(store.playhead * pointsPerSecond))
                            .allowsHitTesting(false)
                    }
                    .frame(width: contentWidth, alignment: .leading)
                }
                .onChange(of: Int(store.playhead / 5)) { _, block in
                    if isPlaying { withAnimation(.linear(duration: 0.2)) { proxy.scrollTo(block, anchor: .leading) } }
                }
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let base = zoomStart ?? pointsPerSecond
                    zoomStart = base
                    pointsPerSecond = min(160, max(3, base * Double(value.magnification)))
                }
                .onEnded { _ in zoomStart = nil }
        )
    }

    private var ruler: some View {
        let step: Double = pointsPerSecond >= 40 ? 1 : pointsPerSecond >= 12 ? 5 : pointsPerSecond >= 5 ? 10 : 30
        let scale = pointsPerSecond
        return Canvas { context, size in
            var second = 0.0
            while CGFloat(second * scale) <= size.width {
                let x = CGFloat(second * scale)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height - 6))
                tick.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(tick, with: .color(.secondary), lineWidth: 1)
                let total = Int(second)
                let label = Text(String(format: "%d:%02d", total / 60, total % 60)).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                context.draw(label, at: CGPoint(x: x + 2, y: 0), anchor: .topLeading)
                second += step
            }
        }
        .frame(height: rulerHeight)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.06))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in onSeek(min(store.timelineDuration, max(0, Double(value.location.x) / pointsPerSecond))) }
        )
        .accessibilityLabel("Régua da timeline. Arraste para mover o cursor.")
    }

    @ViewBuilder
    private func laneView(_ lane: Lane) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08))
            switch lane.id {
            case "#text":
                ForEach(store.project.overlays) { overlay in
                    Text(overlay.text)
                        .font(.system(size: 9, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 5)
                        .frame(width: CGFloat(max(10, overlay.duration * pointsPerSecond)), height: laneHeight - 4, alignment: .leading)
                        .background(lane.tint.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .offset(x: CGFloat(overlay.start * pointsPerSecond))
                }
            case "#captions":
                // Canvas aguenta milhares de palavras sem pesar a interface.
                let words = store.project.captionWords
                let scale = pointsPerSecond
                Canvas { context, size in
                    for word in words {
                        let rect = CGRect(x: CGFloat(word.start * scale), y: 4, width: CGFloat(max(2, word.duration * scale - 1)), height: size.height - 8)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.purple.opacity(0.8)))
                    }
                }
            case "subject":
                // As máscaras são muitas; aparecem como um único bloco.
                let frames = store.project.clips.filter { $0.track == "subject" }
                if let first = frames.map(\.start).min(), let last = frames.map(\.end).max() {
                    Text("Pessoa · \(frames.count) quadros")
                        .font(.system(size: 9, weight: .medium)).lineLimit(1)
                        .padding(.horizontal, 5)
                        .frame(width: CGFloat(max(10, (last - first) * pointsPerSecond)), height: laneHeight - 4, alignment: .leading)
                        .background(lane.tint.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .offset(x: CGFloat(first * pointsPerSecond))
                }
            default:
                ForEach(store.project.clips.filter { $0.track == lane.id }) { clip in
                    clipView(clip, tint: lane.tint)
                }
            }
        }
        .frame(height: laneHeight)
    }

    private func clipView(_ clip: TimelineClip, tint: Color) -> some View {
        let selected = store.selectedClipID == clip.id
        let start = clip.start + (selected ? dragSeconds + trimStartSeconds : 0)
        let duration = clip.duration + (selected ? trimEndSeconds - trimStartSeconds : 0)
        let scale = pointsPerSecond
        return Text(displayName(clip.label))
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .shadow(color: .black, radius: 2)
            .padding(.horizontal, selected ? 16 : 5)
            .frame(width: CGFloat(max(10, duration * scale)), height: laneHeight - 4, alignment: .leading)
            .background {
                ZStack {
                    tint.opacity(selected ? 0.95 : 0.55)
                    if let media = store.project.media.first(where: { $0.id == clip.mediaID }) {
                        ClipPreviewStrip(media: media, clip: clip, url: store.urlForMedia(media), width: CGFloat(max(10, duration * scale)), height: laneHeight - 4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4).stroke(selected ? Color.white : Color.clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                store.selectClip(clip)
                onSeek(store.playhead)
            }
            .gesture(moveGesture(for: clip, scale: scale), including: selected ? .all : .subviews)
            .overlay(alignment: .leading) {
                if selected {
                    trimHandle
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { trimStartSeconds = Double($0.translation.width) / scale }
                            .onEnded { value in
                                store.trimSelectedStart(by: Double(value.translation.width) / scale)
                                trimStartSeconds = 0
                            })
                        .accessibilityLabel("Aparar início")
                }
            }
            .overlay(alignment: .trailing) {
                if selected {
                    trimHandle
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { trimEndSeconds = Double($0.translation.width) / scale }
                            .onEnded { value in
                                store.trimSelectedEnd(by: Double(value.translation.width) / scale)
                                trimEndSeconds = 0
                            })
                        .accessibilityLabel("Aparar fim")
                }
            }
            .offset(x: CGFloat(start * scale))
    }

    private func moveGesture(for clip: TimelineClip, scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragSeconds = Double(value.translation.width) / scale
            }
            .onEnded { value in
                store.moveSelectedClip(toStart: clip.start + Double(value.translation.width) / scale, snapTolerance: 10 / scale)
                dragSeconds = 0
            }
    }

    private var trimHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .frame(width: 14)
            .overlay { Image(systemName: "line.3.horizontal").rotationEffect(.degrees(90)).font(.system(size: 7)).foregroundStyle(.black) }
            .contentShape(Rectangle())
    }

    private func displayName(_ label: String) -> String {
        guard let marker = label.range(of: " [IASEG:") else { return label }
        return String(label[..<marker.lowerBound])
    }
}

private struct ProjectsSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var pendingDelete: ProjectSummary?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.projects) { item in
                    Button {
                        store.openProject(item.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text("\(item.clipCount) clipes · \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.id == store.project.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Apagar", role: .destructive) { pendingDelete = item }
                    }
                }
            }
            .navigationTitle("Projetos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { nameDraft = ""; showNew = true } label: { Label("Novo projeto", systemImage: "plus") }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Renomear") { nameDraft = store.project.name; showRename = true }
                    Spacer()
                    Button("Duplicar versão") { store.duplicateCurrentProject(); dismiss() }
                }
            }
            .alert("Novo projeto", isPresented: $showNew) {
                TextField("Nome", text: $nameDraft)
                Button("Criar") { store.createProject(named: nameDraft); dismiss() }
                Button("Cancelar", role: .cancel) { }
            }
            .alert("Renomear", isPresented: $showRename) {
                TextField("Nome", text: $nameDraft)
                Button("Salvar") { store.renameCurrentProject(nameDraft) }
                Button("Cancelar", role: .cancel) { }
            }
            .confirmationDialog("Apagar \"\(pendingDelete?.name ?? "")\"?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Apagar projeto e mídia", role: .destructive) {
                    if let target = pendingDelete { store.deleteProject(target.id) }
                    pendingDelete = nil
                }
            } message: {
                Text("Os arquivos copiados para este projeto saem do aparelho. Os originais na Fototeca não são afetados.")
            }
            .onAppear { store.refreshProjects() }
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let value = UInt64(cleaned, radix: 16) else { self = .white; return }
        if cleaned.count == 8 {
            self.init(.sRGB, red: Double((value >> 24) & 0xFF) / 255, green: Double((value >> 16) & 0xFF) / 255, blue: Double((value >> 8) & 0xFF) / 255, opacity: Double(value & 0xFF) / 255)
        } else if cleaned.count == 6 {
            self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255, opacity: 1)
        } else { self = .white }
    }
}
