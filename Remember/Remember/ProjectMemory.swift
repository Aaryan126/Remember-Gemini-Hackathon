import Foundation
import GRDB

nonisolated struct ProjectMemoryProgram: Sendable {
    static let current = ProjectMemoryProgram()

    let name = "Private Project Memory"
    let version = "private-project-memory-v1"
    let promptVersion = "project-memory-compiler-v4"
    let objective = "Preserve what a project knows, why choices were made, what changed, and what still needs an answer."

    var pageKinds: [WikiPageKind] { WikiPageKind.allCases }

    func definition(for kind: WikiPageKind) -> String {
        switch kind {
        case .project: "an ongoing effort with an objective and a current state"
        case .decision: "a choice that was made or seriously proposed, including its reasoning"
        case .constraint: "a limiting requirement, risk, dependency, budget, or boundary"
        case .experiment: "a bounded test with a hypothesis, method, observation, or result"
        case .feedback: "actionable input from a user, reviewer, customer, or collaborator"
        case .person: "a person whose role, expertise, commitment, or relationship matters to the project"
        case .openQuestion: "an unresolved question that affects later work or decisions"
        case .concept: "durable reference knowledge that supports the project but is not one of the other types"
        }
    }

    var promptTypeList: String {
        pageKinds
            .map { "- \($0.rawValue): \(definition(for: $0))" }
            .joined(separator: "\n")
    }
}

nonisolated enum ProjectMemoryRunOperation: String, Codable, DatabaseValueConvertible, Sendable {
    case compile
    case lint

    var label: String {
        switch self {
        case .compile: "Memory integration"
        case .lint: "Project memory check"
        }
    }
}

nonisolated enum ProjectMemoryRunStatus: String, Codable, DatabaseValueConvertible, Sendable {
    case running
    case kept
    case discarded
    case passed
    case attention
    case failed

    var label: String {
        switch self {
        case .running: "Running"
        case .kept: "Kept"
        case .discarded: "No change"
        case .passed: "Passed"
        case .attention: "Needs attention"
        case .failed: "Failed"
        }
    }
}

nonisolated enum ProjectMemoryCheckSeverity: String, Codable, DatabaseValueConvertible, Sendable {
    case information
    case warning
    case blocking
}

nonisolated struct ProjectMemoryRun: Codable, Equatable, FetchableRecord, Identifiable, PersistableRecord, Sendable {
    static let databaseTableName = "projectMemoryRun"

    let id: UUID
    let operation: ProjectMemoryRunOperation
    let memoryID: UUID?
    let startedAt: Date
    var completedAt: Date?
    var status: ProjectMemoryRunStatus
    let modelVersion: String
    let promptVersion: String
    let programVersion: String
    var proposedPageCount: Int
    var acceptedPageCount: Int
    var rationale: String
}

nonisolated struct ProjectMemoryCheck: Codable, Equatable, FetchableRecord, Identifiable, PersistableRecord, Sendable {
    static let databaseTableName = "projectMemoryCheck"

    let id: UUID
    let runID: UUID
    let checkID: String
    let label: String
    let severity: ProjectMemoryCheckSeverity
    let passed: Bool
    let message: String
}

nonisolated struct ProjectMemoryCheckDraft: Equatable, Sendable {
    let checkID: String
    let label: String
    let severity: ProjectMemoryCheckSeverity
    let passed: Bool
    let message: String
}

nonisolated struct ProjectMemoryRevisionChange: Equatable, Identifiable, Sendable {
    let revision: WikiRevision
    let pageTitle: String
    let pageKind: WikiPageKind

    var id: UUID { revision.id }
}

nonisolated struct ProjectMemoryRunSnapshot: Equatable, Identifiable, Sendable {
    let run: ProjectMemoryRun
    let memoryTitle: String?
    let checks: [ProjectMemoryCheck]
    let changes: [ProjectMemoryRevisionChange]

    var id: UUID { run.id }
}

nonisolated struct ProjectMemoryPatchDecision: Equatable, Sendable {
    let checks: [ProjectMemoryCheckDraft]
    let proposalToApply: WikiCompilationProposal
    let status: ProjectMemoryRunStatus
    let rationale: String
}

nonisolated struct ProjectMemoryRunCompletion: Equatable, Sendable {
    let status: ProjectMemoryRunStatus
    let proposedPageCount: Int
    let acceptedPageCount: Int
    let rationale: String
    let checks: [ProjectMemoryCheckDraft]
}

