import Foundation
import GRDB

nonisolated enum WikiPageKind: String, CaseIterable, Codable, DatabaseValueConvertible, Identifiable, Sendable {
    case project
    case decision
    case constraint
    case experiment
    case feedback
    case person
    case openQuestion = "open_question"
    case concept

    var id: String { rawValue }

    var label: String {
        switch self {
        case .project: "Projects"
        case .decision: "Decisions"
        case .constraint: "Constraints"
        case .experiment: "Experiments"
        case .feedback: "Feedback"
        case .person: "People"
        case .openQuestion: "Open Questions"
        case .concept: "Reference Knowledge"
        }
    }

    var singularLabel: String {
        switch self {
        case .project: "Project"
        case .decision: "Decision"
        case .constraint: "Constraint"
        case .experiment: "Experiment"
        case .feedback: "Feedback"
        case .person: "Person"
        case .openQuestion: "Open Question"
        case .concept: "Reference"
        }
    }

    var systemImage: String {
        switch self {
        case .project: "shippingbox.fill"
        case .decision: "arrow.triangle.branch"
        case .constraint: "exclamationmark.shield.fill"
        case .experiment: "testtube.2"
        case .feedback: "quote.bubble.fill"
        case .person: "person.fill"
        case .openQuestion: "questionmark.bubble.fill"
        case .concept: "book.closed.fill"
        }
    }
}

nonisolated enum WikiChangeKind: String, Codable, DatabaseValueConvertible, Sendable {
    case introduced
    case strengthened
    case updated
    case contradicted
    case related

    var label: String {
        switch self {
        case .introduced: "Introduced"
        case .strengthened: "Strengthened"
        case .updated: "Updated"
        case .contradicted: "Contradiction found"
        case .related: "Connected"
        }
    }
}

nonisolated enum WikiCompilationStatus: String, Codable, DatabaseValueConvertible, Sendable {
    case pending
    case processing
    case compiled
    case failed
}

nonisolated struct WikiPage: Codable, Equatable, FetchableRecord, Identifiable, PersistableRecord, Sendable {
    static let databaseTableName = "wikiPage"

    let id: UUID
    var kind: WikiPageKind
    var title: String
    var normalizedTitle: String
    var summary: String
    var aliasesJSON: String
    let createdAt: Date
    var updatedAt: Date
    var revisionNumber: Int

    var aliases: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(aliasesJSON.utf8))) ?? []
    }

    mutating func mergeAliases(_ newAliases: [String]) {
        aliasesJSON = Self.encodeAliases(aliases + newAliases)
    }

    static func encodeAliases(_ aliases: [String]) -> String {
        let normalized = aliases
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, alias in
                guard !result.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) else {
                    return
                }
                result.append(alias)
            }
            .prefix(12)
        let data = (try? JSONEncoder().encode(Array(normalized))) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

nonisolated struct WikiEvidence: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "wikiEvidence"

    let pageID: UUID
    let memoryID: UUID
    var effect: WikiChangeKind
    var rationale: String
    var createdAt: Date
}

nonisolated struct WikiPageLink: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "wikiPageLink"

    let sourcePageID: UUID
    let targetPageID: UUID
    var rationale: String
    var createdAt: Date
}

nonisolated struct WikiRevision: Codable, Equatable, FetchableRecord, Identifiable, PersistableRecord, Sendable {
    static let databaseTableName = "wikiRevision"

    let id: UUID
    let runID: UUID?
    let pageID: UUID
    let memoryID: UUID?
    let revisionNumber: Int
    let effect: WikiChangeKind
    let previousSummary: String?
    let newSummary: String
    let rationale: String
    let createdAt: Date
    let modelVersion: String
}

nonisolated struct WikiCompilation: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "wikiCompilation"

    let memoryID: UUID
    var sourceUpdatedAt: Date
    var status: WikiCompilationStatus
    var attemptedAt: Date?
    var completedAt: Date?
    var errorMessage: String?
    var modelVersion: String?
}

nonisolated struct WikiPageSearchIndexRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "wikiPageSearchIndex"

    let pageID: UUID
    let sourceUpdatedAt: Date
    let searchText: String
    let embeddingData: Data?
    let embeddingModel: String
}

nonisolated struct WikiQueueSummary: Equatable, Sendable {
    let pending: Int
    let processing: Int
    let failed: Int

    var hasWork: Bool { pending > 0 || processing > 0 }
}

