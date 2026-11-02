import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import ImageIO
import UIKit
import CoreText

/// Tudo que o compositor precisa para desenhar um quadro. Não muda depois de criado.
final class CompositionScene: @unchecked Sendable {
    let project: EditorProject
    let renderSize: CGSize
    let baseDirectory: URL
    let trackForClip: [UUID: CMPersistentTrackID]
    let orientationForClip: [UUID: CGImagePropertyOrientation]
    let clips: [UUID: TimelineClip]
    let media: [UUID: LocalMedia]
    let overlays: [UUID: TextOverlay]
    let sortedCaptions: [CaptionWord]

    init(project: EditorProject, renderSize: CGSize, baseDirectory: URL, trackForClip: [UUID: CMPersistentTrackID], orientationForClip: [UUID: CGImagePropertyOrientation]) {
        // Tamanhos de texto valem para o lado menor em 1080; em outras resoluções escalam junto.
        let scaled = project.scalingText(by: Double(min(renderSize.width, renderSize.height)) / 1080)
        self.project = scaled
        self.renderSize = renderSize
        self.baseDirectory = baseDirectory
        self.trackForClip = trackForClip
        self.orientationForClip = orientationForClip
        clips = Dictionary(scaled.clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        media = Dictionary(scaled.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        overlays = Dictionary(scaled.overlays.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sortedCaptions = scaled.captionWords.sorted { $0.start < $1.start }
    }
}

final class TimelineInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let scene: CompositionScene

    init(timeRange: CMTimeRange, trackIDs: [CMPersistentTrackID], scene: CompositionScene) {
        self.timeRange = timeRange
        requiredSourceTrackIDs = trackIDs.isEmpty ? nil : trackIDs.map { NSNumber(value: $0) }
        self.scene = scene
        super.init()
    }
}

/// Compositor único da prévia e da exportação: o que aparece na tela é o que sai no arquivo.
final class TimelineCompositor: NSObject, AVVideoCompositing {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]

    private let queue = DispatchQueue(label: "editoria.compositor", qos: .userInitiated)
    private let renderer = FrameRenderer()
    private let lock = NSLock()
    private var cancelled = false

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            lock.lock()
            let shouldCancel = cancelled
            lock.unlock()
            if shouldCancel {
                request.finishCancelledRequest()
                return
            }
            autoreleasepool {
                guard let instruction = request.videoCompositionInstruction as? TimelineInstruction,
                      let output = request.renderContext.newPixelBuffer() else {
                    request.finish(with: NSError(domain: "EditorIA.Compositor", code: 1))
                    return
                }
                renderer.render(scene: instruction.scene, time: request.compositionTime.seconds, into: output) { trackID in
                    request.sourceFrame(byTrackID: trackID)
                }
                request.finish(withComposedVideoFrame: output)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        lock.lock()
        cancelled = true
        lock.unlock()
        queue.async { [self] in
            lock.lock()
            cancelled = false
            lock.unlock()
        }
    }
}

/// Desenha um quadro seguindo o que o `SceneEvaluator` calculou.
final class FrameRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let stills = NSCache<NSString, CIImage>()
    private let textImages = NSCache<NSString, CIImage>()
    private var luts: [String: (dimension: Int, data: Data)] = [:]
    private var chromaCubes: [String: Data] = [:]

    init() {
        _ = CaptionFonts.register
        stills.countLimit = 40
        textImages.countLimit = 600
    }

    func render(scene: CompositionScene, time: Double, into output: CVPixelBuffer, source: (CMPersistentTrackID) -> CVPixelBuffer?) {
        let size = scene.renderSize
        let frame = CGRect(origin: .zero, size: size)
        var canvas = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: frame)
        var flash = 0.0

