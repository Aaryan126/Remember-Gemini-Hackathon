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
    nonisolated static let modelVersion = "gemma-4-e2b-it-4bit-project-memory-v4"
    nonisolated static let promptVersion = ProjectMemoryProgram.current.promptVersion

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
            let allowedCandidateIDs = Set(candidates.map(\.page.id))
            let response = try await session.respond(to: Self.prompt(memory: memory, candidates: candidates))
            do {
                return try WikiCompilationParser.parse(
                    response: response,
                    allowedCandidateIDs: allowedCandidateIDs
                )
            } catch LivingWikiError.invalidModelResponse {
                let repairedResponse = try await session.respond(to: Self.repairPrompt)
                return try WikiCompilationParser.parse(
                    response: repairedResponse,
                    allowedCandidateIDs: allowedCandidateIDs
                )
            }
        }
    }

    nonisolated private static func prompt(memory: MemoryItem, candidates: [WikiCandidate]) -> String {
        let program = ProjectMemoryProgram.current
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
            You maintain a private project memory from one saved item. The source is evidence; do not use outside knowledge.

            PROGRAM: \(program.name)
            PROGRAM_VERSION: \(program.version)
            OBJECTIVE: \(program.objective)

            Decide which durable pages this memory should introduce or update. Allowed types:
            \(program.promptTypeList)

            Rules:
            - Prefer an existing candidate when it represents the same durable subject, even if wording differs.
            - Use candidate_id only by copying an exact CANDIDATE_ID below. Otherwise use null to create a page.
            - Prefer project-specific decisions, constraints, experiments, feedback, people, and open questions over generic concepts.
            - A project is an active effort with an objective. Rules, requirements, deadlines, and submission guidance are constraints or reference knowledge, not projects.
            - Create fewer, broader pages. Do not split one source into pages that express substantially the same subject.
            - Do not make pages for incidental objects, generic words, or details useful only inside this memory.
            - A page summary must integrate the new evidence with its current summary. Preserve still-valid information.
            - If evidence conflicts with a current summary, use effect "contradicted" and describe both sides without choosing one.
            - Use effect "strengthened" when it adds support, "updated" when it adds or revises information, "related" for a useful connection, and "introduced" only for new pages.
            - Return at most 3 high-value pages. Returning zero pages is valid.
            - Keep each title under 12 words, each summary under 90 words, each rationale under 30 words, and aliases to at most 4.
            - related_candidate_ids may contain only exact candidate IDs and should express useful cross-links.
            - Keep every claim traceable to the source memory.
            - Return compact JSON and always finish every closing quote, bracket, and brace before the token limit.

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

    nonisolated private static let repairPrompt = """
        Your previous response was not valid as the required JSON object. Correct it now using the same source and candidate IDs.
        Return only compact JSON in the exact requested shape—no Markdown or explanation.
        Keep at most 3 highest-value pages, summaries under 70 words, rationales under 20 words, aliases to at most 3, and finish every closing bracket and brace.
        If no safe durable page can be expressed, return exactly {"pages":[]}.
        """
}