nonisolated enum ProjectMemoryPatchEvaluator {
    static func evaluate(
        proposal: WikiCompilationProposal,
        allowedCandidateIDs: Set<UUID>,
        candidates: [WikiCandidate] = []
    ) -> ProjectMemoryPatchDecision {
        let originalPages = proposal.pages
        let scopedIDs = originalPages.flatMap { page in
            [page.candidateID].compactMap { $0 } + page.relatedCandidateIDs
        }
        let requiredFieldsPresent = originalPages.allSatisfy {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let refined = refine(originalPages, candidates: candidates)
        let pages = refined.pages
        let targetKeys = pages.map { page in
            if let candidateID = page.candidateID {
                return "existing:\(candidateID.uuidString)"
            }
            return "new:\(page.kind.rawValue):\(normalized(page.title))"
        }
        let uniqueTargets = Set(targetKeys).count == targetKeys.count
        let linksAreClean = pages.allSatisfy { page in
            guard let candidateID = page.candidateID else { return true }
            return !page.relatedCandidateIDs.contains(candidateID)
        }

        let checks = [
            ProjectMemoryCheckDraft(
                checkID: "patch.page_budget",
                label: "Bounded patch",
                severity: .blocking,
                passed: originalPages.count <= 3,
                message: "Proposed \(originalPages.count) of at most 3 high-value page changes."
            ),
            ProjectMemoryCheckDraft(
                checkID: "patch.candidate_scope",
                label: "Retrieved-page boundary",
                severity: .blocking,
                passed: scopedIDs.allSatisfy(allowedCandidateIDs.contains),
                message: "Every referenced page must come from the bounded local candidate set."
            ),
            ProjectMemoryCheckDraft(
                checkID: "patch.traceability",
                label: "Source traceability",
                severity: .blocking,
                passed: requiredFieldsPresent,
                message: "Every proposed change needs a title, integrated summary, and source-grounded rationale."
            ),
            ProjectMemoryCheckDraft(
                checkID: "patch.type_suitability",
                label: "Page types fit their content",
                severity: .information,
                passed: true,
                message: refined.typeFilteredCount == 0
                    ? "Every accepted page uses a suitable project-memory type."
                    : "Filtered \(refined.typeFilteredCount) proposal(s) whose type did not fit the source-grounded content."
            ),
            ProjectMemoryCheckDraft(
                checkID: "patch.semantic_duplicates",
                label: "Equivalent pages are consolidated",
                severity: .information,
                passed: true,
                message: refined.consolidatedCount == 0
                    ? "No semantically equivalent page proposals were found."
                    : "Consolidated or removed \(refined.consolidatedCount) semantically equivalent proposal(s)."
            ),
            ProjectMemoryCheckDraft(
                checkID: "patch.unique_targets",
                label: "One change per page",
                severity: .blocking,
                passed: uniqueTargets,
                message: "A single run cannot update the same canonical page twice."
            ),
            ProjectMemoryCheckDraft(
                checkID: "patch.link_hygiene",
                label: "Link hygiene",
                severity: .blocking,
                passed: linksAreClean,
                message: "Proposed connections cannot link a page to itself."
            ),
        ]
        let safe = !checks.contains { !$0.passed && $0.severity == .blocking }
        if !safe {
            return ProjectMemoryPatchDecision(
                checks: checks,
                proposalToApply: WikiCompilationProposal(pages: []),
                status: .discarded,
                rationale: "The proposed update was discarded because a protected structural check failed."
            )
        }
        if pages.isEmpty {
            return ProjectMemoryPatchDecision(
                checks: checks,
                proposalToApply: WikiCompilationProposal(pages: pages),
                status: .discarded,
                rationale: "Gemma found no durable project knowledge to add from this memory."
            )
        }
        return ProjectMemoryPatchDecision(
            checks: checks,
            proposalToApply: WikiCompilationProposal(pages: pages),
            status: .kept,
            rationale: "The bounded, source-linked patch passed every protected structural check."
        )
    }

    private struct Refinement {
        let pages: [WikiPageProposal]
        let typeFilteredCount: Int
        let consolidatedCount: Int
    }

    private static func refine(
        _ proposals: [WikiPageProposal],
        candidates: [WikiCandidate]
    ) -> Refinement {
        let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.page.id, $0.page) })
        var accepted: [WikiPageProposal] = []
        var typeFilteredCount = 0
        var consolidatedCount = 0

        for original in proposals.prefix(3) {
            var proposal = original
            if let candidateID = proposal.candidateID, let canonical = candidatesByID[candidateID] {
                proposal = WikiPageProposal(
                    candidateID: candidateID,
                    kind: canonical.kind,
                    title: canonical.title,
                    summary: proposal.summary,
                    aliases: proposal.aliases,
                    effect: proposal.effect,
                    rationale: proposal.rationale,
                    relatedCandidateIDs: proposal.relatedCandidateIDs.filter { $0 != candidateID }
                )
            } else if proposal.candidateID == nil {
                guard ProjectMemoryTypeSuitability.isSuitable(proposal) else {
                    typeFilteredCount += 1
                    continue
                }
                if let match = candidates
                    .map(\.page)
                    .filter({ $0.kind == proposal.kind })
                    .max(by: {
                        ProjectMemorySimilarity.similarity(page: $0, proposal: proposal)
                            < ProjectMemorySimilarity.similarity(page: $1, proposal: proposal)
                    }),
                   ProjectMemorySimilarity.similarity(page: match, proposal: proposal) >= 0.55 {
                    proposal = WikiPageProposal(
                        candidateID: match.id,
                        kind: match.kind,
                        title: match.title,
                        summary: proposal.summary,
                        aliases: proposal.aliases + [original.title],
                        effect: .updated,
                        rationale: proposal.rationale,
                        relatedCandidateIDs: proposal.relatedCandidateIDs.filter { $0 != match.id }
                    )
                    consolidatedCount += 1
                }
            }

            let duplicatesAccepted = accepted.contains { existing in
                if let left = existing.candidateID, let right = proposal.candidateID {
                    return left == right
                }
                return ProjectMemorySimilarity.similarity(left: existing, right: proposal) >= 0.64
            }
            if duplicatesAccepted {
                consolidatedCount += 1
            } else {
                accepted.append(proposal)
            }
        }
        return Refinement(
            pages: accepted,
            typeFilteredCount: typeFilteredCount,
            consolidatedCount: consolidatedCount
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

nonisolated enum ProjectMemoryTypeSuitability {
    static func isSuitable(_ proposal: WikiPageProposal) -> Bool {
        let text = ProjectMemorySimilarity.normalized("\(proposal.title) \(proposal.summary)")
        switch proposal.kind {
        case .project:
            let ruleSignals = ["rule", "guideline", "must", "required", "requirement", "submission component"]
            let activeSignals = ["building", "developing", "launching", "initiative", "product", "venture", "objective", "goal"]
            return !containsAny(text, ruleSignals) || containsAny(text, activeSignals)
        case .decision:
            return containsAny(text, ["decided", "decision", "chose", "chosen", "selected", "adopted", "instead of", "will use", "use "])
        case .constraint:
            return containsAny(text, ["must", "required", "cannot", "limit", "deadline", "budget", "risk", "dependency", "constraint", "only"])
        case .experiment:
            return containsAny(text, ["experiment", "hypothesis", "test", "trial", "prototype", "measured", "result"])
        case .feedback:
            return containsAny(text, ["feedback", "reviewer", "customer", "user said", "requested", "suggested", "complaint"])
        case .openQuestion:
            return text.contains("?") || containsAny(text, ["unresolved", "open question", "whether", "how should", "what should", "which should"])
        case .person, .concept:
            return true
        }
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains(where: text.contains)
    }
}

nonisolated enum ProjectMemorySimilarity {
    private static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "is", "it", "of", "on", "or", "that", "the", "this", "to", "with"
    ]

    static func similarity(page: WikiPage, proposal: WikiPageProposal) -> Double {
        similarity(
            leftTitle: page.title,
            leftSummary: page.summary,
            rightTitle: proposal.title,
            rightSummary: proposal.summary
        )
    }

    static func similarity(left: WikiPageProposal, right: WikiPageProposal) -> Double {
        guard left.kind == right.kind else { return 0 }
        return similarity(
            leftTitle: left.title,
            leftSummary: left.summary,
            rightTitle: right.title,
            rightSummary: right.summary
        )
    }

    static func similarity(left: WikiPage, right: WikiPage) -> Double {
        guard left.kind == right.kind else { return 0 }
        return similarity(
            leftTitle: left.title,
            leftSummary: left.summary,
            rightTitle: right.title,
            rightSummary: right.summary
        )
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func similarity(
        leftTitle: String,
        leftSummary: String,
        rightTitle: String,
        rightSummary: String
    ) -> Double {
        let leftTitleTokens = tokens(leftTitle)
        let rightTitleTokens = tokens(rightTitle)
        let leftAllTokens = tokens("\(leftTitle) \(leftSummary)")
        let rightAllTokens = tokens("\(rightTitle) \(rightSummary)")
        let titleScore = overlap(leftTitleTokens, rightTitleTokens)
        let contentScore = overlap(leftAllTokens, rightAllTokens)
        return (titleScore * 0.40) + (contentScore * 0.60)
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(normalized(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) })
    }

    private static func overlap(_ left: Set<String>, _ right: Set<String>) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = Double(left.intersection(right).count)
        let containment = intersection / Double(min(left.count, right.count))
        let jaccard = intersection / Double(left.union(right).count)
        return (containment * 0.72) + (jaccard * 0.28)
    }
}

