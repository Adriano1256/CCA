#if DEBUG
import Foundation
import AVFoundation
import UIKit

/// Teste automático rodado na nuvem, no simulador, com arquivos reais. Não existe na versão instalada.
@MainActor
enum SmokeTest {
    struct Check: Codable {
        var name: String
        var passed: Bool
        var detail: String
    }

    static func runIfRequested(store: ProjectStore) async {
        guard ProcessInfo.processInfo.environment["EDITORIA_SMOKE"] == "1" else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = documents.appendingPathComponent("Smoke", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var checks: [Check] = []

        func record(_ name: String, _ passed: Bool, _ detail: String = "") {
            checks.append(Check(name: name, passed: passed, detail: detail))
        }

        do {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("smoke-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base.appendingPathComponent("Media"), withIntermediateDirectories: true)

            // Vídeos de cores diferentes, um deles gravado "em pé" como no iPhone.
            try await writeVideo(to: base.appendingPathComponent("Media/azul.mp4"), color: (0, 0, 255), seconds: 4, frameRate: 30, rotated: false)
            try await writeVideo(to: base.appendingPathComponent("Media/vermelho.mp4"), color: (255, 0, 0), seconds: 4, frameRate: 60, rotated: true)
            let still = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { context in
                UIColor.green.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            }
            try still.pngData()?.write(to: base.appendingPathComponent("Media/foto.png"))
            let lut = "LUT_3D_SIZE 2\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n"
            try lut.write(to: base.appendingPathComponent("preto.cube"), atomically: true, encoding: .utf8)

            let blue = LocalMedia(name: "azul.mp4", relativePath: "Media/azul.mp4", kind: "Vídeo", byteCount: 1, importOrder: 1, duration: 4)
            let red = LocalMedia(name: "vermelho.mp4", relativePath: "Media/vermelho.mp4", kind: "Vídeo", byteCount: 1, importOrder: 2, duration: 4)
            let photo = LocalMedia(name: "foto.png", relativePath: "Media/foto.png", kind: "Imagem", byteCount: 1, importOrder: 3, duration: 5)

            var project = EditorProject()
            project.media = [blue, red, photo]
            let first = TimelineClip(mediaID: blue.id, track: "video", start: 0, duration: 3, label: "azul")
            let second = TimelineClip(mediaID: red.id, track: "video", start: 3, duration: 3, label: "vermelho")
            let third = TimelineClip(mediaID: photo.id, track: "video", start: 6, duration: 2, label: "foto")
            project.clips = [first, second, third]
            project.clips = TimelineEditing.addTransition(to: second.id, kind: "dissolve", duration: 0.5, in: project.clips) ?? project.clips
            project.overlays = [TextOverlay(text: "TESTE", start: 0.5, duration: 1.5, fontSize: 120, verticalPosition: 0.5, animation: "pop")]
            project.captionWords = [CaptionWord(text: "legenda", start: 1, duration: 1, fontSize: 80, verticalPosition: 0.85)]

            // Exportação horizontal.
            let renderer = TimelineRenderer()
            let horizontal = try await renderer.export(project: project, baseDirectory: base, width: 1920, height: 1080)
            let asset = AVURLAsset(url: horizontal)
            let duration = try await asset.load(.duration).seconds
            record("Exporta MP4 horizontal", abs(duration - project.contentEnd) < 0.3, String(format: "%.2f s, esperado %.2f", duration, project.contentEnd))
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let size = try await tracks.first?.load(.naturalSize) ?? .zero
            record("Tamanho 1920x1080", size == CGSize(width: 1920, height: 1080), "\(size)")
            let rate = try await tracks.first?.load(.nominalFrameRate) ?? 0
            record("Timeline segue o maior frame rate", rate > 50, "\(rate) fps")

            func sampled(_ time: Double, tag: String, x: CGFloat = 0.1, y: CGFloat = 0.1, url: URL) async throws -> (r: Int, g: Int, b: Int) {
                let image = try await frame(of: url, at: time)
                try UIImage(cgImage: image).pngData()?.write(to: folder.appendingPathComponent("\(tag).png"))
                return pixel(of: image, x: x, y: y)
            }

            let blueFrame = try await sampled(0.2, tag: "h-azul", url: horizontal)
            record("Primeiro clipe é azul", blueFrame.b > 200 && blueFrame.r < 60, "\(blueFrame)")
            let redFrame = try await sampled(3.5, tag: "h-vermelho", url: horizontal)
            record("Segundo clipe é vermelho e preenche o quadro", redFrame.r > 200 && redFrame.b < 60, "\(redFrame)")
            let photoFrame = try await sampled(6.5, tag: "h-foto", url: horizontal)
            record("Foto aparece depois dos vídeos", photoFrame.g > 180 && photoFrame.r < 60, "\(photoFrame)")
            let textFrame = try await sampled(1.2, tag: "h-texto", x: 0.5, y: 0.5, url: horizontal)
            record("Texto desenhado no centro", textFrame.r > 200 && textFrame.g > 200, "\(textFrame)")
            let dissolve = try await sampled(2.75, tag: "h-transicao", url: horizontal)
            record("Dissolve mistura os dois clipes", dissolve.r > 40 && dissolve.b > 40, "\(dissolve)")

            // Vertical, com a mesma timeline: o vídeo deitado precisa encher a tela em pé.
            let vertical = try await renderer.export(project: project, baseDirectory: base, width: 1080, height: 1920)
            let verticalRed = try await sampled(3.5, tag: "v-vermelho", x: 0.5, y: 0.1, url: vertical)
            record("Vertical preenche o quadro", verticalRed.r > 200, "\(verticalRed)")

            // Cor e LUT: o LUT preto precisa escurecer o clipe.
            var graded = project
            if let index = graded.clips.firstIndex(where: { $0.id == first.id }) { graded.clips[index].look.lutRelativePath = "preto.cube" }
            let gradedURL = try await renderer.export(project: graded, baseDirectory: base, width: 1280, height: 720)
            let dark = try await sampled(0.2, tag: "lut", url: gradedURL)
            record("LUT .cube é aplicado", dark.b < 40, "\(dark)")

            var brighter = project
            if let index = brighter.clips.firstIndex(where: { $0.id == third.id }) { brighter.clips[index].look.saturation = 0 }
            let bw = try await renderer.export(project: brighter, baseDirectory: base, width: 1280, height: 720)
            let gray = try await sampled(6.5, tag: "saturacao", url: bw)
            record("Saturação zero deixa cinza", abs(gray.r - gray.g) < 25 && abs(gray.g - gray.b) < 25, "\(gray)")

            // Qualidade escolhida: máxima precisa gerar arquivo bem maior que boa.
            var lowOptions = ExportOptions(); lowOptions.quality = .good
            let lowURL = try await renderer.export(project: project, baseDirectory: base, width: 1280, height: 720, options: lowOptions)
            let highURL = try await renderer.export(project: project, baseDirectory: base, width: 1280, height: 720, options: .maximum)
            let lowTracks = try await AVURLAsset(url: lowURL).loadTracks(withMediaType: .video)
            let highTracks = try await AVURLAsset(url: highURL).loadTracks(withMediaType: .video)
            let lowRate = try await lowTracks.first?.load(.estimatedDataRate) ?? 0
            let highRate = try await highTracks.first?.load(.estimatedDataRate) ?? 0
            record("Qualidade máxima usa mais dados", highRate >= lowRate, "\(lowRate) e \(highRate) bps")
            var hevcOptions = ExportOptions(); hevcOptions.codec = .hevc
            let hevcURL = try await renderer.export(project: project, baseDirectory: base, width: 1280, height: 720, options: hevcOptions)
            let hevcFrame = try await sampled(0.2, tag: "hevc", url: hevcURL)
            record("Exporta em HEVC", hevcFrame.b > 200, "\(hevcFrame)")
            var fixedRate = ExportOptions(); fixedRate.frameRate = 24
            let fixedURL = try await renderer.export(project: project, baseDirectory: base, width: 640, height: 360, options: fixedRate)
            let fixedTracks = try await AVURLAsset(url: fixedURL).loadTracks(withMediaType: .video)
            let fixedValue = try await fixedTracks.first?.load(.nominalFrameRate) ?? 0
            record("Frame rate escolhido é respeitado", abs(fixedValue - 24) < 1, "\(fixedValue) fps")

            // Velocidade: 2x dura metade.
            var fast = project
            fast.overlays = []
            fast.captionWords = []
            fast.clips = [TimelineEditing.setSpeed(TimelineClip(mediaID: blue.id, track: "video", start: 0, duration: 4, label: "x"), to: 2)]
            let fastURL = try await renderer.export(project: fast, baseDirectory: base, width: 640, height: 360)
            let fastDuration = try await AVURLAsset(url: fastURL).load(.duration).seconds
            record("Velocidade 2x dura metade", abs(fastDuration - 2) < 0.2, String(format: "%.2f s", fastDuration))

            // Stories em arquivos separados.
            let stories = try await renderer.exportStories(project: project, baseDirectory: base, width: 540, height: 960)
            record("Stories geram um arquivo por clipe", stories.count == 3 && stories.first?.lastPathComponent == "STORY_001.mp4", stories.map(\.lastPathComponent).joined(separator: ","))

            // Motion: HTML e GSAP viram vídeo dentro do app, com e sem transparência.
            let engine = MotionEngine()
            let catalog = MotionTemplate.loadCatalog()
            record("Catálogo de motion carregado", catalog.count >= 15, "\(catalog.count) modelos")
            for (id, time) in [("abertura-institucional", 2.0), ("tarja-nome", 2.0)] {
                guard let template = catalog.first(where: { $0.id == id }) else { continue }
                do {
                    let output = folder.appendingPathComponent("motion-\(id).mov")
                    try await engine.renderTemplate(template, values: ["titulo": "Asfalto novo", "subtitulo": "Bairro Centro", "cor1": "#0B6E4F", "cor2": "#FFFFFF"], duration: 3, width: 1280, height: 720, frameRate: 30, output: output)
                    let picture = try await frame(of: output, at: time)
                    try UIImage(cgImage: picture).pngData()?.write(to: folder.appendingPathComponent("motion-\(id).png"))
                    let seconds = try await AVURLAsset(url: output).load(.duration).seconds
                    record("Motion \(id) renderizado", abs(seconds - 3) < 0.2, String(format: "%.2f s", seconds))

                    var withMotion = project
                    let motionMedia = LocalMedia(name: id, relativePath: "Media/\(id).mov", kind: "Vídeo", byteCount: 1, importOrder: 9, duration: 3, isDerived: true)
                    try? FileManager.default.copyItem(at: output, to: base.appendingPathComponent("Media/\(id).mov"))
                    withMotion.media.append(motionMedia)
                    withMotion.clips.append(TimelineClip(mediaID: motionMedia.id, track: "motion", start: 0, duration: 3, volume: 0, label: id))
                    let mixed = try await renderer.export(project: withMotion, baseDirectory: base, width: 1280, height: 720)
                    let check = try await sampled(2, tag: "mix-\(id)", x: 0.9, y: 0.1, url: mixed)
                    if template.transparent {
                        record("Motion transparente deixa o vídeo aparecer", check.b > 150, "\(check)")
                    } else {
                        record("Motion de tela cheia cobre o vídeo", check.g > 60 && check.b < 150, "\(check)")
                    }
                } catch {
                    record("Motion \(id)", false, error.localizedDescription)
                }
            }

            // Salva e reabre pelo armazenamento real do app; o projeto fica aberto para as fotos das telas.
            let names = ["azul.mp4", "vermelho.mp4", "foto.png"]
            let imports = names.map { base.appendingPathComponent("Media/\($0)") }
            await store.importFiles(imports)
            record("Importação pelo app", store.project.media.count >= 3, "\(store.project.media.count) mídias, \(store.project.clips.count) clipes")
            store.addTextOverlay("Título de teste", duration: 3, animation: "pop")
            store.setClient(store.clients.first?.id)
            let savedID = store.project.id
            store.createProject(named: "Outro projeto")
            store.openProject(savedID)
            record("Projeto salvo e reaberto", store.project.clips.count >= 3 && store.project.overlays.count == 1, "\(store.project.clips.count) clipes")
            let draft = LocalDirectorService.makePlan(command: "monte um institucional", project: store.project).timelineDraft
            record("Diretor monta rascunho", draft != nil, "\(draft?.segments.count ?? 0) trechos")
        } catch {
            record("Erro geral", false, error.localizedDescription)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(checks) {
            try? data.write(to: folder.appendingPathComponent("report.json"), options: .atomic)
        }
    }

    private static func frame(of url: URL, at time: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    private static func pixel(of image: CGImage, x: CGFloat, y: CGFloat) -> (r: Int, g: Int, b: Int) {
        var data = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0, 0) }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        context.draw(image, in: CGRect(x: -x * width, y: -(1 - y) * height, width: width, height: height))
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }

    private static func writeVideo(to url: URL, color: (Int, Int, Int), seconds: Int, frameRate: Int, rotated: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360])
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let pixelBuffer = buffer else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let row = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<360 {
                for x in 0..<640 {
                    let offset = y * row + x * 4
                    bytes[offset] = UInt8(color.2)
                    bytes[offset + 1] = UInt8(color.1)
                    bytes[offset + 2] = UInt8(color.0)
                    bytes[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        for index in 0..<(seconds * frameRate) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate)))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}
#endif
