import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct PickedMediaFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try stagedCopy(from: received.file, fallbackExtension: "mov")
        }
        FileRepresentation(importedContentType: .video) { received in
            try stagedCopy(from: received.file, fallbackExtension: "mp4")
        }
        FileRepresentation(importedContentType: .image) { received in
            try stagedCopy(from: received.file, fallbackExtension: "jpg")
        }
    }

    private static func stagedCopy(from source: URL, fallbackExtension: String) throws -> PickedMediaFile {
        // Mantém o nome original do arquivo em uma pasta temporária própria.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorIA-Photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = source.pathExtension.isEmpty ? "\(source.lastPathComponent).\(fallbackExtension)" : source.lastPathComponent
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return PickedMediaFile(url: destination)
    }
}
