import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

nonisolated protocol LivingWikiCompiling: Sendable {
    func compile(memory: MemoryItem, candidates: [WikiCandidate]) async throws -> WikiCompilationProposal
}

actor GemmaLivingWikiCompiler: LivingWikiCompiling {
    nonisolated static let modelVersion = "gemma-4-e2b-it-4bit-living-wiki-v1"

    nonisolated private static let cacheLimit = 20 * 1024 * 1024
    private let executionGate: GemmaExecutionGate

    init(executionGate: GemmaExecutionGate = .shared) {
        self.executionGate = executionGate
    }

    func compile(memory: MemoryItem, candidates: [WikiCandidate]) async throws -> WikiCompilationProposal {
        try await executionGate.withPermit {
            MLX.Memory.cacheLimit = Self.cacheLimit
            let directory = try GemmaModelBundle.directory()
            let container = try await VLMModelFactory.shared.loadContainer(
                from: directory,
                using: #huggingFaceTokenizerLoader()
            )
            defer { MLX.Memory.clearCache() }

            let session = ChatSession(
                container,
                generateParameters: GenerateParameters(maxTokens: 760, temperature: 0),
                processing: .init(resize: nil)
            )
            let response = try await session.respond(to: Self.prompt(memory: memory, candidates: candidates))
            return try WikiCompilationParser.parse(
                response: response,
                allowedCandidateIDs: Set(candidates.map(\.page.id))
            )
        }
    }

    nonisolated private static func prompt(memory: MemoryItem, candidates: [WikiCandidate]) -> String {
        let candidateText = candidates.map { candidate in
            let page = candidate.page
            return """
                CANDIDATE_ID: \(page.id.uuidString)
                TYPE: \(page.kind.rawValue)
                TITLE: \(String(page.title.prefix(100)))
                ALIASES: \(String(page.aliases.joined(separator: ", ").prefix(300)))
                CURRENT_SUMMARY: \(String(page.summary.prefix(700)))
                """
        }.joined(separator: "\n\n")

        let sourceText = [
            memory.userCaption,
            memory.summary,
            memory.extractedText.map { String($0.prefix(4_000)) },
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        return """
            You maintain a private living wiki from one saved memory. The source is evidence; do not use outside knowledge.

            Decide which durable pages this memory should introduce or update. Allowed types:
            - project: an ongoing effort with an objective
            - concept: a reusable idea or topic
            - decision: a choice that was made or seriously proposed
            - constraint: a limiting requirement, risk, dependency, or boundary
            - open_question: an unresolved question that matters later

            Rules:
            - Prefer an existing candidate when it represents the same durable subject, even if wording differs.
            - Use candidate_id only by copying an exact CANDIDATE_ID below. Otherwise use null to create a page.
            - Do not make pages for incidental objects, generic words, or details useful only inside this memory.
            - A page summary must integrate the new evidence with its current summary. Preserve still-valid information.
            - If evidence conflicts with a current summary, use effect "contradicted" and describe both sides without choosing one.
            - Use effect "strengthened" when it adds support, "updated" when it adds or revises information, "related" for a useful connection, and "introduced" only for new pages.
            - Return at most 5 high-value pages. Returning zero pages is valid.
            - related_candidate_ids may contain only exact candidate IDs and should express useful cross-links.
            - Keep every claim traceable to the source memory.

            Return only one JSON object with this exact shape:
            {"pages":[{"candidate_id":null,"type":"project","title":"Short title","summary":"Current integrated summary","aliases":["alternate name"],"effect":"introduced","rationale":"What this memory changed and why","related_candidate_ids":[]}]}

            SOURCE MEMORY
            MEMORY_ID: \(memory.id.uuidString)
            KIND: \(memory.kind.rawValue)
            SAVED_AT: \(memory.createdAt.formatted(.iso8601))
            TITLE: \(String(memory.displayTitle.prefix(140)))
            TAGS: \(String(memory.tags.joined(separator: ", ").prefix(300)))
            CONTENT:
            \(String(sourceText.prefix(5_000)))

            RETRIEVED CANDIDATE PAGES
            \(candidateText.isEmpty ? "None. Create only pages clearly justified by the source." : candidateText)
            """
    }
}
