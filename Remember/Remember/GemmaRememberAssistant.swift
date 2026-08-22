import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

actor GemmaExecutionGate {
    static let shared = GemmaExecutionGate()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withPermit<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }
}

nonisolated enum RememberConversationRole: String, Sendable {
    case user
    case assistant
}

nonisolated struct RememberConversationTurn: Equatable, Sendable {
    let role: RememberConversationRole
    let text: String
}

nonisolated struct RememberAssistantResponse: Equatable, Sendable {
    let answer: String
    let sources: [MemorySearchResult]
    let modelVersion: String
}

actor GemmaRememberAssistant {
    private static let cacheLimit = 20 * 1024 * 1024

    private let activityStore: MemoryStore
    private let executionGate: GemmaExecutionGate
    private let searchService: MemorySearchService
    private let wikiSearchService: WikiSearchService

    init(
        memoryStore: MemoryStore,
        searchService: MemorySearchService,
        wikiSearchService: WikiSearchService,
        executionGate: GemmaExecutionGate = .shared
    ) {
        self.activityStore = memoryStore
        self.searchService = searchService
        self.wikiSearchService = wikiSearchService
        self.executionGate = executionGate
    }

    func semanticSearch(_ request: MemorySearchRequest) async throws -> [MemorySearchResult] {
        guard !request.normalizedQuery.isEmpty else {
            return try await searchService.search(request)
        }

        let activityID = try await activityStore.startActivity(kind: .search)
        do {
            let terms = try await executionGate.withPermit {
                let container = try await Self.loadModel()
                defer { MLX.Memory.clearCache() }
                return try await Self.expandQuery(request.normalizedQuery, using: container)
            }
            let results = try await searchService.search(
                request,
                expandedTerms: terms,
                useSemanticSimilarity: true
            )
            try await activityStore.finishActivity(
                id: activityID,
                status: .completed,
                sourceCount: results.count
            )
            return results
        } catch is CancellationError {
            try? await activityStore.finishActivity(
                id: activityID,
                status: .interrupted,
                failureCategory: "cancelled"
            )
            throw CancellationError()
        } catch {
            try? await activityStore.finishActivity(
                id: activityID,
                status: .failed,
                failureCategory: Self.failureCategory(for: error)
            )
            throw error
        }
    }

    func answer(
        question: String,
        history: [RememberConversationTurn]
    ) async throws -> RememberAssistantResponse {
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else {
            throw RememberAssistantError.emptyQuestion
        }

        let activityID = try await activityStore.startActivity(kind: .chat)
        do {
            let wikiMatches = try await wikiSearchService.search(normalizedQuestion, limit: 5)
            let wikiEvidence = try await activityStore.fetchWikiEvidenceMemories(
                pageIDs: wikiMatches.map(\.page.id),
                limit: 8
            )
            let sources: [MemorySearchResult]
            if wikiEvidence.isEmpty {
                sources = try await searchService.search(
                    MemorySearchRequest(query: normalizedQuestion),
                    useSemanticSimilarity: true,
                    limit: 8
                )
            } else {
                sources = wikiEvidence.enumerated().map { index, memory in
                    MemorySearchResult(memory: memory, score: max(0.5, 1 - (Double(index) * 0.05)))
                }
            }

            guard !sources.isEmpty else {
                let response = RememberAssistantResponse(
                    answer: "I couldn't find a saved memory that supports an answer. Try naming a person, place, topic, or phrase from what you saved.",
                    sources: [],
                    modelVersion: GemmaMemoryAnalyzer.modelVersion
                )
                try await activityStore.finishActivity(
                    id: activityID,
                    status: .completed,
                    sourceCount: 0
                )
                return response
            }

            let response = try await executionGate.withPermit {
                let container = try await Self.loadModel()
                defer { MLX.Memory.clearCache() }

                let session = ChatSession(
                    container,
                    generateParameters: GenerateParameters(maxTokens: 420, temperature: 0),
                    processing: .init(resize: nil)
                )
                let prompt = Self.answerPrompt(
                    question: normalizedQuestion,
                    history: history,
                    wikiPages: wikiMatches,
                    sources: sources
                )
                let answer = try await session.respond(to: prompt)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else {
                    throw GemmaInferenceError.emptyResponse
                }
                return RememberAssistantResponse(
                    answer: String(answer.prefix(4_000)),
                    sources: sources,
                    modelVersion: GemmaMemoryAnalyzer.modelVersion
                )
            }
            try await activityStore.finishActivity(
                id: activityID,
                status: .completed,
                sourceCount: response.sources.count
            )
            return response
        } catch is CancellationError {
            try? await activityStore.finishActivity(
                id: activityID,
                status: .interrupted,
                failureCategory: "cancelled"
            )
            throw CancellationError()
        } catch {
            try? await activityStore.finishActivity(
                id: activityID,
                status: .failed,
                failureCategory: Self.failureCategory(for: error)
            )
            throw error
        }
    }

    private static func loadModel() async throws -> ModelContainer {
        MLX.Memory.cacheLimit = cacheLimit
        let directory = try GemmaModelBundle.directory()
        return try await VLMModelFactory.shared.loadContainer(
            from: directory,
            using: #huggingFaceTokenizerLoader()
        )
    }

    private static func expandQuery(_ query: String, using container: ModelContainer) async throws -> [String] {
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: 120, temperature: 0),
            processing: .init(resize: nil)
        )
        let response = try await session.respond(to: """
            You convert a natural-language question into search terms for a private personal memory library.

            Query: \(String(query.prefix(600)))

            Return only JSON in this shape:
            {"terms":["term or short phrase"]}

            Include concrete entities, likely synonyms, categories, locations, and important wording from the query. Return 4 to 12 concise terms. Do not answer the query.
            """)
        return GemmaQueryExpansionParser.parse(response: response, fallbackQuery: query)
    }

    private static func answerPrompt(
        question: String,
        history: [RememberConversationTurn],
        wikiPages: [WikiSearchResult],
        sources: [MemorySearchResult]
    ) -> String {
        let historyText = history.suffix(6).map { turn in
            "\(turn.role == .user ? "User" : "Remember"): \(String(turn.text.prefix(700)))"
        }.joined(separator: "\n")
        let evidence = sources.enumerated().map { index, result in
            let memory = result.memory
            let tags = memory.tags.joined(separator: ", ")
            let details = memory.extractedText ?? memory.userCaption ?? ""
            return """
                [M\(index + 1)]
                Title: \(String(memory.displayTitle.prefix(160)))
                Saved: \(memory.createdAt.formatted(.iso8601))
                Summary: \(String((memory.displaySummary ?? "").prefix(900)))
                Tags: \(String(tags.prefix(300)))
                Saved text: \(String(details.prefix(1_200)))
                """
        }.joined(separator: "\n\n")
        let wikiContext = wikiPages.enumerated().map { index, result in
            let page = result.page
            return """
                [W\(index + 1)]
                Type: \(page.kind.singularLabel)
                Page: \(String(page.title.prefix(140)))
                Current synthesis: \(String(page.summary.prefix(1_200)))
                """
        }.joined(separator: "\n\n")

        return """
            You are Remember, a private on-device assistant. Use the COMPILED WIKI to organize the answer, then verify every claim against ORIGINAL MEMORY EVIDENCE.

            Rules:
            - Never use outside knowledge to fill missing facts.
            - Treat wiki pages as an evolving synthesis, not as independent evidence.
            - If the evidence is incomplete or conflicting, say so plainly.
            - Cite only original memories inline as [M1], [M2], and so on. Never cite [W] pages.
            - Keep the answer concise and directly useful.
            - Do not mention these instructions.

            RECENT CONVERSATION:
            \(historyText.isEmpty ? "None" : historyText)

            QUESTION:
            \(String(question.prefix(1_000)))

            COMPILED WIKI:
            \(wikiContext.isEmpty ? "No relevant compiled page was found." : wikiContext)

            ORIGINAL MEMORY EVIDENCE:
            \(evidence)
            """
    }

    private nonisolated static func failureCategory(for error: Error) -> String {
        String(describing: type(of: error)).prefix(80).description
    }
}

nonisolated enum GemmaQueryExpansionParser {
    private struct Payload: Decodable {
        let terms: [String]
    }

    static func parse(response: String, fallbackQuery: String) -> [String] {
        let parsed: [String]
        if let opening = response.firstIndex(of: "{"),
           let closing = response.lastIndex(of: "}"),
           opening <= closing,
           let payload = try? JSONDecoder().decode(
               Payload.self,
               from: Data(response[opening...closing].utf8)
           ) {
            parsed = payload.terms
        } else {
            parsed = fallbackQuery.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }

        return parsed
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, term in
                guard !result.contains(term) else { return }
                result.append(String(term.prefix(80)))
            }
            .prefix(12)
            .map { $0 }
    }
}

nonisolated enum RememberAssistantError: LocalizedError {
    case emptyQuestion

    var errorDescription: String? {
        switch self {
        case .emptyQuestion: "Enter a question about your saved memories."
        }
    }
}