        for item in SceneEvaluator.items(project: scene.project, at: time) {
            switch item {
            case .media(let layer):
                guard let clip = scene.clips[layer.clipID],
                      let media = scene.media[clip.mediaID],
                      let image = mediaImage(clip: clip, media: media, scene: scene, source: source) else { continue }
                canvas = composite(image, state: layer.state, center: CGPoint(x: size.width / 2, y: size.height / 2), frame: frame, over: canvas)
                flash = max(flash, layer.state.flash)
            case .text(let id, let state):
                guard let overlay = scene.overlays[id] else { continue }
                canvas = drawText(overlay, state: state, time: time, scene: scene, over: canvas)
                flash = max(flash, state.flash)
            }
        }
        canvas = drawCaptions(scene: scene, time: time, over: canvas)
        if flash > 0.001 {
            let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(min(1, flash)) )).cropped(to: frame)
            canvas = white.composited(over: canvas)
        }
        context.render(canvas.cropped(to: frame), to: output, bounds: frame, colorSpace: colorSpace)
    }

    private func composite(_ image: CIImage, state: LayerState, center: CGPoint, frame: CGRect, over canvas: CIImage) -> CIImage {
        guard state.opacity > 0.001 else { return canvas }
        var layer = image
        if state.blur > 0.01 { layer = layer.applyingGaussianBlur(sigma: state.blur) }
        var transform = CGAffineTransform(translationX: -center.x, y: -center.y)
        transform = transform.concatenating(CGAffineTransform(scaleX: CGFloat(state.scale), y: CGFloat(state.scale * state.scaleY)))
        // Rotação positiva é horária na tela; no Core Image o eixo Y sobe.
        transform = transform.concatenating(CGAffineTransform(rotationAngle: -CGFloat(state.rotation) * .pi / 180))
        transform = transform.concatenating(CGAffineTransform(
            translationX: center.x + frame.width * CGFloat(state.offsetX),
            y: center.y - frame.height * CGFloat(state.offsetY)
        ))
        layer = layer.transformed(by: transform)
        if state.wipe < 0.999 {
            layer = layer.cropped(to: CGRect(x: 0, y: 0, width: frame.width * CGFloat(state.wipe), height: frame.height))
        }
        if state.opacity < 0.999 {
            let alpha = CGFloat(state.opacity)
            layer = layer.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: alpha, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: alpha, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: alpha, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
            ])
        }
        return layer.composited(over: canvas)
    }

    // MARK: - Mídia

    private func mediaImage(clip: TimelineClip, media: LocalMedia, scene: CompositionScene, source: (CMPersistentTrackID) -> CVPixelBuffer?) -> CIImage? {
        var image: CIImage
        if media.kind == "Imagem" {
            guard let still = stillImage(media: media, scene: scene) else { return nil }
            image = still
        } else {
            guard let trackID = scene.trackForClip[clip.id], let buffer = source(trackID) else { return nil }
            image = CIImage(cvPixelBuffer: buffer).oriented(scene.orientationForClip[clip.id] ?? .up)
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        image = applyLook(clip.look, to: image, scene: scene)

        let size = scene.renderSize
        let scale = max(size.width / max(1, image.extent.width), size.height / max(1, image.extent.height))
        return image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: (size.width - image.extent.width * scale) / 2, y: (size.height - image.extent.height * scale) / 2))
    }

    private func stillImage(media: LocalMedia, scene: CompositionScene) -> CIImage? {
        let maxSide = Int(max(scene.renderSize.width, scene.renderSize.height))
        let limit = media.isDerived ? min(maxSide, 1280) : min(maxSide, 2400)
        let key = "\(media.relativePath)#\(limit)" as NSString
        if let cached = stills.object(forKey: key) { return cached }
        let url = scene.baseDirectory.appendingPathComponent(media.relativePath)
        guard let cg = TimelineCompositionBuilder.loadStill(url: url, maxPixelSize: limit) else { return nil }
        let image = CIImage(cgImage: cg)
        stills.setObject(image, forKey: key)
        return image
    }

    private func applyLook(_ look: ClipLook, to input: CIImage, scene: CompositionScene) -> CIImage {
        var image = input
        if let hex = look.chromaHex, let cube = chromaCube(hex: hex, tolerance: look.chromaTolerance) {
            image = image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": 32, "inputCubeData": cube])
        }
        guard look.hasColorChanges else { return image }
        if look.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": look.exposure])
        }
        if look.temperature != 6500 || look.tint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: CGFloat(look.temperature), y: CGFloat(look.tint)),
                "inputTargetNeutral": CIVector(x: 6500, y: 0)
            ])
        }
        if look.contrast != 1 || look.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: ["inputContrast": look.contrast, "inputSaturation": look.saturation])
        }
        if look.shadows != 0 || look.highlights != 1 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": look.highlights, "inputShadowAmount": look.shadows])
        }
        if let path = look.lutRelativePath, let lut = lut(at: path, scene: scene) {
            let graded = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
                "inputCubeDimension": lut.dimension,
                "inputCubeData": lut.data,
                "inputColorSpace": colorSpace
            ])
            image = look.lutIntensity >= 0.999 ? graded : graded.applyingFilter("CIMix", parameters: ["inputBackgroundImage": image, "inputAmount": look.lutIntensity])
        }
        return image
    }

    private func lut(at path: String, scene: CompositionScene) -> (dimension: Int, data: Data)? {
        if let cached = luts[path] { return cached }
        let url = scene.baseDirectory.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8), let parsed = try? CubeLUT.parse(text) else { return nil }
        let result = (dimension: parsed.dimension, data: parsed.values.withUnsafeBufferPointer { Data(buffer: $0) })
        luts[path] = result
        return result
    }

    private func chromaCube(hex: String, tolerance: Double) -> Data? {
        let key = "\(hex)#\(tolerance)"
        if let cached = chromaCubes[key] { return cached }
        let color = FrameRenderer.uiColor(hex: hex)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        let values = CubeLUT.chromaCube(keyRed: Double(red), keyGreen: Double(green), keyBlue: Double(blue), tolerance: tolerance)
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        chromaCubes[key] = data
        return data
    }

    // MARK: - Texto

    static func uiColor(hex: String) -> UIColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 || cleaned.count == 8, let value = UInt64(cleaned, radix: 16) else { return .white }
        if cleaned.count == 8 {
            return UIColor(red: CGFloat((value >> 24) & 0xFF) / 255, green: CGFloat((value >> 16) & 0xFF) / 255, blue: CGFloat((value >> 8) & 0xFF) / 255, alpha: CGFloat(value & 0xFF) / 255)
        }
        return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private func font(style: String, size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: style == "regular" ? .medium : .heavy)
        let design: UIFontDescriptor.SystemDesign?
        switch style {
        case "serif": design = .serif
        case "rounded": design = .rounded
        case "mono": design = .monospaced
        default: design = nil
        }
        if let design, let descriptor = base.fontDescriptor.withDesign(design) { return UIFont(descriptor: descriptor, size: size) }
        return base
    }

    /// Transforma texto em imagem, com cache para não redesenhar a cada quadro.
    private func textImage(_ attributed: NSAttributedString, key: String, maxWidth: CGFloat, background: UIColor?, padding: CGFloat = 24) -> CIImage? {
        if let cached = textImages.object(forKey: key as NSString) { return cached }
        let bounds = attributed.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let size = CGSize(width: ceil(bounds.width) + padding * 2, height: ceil(bounds.height) + padding * 2)
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let picture = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            if let background {
                background.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: min(24, size.height / 4)).fill()
            }
            attributed.draw(with: CGRect(x: padding, y: padding, width: ceil(bounds.width), height: ceil(bounds.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        guard let cg = picture.cgImage else { return nil }
        let image = CIImage(cgImage: cg)
        textImages.setObject(image, forKey: key as NSString)
        return image
    }

    private func attributes(overlay: TextOverlay) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = CGFloat(overlay.fontSize) * 0.08
        shadow.shadowOffset = CGSize(width: 0, height: CGFloat(overlay.fontSize) * 0.03)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var result: [NSAttributedString.Key: Any] = [
            .font: font(style: overlay.fontStyle, size: CGFloat(overlay.fontSize)),
            .foregroundColor: FrameRenderer.uiColor(hex: overlay.colorHex),
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]
        if overlay.outlineWidth > 0 {
            result[.strokeColor] = FrameRenderer.uiColor(hex: overlay.outlineHex)
            result[.strokeWidth] = -overlay.outlineWidth / max(1, overlay.fontSize) * 100
        }
        return result
    }

    private func drawText(_ overlay: TextOverlay, state: LayerState, time: Double, scene: CompositionScene, over canvas: CIImage) -> CIImage {
        let size = scene.renderSize
        let frame = CGRect(origin: .zero, size: size)
        let center = CGPoint(x: size.width * CGFloat(overlay.horizontalPosition), y: size.height * CGFloat(1 - overlay.verticalPosition))
        let attrs = attributes(overlay: overlay)
        let background = FrameRenderer.uiColor(hex: overlay.backgroundHex)
        var alpha: CGFloat = 0
        background.getWhite(nil, alpha: &alpha)
        let box: UIColor? = alpha > 0.01 ? background : nil
        let baseKey = "\(overlay.fontStyle)|\(overlay.fontSize)|\(overlay.colorHex)|\(overlay.outlineHex)|\(overlay.outlineWidth)|\(overlay.backgroundHex)"

        func placed(_ image: CIImage, at point: CGPoint, state layerState: LayerState) -> CIImage {
            var final = layerState
            final.scale *= overlay.scale
            final.rotation += overlay.rotationDegrees
            let moved = image.transformed(by: CGAffineTransform(translationX: point.x - image.extent.width / 2, y: point.y - image.extent.height / 2))
            return composite(moved, state: final, center: point, frame: frame, over: canvas)
        }

        if overlay.wordAnimation != "none" {
            let words = overlay.text.split(whereSeparator: \.isWhitespace).map(String.init)
            let states = TextMotion.wordStates(kind: overlay.wordAnimation, wordCount: words.count, time: time - overlay.start, duration: overlay.duration)
            let images = words.map { textImage(NSAttributedString(string: $0, attributes: attrs), key: "w|\(baseKey)|\($0)", maxWidth: size.width, background: nil) }
            // Linhas centralizadas que quebram na largura do quadro.
            var lines: [[Int]] = [[]]
            var used: CGFloat = 0
            let maxWidth = size.width * 0.9
            for (index, image) in images.enumerated() {
                let width = image?.extent.width ?? 0
                if used + width > maxWidth, !(lines.last ?? []).isEmpty {
                    lines.append([])
                    used = 0
                }
                lines[lines.count - 1].append(index)
                used += width
            }
            var result = canvas
            let lineHeight = (images.compactMap { $0?.extent.height }.max() ?? 0) * 0.86
            for (lineIndex, line) in lines.enumerated() {
                let total = line.reduce(CGFloat(0)) { $0 + (images[$1]?.extent.width ?? 0) }
                var x = center.x - total / 2
                let y = center.y + (CGFloat(lines.count - 1) / 2 - CGFloat(lineIndex)) * lineHeight
                for index in line {
                    guard let image = images[index] else { continue }
                    var wordState = states[index]
                    wordState.scale *= overlay.scale
                    wordState.rotation += overlay.rotationDegrees
                    let point = CGPoint(x: x + image.extent.width / 2, y: y)
                    let moved = image.transformed(by: CGAffineTransform(translationX: point.x - image.extent.width / 2, y: point.y - image.extent.height / 2))
                    result = composite(moved, state: wordState, center: point, frame: frame, over: result)
                    x += image.extent.width
                }
            }
            return result
        }

        var shown = overlay.text
        if state.reveal < 0.999 { shown = String(shown.prefix(Int(Double(shown.count) * state.reveal))) }
        guard !shown.isEmpty, let image = textImage(NSAttributedString(string: shown, attributes: attrs), key: "t|\(baseKey)|\(shown)", maxWidth: size.width * 0.86, background: box) else { return canvas }
        return placed(image, at: center, state: state)
    }

    private func drawCaptions(scene: CompositionScene, time: Double, over canvas: CIImage) -> CIImage {
        let project = scene.project
        guard project.captionsEnabled, let caption = CaptionAnimator.frame(style: project.captionStyle, words: scene.sortedCaptions, at: time) else { return canvas }
        let preset = caption.preset
        let size = scene.renderSize
        let frame = CGRect(origin: .zero, size: size)
        let fontSize = CGFloat(project.captionFontSize * caption.sizeFactor)
        let maxWidth = size.width * 0.9

        let images: [CIImage?] = caption.words.map { captionImage($0, preset: preset, project: project, fontSize: fontSize, maxWidth: maxWidth) }

        let hasBoxes = preset.wordBox != nil || preset.active == .box
        let gap = hasBoxes ? fontSize * 0.1 : 0
        var lines: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, image) in images.enumerated() {
            let width = (image?.extent.width ?? 0) + gap
            if used + width > maxWidth, !(lines.last ?? []).isEmpty {
                lines.append([])
                used = 0
            }
            lines[lines.count - 1].append(index)
            used += width
        }
        let tallest = images.compactMap { $0?.extent.height }.max() ?? fontSize
        let lineHeight = hasBoxes || preset.lineBox != nil ? tallest + gap : tallest * 0.9
        let vertical = project.captionVertical ?? CaptionLayout.defaultVertical(width: Double(size.width), height: Double(size.height))
        let centerY = size.height * CGFloat(1 - vertical)
        var result = canvas
        for (lineIndex, line) in lines.enumerated() {
            let total = line.reduce(CGFloat(0)) { $0 + (images[$1]?.extent.width ?? 0) } + gap * CGFloat(max(0, line.count - 1))
            var x = (size.width - total) / 2
            let y = centerY + (CGFloat(lines.count - 1) / 2 - CGFloat(lineIndex)) * lineHeight
            if let band = preset.lineBox, let bar = captionBar(hex: band, width: total + fontSize * 0.5, height: tallest) {
                let visible = caption.words.first.map { min(1, $0.state.opacity) } ?? 1
                var bandState = LayerState()
                bandState.opacity = visible
                let center = CGPoint(x: size.width / 2, y: y)
                result = composite(bar.transformed(by: CGAffineTransform(translationX: center.x - bar.extent.width / 2, y: y - bar.extent.height / 2)), state: bandState, center: center, frame: frame, over: result)
            }
            for index in line {
                guard let image = images[index] else { continue }
                let word = caption.words[index]
                let point = CGPoint(x: x + image.extent.width / 2, y: y)
                let moved = image.transformed(by: CGAffineTransform(translationX: x, y: y - image.extent.height / 2))
                if word.split > 0, word.state.opacity > 0 {
                    let shift = fontSize * 0.05 * CGFloat(word.split)
                    for (tint, direction) in [("#FF0044", CGFloat(-1)), ("#00E5FF", CGFloat(1))] {
                        var ghost = word
                        ghost.split = 0
                        ghost.isActive = false
                        ghost.color = tint
                        if let copy = captionImage(ghost, preset: preset, project: project, fontSize: fontSize, maxWidth: maxWidth) {
                            let placed = copy.transformed(by: CGAffineTransform(translationX: x + direction * shift, y: y - copy.extent.height / 2))
                            var state = word.state
                            state.opacity *= 0.75
                            result = composite(placed, state: state, center: point, frame: frame, over: result)
                        }
                    }
                }
                result = composite(moved, state: word.state, center: point, frame: frame, over: result)
                if word.underline, let bar = captionBar(hex: project.captionHighlightHex, width: image.extent.width - fontSize * 0.25, height: max(4, fontSize * 0.09)) {
                    let bottom = y - image.extent.height / 2 + fontSize * 0.1
                    let placed = bar.transformed(by: CGAffineTransform(translationX: point.x - bar.extent.width / 2, y: bottom))
                    result = composite(placed, state: word.state, center: point, frame: frame, over: result)
                }
                x += image.extent.width + gap
            }
        }
        return result
    }

    /// Desenha uma palavra com o visual do preset. Fica em cache: só a animação muda de quadro para quadro.
    private func captionImage(_ word: CaptionAnimator.WordVisual, preset: CaptionPreset, project: EditorProject, fontSize baseSize: CGFloat, maxWidth: CGFloat) -> CIImage? {
        let fontSize = baseSize * (word.isKeyword ? 1.2 : 1)
        let useBox = word.hasBox || preset.wordBox != nil
        let active = word.color ?? ((word.isActive || word.isKeyword) ? project.captionHighlightHex : project.captionTextHex)
        let base = word.hasBox ? preset.boxText : active
        let fontName = word.isEmoji ? "emoji" : (project.captionFontStyle == "preset" ? preset.font : project.captionFontStyle)
        let captionFont: UIFont = word.isEmoji ? UIFont.systemFont(ofSize: fontSize) : (project.captionFontStyle == "preset" ? (UIFont(name: preset.font, size: fontSize) ?? font(style: "heavy", size: fontSize)) : font(style: project.captionFontStyle, size: fontSize))
        let boxColor = word.hasBox ? project.captionHighlightHex : preset.wordBox
        let useGradient = !preset.gradient.isEmpty && !word.isEmoji && word.color == nil && !word.isActive

        func picture(color: String, gradient: Bool) -> CIImage? {
            let key = "cap|\(fontName)|\(fontSize)|\(color)|\(boxColor ?? "")|\(preset.id)|\(word.glow)|\(gradient)|\(word.text)"
            if let cached = textImages.object(forKey: key as NSString) { return cached }
            let fill = FrameRenderer.uiColor(hex: color)
            let plain: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: fill]
            let text = NSAttributedString(string: word.text, attributes: plain)
            let measured = text.boundingRect(with: CGSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            let stroke = word.isEmoji ? 0 : CGFloat(preset.strokeWidth) * fontSize
            let glowing = (preset.shadow == .glow || word.glow) && !word.isEmoji
            let padding = fontSize * (useBox ? 0.16 : 0.1) + stroke + (glowing ? fontSize * 0.25 : 0) + (preset.shadow == .hard ? fontSize * 0.07 : 0)
            let canvasSize = CGSize(width: ceil(measured.width) + padding * 2, height: ceil(measured.height) + padding * 2)
            guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
            let textRect = CGRect(x: padding, y: padding, width: ceil(measured.width), height: ceil(measured.height))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let rendered = UIGraphicsImageRenderer(size: canvasSize, format: format).image { renderer in
                let cg = renderer.cgContext
                cg.setLineJoin(.round)
                if useBox, let boxColor {
                    FrameRenderer.uiColor(hex: boxColor).setFill()
                    UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvasSize), cornerRadius: fontSize * 0.18).fill()
                }
                func draw(_ attributes: [NSAttributedString.Key: Any], offset: CGPoint = .zero) {
                    NSAttributedString(string: word.text, attributes: attributes).draw(with: textRect.offsetBy(dx: offset.x, dy: offset.y), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                }
                if !useBox, !word.isEmoji {
                    switch preset.shadow {
                    case .hard:
                        let depth = fontSize * 0.055
                        var attributes = plain
                        attributes[.foregroundColor] = UIColor.black
                        if stroke > 0 {
                            attributes[.strokeColor] = UIColor.black
                            attributes[.strokeWidth] = Double(stroke / fontSize * 200)
                        }
                        draw(attributes, offset: CGPoint(x: depth, y: depth))
                    case .soft:
                        let shadow = NSShadow()
                        shadow.shadowColor = UIColor.black.withAlphaComponent(0.85)
                        shadow.shadowBlurRadius = fontSize * 0.14
                        shadow.shadowOffset = CGSize(width: 0, height: fontSize * 0.04)
                        var attributes = plain
                        attributes[.shadow] = shadow
                        draw(attributes)
                    case .glow, .none:
                        break
                    }
                }
                if glowing {
                    let shadow = NSShadow()
                    shadow.shadowColor = FrameRenderer.uiColor(hex: word.glow ? project.captionHighlightHex : color)
                    shadow.shadowBlurRadius = fontSize * 0.32
                    var attributes = plain
                    attributes[.shadow] = shadow
                    draw(attributes)
                    draw(attributes)
                }
                if stroke > 0, let strokeHex = preset.stroke {
                    var attributes = plain
                    attributes[.strokeColor] = FrameRenderer.uiColor(hex: strokeHex)
                    attributes[.strokeWidth] = Double(stroke / fontSize * 200)
                    draw(attributes)
                }
                var fillAttributes = plain
                if gradient, let pattern = Self.gradientColor(preset.gradient, height: canvasSize.height) {
                    fillAttributes[.foregroundColor] = pattern
                }
                draw(fillAttributes)
            }
            guard let cg = rendered.cgImage else { return nil }
            let image = CIImage(cgImage: cg)
            textImages.setObject(image, forKey: key as NSString)
            return image
        }

        guard var image = picture(color: base, gradient: useGradient) else { return nil }
        if let progress = word.fill, progress > 0, let filled = picture(color: project.captionHighlightHex, gradient: false) {
            let width = filled.extent.width * CGFloat(min(1, progress))
            image = filled.cropped(to: CGRect(x: 0, y: 0, width: width, height: filled.extent.height)).composited(over: image)
        }
        // Palavra maior que a tela encolhe em vez de quebrar no meio.
        if image.extent.width > maxWidth {
            let shrink = maxWidth / image.extent.width
            image = image.transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))
        }
        return image
    }

    private func captionBar(hex: String, width: CGFloat, height: CGFloat) -> CIImage? {
        guard width > 1, height > 1 else { return nil }
        let w = Int(width), h = Int(height)
        let key = "bar|\(hex)|\(w)|\(h)"
        if let cached = textImages.object(forKey: key as NSString) { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: w, height: h)
        let picture = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            FrameRenderer.uiColor(hex: hex).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: min(CGFloat(h) / 3, 18)).fill()
        }
        guard let cg = picture.cgImage else { return nil }
        let image = CIImage(cgImage: cg)
        textImages.setObject(image, forKey: key as NSString)
        return image
    }

    private static func gradientColor(_ hexes: [String], height: CGFloat) -> UIColor? {
        guard hexes.count >= 2, height > 1 else { return nil }
        let colors = hexes.map { FrameRenderer.uiColor(hex: $0).cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: height), format: format).image { renderer in
            renderer.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
        return UIColor(patternImage: image)
    }
}

/// Fontes das legendas, guardadas dentro do app. Funcionam sem internet.
enum CaptionFonts {
    static let register: Void = {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Motion/captionfonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }()
}

extension CGImagePropertyOrientation {
    /// Converte a rotação gravada na faixa de vídeo na orientação equivalente.
    init(videoTransform transform: CGAffineTransform) {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): self = .right
        case (0, -1, 1, 0): self = .left
        case (-1, 0, 0, -1): self = .down
        case (1, 0, 0, -1): self = .downMirrored
        default: self = .up
        }
    }
}
