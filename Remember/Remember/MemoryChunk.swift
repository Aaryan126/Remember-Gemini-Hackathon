import Foundation
import GRDB

nonisolated struct MemoryChunk: Codable, Equatable, FetchableRecord, Identifiable, PersistableRecord, Sendable {
    static let databaseTableName = "memoryChunk"

    let id: UUID
    let memoryID: UUID
    let ordinal: Int
    let locator: String
    let text: String
    let extractionMethod: MemoryExtractionMethod
    let sourceUpdatedAt: Date
    var embeddingData: Data?
    var embeddingModel: String

    static func make(
        memoryID: UUID,
        sourceUpdatedAt: Date,
        draft: MemoryChunkDraft,
        embeddingData: Data? = nil,
        embeddingModel: String = "lexical-only-v1"
    ) -> MemoryChunk {
        MemoryChunk(
            id: stableID(memoryID: memoryID, ordinal: draft.ordinal),
            memoryID: memoryID,
            ordinal: draft.ordinal,
            locator: String(draft.locator.prefix(120)),
            text: String(draft.text.prefix(1_200)),
            extractionMethod: draft.extractionMethod,
            sourceUpdatedAt: sourceUpdatedAt,
            embeddingData: embeddingData,
            embeddingModel: embeddingModel
        )
    }

    private static func stableID(memoryID: UUID, ordinal: Int) -> UUID {
        var uuid = memoryID.uuid
        var bytes = withUnsafeBytes(of: &uuid) { Array($0) }
        var value = UInt64(max(0, ordinal)).bigEndian
        withUnsafeBytes(of: &value) { ordinalBytes in
            for index in 0..<8 {
                bytes[8 + index] ^= ordinalBytes[index]
            }
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

nonisolated struct MemoryEvidenceExcerpt: Equatable, Identifiable, Sendable {
    let chunk: MemoryChunk
    let memory: MemoryItem
    let score: Double

    var id: UUID { chunk.id }
}

nonisolated enum MemoryChunker {
    static func legacyDrafts(for memory: MemoryItem) -> [MemoryChunkDraft] {
        let text = memory.extractedText
            ?? memory.userCaption
            ?? memory.displaySummary
            ?? ""
        return MemoryTextChunker.chunks(
            from: text,
            locatorPrefix: legacyLocator(for: memory.kind),
            extractionMethod: legacyMethod(for: memory.kind)
        )
    }

    private static func legacyLocator(for kind: MemoryKind) -> String {
        switch kind {
        case .audio: "Transcript"
        case .image: "Image text"
        case .video: "Video caption"
        case .link: "Saved link"
        case .pdf: "Imported document"
        case .text: "Saved note"
        }
    }

    private static func legacyMethod(for kind: MemoryKind) -> MemoryExtractionMethod {
        switch kind {
        case .audio: .transcript
        case .image: .visionOCR
        case .pdf: .pdfText
        case .link, .text, .video: .plainText
        }
    }
}
