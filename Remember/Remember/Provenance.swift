import Foundation
import GRDB

nonisolated enum ProvenanceKind: String, Codable, Sendable {
    case capture, imported, revision, metadata, enrichment, archive, restore, processing
    case placement, rename, merge, splitProposal, split, dismiss, revert, recap, checkpoint

    var label: String {
        switch self {
        case .capture: "Captured"
        case .imported: "Imported history"
        case .revision: "Revised"
        case .metadata: "Updated details"
        case .enrichment: "Enriched"
        case .processing: "Processing updated"
        case .archive: "Archived"
        case .restore: "Restored"
        case .placement: "Organized"
        case .rename: "Named"
        case .merge: "Merged"
        case .splitProposal: "Split suggested"
        case .split: "Split accepted"
        case .dismiss: "Suggestion dismissed"
        case .revert: "Correction reversed"
        case .recap: "Weekly recap"
        case .checkpoint: "Organization checked"
        }
    }
}

/// Payloads are versioned facts. Replaying them never invokes an AI model.
nonisolated struct ProvenancePayload: Codable, Sendable {
    var version = 1
    var memory: MemoryItem?
    var clusterID: UUID?
    var title: String?
    var parents: [UUID] = []
    var assignments: [String: [UUID]] = [:]
    var previousAssignments: [String: [UUID]] = [:]
    var previousTitle: String?
    var referencedEventID: UUID?
    var sourceRevisionID: UUID?
    var rationale = ""
    var model = "local"
    var scores: [String: Double] = [:]
    var vector: [Float]?
    var semanticVector: [Float]?
    var embeddingSpace: String?
    var sourceFilename: String?
    var citedEventIDs: [UUID] = []
    var deviceContext: String?
}

nonisolated struct ProvenanceEvent: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "provenanceEvent"
    var sequence: Int64?
    let id: UUID
    let timestamp: Date
    let kind: ProvenanceKind
    let memoryID: UUID?
    let origin: String
    let payloadJSON: String

    init(kind: ProvenanceKind, memoryID: UUID? = nil, origin: String = "system",
         payload: ProvenancePayload, timestamp: Date = Date(), id: UUID = UUID()) throws {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.memoryID = memoryID
        self.origin = origin
        payloadJSON = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
    }

    func payload() throws -> ProvenancePayload {
        let result = try JSONDecoder().decode(ProvenancePayload.self, from: Data(payloadJSON.utf8))
        guard result.version == 1 else { throw ProvenanceError.unsupportedVersion }
        return result
    }

    /// Display originals only at their capture/revision, never again for generated metadata.
    var riverSource: MemoryItem? {
        guard [.capture, .imported, .revision].contains(kind) else { return nil }
        return try? payload().memory
    }

    /// Refresh metadata only for the same original; old revisions must remain historical.
    func riverMemory(in snapshot: ProvenanceSnapshot) -> MemoryItem? {
        guard let original = riverSource else { return nil }
        guard let current = snapshot.memories[original.id],
              current.originalFilename == original.originalFilename else { return original }
        return current
    }
}

nonisolated struct ProvenanceCluster: Identifiable, Sendable {
    let id: UUID
    var title: String
    var parents: [UUID] = []
    var retired = false
}

