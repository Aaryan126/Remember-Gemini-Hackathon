import Foundation
import Testing
@testable import Remember

struct RecordedProjectEmbeddingTests {
    @Test func realDeviceVectorsStayTopicPureAcrossArrivalOrders() async throws {
        let url = try #require(Bundle(for: EmbeddingFixtureBundle.self)
            .url(forResource: "project-embedding-device-v5", withExtension: "json"))
        let fixture = try JSONDecoder().decode(EmbeddingFixture.self, from: Data(contentsOf: url))
        #expect(fixture.schemaVersion == 1)
        let samples = fixture.samples
        #expect(samples.count == 42)
        #expect(samples.filter { !$0.vector.isEmpty }.count == 41)
        #expect(samples.allSatisfy {
            $0.vector.isEmpty || ($0.vector.count == 512 && $0.semanticVector.count == 512
                && ProjectMath.normalized($0.vector) != nil && ProjectMath.normalized($0.semanticVector) != nil)
        })
        let interleaved = (0..<3).flatMap { offset in stride(from: offset, to: samples.count, by: 3) }
        let orders = [
            Array(0..<12), [0, 3, 6, 9, 1, 4, 7, 10, 2, 5, 8, 11],
            Array(12..<30), Array((12..<30).reversed()), Array(samples.indices),
            interleaved, Array(interleaved.reversed()), Array(30..<42), Array((30..<42).reversed())
        ]
        for (orderIndex, order) in orders.enumerated() {
            let root = URL.temporaryDirectory.appendingPathComponent("RecordedEmbeddingTests-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
            let graph = ProjectGraphService(store: store, embeddings: RecordedEmbeddingProvider(samples: samples),
                reasoner: RecordedNoReasoning())
            var byID: [UUID: EmbeddingFixture.Sample] = [:]
            for (offset, index) in order.enumerated() {
                let sample = samples[index]
                let id = try #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)))
                let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(offset))
                let memory = MemoryItem(id: id, kind: .text, createdAt: date, importedAt: date, updatedAt: date,
                    state: .captured, originalFilename: id.uuidString + ".txt", userCaption: sample.id,
                    title: sample.id, summary: nil, extractedText: nil, tagsJSON: "[]", processingError: nil, modelVersion: nil)
                byID[id] = sample
                try await store.insertIfNeeded(memory)
                try await store.markIndexed(id: id, analysis: MemoryAnalysisResult(title: sample.id,
                    summary: sample.text, tags: [], extractedText: sample.text, modelVersion: "recorded-device-fixture"))
                try await graph.synchronize()
            }
            let events = try await store.provenanceEvents()
            let snapshot = try ProvenanceSnapshot.replay(events)
            for cluster in snapshot.activeClusters {
                let members = snapshot.members(of: cluster.id)
                let topics = Set(members.compactMap { byID[$0.id]?.topic })
                #expect(topics.count == 1, "Mixed topics in order \(orderIndex): \(members.map(\.displayTitle))")
            }
            // Precision cannot pass merely by keeping every capture separate.
            #expect(snapshot.activeClusters.count <= Int(ceil(Double(order.count) * 0.75)))
            for (id, sample) in byID where sample.vector.isEmpty {
                #expect(snapshot.memberships[id] == [id])
                #expect(snapshot.members(of: id).count == 1)
            }
            try await graph.synchronize()
            #expect(try await store.provenanceEvents().count == events.count)
        }
    }
}

private final class EmbeddingFixtureBundle: NSObject {}

private struct EmbeddingFixture: Decodable {
    let schemaVersion: Int
    let samples: [Sample]
    struct Sample: Decodable, Sendable {
        let id: String
        let topic: String
        let text: String
        let space: String
        let vector: [Float]
        let semanticVector: [Float]
    }
}

private struct RecordedEmbeddingProvider: ProjectEmbeddingProviding {
    let samples: [EmbeddingFixture.Sample]
    func embedding(for text: String) async throws -> ProjectEmbedding? {
        guard let sample = samples.first(where: { $0.text == text }), !sample.vector.isEmpty else { return nil }
        return ProjectEmbedding(vector: sample.vector, space: sample.space, semanticVector: sample.semanticVector)
    }
    func expectedSpace(for text: String) async -> String? {
        samples.first(where: { $0.text == text && !$0.vector.isEmpty })?.space
    }
}

private struct RecordedNoReasoning: ProjectReasoning {
    func decide(source: String, candidates: [(id: UUID, title: String, summary: String)]) async throws -> ProjectReasoningResult? { nil }
}
