import Foundation
import Vision
import CoreImage
import CoreVideo
import CoreImage.CIFilterBuiltins
import UIKit

/// Segmentação local de uma pessoa em uma fotografia.
/// O resultado é um PNG transparente para composição em uma faixa acima dos textos.
enum PersonSegmentationService {
    enum SegmentationError: LocalizedError {
        case invalidImage
        case noMask
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "Não foi possível abrir a imagem para recorte."
            case .noMask: return "A IA não conseguiu identificar uma pessoa nesta imagem."
            case .renderFailed: return "Não foi possível gerar a imagem recortada."
            }
        }
    }

    static func createTransparentPersonPNG(from url: URL) async throws -> Data {
        guard let source = UIImage(contentsOfFile: url.path),
              let normalized = normalizedCGImage(source) else {
            throw SegmentationError.invalidImage
        }

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: normalized, options: [:])
        try handler.perform([request])

        guard let maskBuffer = request.results?.first?.pixelBuffer else {
            throw SegmentationError.noMask
        }

        let image = CIImage(cgImage: normalized)
        let rawMask = CIImage(cvPixelBuffer: maskBuffer)
        let scaleX = image.extent.width / rawMask.extent.width
        let scaleY = image.extent.height / rawMask.extent.height
        let mask = rawMask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: image.extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: image.extent)
        blend.maskImage = mask
        guard let output = blend.outputImage,
              let cgImage = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: image.extent) else {
            throw SegmentationError.renderFailed
        }
        guard let data = UIImage(cgImage: cgImage).pngData() else {
            throw SegmentationError.renderFailed
        }
        return data
    }

    static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }
}
