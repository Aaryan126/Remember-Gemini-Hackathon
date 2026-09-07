import Foundation
import NaturalLanguage
import Testing
@testable import Remember

struct ProjectClusteringTests {
    @Test func groundedTermsRejectSharedStyleAndUnrelatedHandsOnTasks() {
        let bread = ProjectTopicEvidence("Feed the sourdough starter, mix bread dough and bake the loaf.")
        #expect(bread.supports(ProjectTopicEvidence("Sourdough bread needs an active starter before you bake the dough.")))
        #expect(!bread.supports(ProjectTopicEvidence("Water tomato seedlings and plant them in a sunny garden.")))
        #expect(!ProjectTopicEvidence("Sewing cotton fabric using a paper pattern and machine stitching.")
            .supports(ProjectTopicEvidence("Repair a bicycle tire by patching the punctured inner tube.")))
        #expect(!ProjectTopicEvidence("Practice notes for today's class. Follow the guide and use the new plan.")
            .supports(ProjectTopicEvidence("Use today's class notes to practice the new plan and follow the guide.")))
        #expect(ProjectTopicEvidence("Math").supports(ProjectTopicEvidence(" math ")))
        #expect(!ProjectTopicEvidence("...").supports(ProjectTopicEvidence("...")))
    }

    @Test func sentenceChunksKeepTheWholeDocumentAndRespectBounds() {
        let text = "First sentence. " + String(repeating: "A long paragraph with Unicode café 🌿 words ", count: 60)
            + String(repeating: "植物", count: 300) + " Final evidence."
        let chunks = AppleProjectEmbedding.chunks(text, language: .english)
        #expect(chunks.count > 3)
        #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 256 })
        #expect(chunks.joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
        #expect(AppleProjectEmbedding.chunks(" \n\t", language: .english).isEmpty)
    }

    @Test func cosineAndPolicyRejectInvalidEvidence() {
        #expect(ProjectMath.cosine([1, 0], [1, 0]) == 1)
        #expect(ProjectMath.cosine([.infinity, 0], [1, 0]) == -1)
        #expect(!ProjectMath.coherent([[0, 0]]))
        #expect(!ProjectMath.coherent([[1, 0], [1]]))
        #expect(!ProjectMath.supports([1, 0], members: []))
        #expect(ProjectMath.isCurrentPolicy(ProjectMath.policy + "+foundation-models"))
        #expect(!ProjectMath.isCurrentPolicy("centroid-v1-080-margin008-merge092"))
        #expect(!ProjectMath.isCurrentPolicy(ProjectMath.policy + "-other"))
        // An excellent centroid cannot disguise a contradictory individual member.
        let members: [[Float]] = [[0.8, 0.6], [0.8, -0.6]]
        #expect(ProjectMath.cosine([1, 0], ProjectMath.centroid(members)!) == 1)
        #expect(!ProjectMath.coherent(members))
    }

    @Test func weakSingleCandidateDoesNotAbsorbUnrelatedCapture() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
        let a = item("a", offset: 0), b = item("b", offset: 1)
        let provider = MappedEmbeddings(values: ["a": [1, 0], "b": vector(degrees: 50)])
        let graph = ProjectGraphService(store: store, embeddings: provider, reasoner: NoDecision())
        for memory in [a, b] {
            try await index(memory, store: store)
            try await graph.synchronize()
        }
        let snapshot = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(snapshot.activeClusters.count == 2)
    }

    @Test func incoherentExistingClusterCannotAttractNewSourceOrMerge() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
        let a = item("Calculus derivatives alpha", offset: 0)
        let b = item("Calculus derivatives beta", offset: 1)
        let c = item("Calculus derivatives gamma", offset: 2)
        try await seed(a, vector: [0.8, 0.6], store: store)
        try await seed(b, vector: [0.8, -0.6], store: store)
        var grouping = ProvenancePayload()
        grouping.assignments = [b.id.uuidString: [a.id]]
        try await store.appendProvenance(ProvenanceEvent(kind: .placement, payload: grouping),
            expectedSequence: await store.provenanceEvents().last?.sequence)
        try await index(c, store: store)
        let graph = ProjectGraphService(store: store, embeddings: MappedEmbeddings(values: [c.displayTitle: [1, 0]]), reasoner: NoDecision())
        try await graph.synchronize()
        let snapshot = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(snapshot.memberships[c.id] == [c.id])
        #expect(snapshot.events.allSatisfy { $0.kind != .merge })
    }

    @Test func mergingRequiresEveryCrossClusterPairNotOnlyCentroids() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
        let items = (0..<4).map { item("Calculus derivatives \($0)", offset: $0) }
        // Each cluster is coherent and centroids have cosine 0.978, but the
        // endpoints across clusters have cosine 0.857 and must prevent merging.
        for (memory, angle) in zip(items, [0.0, 19, 12, 31]) {
            try await seed(memory, vector: vector(degrees: angle), store: store)
        }
        var grouping = ProvenancePayload()
        grouping.assignments = [items[1].id.uuidString: [items[0].id], items[3].id.uuidString: [items[2].id]]
        try await store.appendProvenance(ProvenanceEvent(kind: .placement, payload: grouping),
            expectedSequence: await store.provenanceEvents().last?.sequence)
        try await ProjectGraphService(store: store, embeddings: MappedEmbeddings(values: [:]), reasoner: NoDecision()).synchronize()
        let snapshot = try ProvenanceSnapshot.replay(await store.provenanceEvents())
        #expect(snapshot.activeClusters.count == 2)
        #expect(snapshot.events.allSatisfy { $0.kind != .merge })
    }

    @Test func policyUpgradeRefreshesEvidenceButPreservesPinsAndOriginalHistory() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
        let a = item("a", offset: 0), b = item("b", offset: 1)
        for memory in [a, b] { try await seed(memory, vector: [1, 0], policy: "centroid-v1-080-margin008-merge092", store: store) }
        try await store.assignProjectMemory(id: b.id, clusters: [a.id])
        let before = try await store.provenanceEvents()
        let graph = ProjectGraphService(store: store, embeddings: MappedEmbeddings(values: ["a": [1, 0], "b": [0, 1]]), reasoner: NoDecision())
        try await graph.synchronize()
        let after = try await store.provenanceEvents()
        #expect(Array(after.prefix(before.count)).map(\.payloadJSON) == before.map(\.payloadJSON))
        let snapshot = try ProvenanceSnapshot.replay(after)
        #expect(snapshot.memberships[b.id] == [a.id])
        #expect(snapshot.pinned.contains(b.id))
        let vectors = try ProjectGraphService.vectors(after, snapshot: snapshot)
        #expect(vectors[a.id]?.vector == [1, 0])
        #expect(vectors[b.id]?.vector == [0, 1])
        try await graph.synchronize()
        #expect(try await store.provenanceEvents().count == after.count)
    }

    @Test func latestUnavailablePlacementInvalidatesEarlierVector() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
        let memory = item("a", offset: 0)
        try await seed(memory, vector: [1, 0], store: store)
        let events = try await store.provenanceEvents()
        let previous = try #require(events.last)
        var payload = try previous.payload()
        payload.vector = nil
        try await store.appendProvenance(ProvenanceEvent(kind: .placement, memoryID: memory.id, payload: payload),
            expectedSequence: events.last?.sequence)
        let final = try await store.provenanceEvents()
        #expect(try ProjectGraphService.vectors(final, snapshot: ProvenanceSnapshot.replay(final)).isEmpty)
    }

    @Test func highContextualScoreCannotOverrideContradictorySentenceEvidence() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
        let a = item("Calculus derivatives alpha", offset: 0), b = item("Calculus derivatives beta", offset: 1)
        let provider = MappedEmbeddings(values: [a.displayTitle: [1, 0], b.displayTitle: [1, 0]],
            semantics: [a.displayTitle: [1, 0], b.displayTitle: [0, 1]])
        let graph = ProjectGraphService(store: store, embeddings: provider, reasoner: NoDecision())
        for memory in [a, b] {
            try await index(memory, store: store)
            try await graph.synchronize()
        }
        let events = try await store.provenanceEvents()
        let snapshot = try ProvenanceSnapshot.replay(events)
        #expect(snapshot.activeClusters.count == 2)
        #expect(try ProjectGraphService.vectors(events, snapshot: snapshot).values.allSatisfy { $0.semanticVector != nil })
    }

    @Test func legacyMixedClusterGetsReviewableSplitWithoutRewritingMemberships() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
        let items = (0..<4).map { item("item-\($0)", offset: $0) }
        for memory in items {
            try await seed(memory, vector: [1, 0], policy: "centroid-v1-080-margin008-merge092", store: store)
        }
        var grouping = ProvenancePayload()
        grouping.clusterID = items[0].id
        grouping.title = "Old mixed topic"
        grouping.assignments = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, [items[0].id]) })
        try await store.appendProvenance(ProvenanceEvent(kind: .placement, payload: grouping),
            expectedSequence: await store.provenanceEvents().last?.sequence)
        let graph = ProjectGraphService(store: store, embeddings: MappedEmbeddings(values: [
            "item-0": [1, 0], "item-1": [1, 0], "item-2": [0, 1], "item-3": [0, 1]
        ]), reasoner: NoDecision())
        try await graph.synchronize()
        let events = try await store.provenanceEvents()
        let snapshot = try ProvenanceSnapshot.replay(events)
        #expect(snapshot.members(of: items[0].id).count == 4)
        #expect(events.filter { $0.kind == .splitProposal }.count == 1)
        #expect(events.allSatisfy { $0.kind != .split })
    }

    @Test func oldPolicyVectorsAreNotCandidatesDuringPartialUpgrade() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
        try await seed(item("a", offset: 0), vector: [1, 0], policy: "centroid-v1-080-margin008-merge092", store: store)
        let events = try await store.provenanceEvents()
        #expect(try ProjectGraphService.vectors(events, snapshot: ProvenanceSnapshot.replay(events)).isEmpty)
    }

    private func temporaryRoot() throws -> URL {
        let root = URL.temporaryDirectory.appendingPathComponent("ProjectClusteringTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func item(_ title: String, offset: Int) -> MemoryItem {
        let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(offset))
        return MemoryItem(id: UUID(), kind: .text, createdAt: date, importedAt: date, updatedAt: date,
            state: .captured, originalFilename: UUID().uuidString + ".txt", userCaption: title, title: title,
            summary: nil, extractedText: nil, tagsJSON: "[]", processingError: nil, modelVersion: nil)
    }

    private func index(_ memory: MemoryItem, store: MemoryStore) async throws {
        try await store.insertIfNeeded(memory)
        try await store.markIndexed(id: memory.id, analysis: MemoryAnalysisResult(title: memory.displayTitle,
            summary: "", tags: [], extractedText: memory.displayTitle, modelVersion: "fixture"))
    }

    private func seed(_ memory: MemoryItem, vector: [Float], policy: String = ProjectMath.policy, store: MemoryStore) async throws {
        try await index(memory, store: store)
        let events = try await store.provenanceEvents()
        var payload = ProvenancePayload()
        payload.model = policy
        payload.sourceRevisionID = events.last?.id
        payload.sourceFilename = memory.originalFilename
        payload.vector = vector
        payload.embeddingSpace = "fixture-v2"
        payload.assignments = [memory.id.uuidString: [memory.id]]
        try await store.appendProvenance(ProvenanceEvent(kind: .placement, memoryID: memory.id, payload: payload),
            expectedSequence: events.last?.sequence)
    }

    private func vector(degrees: Double) -> [Float] {
        let radians = degrees * .pi / 180
        return [Float(cos(radians)), Float(sin(radians))]
    }
}

private struct MappedEmbeddings: ProjectEmbeddingProviding {
    let values: [String: [Float]]
    var semantics: [String: [Float]] = [:]
    func embedding(for text: String) async throws -> ProjectEmbedding? {
        values[text].map { ProjectEmbedding(vector: $0, space: "fixture-v2", semanticVector: semantics[text]) }
    }
}

private struct NoDecision: ProjectReasoning {
    func decide(source: String, candidates: [(id: UUID, title: String, summary: String)]) async throws -> ProjectReasoningResult? { nil }
}
