import Foundation
import Combine
import AVFoundation
import WebKit
import UIKit

struct MotionTemplate: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var category: String
    var duration: Double
    var transparent: Bool
    var fields: [String]

    static let fieldTitles = ["titulo": "Título", "subtitulo": "Subtítulo", "numero": "Número", "estilo": "Estilo", "fundo": "Cor de fundo (vazio = transparente)"]
    /// Estilos do texto animado livre; a IA também escolhe por estes nomes.
    static let kineticStyles = MotionStyles.all

    static func loadCatalog() -> [MotionTemplate] {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Motion"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MotionTemplate].self, from: data)) ?? []
    }
}

enum MotionError: LocalizedError {
    case missingLibrary
    case loadFailed(String)
    case notComposition
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingLibrary: return "Os arquivos de motion não foram encontrados no app."
        case .loadFailed(let reason): return "A composição não abriu: \(reason)"
        case .notComposition: return "Este HTML não é uma composição: falta data-composition-id."
        case .writerFailed(let reason): return "Não foi possível gravar o vídeo do motion: \(reason)"
        }
    }
}

/// Renderiza HTML + GSAP quadro a quadro, como o HyperFrames, dentro do aparelho e sem internet:
/// abre a página, avança a timeline, fotografa o quadro e grava em vídeo com transparência.
@MainActor
final class MotionEngine: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var isRendering = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status = ""

    private var webView: WKWebView?
    private var renderWindow: UIWindow?
    /// Estado da última composição: erros, bibliotecas carregadas e fontes.
    @Published private(set) var lastDiagnostics = ""
    private static let diagnosticsScript = "JSON.stringify({erros:window.__errors||[],gsap:typeof gsap,kit:typeof cssVars,seek:typeof window.__seek,timelines:Object.keys(window.__timelines||{}),texto:(document.body.innerText||'').trim().length,fontes:document.fonts?document.fonts.status:'?'})"
    private var navigation: CheckedContinuation<Void, Error>?
    private var cancelled = false

    func cancel() { cancelled = true }

    /// Pasta de trabalho com bibliotecas e fontes; o HTML gerado fica em `templates/`, como no pacote original.
    private func workspace() throws -> URL {
        guard let source = Bundle.main.url(forResource: "Motion", withExtension: nil) else { throw MotionError.missingLibrary }
        return source
    }

    private func prepareFolder() throws -> URL {
        let source = try workspace()
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        // A pasta leva a versão do app, para os modelos serem atualizados junto com ele.
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let folder = caches.appendingPathComponent("EditorIA-Motion-\(build)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.appendingPathComponent("lib/runtime.js").path) {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.copyItem(at: source, to: folder)
        }
        return folder
    }

    /// HTML final de um modelo, com os textos e cores do pedido.
    private func templateHTML(_ template: MotionTemplate, folder: URL, values: [String: String], duration: Double) throws -> String {
        let url = folder.appendingPathComponent("templates/\(template.id).html")
        let html = try String(contentsOf: url, encoding: .utf8)
        let json = try JSONSerialization.data(withJSONObject: values)
        let text = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
        return html
            .replacingOccurrences(of: "{{VARS_JSON}}", with: text)
            .replacingOccurrences(of: "{{DURATION}}", with: String(format: "%.3f", duration))
    }

    func renderTemplate(_ template: MotionTemplate, values: [String: String], duration: Double, width: Int, height: Int, frameRate: Int, output: URL) async throws {
        let folder = try prepareFolder()
        let html = try templateHTML(template, folder: folder, values: values, duration: duration)
        try await render(html: html, folder: folder, duration: duration, width: width, height: height, frameRate: frameRate, output: output)
    }

    /// Composição vinda de fora, por exemplo uma que eu tenha gerado no HyperFrames.
    func renderImported(html source: String, width: Int, height: Int, frameRate: Int, output: URL) async throws -> [String] {
        guard MotionImport.isComposition(source) else { throw MotionError.notComposition }
        let folder = try prepareFolder()
        let prepared = MotionImport.prepare(html: source, libraryPath: "../lib")
        let duration = MotionImport.duration(in: source) ?? 5
        try await render(html: prepared.html, folder: folder, duration: duration, width: width, height: height, frameRate: frameRate, output: output)
        return prepared.warnings
    }

    private func render(html: String, folder: URL, duration: Double, width: Int, height: Int, frameRate: Int, output: URL) async throws {
        guard !isRendering else { throw MotionError.loadFailed("Já existe um motion em andamento.") }
        isRendering = true
        cancelled = false
        progress = 0
        status = "Abrindo a composição"
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isRendering = false
            UIApplication.shared.isIdleTimerDisabled = false
            webView?.removeFromSuperview()
            webView = nil
            renderWindow?.isHidden = true
            renderWindow = nil
        }

        let page = folder.appendingPathComponent("templates/_render_\(UUID().uuidString).html")
        try html.write(to: page, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: page) }

        let view = try await makeWebView(width: width, height: height)
        webView = view
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigation = continuation
            view.loadFileURL(page, allowingReadAccessTo: folder)
        }
        // Espera as fontes carregarem de verdade (evaluateJavaScript não espera promessas).
        for _ in 0..<30 {
            let status = try? await view.evaluateJavaScript("document.fonts ? document.fonts.status : 'loaded'") as? String
            if status == "loaded" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(120))
        lastDiagnostics = (try? await view.evaluateJavaScript(Self.diagnosticsScript) as? String) ?? "sem diagnóstico"

        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw MotionError.writerFailed("codec não suportado") }
        writer.add(input)
        guard writer.startWriting() else { throw MotionError.writerFailed(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)

        let total = max(1, Int((duration * Double(frameRate)).rounded()))
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        configuration.snapshotWidth = NSNumber(value: Double(width) / Double(view.window?.screen.scale ?? UIScreen.main.scale))

        for frame in 0..<total {
            if cancelled {
                input.markAsFinished()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: output)
                throw MotionError.writerFailed("cancelado")
            }
            let time = Double(frame) / Double(frameRate)
            _ = try await view.evaluateJavaScript("window.__seek(\(time)); true")
            let image = try await view.takeSnapshot(configuration: configuration)
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool, let buffer = makeBuffer(pool: pool, image: image, width: width, height: height) else {
                throw MotionError.writerFailed("quadro inválido")
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(frameRate))) else {
                throw MotionError.writerFailed(writer.error?.localizedDescription ?? "falha ao gravar")
            }
            progress = Double(frame + 1) / Double(total)
            status = "Quadro \(frame + 1) de \(total)"
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw MotionError.writerFailed(writer.error?.localizedDescription ?? "") }
    }

    private func makeWebView(width: Int, height: Int) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Guarda erros de JavaScript da composição, para aparecerem no relatório.
        configuration.userContentController.addUserScript(WKUserScript(source: "window.__errors=[];window.addEventListener('error',function(e){window.__errors.push(String(e.message)+' '+String(e.filename||'').split('/').pop()+':'+e.lineno)});", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Tudo local: bloqueia qualquer acesso à internet a partir da composição.
        let rules = #"[{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]"#
        if let list = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "editoria-offline", encodedContentRuleList: rules) {
            configuration.userContentController.add(list)
        }
        let scale = UIScreen.main.scale
        let frame = CGRect(x: 0, y: 0, width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        let view = WKWebView(frame: frame, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = self
        // A página só é redesenhada a cada quadro se estiver numa janela visível.
        // Ela ganha uma janela própria, atrás da janela do app, para não aparecer na tela.
        view.isUserInteractionEnabled = false
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let window = UIWindow(windowScene: scene)
            window.frame = frame
            window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue - 1)
            window.isUserInteractionEnabled = false
            window.backgroundColor = .clear
            window.isHidden = false
            window.addSubview(view)
            renderWindow = window
        }
        // Mesmas medidas em px CSS que a composição espera, independente da escala da tela.
        view.pageZoom = 1 / scale
        return view
    }

    private func makeBuffer(pool: CVPixelBufferPool, image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        var result: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &result)
        guard let buffer = result else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.navigation?.resume()
            self.navigation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in
            self.navigation?.resume(throwing: MotionError.loadFailed(text))
            self.navigation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in
            self.navigation?.resume(throwing: MotionError.loadFailed(text))
            self.navigation = nil
        }
    }
}
