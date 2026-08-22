import Foundation
import GRDB

nonisolated enum MemoryDateRange: String, CaseIterable, Identifiable, Sendable {
    case anytime
    case pastWeek
    case pastMonth
    case pastYear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anytime: "Any time"
        case .pastWeek: "Past week"
        case .pastMonth: "Past month"
        case .pastYear: "Past year"
        }
    }

    func includes(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard self != .anytime else {
            return true
        }

        let component: DateComponents
        switch self {
        case .anytime:
            return true
        case .pastWeek:
            component = DateComponents(day: -7)
        case .pastMonth:
            component = DateComponents(month: -1)
        case .pastYear:
            component = DateComponents(year: -1)
        }

        guard let cutoff = calendar.date(byAdding: component, to: now) else {
            return true
        }
        return date >= cutoff && date <= now
    }
}

nonisolated struct MemorySearchRequest: Equatable, Hashable, Sendable {
    var query = ""
    var kind: MemoryKind?
    var dateRange: MemoryDateRange = .anytime
    var tag: String?

    var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool {
        !normalizedQuery.isEmpty || kind != nil || dateRange != .anytime || tag != nil
    }
}

nonisolated struct MemorySearchResult: Equatable, Identifiable, Sendable {
    let memory: MemoryItem
    let score: Double

    var id: UUID { memory.id }
}

nonisolated struct MemorySearchIndexRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "memorySearchIndex"

    let memoryID: UUID
    let sourceUpdatedAt: Date
    let searchText: String
    let embeddingData: Data?
    let embeddingModel: String
}

