import Foundation
import GRDB

nonisolated enum LocalAIActivityKind: String, Codable, DatabaseValueConvertible, Sendable {
    case analysis
    case search
    case chat
    case transcription
    case wikiCompilation
    case projectOrganization

    var label: String {
        switch self {
        case .analysis: "Memory analysis"
        case .search: "Semantic search"
        case .chat: "Ask Remember"
        case .transcription: "Voice transcription"
        case .wikiCompilation: "Legacy Project processing"
        case .projectOrganization: "Topic organization"
        }
    }

    var systemImage: String {
        switch self {
        case .analysis: "sparkles.rectangle.stack"
        case .search: "magnifyingglass"
        case .chat: "bubble.left.and.bubble.right"
        case .transcription: "waveform"
        case .wikiCompilation: "books.vertical.fill"
        case .projectOrganization: "point.3.connected.trianglepath.dotted"
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
    static let outboundRequestsImplemented = true

    static let summary = "Capture and topic organization use on-device processing by default. Optional cloud assistance, Ask, and AI search send relevant content through the configured OpenAI proxy. Apple may download embedding assets without sending your captures."

    static let limitation = "This screen describes Remember's implemented data flow and activity records; it is not a device-wide network monitor. The proxy keeps the API key out of the iOS app, but submitted excerpts still leave the device."
}
