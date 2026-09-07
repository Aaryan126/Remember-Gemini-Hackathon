import Foundation
import GRDB
import Testing
@testable import Remember

struct ProvenanceTests {
    @Test func archivingThreadPreservesMemoriesSharedMembershipsAndHistory() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let first = memory("Thread one"), second = memory("Thread two")
        try await store.insertIfNeeded(first)
        try await store.insertIfNeeded(second)
        try await store.assignProjectMemory(id: first.id, clusters: [first.id, second.id])
        let before = try await store.provenanceEvents()
        try await store.setProjectThreadArchived(id: first.id, archived: true)
        try await store.setProjectThreadArchived(id: first.id, archived: true)
        let archived = try await store.provenanceEvents()
        #expect(archived.count == before.count + 1)
        let state = try ProvenanceSnapshot.replay(archived)
        #expect(state.activeClusters.map(\.id) == [second.id])
        #expect(state.archivedClusters.map(\.id) == [first.id])
        #expect(state.memories[first.id]?.isArchived == false)
        #expect(state.members(of: second.id).count == 2)
        #expect(state.memberships[first.id] == [first.id, second.id])
        #expect(state.preservesOrganization(for: first.id))
        #expect(try await store.fetchAll().count == 2)
        #expect(try ProvenanceSnapshot.replay(before).activeClusters.count == 2)
        try await store.setProjectThreadArchived(id: first.id, archived: false)
        try await store.setProjectThreadArchived(id: first.id, archived: false)
        let restored = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(restored.activeClusters.count == 2)
        #expect(restored.archivedClusters.isEmpty)
        #expect(restored.memories[first.id]?.originalFilename == first.originalFilename)
        #expect(restored.events.count == archived.count + 1)
    }

    @Test func archivedThreadDoesNotReappearDuringAutomaticOrganization() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let item = memory("Calculus derivatives")
        try await store.insertIfNeeded(item)
        try await store.markIndexed(id: item.id, analysis: MemoryAnalysisResult(title: item.displayTitle,
            summary: "Calculus", tags: [], extractedText: "Calculus derivatives", modelVersion: "fixture"))
        try await store.setProjectThreadArchived(id: item.id, archived: true)
        let graph = ProjectGraphService(store: store, embeddings: FixtureEmbedding(vector: [1, 0]), reasoner: NoReasoning())
        try await graph.synchronize()
        let state = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(state.activeClusters.isEmpty)
        #expect(state.archivedClusters.map(\.id) == [item.id])
        #expect(!state.pinned.contains(item.id))
        try await store.setProjectThreadArchived(id: item.id, archived: false)
        let restored = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(restored.activeClusters.count == 1)
        #expect(!restored.preservesOrganization(for: item.id))
        await #expect(throws: ProvenanceError.self) { try await store.setProjectThreadArchived(id: UUID(), archived: true) }
    }

    @Test func liveConsumersShareTheObservableStore() throws {
        #expect(try MemoryStore.live() === MemoryStore.live())
    }

    @Test func upgradeBackfillsLegacyMemoriesExactlyOnce() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("db.sqlite")
        let item = memory("Existing memory")
        do {
            let seed = try MemoryStore(databaseURL: url)
            try await seed.insertIfNeeded(item)
            let pool = await seed.databasePool
            // Recreate the pre-feature schema in this disposable test database only.
            try await pool.write { db in
                try db.execute(sql: "DROP TABLE provenanceEvent")
                try db.execute(sql: "ALTER TABLE memory DROP COLUMN isArchived")
                try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'createImmutableProvenanceV1'")
            }
        }
        let migrated = try MemoryStore(databaseURL: url)
        let events = try await migrated.provenanceEvents()
        #expect(events.count == 1)
        #expect(events.first?.kind == .imported)
        #expect(try events.first?.payload().memory?.createdAt == item.createdAt)
        let reopened = try MemoryStore(databaseURL: url)
        #expect(try await reopened.provenanceEvents().count == 1)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProvenanceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func memory(_ title: String = "Math", id: UUID = UUID()) -> MemoryItem {
        MemoryItem(id: id, kind: .text, createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            importedAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            state: .captured, originalFilename: "\(id).txt", userCaption: title, title: title,
            summary: nil, extractedText: nil, tagsJSON: "[]", processingError: nil, modelVersion: nil)
    }

    @Test func captureIsIdempotentAndVisibleBeforeEnrichment() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let item = memory()
        try await store.insertIfNeeded(item)
        try await store.insertIfNeeded(item)
        let events = try await store.provenanceEvents()
        #expect(events.count == 1)
        let state = try ProvenanceSnapshot.replay(events)
        #expect(state.activeClusters.count == 1)
        #expect(state.members(of: item.id).map(\.id) == [item.id])
        #expect(state.memories[item.id]?.state == .captured)
    }

    @Test func archiveRetainsOriginalAndExcludesRetrievalUntilRestore() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let item = memory("Calculus")
        let files = try LibraryFileStore(directoryURL: root.appendingPathComponent("Originals"))
        try files.replaceText("Calculus", filename: item.originalFilename)
        try await store.insertIfNeeded(item)
        try await store.markIndexed(id: item.id, analysis: MemoryAnalysisResult(title: "Calculus", summary: "Derivatives", tags: [], extractedText: "Calculus derivatives", modelVersion: "fixture"))
        try await store.delete(id: item.id)
        try await store.delete(id: item.id)
        #expect(try await store.fetchAll().isEmpty)
        #expect(try await store.fetchIndexed().isEmpty)
        #expect(try await MemorySearchService(memoryStore: store).search(MemorySearchRequest(query: "Calculus")).isEmpty)
        #expect(FileManager.default.fileExists(atPath: files.url(for: item.originalFilename).path))
        #expect(try await store.provenanceEvents().filter { $0.kind == .archive }.count == 1)
        try await store.setArchived(id: item.id, archived: false)
        #expect(try await store.fetchIndexed().count == 1)
    }

    @Test func noteRevisionAndHistoricalReplayPreservePriorPayload() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let item = memory("Before")
        try await store.insertIfNeeded(item)
        let initial = try await store.provenanceEvents()
        try await store.updateNoteContent(id: item.id, document: NoteDocument(text: "After\nNew evidence"), filename: "new-revision.txt")
        let events = try await store.provenanceEvents()
        let before = try ProvenanceSnapshot.replay(events, through: initial[0].timestamp)
        let after = try ProvenanceSnapshot.replay(events)
        #expect(before.memories[item.id]?.displayTitle == "Before")
        #expect(before.memories[item.id]?.originalFilename == item.originalFilename)
        #expect(after.memories[item.id]?.originalFilename == "new-revision.txt")
        #expect(after.memories[item.id]?.extractedText == "After\nNew evidence")
        #expect(try events.last?.payload().sourceRevisionID == initial[0].id)
    }

    @Test func databaseRejectsHistoryMutationAndReopeningDoesNotDuplicateEvents() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("db.sqlite")
        let store = try MemoryStore(databaseURL: url)
        try await store.insertIfNeeded(memory())
        let pool = await store.databasePool
        await #expect(throws: (any Error).self) {
            try await pool.write { try $0.execute(sql: "DELETE FROM provenanceEvent") }
        }
        await #expect(throws: (any Error).self) {
            try await pool.write { try $0.execute(sql: "UPDATE provenanceEvent SET origin = 'rewritten'") }
        }
        let reopened = try MemoryStore(databaseURL: url)
        #expect(try await reopened.provenanceEvents().count == 1)
    }

    @Test func staleEnrichmentCannotOverwriteEditedOrArchivedMemory() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let item = memory()
        try await store.insertIfNeeded(item)
        _ = try await store.claimNextCaptured()
        try await store.updateNoteContent(id: item.id, document: NoteDocument(text: "Correction"), filename: "new.txt")
        let analysis = MemoryAnalysisResult(title: "Stale", summary: "Stale", tags: [], extractedText: "Stale", modelVersion: "fixture")
        try await store.markIndexed(id: item.id, analysis: analysis, expectedFilename: item.originalFilename)
        #expect(try await store.fetch(id: item.id)?.displayTitle == "Correction")
        try await store.setArchived(id: item.id, archived: true)
        try await store.markIndexed(id: item.id, analysis: analysis)
        #expect(try await store.fetch(id: item.id)?.displayTitle == "Correction")
    }

    @Test func mergeUndoPreservesUnrelatedChangesAndPreventsRemerge() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let a = memory("Math 1"), b = memory("Math 2"), c = memory("Work")
        for item in [a, b, c] { try await store.insertIfNeeded(item) }
        let events = try await store.provenanceEvents()
        let merged = UUID()
        var payload = ProvenancePayload()
        payload.clusterID = merged; payload.title = "Math"; payload.parents = [a.id, b.id]
        payload.assignments = [a.id.uuidString: [merged], b.id.uuidString: [merged]]
        payload.previousAssignments = [a.id.uuidString: [a.id], b.id.uuidString: [b.id]]
        let event = try ProvenanceEvent(kind: .merge, payload: payload)
        try await store.appendProvenance(event, expectedSequence: events.last?.sequence)
        try await store.renameProjectCluster(id: c.id, title: "Office")
        try await store.undoProjectEvent(id: event.id)
        let state = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(state.memberships[a.id] == [a.id])
        #expect(state.memberships[b.id] == [b.id])
        #expect(state.clusters[c.id]?.title == "Office")
        #expect(state.blockedPairs.contains(ProvenanceSnapshot.pair(a.id, b.id)))
        #expect(state.resolved.contains(event.id))
        await #expect(throws: (any Error).self) { try await store.undoProjectEvent(id: event.id) }
    }

    @Test func graphUsesLocalVectorsAndPreservesExplicitPlacement() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let a = memory("Calculus derivatives notes"), b = memory("Calculus derivatives practice")
        for item in [a, b] {
            try await store.insertIfNeeded(item)
            try await store.markIndexed(id: item.id, analysis: MemoryAnalysisResult(title: item.displayTitle,
                summary: "Math", tags: ["math"], extractedText: item.displayTitle, modelVersion: "fixture"))
        }
        let engine = ProjectGraphService(store: store, embeddings: FixtureEmbedding(vector: [1, 0]), reasoner: NoReasoning())
        try await engine.synchronize()
        let organized = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(organized.activeClusters.count == 1)
        try await store.assignProjectMemory(id: b.id, clusters: [])
        let corrected = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        try await engine.synchronize()
        let final = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(final.memberships[b.id] == corrected.memberships[b.id])
        #expect(final.pinned.contains(b.id))
    }

    @Test func unavailableEmbeddingsLeaveSingletonAndDoNotRepeatedlyAppend() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let item = memory()
        try await store.insertIfNeeded(item)
        try await store.markIndexed(id: item.id, analysis: MemoryAnalysisResult(title: "Math", summary: "", tags: [], extractedText: "Math", modelVersion: "fixture"))
        let engine = ProjectGraphService(store: store, embeddings: FixtureEmbedding(vector: nil), reasoner: NoReasoning())
        try await engine.synchronize()
        let count = try await store.provenanceEvents().count
        try await engine.synchronize()
        #expect(try await store.provenanceEvents().count == count)
        #expect(try ProvenanceSnapshot.replay(await store.provenanceEvents()).activeClusters.count == 1)
    }

    @Test func localCaptureDoesNotCallCloudAnalyzer() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try LibraryFileStore(directoryURL: root)
        let item = memory("A private note")
        try files.replaceText("A private note", filename: item.originalFilename)
        let spy = CloudAnalysisSpy()
        let analyzer = LocalCaptureAnalyzer(cloudEnabled: { false }, usesFoundationModels: false, cloudAnalyzer: spy)
        let result = try await analyzer.analyze(memory: item, originalURL: files.url(for: item.originalFilename), supportingText: nil)
        #expect(result.extractedText == "A private note")
        #expect(await spy.calls == 0)
    }

    @Test func failedModelLoadKeepsNamedSingletonAndCancellationAppendsNothing() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let item = memory("Calculus notes")
        try await store.insertIfNeeded(item)
        try await store.markIndexed(id: item.id, analysis: MemoryAnalysisResult(title: item.displayTitle,
            summary: "", tags: [], extractedText: item.displayTitle, modelVersion: "fixture"))
        let cancelled = ProjectGraphService(store: store, embeddings: FailedEmbedding(cancelled: true), reasoner: NoReasoning())
        await #expect(throws: CancellationError.self) { try await cancelled.synchronize() }
        #expect(try await store.provenanceEvents().count == 2)
        let failed = ProjectGraphService(store: store, embeddings: FailedEmbedding(cancelled: false), reasoner: NoReasoning())
        try await failed.synchronize()
        let state = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(state.activeClusters.first?.title == item.displayTitle)
        #expect(try state.events.last?.payload().vector == nil)
    }

    @Test func staleSequenceRejectsDecisionWithoutChangingHistory() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let item = memory()
        try await store.insertIfNeeded(item)
        let sequence = try await store.provenanceEvents().last?.sequence
        try await store.renameProjectCluster(id: item.id, title: "User correction")
        var payload = ProvenancePayload()
        payload.clusterID = item.id; payload.title = "Outdated model name"
        let event = try ProvenanceEvent(kind: .rename, payload: payload)
        await #expect(throws: (any Error).self) { try await store.appendProvenance(event, expectedSequence: sequence) }
        #expect(try ProvenanceSnapshot.replay(await store.provenanceEvents()).clusters[item.id]?.title == "User correction")
    }

    @Test func similarityPolicyRejectsTiesInvalidAndIncompatibleVectors() {
        #expect(ProjectMath.clearWinner([0.97, 0.90]))
        #expect(!ProjectMath.clearWinner([0.97, 0.965]))
        #expect(!ProjectMath.clearWinner([0.69]))
        #expect(!ProjectMath.clearWinner([.nan]))
        #expect(!ProjectMath.clearWinner([0.9, .nan]))
        #expect(ProjectMath.normalized([0, 0]) == nil)
        #expect(ProjectMath.normalized([.nan, 1]) == nil)
        #expect(ProjectMath.cosine([1, 0], [1]) == -1)
        #expect(ProjectMath.cosine([1, 0], [0, 1]) == 0)
    }

    @Test func batchAutomaticallyMergesStrongSingletonsAndRecordsLineage() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let items = [memory("Calculus derivatives 1"), memory("Calculus derivatives 2"), memory("Calculus derivatives 3")]
        for item in items { try await seedVector(item, vector: [1, 0], store: store) }
        let engine = ProjectGraphService(store: store, embeddings: FixtureEmbedding(vector: [1, 0]), reasoner: NoReasoning())
        try await engine.synchronize()
        let events = try await store.provenanceEvents()
        let merge = try #require(events.first { $0.kind == .merge })
        let payload = try merge.payload()
        #expect(payload.parents.count == 2)
        #expect(payload.previousAssignments.count == 2)
        #expect(payload.scores["centroidSimilarity"] == 1)
        let state = try ProvenanceSnapshot.replay(events)
        #expect(state.activeClusters.count == 2)
    }

    @Test func broadClusterSplitWaitsForAcceptanceAndCanBeUndone() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let items = [memory("Math 1"), memory("Math 2"), memory("Travel 1"), memory("Travel 2")]
        for (index, item) in items.enumerated() { try await seedVector(item, vector: index < 2 ? [1, 0] : [0, 1], store: store) }
        let clusterID = UUID()
        var grouping = ProvenancePayload()
        grouping.clusterID = clusterID; grouping.title = "Broad topic"
        grouping.assignments = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, [clusterID]) })
        try await store.appendProvenance(ProvenanceEvent(kind: .placement, payload: grouping), expectedSequence: await store.provenanceEvents().last?.sequence)
        let engine = ProjectGraphService(store: store, embeddings: FixtureEmbedding(vector: [1, 0]), reasoner: NoReasoning())
        try await engine.synchronize()
        let proposed = try await store.provenanceEvents()
        let proposal = try #require(proposed.first { $0.kind == .splitProposal })
        #expect(try ProvenanceSnapshot.replay(proposed).members(of: clusterID).count == 4)
        try await store.resolveProjectSplit(id: proposal.id, accept: true)
        let accepted = try await store.provenanceEvents()
        #expect(try ProvenanceSnapshot.replay(accepted).members(of: clusterID).count == 2)
        let split = try #require(accepted.last { $0.kind == .split })
        try await store.undoProjectEvent(id: split.id)
        #expect(try ProvenanceSnapshot.replay(await store.provenanceEvents()).members(of: clusterID).count == 4)
    }

    private func seedVector(_ item: MemoryItem, vector: [Float], store: MemoryStore) async throws {
        try await store.insertIfNeeded(item)
        try await store.markIndexed(id: item.id, analysis: MemoryAnalysisResult(title: item.displayTitle, summary: "", tags: [], extractedText: item.displayTitle, modelVersion: "fixture"))
        let events = try await store.provenanceEvents()
        var payload = ProvenancePayload()
        payload.sourceRevisionID = events.last?.id
        payload.sourceFilename = item.originalFilename
        payload.vector = vector; payload.embeddingSpace = "fixture-v1"
        payload.model = ProjectMath.policy
        payload.assignments = [item.id.uuidString: [item.id]]
        try await store.appendProvenance(ProvenanceEvent(kind: .placement, memoryID: item.id, payload: payload), expectedSequence: events.last?.sequence)
    }
}

private struct FixtureEmbedding: ProjectEmbeddingProviding {
    let vector: [Float]?
    func embedding(for text: String) async throws -> ProjectEmbedding? {
        vector.map { ProjectEmbedding(vector: $0, space: "fixture-v1") }
    }
}
private struct FailedEmbedding: ProjectEmbeddingProviding {
    let cancelled: Bool
    func embedding(for text: String) async throws -> ProjectEmbedding? {
        if cancelled { throw CancellationError() }
        throw CocoaError(.fileReadNoPermission)
    }
}
private struct NoReasoning: ProjectReasoning {
    func decide(source: String, candidates: [(id: UUID, title: String, summary: String)]) async throws -> ProjectReasoningResult? { nil }
}
private actor CloudAnalysisSpy: MemoryAnalyzing {
    var calls = 0
    func analyze(memory: MemoryItem, originalURL: URL, supportingText: String?) async throws -> MemoryAnalysisResult {
        calls += 1
        return MemoryAnalysisResult(title: "Cloud", summary: "", tags: [], extractedText: "", modelVersion: "spy")
    }
}
