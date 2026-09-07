import Foundation

nonisolated enum LocalAIUnavailableReason: String, Equatable, Sendable {
    case missingConfiguration
    case networkUnavailable
    case serviceUnavailable

    var title: String {
        switch self {
        case .missingConfiguration: "OpenAI is not configured"
        case .networkUnavailable: "OpenAI is offline"
        case .serviceUnavailable: "OpenAI is temporarily unavailable"
        }
    }

    var detail: String {
        switch self {
        case .missingConfiguration:
            "Start the OpenAI proxy and configure its API key to enable generated summaries and answers."
        case .networkUnavailable:
            "Remember cannot reach the configured OpenAI proxy. Local capture and lexical search still work."
        case .serviceUnavailable:
            "The OpenAI request could not be completed. Your saved memories remain available locally."
        }
    }
}

nonisolated enum LocalAIAvailability: Equatable, Sendable {
    case available
    case unavailable(LocalAIUnavailableReason)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

nonisolated struct LocalAIModelDescriptor: Equatable, Sendable {
    let provider: String
    let modelVersion: String
    let promptVersion: String
}

nonisolated enum LocalAIGenerationError: LocalizedError, Sendable {
    case unavailable(LocalAIUnavailableReason)
    case contextWindowExceeded
    case decoding
    case busy
    case refusal
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason.detail
        case .contextWindowExceeded: "The selected evidence was too long for the configured OpenAI model."
        case .decoding: "OpenAI did not return a usable structured response."
        case .busy: "OpenAI is busy. Please try again in a moment."
        case .refusal: "The configured OpenAI model declined this request."
        case .failed: "The OpenAI request could not be completed."
        }
    }
}

nonisolated protocol LocalAIAvailabilityProviding: Sendable {
    var descriptor: LocalAIModelDescriptor { get }
    func availability() -> LocalAIAvailability
}

nonisolated protocol RememberAssisting: Sendable {
    var descriptor: LocalAIModelDescriptor { get }
    func availability() -> LocalAIAvailability
    func semanticSearch(_ request: MemorySearchRequest) async throws -> [MemorySearchResult]
    func answer(question: String, history: [RememberConversationTurn]) async throws -> RememberAssistantResponse
}

nonisolated enum RememberAnswerMode: String, Equatable, Sendable {
    case grounded
    case partial
    case sourcesOnly
    case noEvidence
}

nonisolated struct GroundedCitation: Equatable, Identifiable, Sendable {
    let id: String
    let statement: String
    let memoryID: UUID
    let chunkID: UUID
    let locator: String
    let excerpt: String
}

nonisolated enum GroundedEvidenceVerifier {
    static func quoteAppears(_ quote: String, in source: String) -> Bool {
        let excerpt = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        return excerpt.count >= 4 && source.contains(excerpt)
    }
}

nonisolated struct OpenAIAvailability: LocalAIAvailabilityProviding {
    let descriptor = LocalAIModelDescriptor(
        provider: "OpenAI",
        modelVersion: OpenAIConfiguration.model,
        promptVersion: "remember-openai-v1"
    )

    func availability() -> LocalAIAvailability {
        OpenAIConfiguration.baseURL == nil
            ? .unavailable(.missingConfiguration)
            : .available
    }
}

nonisolated enum DeterministicMemoryAnalyzer {
    static let modelVersion = "deterministic-basic-mode-v1"

    static func result(
        memory: MemoryItem,
        extracted: ExtractedMemoryContent
    ) -> MemoryAnalysisResult {
        let caption = normalized(memory.userCaption, maximumLength: 1_000)
        let visualNames = extracted.visualLabels.map(\.displayName)
        let firstLine = extracted.text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        let title = normalized(caption, maximumLength: 120)
            ?? visualNames.first.map { String($0.capitalized.prefix(120)) }
            ?? firstLine.map { String($0.prefix(120)) }
            ?? fallbackTitle(for: memory.kind)
        let summary = caption
            ?? (!visualNames.isEmpty
                ? "Apple Vision found possible image labels: \(visualNames.joined(separator: ", "))."
                : nil)
            ?? normalized(extracted.text, maximumLength: 1_000)
            ?? "Saved locally in Remember."
        return MemoryAnalysisResult(
            title: title,
            summary: summary,
            tags: visualNames.map { $0.lowercased() },
            extractedText: extracted.text,
            modelVersion: modelVersion,
            chunks: extracted.chunks,
            isPartial: extracted.isPartial
        )
    }

    private static func fallbackTitle(for kind: MemoryKind) -> String {
        switch kind {
        case .audio: "Voice memory"
        case .image: "Saved image"
        case .video: "Saved video"
        case .link: "Saved link"
        case .pdf: "Saved PDF"
        case .text: "Saved note"
        }
    }

    private static func normalized(_ value: String?, maximumLength: Int) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }
}
