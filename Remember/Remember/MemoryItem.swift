import Foundation
import GRDB

nonisolated enum MemoryKind: String, Codable, DatabaseValueConvertible, Hashable, Sendable {
    case audio
    case image
    case video
    case link
    case pdf
    case text
}

nonisolated enum MemoryProcessingState: String, Codable, DatabaseValueConvertible, Sendable {
    case captured
    case processing
    case indexed
    case failed

    var label: String {
        switch self {
        case .captured: "Captured"
        case .processing: "Analyzing"
        case .indexed: "Ready"
        case .failed: "Needs attention"
        }
    }
}

nonisolated struct NoteDocument: Equatable, Sendable {
    let title: String
    let body: String

    init(text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        title = lines.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        body = lines.dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(title: String, body: String) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var text: String {
        if title.isEmpty { return body }
        if body.isEmpty { return title }
        return "\(title)\n\(body)"
    }

    var displayTitle: String {
        title.isEmpty ? "Untitled Note" : title
    }
}

nonisolated struct MemoryItem: Codable, Equatable, FetchableRecord, Identifiable, PersistableRecord, Sendable {
    static let databaseTableName = "memory"

    let id: UUID
    let kind: MemoryKind
    let createdAt: Date
    let importedAt: Date
    var updatedAt: Date
    var state: MemoryProcessingState
    var originalFilename: String
    var userCaption: String?
    var title: String?
    var summary: String?
    var extractedText: String?
    var tagsJSON: String
    var processingError: String?
    var modelVersion: String?
    var analysisIsPartial: Bool = false
    var isArchived: Bool = false

    var tags: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
    }

    var displayTitle: String {
        if let title = Self.nonempty(title) {
            return title
        }
        if let caption = Self.nonempty(userCaption) {
            return String(caption.prefix(80))
        }
        switch kind {
        case .audio: return "Voice memory"
        case .image: return "Untitled image"
        case .video: return "Saved video"
        case .link: return "Saved link"
        case .pdf: return "Saved PDF"
        case .text: return "Text note"
        }
    }

    var displaySummary: String? {
        Self.nonempty(summary) ?? Self.nonempty(userCaption)
    }

    mutating func setTags(_ tags: [String]) {
        tagsJSON = Self.encodeTags(tags)
    }

    static func encodeTags(_ tags: [String]) -> String {
        let normalized = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, tag in
                guard !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
                    return
                }
                result.append(String(tag.prefix(40)))
            }
            .prefix(8)
        let data = (try? JSONEncoder().encode(Array(normalized))) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

nonisolated struct MemoryLibraryItem: Equatable, Identifiable, Sendable {
    var memory: MemoryItem
    let originalURL: URL

    var id: UUID { memory.id }
}

nonisolated struct MemoryAnalysisResult: Equatable, Sendable {
    let title: String
    let summary: String
    let tags: [String]
    let extractedText: String
    let modelVersion: String
    let chunks: [MemoryChunkDraft]
    let isPartial: Bool

    init(
        title: String,
        summary: String,
        tags: [String],
        extractedText: String,
        modelVersion: String,
        chunks: [MemoryChunkDraft] = [],
        isPartial: Bool = false
    ) {
        self.title = title
        self.summary = summary
        self.tags = tags
        self.extractedText = extractedText
        self.modelVersion = modelVersion
        self.chunks = chunks
        self.isPartial = isPartial
    }
}

nonisolated struct RememberLibraryAssistantResponse: Equatable, Sendable {
    let answer: String
    let sources: [MemoryLibraryItem]
    let modelVersion: String
    let citations: [GroundedCitation]
    let mode: RememberAnswerMode
}

nonisolated enum MemoryStoreError: LocalizedError {
    case missingMemory(UUID)
    case invalidMemoryKind(expected: MemoryKind, actual: MemoryKind)

    var errorDescription: String? {
        switch self {
        case .missingMemory(let id):
            "The memory \(id.uuidString) no longer exists."
        case .invalidMemoryKind(let expected, let actual):
            "Expected a \(expected.rawValue) memory, but found \(actual.rawValue)."
        }
    }
}
