import Foundation
import GRDB

nonisolated struct MemoryCollection: Codable, Equatable, FetchableRecord, Identifiable, PersistableRecord, Sendable {
    static let databaseTableName = "memoryCollection"

    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
}

nonisolated struct MemoryCollectionMembership: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "memoryCollectionMembership"

    let collectionID: UUID
    let memoryID: UUID
    let addedAt: Date
}

nonisolated struct MemoryCollectionSummary: Equatable, Identifiable, Sendable {
    let collection: MemoryCollection
    let memoryCount: Int

    var id: UUID { collection.id }
}

nonisolated struct MemoryTagSummary: Equatable, Identifiable, Sendable {
    let name: String
    let memoryCount: Int

    var id: String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() }
}

nonisolated enum MemoryOrganizationError: LocalizedError {
    case blankCollectionName
    case duplicateCollectionName
    case missingCollection
    case blankTag
    case duplicateTag

    var errorDescription: String? {
        switch self {
        case .blankCollectionName:
            "Enter a name for the collection."
        case .duplicateCollectionName:
            "A collection with that name already exists."
        case .missingCollection:
            "That collection no longer exists."
        case .blankTag:
            "Enter a tag name."
        case .duplicateTag:
            "That tag already exists."
        }
    }
}
