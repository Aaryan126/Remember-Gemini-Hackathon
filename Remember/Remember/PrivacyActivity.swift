import Foundation
import GRDB

nonisolated enum LocalAIActivityKind: String, Codable, DatabaseValueConvertible, Sendable {
    case analysis
    case search
    case chat
    case transcription
    case wikiCompilation

    var label: String {
        switch self {
        case .analysis: "Memory analysis"
        case .search: "Semantic search"
        case .chat: "Ask Remember"
        case .transcription: "Voice transcription"
        case .wikiCompilation: "Project Memory compilation"
        }
    }

    var systemImage: String {
        switch self {
        case .analysis: "sparkles.rectangle.stack"
        case .search: "magnifyingglass"
        case .chat: "bubble.left.and.bubble.right"
        case .transcription: "waveform"
        case .wikiCompilation: "books.vertical.fill"
        }
    }
}

nonisolated enum LocalAIActivityStatus: String, Codable, DatabaseValueConvertible, Sendable {
    case running
    case completed
    case failed
    case interrupted

    var label: String {
        switch self {
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .interrupted: "Interrupted"
        }
    }
}

nonisolated struct LocalAIActivity: Codable, Equatable, FetchableRecord, Identifiable, PersistableRecord, Sendable {
    static let databaseTableName = "localAIActivity"

    let id: UUID
    let kind: LocalAIActivityKind
    let startedAt: Date
    var finishedAt: Date?
    var status: LocalAIActivityStatus
    let memoryID: UUID?
    var sourceCount: Int
    let modelVersion: String
    var failureCategory: String?
}

nonisolated enum RememberNetworkPolicy {
    static let outboundRequestsImplemented = false

    static let summary = "Remember has no application networking path. Captures, voice transcription, OCR, search, Project Memory compilation, and Gemma inference use local files and on-device frameworks."

    static let limitation = "iOS does not provide an app with a complete live packet log for itself. This screen reports Remember's implemented behavior and local AI audit records, not device-wide network traffic."
}
