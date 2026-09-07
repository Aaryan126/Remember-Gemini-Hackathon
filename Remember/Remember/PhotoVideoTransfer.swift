import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The Photos-owned URL expires after transfer; keep a protected copy until save/cancel.
nonisolated struct PhotoVideoTransfer: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copy = try temporaryCopy(of: received.file)
            do {
                try await LocalVideoAsset.validate(copy)
                return Self(url: copy)
            } catch {
                try? FileManager.default.removeItem(at: copy)
                throw error
            }
        }
    }

    static func temporaryCopy(of source: URL) throws -> URL {
        try Task.checkCancellation()
        let ext = source.pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext), type.conforms(to: .movie) else {
            throw InAppCaptureError.unsupportedFile
        }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("RememberVideo-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: copy.path
            )
            try Task.checkCancellation()
            return copy
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }
}
