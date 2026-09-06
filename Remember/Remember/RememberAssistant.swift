import Foundation

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
    let citations: [GroundedCitation]
    let mode: RememberAnswerMode

    init(
        answer: String,
        sources: [MemorySearchResult],
        modelVersion: String,
        citations: [GroundedCitation] = [],
        mode: RememberAnswerMode = .grounded
    ) {
        self.answer = answer
        self.sources = sources
        self.modelVersion = modelVersion
        self.citations = citations
        self.mode = mode
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
