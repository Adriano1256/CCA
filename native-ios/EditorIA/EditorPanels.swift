import SwiftUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

struct IdentifiedUUID: Identifiable {
    let id: UUID
}

private func panelBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12, content: content)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
}

// MARK: - IA local

struct AIAssistantPanel: View {
    @EnvironmentObject private var store: ProjectStore
    @ObservedObject var models: ModelManager
    @ObservedObject var agent: AgentController
    let onRequests: ([AgentRequest]) -> Void
    @State private var text = ""
    @State private var showModels = false

    var body: some View {
        panelBackground {
            HStack {
                Label("IA do editor", systemImage: "brain")
                    .font(.title3.bold())
                Spacer()
                Button { showModels = true } label: {
                    Label(models.activeModel?.name ?? "Instalar", systemImage: models.activeModel == nil ? "arrow.down.circle" : "cpu")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            if models.activeModel == nil {
                Text("Baixe um modelo uma vez, com internet. Depois a IA funciona em modo avião, e nada do seu vídeo sai do aparelho.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { showModels = true } label: { Label("Escolher modelo de IA", systemImage: "arrow.down.circle.fill") }
                    .buttonStyle(.borderedProminent)
            }
            ForEach(agent.messages) { message in
                messageView(message)
            }
            if agent.isThinking {
                HStack {
                    ProgressView()
                    Text(agent.tokens == 0 ? "Pensando…" : "Escrevendo… \(agent.tokens)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Parar") { agent.stop() }.font(.caption)
                }
            }
            HStack(alignment: .bottom) {
                TextField("Ex.: tire o som do B-roll e coloque um título no início", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agent.isThinking || models.activeModel == nil)
                .accessibilityLabel("Enviar pedido")
            }
            Text("A IA propõe e você aprova. Cortes em fala nunca são feitos por ela. Pode errar: confira, e use Desfazer se precisar.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showModels) { ModelManagerSheet(models: models) }
    }

    private func send() {
        guard let model = models.activeModel else { return }
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        let templates = MotionTemplate.loadCatalog().map(\.id)
        let summary = AgentProtocol.projectSummary(store.project, playhead: store.playhead, selectedClip: store.selectedClipID, motionTemplates: templates)
        agent.ask(request, model: model, modelURL: models.url(for: model), summary: summary)
    }

    @ViewBuilder
    private func messageView(_ message: AgentController.Message) -> some View {
        VStack(alignment: message.fromUser ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .font(.subheadline)
                .padding(10)
                .background(message.fromUser ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            if let plan = message.plan {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(plan.actions.enumerated()), id: \.offset) { _, action in
                        Label(action.readable, systemImage: "wand.and.rays").font(.caption2)
                    }
                    if message.applied {
                        Label("Aplicado", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    } else {
                        Button {
                            let outcome = store.applyAgentPlan(plan)
                            agent.markApplied(message.id)
                            if !outcome.blocked.isEmpty { agent.addNote(outcome.blocked.joined(separator: "\n")) }
                            onRequests(outcome.requests)
                        } label: { Label("Aplicar na timeline", systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
    }
}

struct ModelManagerSheet: View {
    @ObservedObject var models: ModelManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(String(format: "Este aparelho tem %.0f GB de memória. Recomendado: %@.", models.memoryGB, models.recommended.name))
                        .font(.subheadline)
                    Text("O download precisa de internet só uma vez, e use Wi-Fi: os arquivos são grandes. Nenhum vídeo é enviado.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(LocalModel.catalog) { model in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(model.name).font(.headline)
                            if model.id == models.recommended.id {
                                Text("RECOMENDADO").font(.system(size: 9, weight: .bold)).padding(4).background(.green.opacity(0.25), in: Capsule())
                            }
                            Spacer()
                            Text(String(format: "%.1f GB", Double(model.approximateBytes) / 1_000_000_000)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(model.detail).font(.caption).foregroundStyle(.secondary)
                        if models.memoryGB < model.minimumMemoryGB {
                            Label("Pode faltar memória neste aparelho", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                        }
                        if models.downloadingID == model.id {
                            ProgressView(value: models.progress)
                            Button("Cancelar") { models.cancelDownload() }.font(.caption)
                        } else if models.installed.contains(model.id) {
                            HStack {
                                Button(models.selectedID == model.id ? "Em uso" : "Usar este") { models.selectedID = model.id }
                                    .buttonStyle(.bordered)
                                    .disabled(models.selectedID == model.id)
                                Button("Apagar", role: .destructive) { models.delete(model) }
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            Button("Baixar") { models.download(model) }
                                .buttonStyle(.borderedProminent)
                                .disabled(models.downloadingID != nil)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let message = models.message {
                    Text(message).font(.caption)
                }
            }
            .navigationTitle("Modelos de IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } } }
        }
    }
}

// MARK: - Motion

struct MotionGalleryPanel: View {
    @EnvironmentObject private var store: ProjectStore
    @ObservedObject var engine: MotionEngine
    let width: Int
    let height: Int
    @State private var catalog: [MotionTemplate] = []
    @State private var selected: MotionTemplate?
    @State private var showImporter = false
    @State private var errorText: String?

    var body: some View {
        panelBackground {
            Label("Motion", systemImage: "wand.and.stars").font(.title3.bold())
            Text("Animações em HTML e GSAP, como no HyperFrames, geradas aqui no aparelho e sem internet. Elas usam as cores e o logo do cliente do projeto e se adaptam à proporção escolhida.")
                .font(.caption).foregroundStyle(.secondary)
            if engine.isRendering {
                ProgressView(value: engine.progress)
                HStack {
                    Text(engine.status).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancelar") { engine.cancel() }.font(.caption)
                }
            }
            ForEach(Array(Set(catalog.map(\.category))).sorted(), id: \.self) { category in
                Text(category).font(.subheadline.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(catalog.filter { $0.category == category }) { template in
                        Button { selected = template } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name).font(.caption.weight(.semibold)).multilineTextAlignment(.leading)
                                Text(template.transparent ? "Sobre o vídeo" : "Tela cheia").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .padding(8)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(engine.isRendering)
                    }
                }
            }
            Button { showImporter = true } label: { Label("Importar composição HTML", systemImage: "square.and.arrow.down") }
                .buttonStyle(.bordered)
                .disabled(engine.isRendering)
            Text("Aceita composições no formato do HyperFrames, como as que eu gero para você no Claude. Vídeo e áudio dentro do HTML ainda não são aceitos.")
                .font(.caption2).foregroundStyle(.secondary)
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { if catalog.isEmpty { catalog = MotionTemplate.loadCatalog() } }
        .sheet(item: $selected) { template in
            MotionTemplateSheet(template: template, engine: engine, width: width, height: height)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.html]) { result in
            if case .success(let url) = result { importHTML(url) }
        }
    }

    private func importHTML(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let html = try? String(contentsOf: url, encoding: .utf8) else {
            errorText = "Não foi possível ler o arquivo."
            return
        }
        let output = store.newMotionURL()
        let name = url.deletingPathExtension().lastPathComponent
        let duration = MotionImport.duration(in: html) ?? 5
        let start = store.playhead
        errorText = nil
        Task {
            do {
                let warnings = try await engine.renderImported(html: html, width: width, height: height, frameRate: 30, output: output)
                store.addMotionClip(file: output, name: name, start: start, duration: duration, opaque: false)
                if !warnings.isEmpty { errorText = "Estes recursos dependem de internet e não foram carregados: \(warnings.joined(separator: ", "))" }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

struct MotionTemplateSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let template: MotionTemplate
    @ObservedObject var engine: MotionEngine
    let width: Int
    let height: Int
    @State private var values: [String: String] = [:]
    @State private var duration = 4.0
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                ForEach(template.fields, id: \.self) { field in
                    TextField(MotionTemplate.fieldTitles[field] ?? field, text: Binding(get: { values[field] ?? "" }, set: { values[field] = $0 }), axis: .vertical)
                }
                if template.id == "lista-entregas" {
                    Text("Em Subtítulo, separe os itens com ponto e vírgula.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Duração") {
                    Stepper(value: $duration, in: 0.5...60, step: 0.5) { Text(String(format: "%.1f s", duration)) }
                }
                Section {
                    Text(store.currentClient.map { "Cliente: \($0.name)" } ?? "Sem cliente neste projeto: usa as cores padrão.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "Entra na timeline em %.1f s, no cursor.", store.playhead))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Gerar") { generate() } }
            }
            .onAppear { duration = template.duration }
        }
    }

    private func generate() {
        var all = values
        let client = store.currentClient
        all["cor1"] = client?.primaryHex ?? "#1F6FEB"
        all["cor2"] = client?.secondaryHex ?? "#FFFFFF"
        all["logo"] = store.logoDataURI(for: client)
        let output = store.newMotionURL()
        let start = store.playhead
        let chosen = duration
        let item = template
        let w = width, h = height
        dismiss()
        Task {
            do {
                try await engine.renderTemplate(item, values: all, duration: chosen, width: w, height: h, frameRate: 30, output: output)
                store.addMotionClip(file: output, name: item.name, start: start, duration: chosen, opaque: !item.transparent)
            } catch {
                store.status = error.localizedDescription
            }
        }
    }
}

// MARK: - Cor

struct ColorPanel: View {
    @EnvironmentObject private var store: ProjectStore
    @Binding var showLUTImporter: Bool

    private func binding(_ key: String, _ path: WritableKeyPath<ClipLook, Double>, fallback: Double) -> Binding<Double> {
        Binding(
            get: { store.selectedClip?.look[keyPath: path] ?? fallback },
            set: { value in store.updateSelectedLook(key) { $0[keyPath: path] = value } }
        )
    }

    private func slider(_ title: String, _ key: String, _ path: WritableKeyPath<ClipLook, Double>, _ range: ClosedRange<Double>, neutral: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: range.upperBound > 100 ? "%.0f" : "%.2f", binding(key, path, fallback: neutral).wrappedValue))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Button { store.updateSelectedLook(key) { $0[keyPath: path] = neutral } } label: { Image(systemName: "arrow.counterclockwise").font(.caption2) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voltar \(title) ao normal")
            }
            Slider(value: binding(key, path, fallback: neutral), in: range)
        }
    }

    var body: some View {
        panelBackground {
            Label("Cor", systemImage: "circle.lefthalf.filled").font(.title3.bold())
            if store.selectedClip == nil {
                Text("Toque em um clipe na timeline para ajustar a cor.").font(.caption).foregroundStyle(.secondary)
            } else {
                slider("Exposição", "exposure", \.exposure, -2...2, neutral: 0)
                slider("Contraste", "contrast", \.contrast, 0.5...1.5, neutral: 1)
                slider("Saturação", "saturation", \.saturation, 0...2, neutral: 1)
                slider("Temperatura", "temperature", \.temperature, 3000...10000, neutral: 6500)
                slider("Matiz", "tint", \.tint, -100...100, neutral: 0)
                slider("Sombras", "shadows", \.shadows, -1...1, neutral: 0)
                slider("Realces", "highlights", \.highlights, 0...1, neutral: 1)
                Divider()
                HStack {
                    Button { showLUTImporter = true } label: { Label("Importar LUT .cube", systemImage: "camera.filters") }
                        .buttonStyle(.bordered)
                    if store.selectedClip?.look.lutRelativePath != nil {
                        Button("Tirar LUT", role: .destructive) { store.updateSelectedLook("lut") { $0.lutRelativePath = nil } }
                            .buttonStyle(.bordered)
                    }
                }
                if store.selectedClip?.look.lutRelativePath != nil {
                    slider("Força do LUT", "lutIntensity", \.lutIntensity, 0...1, neutral: 1)
                }
                Button { store.copySelectedColorToTrack() } label: { Label("Aplicar em toda a trilha", systemImage: "square.on.square") }
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Efeitos do clipe

struct ClipEffectsPanel: View {
    @EnvironmentObject private var store: ProjectStore
    let clip: TimelineClip
    let onReviewSpeech: () -> Void
    @State private var transitionKind = "dissolve"
    @State private var transitionDuration = 0.5

    private var media: LocalMedia? { store.project.media.first { $0.id == clip.mediaID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if AgentProtocol.isSpeech(clip, media: media) {
                Button(action: onReviewSpeech) { Label("Revisar e cortar a fala", systemImage: "text.quote") }
                    .buttonStyle(.borderedProminent)
            }
            if media?.kind != "Imagem" {
                HStack {
                    Text("Velocidade").font(.caption)
                    Slider(value: Binding(get: { store.selectedClip?.look.speed ?? 1 }, set: { store.setSelectedSpeed($0) }), in: 0.25...4)
                    Text(String(format: "%.2fx", store.selectedClip?.look.speed ?? 1)).font(.caption2.monospacedDigit()).frame(width: 44)
                }
            }
            HStack {
                Text("Zoom").font(.caption)
                Slider(value: Binding(get: { store.selectedClip?.look.scale ?? 1 }, set: { value in store.updateSelectedLook("scale") { $0.scale = value } }), in: 0.5...3)
            }
            HStack {
                Text("Horizontal").font(.caption)
                Slider(value: Binding(get: { store.selectedClip?.look.offsetX ?? 0 }, set: { value in store.updateSelectedLook("x") { $0.offsetX = value } }), in: -1...1)
            }
            HStack {
                Text("Vertical").font(.caption)
                Slider(value: Binding(get: { store.selectedClip?.look.offsetY ?? 0 }, set: { value in store.updateSelectedLook("y") { $0.offsetY = value } }), in: -1...1)
            }
            Toggle("Zoom lento (Ken Burns)", isOn: Binding(get: { store.selectedClip?.look.kenBurns ?? false }, set: { value in store.updateSelectedLook("kb") { $0.kenBurns = value } }))
                .font(.caption)
            Toggle("Fundo verde (chroma key)", isOn: Binding(get: { store.selectedClip?.look.chromaHex != nil }, set: { value in store.updateSelectedLook("chroma") { $0.chromaHex = value ? "#00FF00" : nil } }))
                .font(.caption)
            if store.selectedClip?.look.chromaHex != nil {
                HStack {
                    Text("Tolerância").font(.caption)
                    Slider(value: Binding(get: { store.selectedClip?.look.chromaTolerance ?? 0.18 }, set: { value in store.updateSelectedLook("chromaT") { $0.chromaTolerance = (value * 50).rounded() / 50 } }), in: 0.04...0.4)
                }
            }
            HStack {
                Picker("Transição", selection: $transitionKind) {
                    Text("Dissolver").tag("dissolve")
                    Text("Deslizar").tag("slideLeft")
                    Text("Subir").tag("slideUp")
                    Text("Zoom").tag("zoom")
                    Text("Cortina").tag("wipe")
                    Text("Flash").tag("flash")
                }
                .pickerStyle(.menu)
                Stepper(String(format: "%.1f s", transitionDuration), value: $transitionDuration, in: 0.1...3, step: 0.1).font(.caption)
            }
            Button { store.addTransitionToSelected(kind: transitionKind, duration: transitionDuration) } label: {
                Label("Transição na entrada deste clipe", systemImage: "rectangle.2.swap")
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Revisão de fala

/// Antes de cortar uma fala: transcrição, trecho, contexto, durações e aprovação explícita.
struct SonoraCutSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let clipID: UUID
    @State private var firstWord: Int?
    @State private var lastWord: Int?
    @State private var isTranscribing = false

    private var clip: TimelineClip? { store.project.clips.first { $0.id == clipID } }
    private var words: [CaptionWord] {
        guard let clip else { return [] }
        return store.project.captionWords.filter { $0.start >= clip.start - 0.01 && $0.start < clip.end }.sorted { $0.start < $1.start }
    }

    private var range: AudioDuckingRange? {
        guard let firstWord else { return nil }
        let list = words
        let last = lastWord ?? firstWord
        guard firstWord < list.count, last < list.count else { return nil }
        let low = min(firstWord, last), high = max(firstWord, last)
        return AudioDuckingRange(start: list[low].start, end: list[high].start + list[high].duration)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if words.isEmpty {
                        Text("Esta sonora ainda não foi transcrita. Sem o texto, nenhum corte pode ser proposto.").font(.subheadline)
                        Button {
                            isTranscribing = true
                            store.selectedClipID = clipID
                            store.selectedMediaID = clip?.mediaID
                            Task {
                                await store.transcribeSelectedClip()
                                isTranscribing = false
                            }
                        } label: { Label(isTranscribing ? "Transcrevendo…" : "Transcrever agora", systemImage: "text.quote") }
                            .buttonStyle(.borderedProminent)
                            .disabled(isTranscribing)
                    } else {
                        Text("Toque na primeira e na última palavra que quer tirar.").font(.subheadline)
                        wordFlow
                        if let range, let clip {
                            let preview = SpeechCutPreview.make(words: store.project.captionWords, clip: clip, removing: range)
                            GroupBox("Como fica") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Antes: …\(preview.before)").font(.caption)
                                    Text("Sai: \(preview.removed)").font(.caption.bold()).foregroundStyle(.red)
                                    Text("Depois: \(preview.after)…").font(.caption)
                                    Text(String(format: "Duração: %.1f s → %.1f s", preview.originalDuration, preview.finalDuration)).font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text("Confira se a frase continua fazendo sentido e não muda o que a pessoa quis dizer.")
                                .font(.caption).foregroundStyle(.orange)
                            Button {
                                store.applyApprovedSpeechCut(clipID: clipID, range: range)
                                dismiss()
                            } label: { Label("Aprovar este corte", systemImage: "checkmark.seal") }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Revisar fala")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
    }

    private var wordFlow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 4)], alignment: .leading, spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Button {
                    if firstWord == nil || lastWord != nil {
                        firstWord = index
                        lastWord = nil
                    } else {
                        lastWord = index
                    }
                } label: {
                    Text(word.text)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(isSelected(index) ? Color.red.opacity(0.45) : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isSelected(_ index: Int) -> Bool {
        guard let firstWord else { return false }
        let last = lastWord ?? firstWord
        return index >= min(firstWord, last) && index <= max(firstWord, last)
    }
}

// MARK: - Clientes

struct ClientProfilesPanel: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var editing: ClientProfile?
    @State private var showNew = false
    @State private var nameDraft = ""

    var body: some View {
        panelBackground {
            Label("Cliente do projeto", systemImage: "building.2").font(.title3.bold())
            Picker("Cliente", selection: Binding(get: { store.project.clientID }, set: { store.setClient($0) })) {
                Text("Nenhum").tag(UUID?.none)
                ForEach(store.clients) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .pickerStyle(.menu)
            Text("Cada cliente guarda seu logo, cores e tempos. Eles são usados nos motions e na montagem, sem misturar um cliente com outro.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(store.clients) { client in
                Button { editing = client } label: {
                    HStack {
                        Circle().fill(Color(hex: client.primaryHex)).frame(width: 18, height: 18)
                        Text(client.name).font(.subheadline)
                        Spacer()
                        Image(systemName: client.logoRelativePath == nil ? "photo.badge.plus" : "checkmark.circle").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 40)
                }
                .buttonStyle(.plain)
            }
            Button { nameDraft = ""; showNew = true } label: { Label("Novo cliente", systemImage: "plus") }
                .buttonStyle(.bordered)
            Divider()
            Picker("Perfil de edição", selection: Binding(get: { store.project.profile }, set: { store.setProfile($0) })) {
                ForEach(["Institucional", "Stories", "Entrevistas", "Eventos", "Viral", "Publicidade", "Documentário", "Casamento"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Text("Hoje só Institucional e Stories têm regras de montagem próprias. Nos outros perfis, peça o que quiser para a IA.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $editing) { client in ClientEditorSheet(client: client) }
        .alert("Novo cliente", isPresented: $showNew) {
            TextField("Nome", text: $nameDraft)
            Button("Criar") { store.addClient(named: nameDraft) }
            Button("Cancelar", role: .cancel) { }
        }
    }
}

struct ClientEditorSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State var client: ClientProfile
    @State private var showLogoImporter = false

    private func colorBinding(_ path: WritableKeyPath<ClientProfile, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: client[keyPath: path]) },
            set: { value in client[keyPath: path] = value.hexString }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $client.name)
                Section("Identidade") {
                    ColorPicker("Cor principal", selection: colorBinding(\.primaryHex), supportsOpacity: false)
                    ColorPicker("Cor do texto sobre ela", selection: colorBinding(\.secondaryHex), supportsOpacity: false)
                    Button(client.logoRelativePath == nil ? "Escolher logo" : "Trocar logo") { showLogoImporter = true }
                }
                Section("Montagem") {
                    Stepper(String(format: "Abertura: %.0f s", client.openingDuration), value: $client.openingDuration, in: 2...20)
                    Stepper(String(format: "Duração mínima: %.0f s", client.targetMinimum), value: $client.targetMinimum, in: 10...600, step: 5)
                    Stepper(String(format: "Duração máxima: %.0f s", client.targetMaximum), value: $client.targetMaximum, in: 10...900, step: 5)
                }
                Section("Observações") {
                    TextField("Ex.: autoridade encerra o vídeo", text: $client.notes, axis: .vertical)
                }
                Section {
                    Button("Apagar cliente", role: .destructive) {
                        store.deleteClient(client.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(client.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        store.updateClient(client)
                        dismiss()
                    }
                }
            }
            .fileImporter(isPresented: $showLogoImporter, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result {
                    store.importClientLogo(from: url, clientID: client.id)
                    client.logoRelativePath = store.clients.first { $0.id == client.id }?.logoRelativePath
                }
            }
        }
    }
}

extension Color {
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(max(0, min(1, red)) * 255), Int(max(0, min(1, green)) * 255), Int(max(0, min(1, blue)) * 255))
    }
}

// MARK: - Narração

struct VoiceRecorderSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: isRecording ? "mic.fill" : "mic").font(.system(size: 60)).foregroundStyle(isRecording ? .red : .primary)
                Text(isRecording ? "Gravando…" : String(format: "A narração entra em %.1f s, no cursor.", store.playhead)).font(.subheadline)
                Button(isRecording ? "Parar e colocar na timeline" : "Começar a gravar") { toggle() }
                    .buttonStyle(.borderedProminent)
                if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
            }
            .padding()
            .navigationTitle("Narração")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { stopSession(); dismiss() } } }
        }
    }

    private func stopSession() {
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    private func toggle() {
        if isRecording, let recorder {
            let url = recorder.url
            stopSession()
            isRecording = false
            Task {
                await store.importFiles([url], moveFiles: true)
                if let item = store.project.media.last { store.setSonora(item.id, true) }
                dismiss()
            }
            return
        }
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                errorText = "Sem permissão para usar o microfone. Libere em Ajustes."
                return
            }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default)
                try session.setActive(true)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Narração-\(Int(Date().timeIntervalSince1970)).m4a")
                let next = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ])
                next.record()
                recorder = next
                isRecording = true
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