nonisolated struct ProvenanceSnapshot: Sendable {
    var memories: [UUID: MemoryItem] = [:]
    var clusters: [UUID: ProvenanceCluster] = [:]
    var memberships: [UUID: Set<UUID>] = [:]
    var pinned: Set<UUID> = []
    var blockedPairs: Set<String> = []
    var archivedClusterIDs: Set<UUID> = []
    var resolved: Set<UUID> = []
    var events: [ProvenanceEvent] = []

    static func replay(_ events: [ProvenanceEvent], through date: Date? = nil) throws -> Self {
        var snapshot = Self()
        for event in events where date == nil || event.timestamp <= date! {
            let payload = try event.payload()
            snapshot.events.append(event)
            if let memory = payload.memory {
                snapshot.memories[memory.id] = memory
                if event.kind == .capture || event.kind == .imported {
                    snapshot.clusters[memory.id] = ProvenanceCluster(id: memory.id, title: memory.displayTitle)
                    snapshot.memberships[memory.id] = [memory.id]
                }
            }
            if let referenced = payload.referencedEventID { snapshot.resolved.insert(referenced) }
            if [.placement, .merge, .split, .revert].contains(event.kind) {
                if let id = payload.clusterID, let title = payload.title {
                    snapshot.clusters[id] = ProvenanceCluster(id: id, title: title, parents: payload.parents)
                }
                for (key, ids) in payload.assignments {
                    guard let memoryID = UUID(uuidString: key) else { continue }
                    snapshot.memberships[memoryID] = Set(ids)
                    if event.origin == "user" { snapshot.pinned.insert(memoryID) }
                }
                if event.kind == .merge {
                    for parent in payload.parents { snapshot.clusters[parent]?.retired = true }
                }
                if event.kind == .revert {
                    for parent in payload.parents { snapshot.clusters[parent]?.retired = false }
                    for first in payload.parents {
                        for second in payload.parents where first != second {
                            snapshot.blockedPairs.insert(Self.pair(first, second))
                        }
                    }
                }
            }
            if event.kind == .rename, let id = payload.clusterID, let title = payload.title {
                snapshot.clusters[id]?.title = title
            }
            // Thread archival hides the grouping without archiving its shared memories.
            if event.memoryID == nil, let id = payload.clusterID {
                if event.kind == .archive { snapshot.archivedClusterIDs.insert(id) }
                if event.kind == .restore { snapshot.archivedClusterIDs.remove(id) }
            }
        }
        return snapshot
    }

    var activeClusters: [ProvenanceCluster] {
        clusters.values.filter { !$0.retired && !archivedClusterIDs.contains($0.id) && !members(of: $0.id).isEmpty }
            .sorted { $0.title == $1.title ? $0.id.uuidString < $1.id.uuidString : $0.title < $1.title }
    }

    var archivedClusters: [ProvenanceCluster] {
        clusters.values.filter { archivedClusterIDs.contains($0.id) }
            .sorted { $0.title == $1.title ? $0.id.uuidString < $1.id.uuidString : $0.title < $1.title }
    }

    func preservesOrganization(for memoryID: UUID) -> Bool {
        pinned.contains(memoryID) || !memberships[memoryID, default: []].isDisjoint(with: archivedClusterIDs)
    }

    func members(of clusterID: UUID, includeArchived: Bool = false) -> [MemoryItem] {
        memories.values.filter {
            (includeArchived || !$0.isArchived) && memberships[$0.id, default: []].contains(clusterID)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func ancestors(of id: UUID) -> Set<UUID> {
        var found: Set<UUID> = [id]
        var pending = [id]
        while let next = pending.popLast() {
            for parent in clusters[next]?.parents ?? [] where found.insert(parent).inserted { pending.append(parent) }
        }
        return found
    }

    static func pair(_ first: UUID, _ second: UUID) -> String {
        [first.uuidString, second.uuidString].sorted().joined(separator: ":")
    }
}

nonisolated enum ProvenanceError: LocalizedError {
    case unsupportedVersion, invalidCorrection, staleDecision
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This history was created by a newer version of Remember."
        case .invalidCorrection: "This correction is no longer available. Refresh the project and try again."
        case .staleDecision: "The source or its organization changed. Please try again."
        }
    }
}