nonisolated struct WikiEvidenceSource: Equatable, Identifiable, Sendable {
    let evidence: WikiEvidence
    let memory: MemoryItem

    var id: UUID { memory.id }
}

nonisolated struct WikiLinkedPage: Equatable, Identifiable, Sendable {
    let page: WikiPage
    let rationale: String

    var id: UUID { page.id }
}

nonisolated struct WikiPageSnapshot: Equatable, Sendable {
    let page: WikiPage
    let evidence: [WikiEvidenceSource]
    let linkedPages: [WikiLinkedPage]
    let revisions: [WikiRevision]
}

nonisolated struct WikiCandidate: Equatable, Sendable {
    let page: WikiPage
    let score: Double
}

nonisolated struct WikiSearchResult: Equatable, Identifiable, Sendable {
    let page: WikiPage
    let score: Double

    var id: UUID { page.id }
}

nonisolated struct WikiPageProposal: Equatable, Sendable {
    let candidateID: UUID?
    let kind: WikiPageKind
    let title: String
    let summary: String
    let aliases: [String]
    let effect: WikiChangeKind
    let rationale: String
    let relatedCandidateIDs: [UUID]
}

nonisolated struct WikiCompilationProposal: Equatable, Sendable {
    let pages: [WikiPageProposal]
}

