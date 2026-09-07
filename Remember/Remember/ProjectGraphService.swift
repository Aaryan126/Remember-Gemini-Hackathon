import Foundation

actor ProjectGraphService {
    private let store: MemoryStore
    private let embeddings: any ProjectEmbeddingProviding
    private let reasoner: any ProjectReasoning
    private var evidenceCache: [UUID: (text: String, evidence: ProjectTopicEvidence)] = [:]

    init(store: MemoryStore, embeddings: any ProjectEmbeddingProviding = AppleProjectEmbedding(),
         reasoner: any ProjectReasoning = ProjectReasoner()) {
        self.store = store
        self.embeddings = embeddings
        self.reasoner = reasoner
    }

    func synchronize(retryUnavailable: Bool = false) async throws {
        let events = try await store.provenanceEvents()
        let snapshot = try ProvenanceSnapshot.replay(events)
        evidenceCache = evidenceCache.filter { snapshot.memories[$0.key]?.isArchived == false }
        for memory in snapshot.memories.values.sorted(by: {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        })
            where !memory.isArchived && memory.state == .indexed {
            try Task.checkCancellation()
            let source = events.last { $0.memoryID == memory.id && [.enrichment, .revision, .imported].contains($0.kind) }
            guard let source else { continue }
            let placement = try events.last { $0.memoryID == memory.id && $0.kind == .placement }?.payload()
            let expectedSpace = await embeddings.expectedSpace(for: memory.extractedText ?? memory.displayTitle)
            let currentPolicy = placement.map { ProjectMath.isCurrentPolicy($0.model) } ?? false
            if currentPolicy, placement?.sourceRevisionID == source.id,
               let vector = placement?.vector, ProjectMath.normalized(vector) != nil,
               expectedSpace == nil || placement?.embeddingSpace == expectedSpace { continue }
            // Retry unavailable embeddings on a later foreground pass, not on every observation emission.
            if currentPolicy, !retryUnavailable, placement?.sourceRevisionID == source.id,
               let last = events.last(where: { $0.memoryID == memory.id && $0.kind == .placement }),
               Date().timeIntervalSince(last.timestamp) < 60 { continue }
            try await place(memory: memory, source: source)
        }
        try await batchIfDue()
    }

    private func place(memory: MemoryItem, source: ProvenanceEvent) async throws {
        let events = try await store.provenanceEvents()
        let snapshot = try ProvenanceSnapshot.replay(events)
        guard snapshot.memories[memory.id]?.originalFilename == memory.originalFilename,
              snapshot.memories[memory.id]?.isArchived == false,
              events.last(where: { $0.memoryID == memory.id && [.enrichment, .revision, .imported].contains($0.kind) })?.id == source.id else { return }
        let text = memory.extractedText ?? memory.userCaption ?? memory.displayTitle
        let embedding: ProjectEmbedding?
        do { embedding = try await embeddings.embedding(for: text) }
        catch is CancellationError { throw CancellationError() }
        catch { embedding = nil }
        var payload = ProvenancePayload()
        payload.sourceRevisionID = source.id
        payload.sourceFilename = memory.originalFilename
        payload.vector = embedding?.vector
        payload.semanticVector = embedding?.semanticVector
        payload.embeddingSpace = embedding?.space
        payload.model = ProjectMath.policy
        payload.rationale = embedding == nil
            ? "Kept as a separate thread while local embeddings are unavailable or the source has no supported text."
            : "No sufficiently strong match. Kept as a separate thread."
        let oldIDs = snapshot.memberships[memory.id, default: [memory.id]].sorted { $0.uuidString < $1.uuidString }
        var selected = oldIDs
        let vectors = try Self.vectors(events, snapshot: snapshot)
        let evidence = topicEvidence(for: memory)
        let groundedClusters = Set(snapshot.activeClusters.filter { cluster in
            snapshot.members(of: cluster.id).allSatisfy {
                evidence.supports(topicEvidence(for: $0))
            }
        }.map(\.id))
        if let embedding, !snapshot.preservesOrganization(for: memory.id) {
            let candidates = snapshot.activeClusters.compactMap { cluster -> (UUID, Double, Double)? in
                guard !oldIDs.contains(cluster.id) else { return nil }
                let members = snapshot.members(of: cluster.id)
                let compatible = members.compactMap { vectors[$0.id] }.filter { $0.space == embedding.space }
                guard compatible.count == members.count,
                      ProjectMath.coherent(compatible),
                      ProjectMath.supports(embedding, members: compatible),
                      let centroid = ProjectMath.centroid(compatible.map(\.vector)) else { return nil }
                return (cluster.id, ProjectMath.cosine(embedding.vector, centroid),
                        ProjectMath.semanticScore(embedding, members: compatible))
            }.sorted { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1 }
            payload.scores = Dictionary(uniqueKeysWithValues: candidates.prefix(2).map { ($0.0.uuidString, $0.1) })
            let grounded = candidates.filter { groundedClusters.contains($0.0) }
            if ProjectMath.clearWinner(grounded.map(\.1)), let winner = grounded.first,
               winner.2 >= ProjectMath.semanticThreshold {
                selected = [winner.0]
                payload.rationale = "Both similarity signals and specific shared source terms support every member, with a clear lead among grounded candidates."
                payload.scores["sentenceSimilarity"] = winner.2
            } else if let first = candidates.first, first.1 >= ProjectMath.reasoningThreshold {
                let options = candidates.prefix(2).filter { $0.1 >= ProjectMath.reasoningThreshold }.compactMap { candidate -> (id: UUID, title: String, summary: String)? in
                    guard let cluster = snapshot.clusters[candidate.0] else { return nil }
                    return (cluster.id, cluster.title, Self.summary(snapshot.members(of: cluster.id)))
                }
                let activityID = try await store.startActivity(kind: .projectOrganization, memoryID: memory.id,
                    sourceCount: options.count + 1, modelVersion: ProjectPreferences.cloudEnabled ? "openai-topic-reasoning" : "apple-topic-reasoning")
                do {
                    if let decision = try await reasoner.decide(source: text, candidates: options) {
                        let ids = decision.candidateIDs.compactMap(UUID.init(uuidString:))
                        let allowed = Set(options.map(\.id))
                        if !ids.isEmpty, ids.count == decision.candidateIDs.count,
                           ids.allSatisfy(allowed.contains), !decision.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            selected = Array(Set(ids)).sorted { $0.uuidString < $1.uuidString }
                            payload.rationale = String(decision.rationale.prefix(800))
                            payload.model += ProjectPreferences.cloudEnabled ? "+openai" : "+foundation-models"
                        }
                    }
                    try await store.finishActivity(id: activityID, status: .completed, sourceCount: options.count + 1)
                } catch is CancellationError {
                    try? await store.finishActivity(id: activityID, status: .interrupted, failureCategory: "cancelled")
                    throw CancellationError()
                } catch {
                    try? await store.finishActivity(id: activityID, status: .failed, failureCategory: "reasoning_unavailable")
                    payload.rationale = "Reasoning was unavailable; retained the existing thread for review."
                }
            }
        } else if snapshot.preservesOrganization(for: memory.id) {
            payload.rationale = "Preserved your explicit topic assignment."
        }
        payload.assignments = [memory.id.uuidString: selected]
        payload.previousAssignments = [memory.id.uuidString: oldIDs]
        let explicitlyNamed = try events.contains {
            guard $0.kind == .rename else { return false }
            return try $0.payload().clusterID == memory.id
        }
        if selected == [memory.id], snapshot.members(of: memory.id).count <= 1, !explicitlyNamed {
            payload.clusterID = memory.id
            payload.title = String(memory.displayTitle.prefix(80))
        }
        try await store.appendProvenance(
            ProvenanceEvent(kind: .placement, memoryID: memory.id, payload: payload),
            expectedSequence: events.last?.sequence)
    }

    nonisolated static func vectors(_ events: [ProvenanceEvent], snapshot: ProvenanceSnapshot) throws -> [UUID: ProjectEmbedding] {
        var result: [UUID: ProjectEmbedding] = [:]
        let sources = Dictionary(grouping: events.filter { [.enrichment, .revision, .imported].contains($0.kind) && $0.memoryID != nil }, by: { $0.memoryID! })
        // A later unavailable/invalid vector must invalidate earlier cached evidence.
        let latest = Dictionary(grouping: events.filter { $0.kind == .placement && $0.memoryID != nil }, by: { $0.memoryID! })
        for event in latest.values.compactMap(\.last) {
            let payload = try event.payload()
            guard let id = event.memoryID, snapshot.memories[id]?.originalFilename == payload.sourceFilename,
                  payload.sourceRevisionID == sources[id]?.last?.id,
                  ProjectMath.isCurrentPolicy(payload.model),
                  let vector = payload.vector, ProjectMath.normalized(vector) != nil,
                  let space = payload.embeddingSpace else { continue }
            if space.hasPrefix("apple-dual:"),
               payload.semanticVector.flatMap(ProjectMath.normalized) == nil { continue }
            result[id] = ProjectEmbedding(vector: vector, space: space, semanticVector: payload.semanticVector)
        }
        return result
    }

    private func batchIfDue() async throws {
        let events = try await store.provenanceEvents()
        let placements = events.filter { $0.kind == .placement }
        let checkpoint = events.last { $0.kind == .checkpoint }
        let since = placements.filter { ($0.sequence ?? 0) > (checkpoint?.sequence ?? 0) }.count
        let early = events.first.map { Date().timeIntervalSince($0.timestamp) < 7 * 86_400 } ?? true
        let daily = checkpoint.map { Date().timeIntervalSince($0.timestamp) >= 86_400 } ?? false
        guard since >= (early ? 3 : 20) || daily else { return }
        let snapshot = try ProvenanceSnapshot.replay(events)
        let vectors = try Self.vectors(events, snapshot: snapshot)
        let clusters = snapshot.activeClusters
        let evidence = snapshot.memories.mapValues { topicEvidence(for: $0) }
        for (index, first) in clusters.enumerated() {
            let leftMembers = snapshot.members(of: first.id)
            let left = leftMembers.compactMap { vectors[$0.id] }
            guard left.count == leftMembers.count, let space = left.first?.space,
                  left.allSatisfy({ $0.space == space }), let a = ProjectMath.centroid(left.map(\.vector)) else { continue }
            for second in clusters.dropFirst(index + 1) {
                guard !snapshot.blockedPairs.contains(ProvenanceSnapshot.pair(first.id, second.id)) else { continue }
                let rightMembers = snapshot.members(of: second.id)
                let allMembers = leftMembers + rightMembers
                guard allMembers.allSatisfy({ !snapshot.preservesOrganization(for: $0.id) }) else { continue }
                let right = rightMembers.compactMap { vectors[$0.id] }
                guard right.count == rightMembers.count, right.allSatisfy({ $0.space == space }),
                      ProjectMath.coherent(left), ProjectMath.coherent(right),
                      leftMembers.allSatisfy({ first in
                          rightMembers.allSatisfy { second in
                              guard let a = evidence[first.id], let b = evidence[second.id] else { return false }
                              return a.supports(b)
                          }
                      }),
                      let b = ProjectMath.centroid(right.map(\.vector)), ProjectMath.cosine(a, b) >= ProjectMath.mergeThreshold,
                      left.allSatisfy({ ProjectMath.supports($0, members: right, threshold: ProjectMath.crossMemberThreshold) }),
                      ProjectMath.semanticScore(ProjectEmbedding(vector: a, space: space,
                          semanticVector: ProjectMath.centroid(left.compactMap(\.semanticVector))), members: right) >= ProjectMath.semanticThreshold else { continue }
                let id = UUID()
                var payload = ProvenancePayload()
                payload.clusterID = id
                let commonTags = Set(leftMembers.flatMap(\.tags)).intersection(rightMembers.flatMap(\.tags))
                payload.title = commonTags.sorted().first?.capitalized ?? (first.title == second.title ? first.title : "\(first.title) & \(second.title)")
                payload.parents = [first.id, second.id]
                payload.model = ProjectMath.policy
                payload.rationale = "Both similarity signals and specific shared source terms support every cross-thread source pair."
                payload.scores = ["centroidSimilarity": ProjectMath.cosine(a, b)]
                payload.citedEventIDs = allMembers.compactMap { member in
                    events.last { $0.memoryID == member.id && $0.kind == .placement }?.id
                }
                for memory in allMembers {
                    let old = snapshot.memberships[memory.id, default: []]
                    payload.previousAssignments[memory.id.uuidString] = Array(old)
                    payload.assignments[memory.id.uuidString] = Array(old.subtracting([first.id, second.id]).union([id]))
                }
                try await store.appendProvenance(ProvenanceEvent(kind: .merge, payload: payload), expectedSequence: events.last?.sequence)
                return // Next observation resumes with fresh centroids; no stale batch mutations.
            }
            if leftMembers.count >= 4, let seed = left.min(by: {
                ProjectMath.cosine($0.vector, a) < ProjectMath.cosine($1.vector, a)
            }), !ProjectMath.coherent(left) {
                var subset: [MemoryItem] = []
                for memory in leftMembers.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                    guard let vector = vectors[memory.id],
                          ProjectMath.supports(vector, members: [seed]) else { continue }
                    let accepted = subset.compactMap { vectors[$0.id] }
                    if accepted.isEmpty || ProjectMath.supports(vector, members: accepted) {
                        subset.append(memory)
                    }
                }
                let alreadySuggested = try events.contains { event in
                    guard [.splitProposal, .split, .dismiss].contains(event.kind) else { return false }
                    return try event.payload().clusterID == first.id
                }
                if subset.count >= 2, subset.count <= leftMembers.count - 2, !alreadySuggested {
                    var payload = ProvenancePayload()
                    payload.clusterID = first.id
                    payload.title = "Separate \(subset.first?.displayTitle ?? "thread")"
                    let newID = UUID()
                    payload.parents = [newID]
                    payload.rationale = "This group is internally similar but differs from the wider topic. Review before splitting."
                    payload.citedEventIDs = subset.compactMap { member in
                        events.last { $0.memoryID == member.id && $0.kind == .placement }?.id
                    }
                    for memory in subset {
                        let old = snapshot.memberships[memory.id, default: []]
                        payload.previousAssignments[memory.id.uuidString] = Array(old)
                        payload.assignments[memory.id.uuidString] = Array(old.subtracting([first.id]).union([newID]))
                    }
                    try await store.appendProvenance(ProvenanceEvent(kind: .splitProposal, payload: payload), expectedSequence: events.last?.sequence)
                    return
                }
            }
        }
        if ProjectPreferences.cloudEnabled {
            for cluster in clusters where snapshot.members(of: cluster.id).count >= 4 {
                let hasProposal = try events.contains { event in
                    guard [.splitProposal, .dismiss].contains(event.kind) else { return false }
                    return try event.payload().clusterID == cluster.id
                }
                guard !hasProposal else { continue }
                let members = Array(snapshot.members(of: cluster.id).prefix(24))
                let candidates = members.map { (id: $0.id, title: $0.displayTitle, summary: String(($0.extractedText ?? "").prefix(400))) }
                let activity = try await store.startActivity(kind: .projectOrganization, sourceCount: members.count, modelVersion: "openai-history-review")
                do {
                    let suggestion = try await reasoner.suggestSplit(candidates: candidates)
                    try await store.finishActivity(id: activity, status: .completed, sourceCount: members.count)
                    guard let suggestion, !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !suggestion.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let ids = Set(suggestion.candidateIDs.compactMap(UUID.init(uuidString:)))
                    guard ids.count == suggestion.candidateIDs.count, ids.count >= 2, ids.count <= members.count - 2,
                          ids.isSubset(of: Set(members.map(\.id))) else { continue }
                    var payload = ProvenancePayload()
                    let newID = UUID()
                    payload.clusterID = cluster.id; payload.parents = [newID]
                    payload.title = String(suggestion.title.prefix(80))
                    payload.rationale = String(suggestion.rationale.prefix(800))
                    payload.model = "openai-history-review"
                    payload.citedEventIDs = members.compactMap { member in
                        events.last { $0.memoryID == member.id && [.enrichment, .revision].contains($0.kind) }?.id
                    }
                    for id in ids {
                        let old = snapshot.memberships[id, default: []]
                        payload.previousAssignments[id.uuidString] = Array(old)
                        payload.assignments[id.uuidString] = Array(old.subtracting([cluster.id]).union([newID]))
                    }
                    try await store.appendProvenance(ProvenanceEvent(kind: .splitProposal, payload: payload), expectedSequence: events.last?.sequence)
                    return
                } catch is CancellationError {
                    try? await store.finishActivity(id: activity, status: .interrupted, failureCategory: "cancelled")
                    throw CancellationError()
                } catch ProvenanceError.staleDecision { throw ProvenanceError.staleDecision }
                catch { try? await store.finishActivity(id: activity, status: .failed, failureCategory: "history_review_unavailable") }
            }
        }
        var payload = ProvenancePayload()
        payload.model = ProjectMath.policy
        payload.rationale = "Completed local cluster review."
        try await store.appendProvenance(ProvenanceEvent(kind: .checkpoint, payload: payload), expectedSequence: events.last?.sequence)
    }

    private func topicEvidence(for memory: MemoryItem) -> ProjectTopicEvidence {
        let text = memory.extractedText ?? memory.userCaption ?? memory.displayTitle
        if let cached = evidenceCache[memory.id], cached.text == text { return cached.evidence }
        let evidence = ProjectTopicEvidence(text)
        evidenceCache[memory.id] = (text, evidence)
        return evidence
    }

    nonisolated private static func summary(_ memories: [MemoryItem]) -> String {
        memories.prefix(ProjectPreferences.cloudEnabled ? 12 : 3).map {
            "\($0.displayTitle): \(String(($0.extractedText ?? $0.displaySummary ?? "").prefix(250)))"
        }.joined(separator: "\n")
    }
}
