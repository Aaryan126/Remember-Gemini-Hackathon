import Foundation

// Legacy Project persistence still refers to these value types. The live Project
// feature is intentionally disabled while its replacement is designed.
nonisolated protocol LivingWikiCompiling: Sendable {
    var modelVersion: String { get }
    var promptVersion: String { get }
    func compile(memory: MemoryItem, candidates: [WikiCandidate]) async throws -> LivingWikiCompilationResult
}

nonisolated struct LivingWikiCompilationResult: Equatable, Sendable {
    let proposal: WikiCompilationProposal
    let recovery: LivingWikiCompilationRecovery
}

nonisolated enum LivingWikiCompilationRecovery: Equatable, Sendable {
    case none
    case linkedAfterMalformedOutput
    case linkedAfterNoChange
    case noChange
}

nonisolated enum LivingWikiEvidenceRecovery {
    private static let minimumCandidateScore = 0.12

    static func proposal(candidates: [WikiCandidate]) -> WikiCompilationProposal? {
        guard let candidate = candidates.first,
              candidate.score >= minimumCandidateScore else { return nil }
        let page = candidate.page
        return WikiCompilationProposal(pages: [
            WikiPageProposal(
                candidateID: page.id,
                kind: page.kind,
                title: page.title,
                summary: page.summary,
                aliases: [],
                effect: .related,
                rationale: "The source matches this retained legacy page.",
                relatedCandidateIDs: []
            ),
        ])
    }
}