nonisolated enum LivingWikiCandidateIndex {
    static func candidates(
        for memory: MemoryItem,
        from pages: [WikiPage],
        links: [WikiPageLink] = [],
        semanticScores: [UUID: Double] = [:],
        limit: Int = 8
    ) -> [WikiCandidate] {
        let memoryText = [
            memory.displayTitle,
            memory.displaySummary ?? "",
            memory.userCaption ?? "",
            memory.tags.joined(separator: " "),
            String((memory.extractedText ?? "").prefix(4_000)),
        ].joined(separator: " ")
        let memoryTokens = Set(tokens(in: memoryText))
        guard !memoryTokens.isEmpty || !semanticScores.isEmpty else { return [] }
        let normalizedMemoryText = normalized(memoryText)

        let directlyRanked = pages.compactMap { page -> WikiCandidate? in
            let names = [page.title] + page.aliases
            let nameTokens = Set(names.flatMap(tokens(in:)))
            let summaryTokens = Set(tokens(in: page.summary))
            let nameOverlap = coverage(nameTokens, in: memoryTokens)
            let summaryOverlap = coverage(summaryTokens, in: memoryTokens)
            let exactNameMatch = names.contains { name in
                let value = normalized(name)
                return value.count >= 4 && normalizedMemoryText.contains(value)
            }
            let lexicalScore = min(
                1,
                (nameOverlap * 0.62) + (summaryOverlap * 0.23) + (exactNameMatch ? 0.45 : 0)
            )
            let cosine = semanticScores[page.id] ?? 0
            let semanticScore = cosine >= 0.32
                ? min(1, max(0, (cosine - 0.20) / 0.65))
                : 0
            guard lexicalScore >= 0.12 || cosine >= 0.42 else { return nil }
            let score = semanticScore > 0
                ? min(1, (lexicalScore * 0.55) + (semanticScore * 0.45))
                : lexicalScore
            return WikiCandidate(page: page, score: score)
        }
        .sorted { left, right in
            if abs(left.score - right.score) > 0.000_1 {
                return left.score > right.score
            }
            return left.page.updatedAt > right.page.updatedAt
        }
        let pageByID = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        var scoreByID = Dictionary(uniqueKeysWithValues: directlyRanked.map { ($0.page.id, $0.score) })
        let directIDs = Set(directlyRanked.prefix(4).map(\.page.id))
        for link in links {
            let neighborID: UUID?
            let anchorID: UUID?
            if directIDs.contains(link.sourcePageID) {
                anchorID = link.sourcePageID
                neighborID = link.targetPageID
            } else if directIDs.contains(link.targetPageID) {
                anchorID = link.targetPageID
                neighborID = link.sourcePageID
            } else {
                anchorID = nil
                neighborID = nil
            }
            guard let anchorID, let neighborID, pageByID[neighborID] != nil else { continue }
            let graphScore = (scoreByID[anchorID] ?? 0) * 0.35
            scoreByID[neighborID] = max(scoreByID[neighborID] ?? 0, graphScore)
        }

        return scoreByID.compactMap { id, score in
            pageByID[id].map { WikiCandidate(page: $0, score: score) }
        }
        .sorted { left, right in
            if abs(left.score - right.score) > 0.000_1 {
                return left.score > right.score
            }
            return left.page.updatedAt > right.page.updatedAt
        }
        .prefix(max(1, min(limit, 12)))
        .map { $0 }
    }

    static func matches(query: String, page: WikiPage) -> Bool {
        let queryTokens = Set(tokens(in: query))
        guard !queryTokens.isEmpty else { return true }
        let pageText = ([page.title, page.summary] + page.aliases).joined(separator: " ")
        return !queryTokens.isDisjoint(with: Set(tokens(in: pageText)))
    }

    private static func coverage(_ terms: Set<String>, in document: Set<String>) -> Double {
        guard !terms.isEmpty else { return 0 }
        return Double(terms.intersection(document).count) / Double(terms.count)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokens(in value: String) -> [String] {
        normalized(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 }
    }
}

nonisolated enum WikiCompilationParser {
    private struct Payload: Decodable {
        let pages: [PagePayload]
    }

    private struct PagePayload: Decodable {
        let candidateID: String?
        let type: String
        let title: String
        let summary: String
        let aliases: [String]?
        let effect: String
        let rationale: String
        let relatedCandidateIDs: [String]?

        enum CodingKeys: String, CodingKey {
            case candidateID = "candidate_id"
            case type
            case title
            case summary
            case aliases
            case effect
            case rationale
            case relatedCandidateIDs = "related_candidate_ids"
        }
    }

    static func parse(response: String, allowedCandidateIDs: Set<UUID>) throws -> WikiCompilationProposal {
        guard let payload = jsonObjects(in: response).lazy.compactMap({ data in
            try? JSONDecoder().decode(Payload.self, from: data)
        }).first else {
            throw LivingWikiError.invalidModelResponse
        }

        let pages = payload.pages.prefix(5).compactMap { item -> WikiPageProposal? in
            guard let kind = WikiPageKind(rawValue: item.type),
                  let effect = WikiChangeKind(rawValue: item.effect),
                  let title = bounded(item.title, limit: 100),
                  let summary = bounded(item.summary, limit: 1_500),
                  let rationale = bounded(item.rationale, limit: 500) else {
                return nil
            }
            let candidateID = item.candidateID.flatMap(UUID.init(uuidString:))
            if item.candidateID != nil, candidateID == nil || !allowedCandidateIDs.contains(candidateID!) {
                return nil
            }
            let relatedIDs = (item.relatedCandidateIDs ?? [])
                .compactMap(UUID.init(uuidString:))
                .filter { allowedCandidateIDs.contains($0) && $0 != candidateID }
                .reduce(into: [UUID]()) { result, id in
                    guard !result.contains(id) else { return }
                    result.append(id)
                }
                .prefix(6)
            let aliases = (item.aliases ?? [])
                .compactMap { bounded($0, limit: 80) }
                .prefix(12)
            return WikiPageProposal(
                candidateID: candidateID,
                kind: kind,
                title: title,
                summary: summary,
                aliases: Array(aliases),
                effect: candidateID == nil ? .introduced : effect,
                rationale: rationale,
                relatedCandidateIDs: Array(relatedIDs)
            )
        }
        return WikiCompilationProposal(pages: pages)
    }

    private static func jsonObjects(in response: String) -> [Data] {
        var objects: [Data] = []
        var start: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in response.indices {
            let character = response[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let objectStart = start {
                    objects.append(Data(response[objectStart...index].utf8))
                    start = nil
                }
            }
        }
        return objects
    }

    private static func bounded(_ value: String, limit: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
    }
}

nonisolated enum LivingWikiError: LocalizedError {
    case invalidModelResponse
    case missingMemory
    case missingPage
    case sourceChanged

    var errorDescription: String? {
        switch self {
        case .invalidModelResponse: "Gemma returned a wiki update that Remember could not safely validate."
        case .missingMemory: "The source memory no longer exists."
        case .missingPage: "A referenced wiki page no longer exists."
        case .sourceChanged: "The source memory changed during compilation and is ready to compile again."
        }
    }
}