nonisolated enum ProjectMemoryLinter {
    static func checks(
        pages: [WikiPage],
        evidence: [WikiEvidence],
        revisions: [WikiRevision],
        links: [WikiPageLink]
    ) -> [ProjectMemoryCheckDraft] {
        let pageIDs = Set(pages.map(\.id))
        let evidencedPageIDs = Set(evidence.map(\.pageID))
        let revisionsByPage = Dictionary(grouping: revisions, by: \.pageID)
        let untraceable = pages.filter { !evidencedPageIDs.contains($0.id) }
        let inconsistent = pages.filter { page in
            guard let newest = revisionsByPage[page.id]?.map(\.revisionNumber).max() else { return true }
            return newest != page.revisionNumber
        }
        let invalidLinks = links.filter {
            $0.sourcePageID == $0.targetPageID
                || !pageIDs.contains($0.sourcePageID)
                || !pageIDs.contains($0.targetPageID)
        }
        let duplicateGroups = Dictionary(grouping: pages) {
            "\($0.kind.rawValue):\($0.normalizedTitle)"
        }.values.filter { $0.count > 1 }
        var likelyDuplicatePairs: [(WikiPage, WikiPage)] = []
        for leftIndex in pages.indices {
            for rightIndex in pages.indices where rightIndex > leftIndex {
                let left = pages[leftIndex]
                let right = pages[rightIndex]
                // Lint is read-only, so it deliberately favors recall. The write
                // gate above remains stricter before it redirects a live patch.
                if ProjectMemorySimilarity.similarity(left: left, right: right) >= 0.45 {
                    likelyDuplicatePairs.append((left, right))
                }
            }
        }
        let connectedPageIDs = Set(links.flatMap { [$0.sourcePageID, $0.targetPageID] })
        let isolatedCount = pages.count > 1 ? pages.filter { !connectedPageIDs.contains($0.id) }.count : 0

        return [
            ProjectMemoryCheckDraft(
                checkID: "wiki.source_traceability",
                label: "Every page has evidence",
                severity: .blocking,
                passed: untraceable.isEmpty,
                message: untraceable.isEmpty
                    ? "All \(pages.count) pages link back to at least one saved memory."
                    : "\(untraceable.count) pages have no remaining source memory."
            ),
            ProjectMemoryCheckDraft(
                checkID: "wiki.revision_integrity",
                label: "Revision history matches",
                severity: .blocking,
                passed: inconsistent.isEmpty,
                message: inconsistent.isEmpty
                    ? "Every current page matches its latest stored revision."
                    : "\(inconsistent.count) pages have an incomplete revision trail."
            ),
            ProjectMemoryCheckDraft(
                checkID: "wiki.canonical_uniqueness",
                label: "Canonical pages are unique",
                severity: .blocking,
                passed: duplicateGroups.isEmpty,
                message: duplicateGroups.isEmpty
                    ? "No exact duplicate page identities were found."
                    : "\(duplicateGroups.count) exact duplicate page groups need attention."
            ),
            ProjectMemoryCheckDraft(
                checkID: "wiki.semantic_uniqueness",
                label: "No likely duplicate pages",
                severity: .warning,
                passed: likelyDuplicatePairs.isEmpty,
                message: likelyDuplicatePairs.isEmpty
                    ? "No semantically equivalent pages were detected."
                    : "Possible overlap: " + likelyDuplicatePairs.prefix(3).map { "\($0.0.title) ↔ \($0.1.title)" }.joined(separator: "; ")
            ),
            ProjectMemoryCheckDraft(
                checkID: "wiki.link_integrity",
                label: "Connections are valid",
                severity: .blocking,
                passed: invalidLinks.isEmpty,
                message: invalidLinks.isEmpty
                    ? "All \(links.count) page connections point to valid pages."
                    : "\(invalidLinks.count) invalid page connections were found."
            ),
            ProjectMemoryCheckDraft(
                checkID: "wiki.connectedness",
                label: "Pages form a useful graph",
                severity: .information,
                passed: isolatedCount == 0,
                message: isolatedCount == 0
                    ? "Every page is connected, or the project memory has only one page."
                    : "\(isolatedCount) pages are not connected yet; future memories may connect them."
            ),
        ]
    }
}
