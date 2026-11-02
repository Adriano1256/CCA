import Foundation
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

/// Gera uma sequência temporal de PNGs transparentes a partir de um vídeo.
/// O processamento é local. A amostragem é intencionalmente configurável para
/// evitar criar milhares de arquivos sem necessidade durante a análise inicial.
enum VideoPersonSegmentationService {
    struct FrameRecord: Codable {
        let file: String
        let time: Double
    }

    struct Manifest: Codable {
        let sourceName: String
        let sourceDuration: Double
        let sampleRate: Double
        let maskFeatherRadius: Double
        let frameCount: Int
        let createdAt: Date
        let frames: [FrameRecord]

        enum CodingKeys: String, CodingKey {
            case sourceName, sourceDuration, sampleRate, maskFeatherRadius, frameCount, createdAt, frames
        }

        init(sourceName: String, sourceDuration: Double, sampleRate: Double, maskFeatherRadius: Double, frameCount: Int, createdAt: Date, frames: [FrameRecord]) {
            self.sourceName = sourceName
            self.sourceDuration = sourceDuration
            self.sampleRate = sampleRate
            self.maskFeatherRadius = maskFeatherRadius
            self.frameCount = frameCount
            self.createdAt = createdAt
            self.frames = frames
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            sourceName = try values.decode(String.self, forKey: .sourceName)
            sourceDuration = try values.decode(Double.self, forKey: .sourceDuration)
            sampleRate = try values.decode(Double.self, forKey: .sampleRate)
            maskFeatherRadius = try values.decodeIfPresent(Double.self, forKey: .maskFeatherRadius) ?? 0
            frameCount = try values.decode(Int.self, forKey: .frameCount)
            createdAt = try values.decode(Date.self, forKey: .createdAt)
            frames = try values.decode([FrameRecord].self, forKey: .frames)
        }
    }

    struct Result {
        let directory: URL
        let manifestURL: URL
        let frameCount: Int
        let sampleRate: Double
        let sourceDuration: Double
    }

    enum SegmentationError: LocalizedError {
        case noVideoTrack
        case cannotCreateReader
        case cannotCreateOutput
        case cannotReadFrames
        case noFrames
        case maskUnavailable
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "O arquivo não contém uma faixa de vídeo compatível."
            case .cannotCreateReader: return "Não foi possível preparar a leitura do vídeo."
            case .cannotCreateOutput: return "Não foi possível preparar a extração dos quadros."
            case .cannotReadFrames: return "A leitura dos quadros foi interrompida."
            case .noFrames: return "Nenhum quadro pôde ser analisado."
            case .maskUnavailable: return "A segmentação não conseguiu gerar uma máscara para um quadro."
            case .imageEncodingFailed: return "Não foi possível salvar um quadro transparente."
            }
        }
    }

    static func generateMaskFrames(
        from sourceURL: URL,
        outputDirectory: URL,
        sampleRate: Double = 5,
        maskFeatherRadius: Double = 2
    ) async throws -> Result {
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else { throw SegmentationError.noVideoTrack }
        let durationTime = try await asset.load(.duration)
        // Vídeo gravado em pé vem deitado no arquivo; a máscara precisa sair em pé, como na timeline.
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let orientation = imageOrientation(for: preferredTransform)
        let duration = max(0, CMTimeGetSeconds(durationTime))
        guard duration.isFinite, duration > 0 else { throw SegmentationError.noFrames }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) }
        catch { throw SegmentationError.cannotCreateReader }

        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw SegmentationError.cannotCreateOutput }
        reader.add(output)
        guard reader.startReading() else { throw SegmentationError.cannotReadFrames }

        let safeRate = min(12, max(1, sampleRate))
        let safeFeather = min(12, max(0, maskFeatherRadius))
        let interval = 1.0 / safeRate
        var nextSampleTime = 0.0
        var records: [FrameRecord] = []
        var frameIndex = 0
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard reader.status == .reading || reader.status == .completed else {
                throw SegmentationError.cannotReadFrames
            }
            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard timestamp.isFinite, timestamp + 0.0001 >= nextSampleTime else { continue }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            try autoreleasepool {
            let upright = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
            let uprightOrigin = CGAffineTransform(translationX: -upright.extent.minX, y: -upright.extent.minY)
            let sourceImage = upright.transformed(by: uprightOrigin)
            guard let uprightFrame = ciContext.createCGImage(sourceImage, from: sourceImage.extent) else {
                throw SegmentationError.imageEncodingFailed
            }
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(cgImage: uprightFrame, options: [:])
            try handler.perform([request])
            guard let maskBuffer = request.results?.first?.pixelBuffer else {
                nextSampleTime = timestamp + interval
                return
            }

            let rawMask = CIImage(cvPixelBuffer: maskBuffer)
            let scaleX = sourceImage.extent.width / rawMask.extent.width
            let scaleY = sourceImage.extent.height / rawMask.extent.height
            var mask = rawMask
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .cropped(to: sourceImage.extent)

            // Feather da borda reduz o aspecto recortado duro. O raio é limitado
            // para evitar halos exagerados e custo excessivo em aparelhos móveis.
            if safeFeather > 0.01 {
                let blur = CIFilter.gaussianBlur()
                blur.inputImage = mask.clampedToExtent()
                blur.radius = Float(safeFeather)
                if let softened = blur.outputImage {
                    mask = softened.cropped(to: sourceImage.extent)
                }
            }

            let blend = CIFilter.blendWithMask()
            blend.inputImage = sourceImage
            blend.backgroundImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: sourceImage.extent)
            blend.maskImage = mask
            guard let outputImage = blend.outputImage,
                  let cgImage = ciContext.createCGImage(outputImage, from: sourceImage.extent) else {
                throw SegmentationError.imageEncodingFailed
            }

            frameIndex += 1
            let filename = String(format: "person-%06d.png", frameIndex)
            let frameURL = outputDirectory.appendingPathComponent(filename)
            guard let destination = CGImageDestinationCreateWithURL(frameURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw SegmentationError.imageEncodingFailed
            }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else { throw SegmentationError.imageEncodingFailed }
            records.append(FrameRecord(file: filename, time: timestamp))
            nextSampleTime = timestamp + interval
            }
        }

        if reader.status == .failed {
            if let readerError = reader.error { throw readerError }
            throw SegmentationError.cannotReadFrames
        }
        guard !records.isEmpty else { throw SegmentationError.noFrames }

        let manifest = Manifest(
            sourceName: sourceURL.lastPathComponent,
            sourceDuration: duration,
            sampleRate: safeRate,
            maskFeatherRadius: safeFeather,
            frameCount: records.count,
            createdAt: .now,
            frames: records
        )
        let manifestURL = outputDirectory.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return Result(
            directory: outputDirectory,
            manifestURL: manifestURL,
            frameCount: records.count,
            sampleRate: safeRate,
            sourceDuration: duration
        )
    }

    /// Converte a rotação gravada na faixa de vídeo na orientação de imagem equivalente.
    private static func imageOrientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
