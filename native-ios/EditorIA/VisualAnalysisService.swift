import Foundation
import AVFoundation
import Vision

/// Olha as imagens do material no próprio aparelho, para a IA saber o que aparece em cada arquivo.
enum VisualAnalysisService {
    struct Report: Sendable {
        var tags: [String]
        var faceShare: Double
        var interestX: Double
        var interestY: Double
        var imageWidth: Double
        var imageHeight: Double
    }

    /// Termos genéricos que não ajudam a descrever a cena.
    private static let ignored: Set<String> = ["structure", "material", "conveyance", "people", "machine", "liquid"]

    static func analyze(url: URL, isVideo: Bool, duration: Double) async throws -> Report {
        var images: [CGImage] = []
        if isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 720)
            let count = max(1, min(6, Int(duration / 3)))
            for index in 0..<count {
                let time = duration * (Double(index) + 0.5) / Double(count)
                if let frame = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image { images.append(frame) }
            }
        } else if let still = TimelineCompositionBuilder.loadStill(url: url, maxPixelSize: 900) {
            images = [still]
        }
        guard let first = images.first else { throw RenderError.noRenderableMedia }
        let frames = images
        return try await Task.detached(priority: .utility) { () throws -> Report in
            var scores: [String: Float] = [:]
            var withFace = 0
            var interestX = 0.5, interestY = 0.5
            for (index, image) in frames.enumerated() {
                let classify = VNClassifyImageRequest()
                let faces = VNDetectFaceRectanglesRequest()
                let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([classify, faces, saliency])
                for item in (classify.results ?? []).prefix(12) where item.confidence > 0.3 && !ignored.contains(item.identifier) {
                    scores[item.identifier, default: 0] += item.confidence
                }
                if !(faces.results ?? []).isEmpty { withFace += 1 }
                // O ponto de interesse vem do quadro do meio; Vision conta Y de baixo para cima.
                if index == frames.count / 2, let box = saliency.results?.first?.salientObjects?.first?.boundingBox {
                    interestX = Double(box.midX)
                    interestY = 1 - Double(box.midY)
                }
            }
            let tags = scores.sorted { $0.value > $1.value }.prefix(6).map(\.key)
            return Report(tags: Array(tags), faceShare: Double(withFace) / Double(frames.count), interestX: interestX, interestY: interestY, imageWidth: Double(first.width), imageHeight: Double(first.height))
        }.value
    }
}
