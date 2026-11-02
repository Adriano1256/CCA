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
    var fillsHeight = false
    @State private var text = ""
    @State private var showModels = false

    private let suggestions = [
        "Monta o vídeo institucional",
        "Coloca legenda animada karaokê",
        "Tira o som do B-roll",
        "Coloca uma música emocionante",
        "Deixa com visual de cinema",
        "Faz os Stories"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Peça a edição", systemImage: "bubble.left.and.text.bubble.right.fill")
                    .font(.headline)
                Spacer()
                Button { showModels = true } label: {
                    Label(models.activeModel?.name ?? "Modelos", systemImage: models.activeModel == nil ? "arrow.down.circle" : "cpu")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
            }
            if store.isPreparing {
                HStack {
                    ProgressView()
                    Text(store.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if agent.messages.isEmpty {
                            Text(models.activeModel == nil
                                 ? "Sem modelo de IA, o chat entende só os pedidos mais comuns. Baixe um modelo uma vez, com internet, para pedir qualquer coisa em modo avião."
                                 : "Importe seus vídeos e diga o que quer. A IA conhece seus clipes, as falas e o que aparece nas imagens.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(agent.messages) { message in
                            messageView(message).id(message.id)
                        }
                        if agent.isThinking {
                            HStack {
                                ProgressView()
                                Text(agent.tokens == 0 ? "Pensando…" : "Escrevendo… \(agent.tokens)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Parar") { agent.stop() }.font(.caption)
                            }
                            .id("pensando")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: fillsHeight ? .infinity : 420)
                .onChange(of: agent.messages.count) { _, _ in
                    if let last = agent.messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { send(suggestion) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .disabled(agent.isThinking)
                    }
                }
            }
            HStack(alignment: .bottom) {
                TextField("Peça aqui o que quer no vídeo", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    send(text)
                    text = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agent.isThinking)
                .accessibilityLabel("Enviar pedido")
            }
            Text("A edição entra direto na timeline. Se não gostar, use Desfazer. Corte em fala sempre pede sua aprovação.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showModels) { ModelManagerSheet(models: models) }
    }

    private func send(_ raw: String) {
        let request = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        if let model = models.activeModel {
            let summary = AgentProtocol.projectSummary(
                store.project,
                playhead: store.playhead,
                selectedClip: store.selectedClipID,
                motionTemplates: MotionTemplate.loadCatalog().map(\.id) + MotionTemplate.kineticStyles,
                libraryMoods: Array(Set(store.library.map(\.mood))).sorted()
            )
            agent.ask(request, model: model, modelURL: models.url(for: model), summary: summary, fallback: RuleAgent.plan(for: request, project: store.project))
        } else if let plan = RuleAgent.plan(for: request, project: store.project) {
            agent.addExchange(request: request, plan: plan)
        } else {
            agent.addExchange(request: request, plan: AgentPlan(reply: "Sem modelo de IA instalado, só entendo pedidos comuns. Toque em Modelos para instalar e poder pedir qualquer coisa.", actions: []))
        }
    }

    @ViewBuilder
    private func messageView(_ message: AgentController.Message) -> some View {
        VStack(alignment: message.fromUser ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .font(.subheadline)
                .padding(10)
                .background(message.fromUser ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            if message.applied, !message.done.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(message.done, id: \.self) { line in
                        Label(line, systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                    }
                    if message.id == agent.messages.last(where: { $0.applied })?.id {
                        Button { store.undo() } label: { Label("Desfazer", systemImage: "arrow.uturn.backward") }
                            .font(.caption)
                            .buttonStyle(.bordered)
                    }
                }
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
                    Text(AIStorageBudget.summary(installedBytes: models.installedBytes()))
                        .font(.caption.weight(.semibold))
                }
                WhisperModelSection()
                Section("Modelo de linguagem") { ForEach(LocalModel.catalog) { model in
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
                                Button(models.selectedID == model.id ? "Em uso" : "Usar este") { models.select(model) }
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
                } }
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
                    if field == "estilo" {
                        Picker("Estilo", selection: Binding(get: { values[field] ?? "impacto" }, set: { values[field] = $0 })) {
                            ForEach(MotionTemplate.kineticStyles, id: \.self) { Text($0).tag($0) }
                        }
                    } else {
                        TextField(MotionTemplate.fieldTitles[field] ?? field, text: Binding(get: { values[field] ?? "" }, set: { values[field] = $0 }), axis: .vertical)
                    }
                }
                if template.id == "kinetic" {
                    Text("Cada frase vira uma cena. Separe com ponto final ou com |.").font(.caption).foregroundStyle(.secondary)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(ColorLooks.names, id: \.self) { name in
                            Button(name.capitalized) { store.updateSelectedLook("preset") { ColorLooks.apply(name, to: &$0) } }
                                .font(.caption)
                                .buttonStyle(.bordered)
                        }
                    }
                }
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


// MARK: - Whisper

struct WhisperModelSection: View {
    @State private var installed = WhisperService.isInstalled
    @State private var progress: Double?
    @State private var errorText: String?

    var body: some View {
        Section("Transcrição de fala (Whisper)") {
            if installed {
                Label("Whisper instalado", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Apagar", role: .destructive) {
                    WhisperService.remove()
                    installed = false
                }
            } else if let progress {
                ProgressView(value: progress)
            } else {
                ForEach(WhisperService.options) { option in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.name).font(.headline)
                        Text(option.detail).font(.caption).foregroundStyle(.secondary)
                        Button("Baixar") { download(option) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!AIStorageBudget.fits(adding: option.bytes, installedBytes: ModelManager.installedBytesOnDisk()))
                    }
                }
                Text("Sem ele, o app tenta o reconhecimento do próprio iPhone, que pode não ter português offline.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
        }
    }

    private func download(_ option: WhisperService.Option) {
        progress = 0
        errorText = nil
        Task {
            do {
                try await WhisperService.download(option) { value in
                    Task { @MainActor in progress = value }
                }
                installed = WhisperService.isInstalled
            } catch {
                errorText = error.localizedDescription
            }
            progress = nil
        }
    }
}

// MARK: - Legendas

struct CaptionStylePanel: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var category = CaptionPreset.categories[0]

    private var current: CaptionPreset { CaptionPreset.find(store.project.captionStyle) ?? CaptionPreset.all[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Legenda animada").font(.subheadline.bold())
            CaptionLivePreview(preset: current, textHex: store.project.captionTextHex, highlightHex: store.project.captionHighlightHex)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CaptionPreset.categories, id: \.self) { name in
                        Button(name) { category = name }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(category == name ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14), in: Capsule())
                            .buttonStyle(.plain)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                ForEach(CaptionPreset.all.filter { $0.category == category }) { preset in
                    Button { choose(preset) } label: { card(preset) }
                        .buttonStyle(.plain)
                }
            }
            ColorPicker("Cor do destaque", selection: Binding(
                get: { Color(hex: store.project.captionHighlightHex) },
                set: { value in store.setCaptionOption { $0.captionHighlightHex = value.hexString } }
            ), supportsOpacity: false).font(.caption)
            ColorPicker("Cor do texto", selection: Binding(
                get: { Color(hex: store.project.captionTextHex) },
                set: { value in store.setCaptionOption { $0.captionTextHex = value.hexString } }
            ), supportsOpacity: false).font(.caption)
            HStack {
                Text("Tamanho").font(.caption)
                Slider(value: Binding(get: { store.project.captionFontSize }, set: { value in store.setCaptionOption { $0.captionFontSize = value } }), in: 40...140)
            }
            HStack {
                Text("Altura").font(.caption)
                Slider(value: Binding(get: { store.project.captionVertical ?? 0.8 }, set: { value in store.setCaptionOption { $0.captionVertical = value } }), in: 0.1...0.95)
            }
            Picker("Fonte", selection: Binding(get: { store.project.captionFontStyle }, set: { value in store.setCaptionOption { $0.captionFontStyle = value } })) {
                Text("Do estilo").tag("preset")
                Text("Forte").tag("heavy")
                Text("Redonda").tag("rounded")
                Text("Serifa").tag("serif")
            }
            .pickerStyle(.segmented)
            Toggle("Mostrar legendas", isOn: Binding(get: { store.project.captionsEnabled }, set: { value in store.setCaptionOption { $0.captionsEnabled = value } }))
                .font(.caption)
        }
    }

    private func choose(_ preset: CaptionPreset) {
        let clientColor = preset.id == "inst-cor" ? store.currentClient?.primaryHex : nil
        store.setCaptionOption {
            preset.apply(to: &$0)
            if let clientColor { $0.captionHighlightHex = clientColor }
        }
    }

    private func card(_ preset: CaptionPreset) -> some View {
        VStack(spacing: 2) {
            Text(preset.upper ? "VIRAL" : "Viral")
                .font(.custom(preset.font, size: 19))
                .foregroundStyle(Color(hex: preset.highlight))
                .shadow(color: preset.stroke == nil ? .clear : .black, radius: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(preset.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 4)
        .background(store.project.captionStyle == preset.id ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Mostra o estilo escolhido se mexendo, mesmo antes de o vídeo ter legenda.
struct CaptionLivePreview: View {
    let preset: CaptionPreset
    let textHex: String
    let highlightHex: String

    private static let sample: [CaptionWord] = ["Agora", "a", "nossa", "rua", "tem", "asfalto", "novo"].enumerated().map {
        CaptionWord(text: $0.element, start: 0.2 + Double($0.offset) * 0.42, duration: 0.38)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6)
            let frame = CaptionAnimator.frame(style: preset.id, words: Self.sample, at: time)
            ZStack {
                LinearGradient(colors: [Color(white: 0.28), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                if let frame {
                    HStack(spacing: preset.wordBox == nil ? 6 : 3) {
                        ForEach(Array(frame.words.enumerated()), id: \.offset) { _, word in
                            wordView(word, size: 22 * frame.sizeFactor)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(preset.lineBox.map { Color(hex: String($0.prefix(7))).opacity(0.75) } ?? .clear, in: RoundedRectangle(cornerRadius: 8))
                    .minimumScaleFactor(0.5)
                }
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Prévia da legenda \(preset.name)")
    }

    @ViewBuilder
    private func wordView(_ word: CaptionAnimator.WordVisual, size: Double) -> some View {
        let color = word.hasBox ? preset.boxText : (word.color ?? ((word.isActive || word.isKeyword || (word.fill ?? 0) > 0.5) ? highlightHex : textHex))
        let box = word.hasBox ? highlightHex : preset.wordBox
        Text(word.text)
            .font(word.isEmoji ? .system(size: size) : .custom(preset.font, size: word.isKeyword ? size * 1.2 : size))
            .foregroundStyle(Color(hex: color))
            .lineLimit(1)
            .padding(.horizontal, box == nil ? 0 : 4)
            .background(box.map { Color(hex: $0) } ?? .clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .bottom) {
                if word.underline { Rectangle().fill(Color(hex: highlightHex)).frame(height: 3) }
            }
            .shadow(color: preset.stroke != nil || preset.shadow == .hard ? .black : .clear, radius: 0.6, x: 1, y: 1)
            .shadow(color: (preset.shadow == .glow || word.glow) ? Color(hex: highlightHex) : .clear, radius: 6)
            .scaleEffect(x: word.state.scale, y: word.state.scale * word.state.scaleY)
            .rotationEffect(.degrees(word.state.rotation))
            .offset(x: word.state.offsetX * 340, y: word.state.offsetY * 340)
            .blur(radius: word.state.blur / 4)
            .opacity(word.state.opacity)
    }
}

// MARK: - Biblioteca de sons

struct SoundLibraryPanel: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var showImporter = false
    @State private var importKind = "music"
    @State private var importMood = LibraryItem.musicMoods[0]
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?

    var body: some View {
        GroupBox("Biblioteca de sons") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Suas músicas e efeitos, guardados no aparelho e usados em qualquer projeto, sem internet. Importe só o que você tem licença para usar.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Tipo", selection: $importKind) {
                    Text("Música").tag("music")
                    Text("Efeito").tag("sfx")
                }
                .pickerStyle(.segmented)
                .onChange(of: importKind) { _, kind in
                    importMood = kind == "music" ? LibraryItem.musicMoods[0] : LibraryItem.sfxKinds[0]
                }
                Picker("Clima", selection: $importMood) {
                    ForEach(importKind == "music" ? LibraryItem.musicMoods : LibraryItem.sfxKinds, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                Button { showImporter = true } label: { Label("Importar para a biblioteca", systemImage: "plus") }
                    .buttonStyle(.bordered)
                ForEach(store.library.filter { $0.kind == importKind }) { item in
                    HStack {
                        Button { toggle(item) } label: {
                            Image(systemName: playingID == item.id ? "stop.fill" : "play.fill").frame(width: 36, height: 36)
                        }
                        .accessibilityLabel(playingID == item.id ? "Parar" : "Ouvir")
                        VStack(alignment: .leading) {
                            Text(item.name).font(.caption.weight(.medium)).lineLimit(1)
                            Text("\(item.mood) · \(Int(item.duration)) s").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Usar") { store.addFromLibrary(item) }.font(.caption).buttonStyle(.borderedProminent)
                        Button(role: .destructive) { store.removeFromLibrary(item.id) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Tirar da biblioteca")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let kind = importKind, mood = importMood
                Task { await store.importToLibrary(urls, kind: kind, mood: mood, source: "") }
            }
        }
    }

    private func toggle(_ item: LibraryItem) {
        if playingID == item.id {
            player?.stop()
            playingID = nil
            return
        }
        player = try? AVAudioPlayer(contentsOf: store.baseDirectoryURL.appendingPathComponent(item.relativePath))
        player?.play()
        playingID = item.id
    }
}

// MARK: - Imagens na timeline

@MainActor
private enum ThumbnailCache {
    static let images = NSCache<NSString, UIImage>()
}

/// Miniaturas dos vídeos e fotos, e forma de onda do áudio, dentro dos clipes da timeline.
struct ClipPreviewStrip: View {
    let media: LocalMedia
    let clip: TimelineClip
    let url: URL
    let width: CGFloat
    let height: CGFloat
    @State private var frames: [UIImage] = []
    @State private var levels: [Float] = []

    var body: some View {
        Group {
            if media.kind == "Áudio" {
                Canvas { context, size in
                    guard !levels.isEmpty else { return }
                    let step = size.width / CGFloat(levels.count)
                    for (index, level) in levels.enumerated() {
                        let bar = max(1, CGFloat(level) * size.height)
                        let rect = CGRect(x: CGFloat(index) * step, y: (size.height - bar) / 2, width: max(1, step - 1), height: bar)
                        context.fill(Path(rect), with: .color(.white.opacity(0.75)))
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                        Image(uiImage: frame)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width / CGFloat(max(1, frames.count)), height: height)
                            .clipped()
                    }
                }
                .opacity(0.8)
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .task(id: "\(clip.sourceIn)-\(clip.duration)-\(Int(width / 60))") { await load() }
    }

    @MainActor
    private func load() async {
        if media.kind == "Áudio" {
            if levels.isEmpty {
                levels = (try? await WaveformReader.levels(url: url, sourceIn: clip.sourceIn, duration: clip.duration * clip.look.speed, count: 80)) ?? []
            }
            return
        }
        if media.kind == "Imagem" {
            let key = url.path as NSString
            if let cached = ThumbnailCache.images.object(forKey: key) {
                frames = [cached]
            } else if let still = TimelineCompositionBuilder.loadStill(url: url, maxPixelSize: 160) {
                let image = UIImage(cgImage: still)
                ThumbnailCache.images.setObject(image, forKey: key)
                frames = [image]
            }
            return
        }
        let count = max(1, min(8, Int(width / 60)))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        var result: [UIImage] = []
        for index in 0..<count {
            let seconds = clip.sourceIn + clip.duration * clip.look.speed * (Double(index) + 0.5) / Double(count)
            let key = "\(url.lastPathComponent)#\(Int(seconds * 2))" as NSString
            if let cached = ThumbnailCache.images.object(forKey: key) {
                result.append(cached)
            } else if let frame = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image {
                let image = UIImage(cgImage: frame)
                ThumbnailCache.images.setObject(image, forKey: key)
                result.append(image)
            }
        }
        frames = result
    }
}

enum WaveformReader {
    static func levels(url: URL, sourceIn: Double, duration: Double, count: Int) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { return [] }
        return try await Task.detached(priority: .utility) { () throws -> [Float] in
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(start: CMTime(seconds: sourceIn, preferredTimescale: 600), duration: CMTime(seconds: duration, preferredTimescale: 600))
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 2000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            guard reader.canAdd(output) else { return [] }
            reader.add(output)
            guard reader.startReading() else { return [] }
            var peaks = [Float](repeating: 0, count: count)
            let perBar = max(1, Int(duration * 2000) / count)
            var sampleIndex = 0
            while let buffer = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let total = CMBlockBufferGetDataLength(block) / 2
                guard total > 0 else { continue }
                var pcm = [Int16](repeating: 0, count: total)
                let status = pcm.withUnsafeMutableBytes { raw in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: total * 2, destination: raw.baseAddress!)
                }
                guard status == kCMBlockBufferNoErr else { continue }
                for value in pcm {
                    let bar = min(count - 1, sampleIndex / perBar)
                    peaks[bar] = max(peaks[bar], abs(Float(value)) / 32768)
                    sampleIndex += 1
                }
            }
            return peaks
        }.value
    }
}