actor MemorySearchService {
    private static let indexModelIdentifier = "gemma-4-generated-memory-fields-v1"

    private let embeddingService: (any TextEmbedding)?
    private let memoryStore: MemoryStore
    private let now: @Sendable () -> Date

    init(
        memoryStore: MemoryStore,
        embeddingService: (any TextEmbedding)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.memoryStore = memoryStore
        self.embeddingService = embeddingService
        self.now = now
    }

    func synchronizeIndex() async throws {
        let memories = try await memoryStore.fetchIndexed()
        let existing = try await memoryStore.fetchSearchIndexRecords()
        let recordsByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.memoryID, $0) })

        let staleMemories = memories.filter { memory in
            let record = recordsByID[memory.id]
            let expectedModel = embeddingService?.modelIdentifier ?? Self.indexModelIdentifier
            return record == nil
                || record?.embeddingModel != expectedModel
                || record?.sourceUpdatedAt != memory.updatedAt
                || (embeddingService != nil && record?.embeddingData == nil)
        }
        guard !staleMemories.isEmpty else { return }

        let documents = staleMemories.map(MemorySearchDocument.init(memory:))
        let embeddings: [[Float]]?
        if let embeddingService {
            embeddings = try? await embeddingService.embed(documents.map(\.searchText))
        } else {
            embeddings = nil
        }

        for (index, memory) in staleMemories.enumerated() {
            try Task.checkCancellation()
            let vector = embeddings.flatMap { values in
                values.indices.contains(index) ? values[index] : nil
            }
            try await saveIndex(memory, document: documents[index], vector: vector)
        }
    }

    func index(_ memory: MemoryItem) async throws {
        guard memory.state == .indexed else {
            return
        }

        let document = MemorySearchDocument(memory: memory)
        let vector: [Float]?
        if let embeddingService {
            vector = try? await embeddingService.embed([document.searchText]).first
        } else {
            vector = nil
        }
        try await saveIndex(memory, document: document, vector: vector)
    }

    private func saveIndex(
        _ memory: MemoryItem,
        document: MemorySearchDocument,
        vector: [Float]?
    ) async throws {
        let record = MemorySearchIndexRecord(
            memoryID: memory.id,
            sourceUpdatedAt: memory.updatedAt,
            searchText: document.searchText,
            embeddingData: vector.map(EmbeddingVectorCodec.encode),
            embeddingModel: vector == nil
                ? Self.indexModelIdentifier
                : (embeddingService?.modelIdentifier ?? Self.indexModelIdentifier)
        )
        try await memoryStore.saveSearchIndexRecord(record)
    }

    func search(
        _ request: MemorySearchRequest,
        expandedTerms: [String] = [],
        useSemanticSimilarity: Bool = false,
        limit: Int = 50
    ) async throws -> [MemorySearchResult] {
        try await synchronizeIndex()

        let memories = try await memoryStore.fetchIndexed()
        let records = try await memoryStore.fetchSearchIndexRecords()
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.memoryID, $0) })
        let query = request.normalizedQuery
        let normalizedExpandedTerms = expandedTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let currentDate = now()
        let queryEmbedding: [Float]?
        if useSemanticSimilarity, !query.isEmpty, let embeddingService {
            queryEmbedding = try? await embeddingService.embed([query]).first
        } else {
            queryEmbedding = nil
        }

        return memories.compactMap { memory -> MemorySearchResult? in
            guard Self.includes(memory, request: request, now: currentDate),
                  let record = recordsByID[memory.id] else {
                return nil
            }

            guard !query.isEmpty else {
                return MemorySearchResult(memory: memory, score: 1)
            }

            let lexicalScore = Self.lexicalScore(query: query, memory: memory, searchText: record.searchText)
            let expansionScore = normalizedExpandedTerms
                .map { Self.lexicalScore(query: $0, memory: memory, searchText: record.searchText) }
                .max() ?? 0
            let semanticScore = Self.semanticScore(
                queryEmbedding: queryEmbedding,
                documentEmbedding: EmbeddingVectorCodec.decode(record.embeddingData)
            )
            guard lexicalScore > 0 || expansionScore > 0 || semanticScore > 0 else {
                return nil
            }

            let lexicalBest = max(lexicalScore, expansionScore)
            let score = semanticScore > 0
                ? min(1, (lexicalBest * 0.45) + (semanticScore * 0.55))
                : min(1, (lexicalScore * 0.55) + (expansionScore * 0.45))
            return MemorySearchResult(memory: memory, score: score)
        }
        .sorted { left, right in
            if abs(left.score - right.score) > 0.000_1 {
                return left.score > right.score
            }
            return left.memory.createdAt > right.memory.createdAt
        }
        .prefix(max(1, limit))
        .map { $0 }
    }

    private nonisolated static func includes(
        _ memory: MemoryItem,
        request: MemorySearchRequest,
        now: Date
    ) -> Bool {
        if let kind = request.kind, memory.kind != kind {
            return false
        }
        guard request.dateRange.includes(memory.createdAt, now: now) else {
            return false
        }
        if let tag = request.tag,
           !memory.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            return false
        }
        return true
    }

    private nonisolated static func lexicalScore(
        query: String,
        memory: MemoryItem,
        searchText: String
    ) -> Double {
        let normalizedQuery = normalized(query)
        let normalizedDocument = normalized(searchText)
        let queryTokens = Set(tokens(in: normalizedQuery))
        guard !queryTokens.isEmpty else {
            return 0
        }

        let documentTokens = Set(tokens(in: normalizedDocument))
        let matchedTokens = queryTokens.intersection(documentTokens).count
        let coverage = Double(matchedTokens) / Double(queryTokens.count)
        let phraseBoost = normalizedDocument.contains(normalizedQuery) ? 0.25 : 0
        let title = normalized(memory.displayTitle)
        let titleBoost = title.contains(normalizedQuery) ? 0.25 : 0
        let tagBoost = memory.tags.contains(where: {
            normalized($0).contains(normalizedQuery) || queryTokens.contains(normalized($0))
        }) ? 0.15 : 0
        return min(1, (coverage * 0.5) + phraseBoost + titleBoost + tagBoost)
    }

    private nonisolated static func semanticScore(
        queryEmbedding: [Float]?,
        documentEmbedding: [Float]?
    ) -> Double {
        guard let queryEmbedding,
              let documentEmbedding,
              let cosine = EmbeddingVectorCodec.cosineSimilarity(queryEmbedding, documentEmbedding),
              cosine >= 0.32 else {
            return 0
        }
        return min(1, max(0, (cosine - 0.20) / 0.65))
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func tokens(in value: String) -> [String] {
        value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

}

nonisolated struct MemorySearchDocument {
    let searchText: String

    init(memory: MemoryItem) {
        let title = memory.title ?? ""
        let summary = memory.summary ?? ""
        let caption = memory.userCaption ?? ""
        let tags = memory.tags.joined(separator: " ")
        let extractedText = String((memory.extractedText ?? "").prefix(4_000))

        searchText = [title, summary, caption, tags, extractedText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