extension MemoryStore {
    nonisolated static func registerProvenanceMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("createImmutableProvenanceV1") { db in
            try db.alter(table: "memory") { $0.add(column: "isArchived", .boolean).notNull().defaults(to: false) }
            try db.create(table: "provenanceEvent") { table in
                table.autoIncrementedPrimaryKey("sequence")
                table.column("id", .text).notNull().unique()
                table.column("timestamp", .datetime).notNull().indexed()
                table.column("kind", .text).notNull()
                table.column("memoryID", .text).indexed()
                table.column("origin", .text).notNull()
                table.column("payloadJSON", .text).notNull()
            }
            for memory in try MemoryItem.order(Column("createdAt"), Column("id")).fetchAll(db) {
                try recordMemory(memory, kind: .imported, in: db)
            }
            try db.execute(sql: """
                CREATE TRIGGER provenanceNoUpdate BEFORE UPDATE ON provenanceEvent
                BEGIN SELECT RAISE(ABORT, 'History is append-only'); END;
                CREATE TRIGGER provenanceNoDelete BEFORE DELETE ON provenanceEvent
                BEGIN SELECT RAISE(ABORT, 'History is append-only'); END;
                """)
        }
    }

    nonisolated static func recordMemory(_ memory: MemoryItem, kind: ProvenanceKind, in db: Database) throws {
        var payload = ProvenancePayload()
        payload.memory = memory
        payload.model = memory.modelVersion ?? "local"
        payload.sourceFilename = memory.originalFilename
        if kind == .capture {
            payload.deviceContext = "\(ProcessInfo.processInfo.operatingSystemVersionString); \(TimeZone.current.identifier)"
        }
        payload.sourceRevisionID = try ProvenanceEvent
            .filter(Column("memoryID") == memory.id)
            .filter(["capture", "imported", "revision"].contains(Column("kind")))
            .order(Column("sequence").desc).fetchOne(db)?.id
        payload.rationale = kind == .imported
            ? "Existing memory imported at upgrade. Earlier revisions are unavailable."
            : kind.label
        try ProvenanceEvent(kind: kind, memoryID: memory.id,
            origin: [.revision, .metadata, .archive, .restore].contains(kind) ? "user" : "system",
            payload: payload).insert(db)
    }

    func provenanceEvents() async throws -> [ProvenanceEvent] {
        try await databasePool.read { try ProvenanceEvent.order(Column("sequence")).fetchAll($0) }
    }

    func observeProvenance() -> AsyncThrowingStream<[ProvenanceEvent], Error> {
        let pool = databasePool
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let observation = ValueObservation.tracking { db in
                        try ProvenanceEvent.order(Column("sequence")).fetchAll(db)
                    }
                    for try await events in observation.values(in: pool) { continuation.yield(events) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func setArchived(id: UUID, archived: Bool) async throws {
        try await databasePool.write { db in
            guard var memory = try MemoryItem.fetchOne(db, key: id) else { throw MemoryStoreError.missingMemory(id) }
            guard memory.isArchived != archived else { return }
            memory.isArchived = archived
            memory.updatedAt = Date()
            try memory.update(db)
            try Self.recordMemory(memory, kind: archived ? .archive : .restore, in: db)
        }
    }

    /// Optimistic sequence check prevents asynchronous reasoning from replacing newer corrections.
    func appendProvenance(_ event: ProvenanceEvent, expectedSequence: Int64?) async throws {
        try await databasePool.write { db in
            let last = try Int64.fetchOne(db, sql: "SELECT MAX(sequence) FROM provenanceEvent")
            guard last == expectedSequence else { throw ProvenanceError.staleDecision }
            try event.insert(db)
        }
    }

    func saveExtraction(id: UUID, filename: String, extracted: ExtractedMemoryContent) async throws {
        try await databasePool.write { db in
            guard var memory = try MemoryItem.fetchOne(db, key: id), !memory.isArchived,
                  memory.originalFilename == filename, memory.state == .processing else { throw ProvenanceError.staleDecision }
            memory.extractedText = extracted.text
            memory.analysisIsPartial = extracted.isPartial
            memory.modelVersion = "apple-extraction-v1"
            try memory.update(db)
            try Self.recordMemory(memory, kind: .enrichment, in: db)
        }
    }
}
