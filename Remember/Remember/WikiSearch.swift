import Foundation

actor WikiSearchService {
    private static let lexicalIndexIdentifier = "living-wiki-lexical-v1"

    private let embeddingService: (any TextEmbedding)?
    private let memoryStore: MemoryStore

    init(
        memoryStore: MemoryStore,
        embeddingService: (any TextEmbedding)? = nil
    ) {
        self.memoryStore = memoryStore
        self.embeddingService = embeddingService
    }

    func synchronizeIndex() async throws {
        let pages = try await memoryStore.fetchWikiPages()
        let records = try await memoryStore.fetchWikiSearchIndexRecords()
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.pageID, $0) })
        let expectedModel = embeddingService?.modelIdentifier ?? Self.lexicalIndexIdentifier
        let stalePages = pages.filter { page in
            let record = recordsByID[page.id]
            return record == nil
                || record?.sourceUpdatedAt != page.updatedAt
                || record?.embeddingModel != expectedModel
                || (embeddingService != nil && record?.embeddingData == nil)
        }
        guard !stalePages.isEmpty else { return }

        let documents = stalePages.map(WikiSearchDocument.init(page:))
        let embeddings: [[Float]]?
        if let embeddingService {
            embeddings = try? await embeddingService.embed(documents.map(\.searchText))
        } else {
            embeddings = nil
        }

        for (index, page) in stalePages.enumerated() {
            try Task.checkCancellation()
            let vector = embeddings.flatMap { values in
                values.indices.contains(index) ? values[index] : nil
            }
            let record = WikiPageSearchIndexRecord(
                pageID: page.id,
                sourceUpdatedAt: page.updatedAt,
                searchText: documents[index].searchText,
                embeddingData: vector.map(EmbeddingVectorCodec.encode),
                embeddingModel: vector == nil
                    ? Self.lexicalIndexIdentifier
                    : (embeddingService?.modelIdentifier ?? Self.lexicalIndexIdentifier)
            )
            try await memoryStore.saveWikiSearchIndexRecord(record)
        }
    }

    func candidates(for memory: MemoryItem, limit: Int = 8) async throws -> [WikiCandidate] {
        try await synchronizeIndex()
        let pages = try await memoryStore.fetchWikiPages()
        guard !pages.isEmpty else { return [] }
        let links = try await memoryStore.fetchWikiPageLinks()
        let semanticScores = await similarities(for: MemorySearchDocument(memory: memory).searchText)
        return LivingWikiCandidateIndex.candidates(
            for: memory,
            from: pages,
            links: links,
            semanticScores: semanticScores,
            limit: limit
        )
    }

    func search(_ query: String, limit: Int = 5) async throws -> [WikiSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        try await synchronizeIndex()

        let pages = try await memoryStore.fetchWikiPages()
        let records = try await memoryStore.fetchWikiSearchIndexRecords()
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.pageID, $0) })
        let semanticScores = await similarities(for: normalizedQuery, records: records)

        return pages.compactMap { page -> WikiSearchResult? in
            let searchText = recordsByID[page.id]?.searchText ?? WikiSearchDocument(page: page).searchText
            let lexicalScore = Self.lexicalScore(query: normalizedQuery, document: searchText)
            let cosine = semanticScores[page.id] ?? 0
            let semanticScore = Self.normalizedSemanticScore(cosine)
            guard lexicalScore > 0 || cosine >= 0.42 else { return nil }
            let score = semanticScore > 0
                ? min(1, (lexicalScore * 0.45) + (semanticScore * 0.55))
                : lexicalScore
            return WikiSearchResult(page: page, score: score)
        }
        .sorted { left, right in
            if abs(left.score - right.score) > 0.000_1 {
                return left.score > right.score
            }
            return left.page.updatedAt > right.page.updatedAt
        }
        .prefix(max(1, min(limit, 8)))
        .map { $0 }
    }

    private func similarities(for text: String) async -> [UUID: Double] {
        let records = (try? await memoryStore.fetchWikiSearchIndexRecords()) ?? []
        return await similarities(for: text, records: records)
    }

    private func similarities(
        for text: String,
        records: [WikiPageSearchIndexRecord]
    ) async -> [UUID: Double] {
        guard let embeddingService,
              let queryVector = try? await embeddingService.embed([text]).first else {
            return [:]
        }
        return records.reduce(into: [UUID: Double]()) { result, record in
            guard let vector = EmbeddingVectorCodec.decode(record.embeddingData),
                  let similarity = EmbeddingVectorCodec.cosineSimilarity(queryVector, vector) else {
                return
            }
            result[record.pageID] = similarity
        }
    }

    private nonisolated static func lexicalScore(query: String, document: String) -> Double {
        let normalizedQuery = normalized(query)
        let queryTokens = Set(tokens(in: normalizedQuery))
        guard !queryTokens.isEmpty else { return 0 }
        let normalizedDocument = normalized(document)
        let documentTokens = Set(tokens(in: normalizedDocument))
        let coverage = Double(queryTokens.intersection(documentTokens).count) / Double(queryTokens.count)
        let phraseBoost = normalizedDocument.contains(normalizedQuery) ? 0.35 : 0
        return min(1, (coverage * 0.65) + phraseBoost)
    }

    private nonisolated static func normalizedSemanticScore(_ cosine: Double) -> Double {
        guard cosine >= 0.32 else { return 0 }
        return min(1, max(0, (cosine - 0.20) / 0.65))
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func tokens(in value: String) -> [String] {
        normalized(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 }
    }
}

private nonisolated struct WikiSearchDocument {
    let searchText: String

    init(page: WikiPage) {
        searchText = ([page.kind.singularLabel, page.title, page.summary] + page.aliases)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
