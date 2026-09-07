import Foundation
import FoundationModels
import Observation
import GRDB

@MainActor @Observable
final class ProjectViewModel {
    private(set) var snapshot = ProvenanceSnapshot()
    private(set) var isLoading = true
    private(set) var isOrganizing = false
    var errorMessage: String?
    private var store: MemoryStore?
    private var graph: ProjectGraphService?
    private var running = false
    private var graphTask: Task<Void, Never>?
    private var needsOrganization = false
    private var retryUnavailable = false

    func observe() async {
        guard !running else { return }
        running = true
        defer {
            running = false
            isLoading = false
            graphTask?.cancel()
            graphTask = nil
        }
        do {
            let store = try liveStore()
            let graph = ProjectGraphService(store: store)
            self.graph = graph
            for try await events in await store.observeProvenance() {
                try Task.checkCancellation()
                snapshot = try ProvenanceSnapshot.replay(events)
                isLoading = false
                scheduleOrganization()
            }
        } catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }

    func refreshOrganization(retryUnavailable: Bool = false) async {
        self.retryUnavailable = self.retryUnavailable || retryUnavailable
        scheduleOrganization()
    }

    private func scheduleOrganization() {
        needsOrganization = true
        guard graphTask == nil, let graph else { return }
        graphTask = Task {
            isOrganizing = true
            defer { graphTask = nil; isOrganizing = false }
            while needsOrganization, !Task.isCancelled {
                needsOrganization = false
                let retry = retryUnavailable
                retryUnavailable = false
                do { try await graph.synchronize(retryUnavailable: retry) }
                catch ProvenanceError.staleDecision { needsOrganization = true }
                catch is CancellationError { return }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    func historical(at date: Date?) -> ProvenanceSnapshot {
        guard let date else { return snapshot }
        do { return try ProvenanceSnapshot.replay(snapshot.events, through: date) }
        catch { return ProvenanceSnapshot() }
    }

    func archive(_ id: UUID, archived: Bool) async {
        do { try await liveStore().setArchived(id: id, archived: archived) }
        catch { errorMessage = error.localizedDescription }
    }

    func rename(_ id: UUID, title: String) async {
        await perform { store in try await store.renameProjectCluster(id: id, title: title) }
    }

    func assign(_ memoryID: UUID, clusters: Set<UUID>) async {
        await perform { store in try await store.assignProjectMemory(id: memoryID, clusters: clusters) }
    }

    func undo(_ event: ProvenanceEvent) async {
        await perform { store in try await store.undoProjectEvent(id: event.id) }
    }

    func resolve(_ event: ProvenanceEvent, accept: Bool) async {
        await perform { store in try await store.resolveProjectSplit(id: event.id, accept: accept) }
    }

    func recap(_ clusterID: UUID) async {
        await perform { store in try await store.recordProjectRecap(clusterID: clusterID) }
    }

    func restoreRevision(_ event: ProvenanceEvent) async {
        await perform { store in try await store.restoreProjectRevision(id: event.id) }
    }

    private func perform(_ action: (MemoryStore) async throws -> Void) async {
        do { try await action(liveStore()) }
        catch { errorMessage = error.localizedDescription }
    }

    private func liveStore() throws -> MemoryStore {
        if let store { return store }
        let created = try MemoryStore.live()
        store = created
        return created
    }
}

extension MemoryStore {
    func restoreProjectRevision(id: UUID) async throws {
        let files = try LibraryFileStore(directoryURL: LibraryFileStore.defaultDirectory())
        try await databasePool.write { db in
            guard let event = try ProvenanceEvent.filter(Column("id") == id).fetchOne(db),
                  [.capture, .revision, .imported].contains(event.kind),
                  let source = try event.payload().memory, source.kind == .text,
                  var current = try MemoryItem.fetchOne(db, key: source.id), !current.isArchived,
                  FileManager.default.fileExists(atPath: files.url(for: source.originalFilename).path) else { throw ProvenanceError.invalidCorrection }
            guard current.originalFilename != source.originalFilename else { return }
            current.originalFilename = source.originalFilename
            current.userCaption = source.userCaption
            current.title = source.title
            current.summary = source.summary
            current.extractedText = source.extractedText
            current.tagsJSON = source.tagsJSON
            current.state = .captured
            current.updatedAt = Date()
            try current.update(db)
            var payload = ProvenancePayload()
            payload.memory = current
            payload.referencedEventID = event.id
            payload.rationale = "You restored an earlier note revision; later history remains available."
            try ProvenanceEvent(kind: .revision, memoryID: current.id, origin: "user", payload: payload).insert(db)
        }
    }

    func renameProjectCluster(id: UUID, title: String) async throws {
        let clean = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let events = try await provenanceEvents()
        let snapshot = try ProvenanceSnapshot.replay(events)
        guard !clean.isEmpty, let cluster = snapshot.clusters[id], !cluster.retired else { throw ProvenanceError.invalidCorrection }
        var payload = ProvenancePayload()
        payload.clusterID = id
        payload.title = clean
        payload.previousTitle = cluster.title
        payload.rationale = "You renamed this topic."
        try await appendProvenance(ProvenanceEvent(kind: .rename, origin: "user", payload: payload), expectedSequence: events.last?.sequence)
    }

    func assignProjectMemory(id: UUID, clusters: Set<UUID>) async throws {
        let events = try await provenanceEvents()
        let snapshot = try ProvenanceSnapshot.replay(events)
        guard let memory = snapshot.memories[id], !memory.isArchived,
              clusters.allSatisfy({ snapshot.clusters[$0]?.retired == false }) else { throw ProvenanceError.invalidCorrection }
        var payload = ProvenancePayload()
        // Removing every membership creates a fresh branch, so no capture becomes invisible.
        let selected: Set<UUID>
        if clusters.isEmpty {
            let newID = UUID()
            selected = [newID]
            payload.clusterID = newID
            payload.title = memory.displayTitle
        } else { selected = clusters }
        payload.assignments = [id.uuidString: Array(selected)]
        payload.previousAssignments = [id.uuidString: Array(snapshot.memberships[id, default: []])]
        payload.rationale = "You chose these topics. Automatic organization will preserve this assignment."
        try await appendProvenance(ProvenanceEvent(kind: .placement, memoryID: id, origin: "user", payload: payload), expectedSequence: events.last?.sequence)
    }

    func undoProjectEvent(id: UUID) async throws {
        let events = try await provenanceEvents()
        let snapshot = try ProvenanceSnapshot.replay(events)
        guard let event = events.first(where: { $0.id == id }), !snapshot.resolved.contains(id),
              [.merge, .placement, .split, .rename].contains(event.kind) else { throw ProvenanceError.invalidCorrection }
        let original = try event.payload()
        if event.kind == .rename {
            guard let clusterID = original.clusterID, let oldTitle = original.previousTitle,
                  snapshot.clusters[clusterID]?.title == original.title else { throw ProvenanceError.staleDecision }
            var payload = ProvenancePayload()
            payload.clusterID = clusterID
            payload.title = oldTitle
            payload.previousTitle = original.title
            payload.referencedEventID = event.id
            payload.rationale = "You restored the previous topic name."
            try await appendProvenance(ProvenanceEvent(kind: .rename, origin: "user", payload: payload), expectedSequence: events.last?.sequence)
            return
        }
        guard !original.previousAssignments.isEmpty else { throw ProvenanceError.invalidCorrection }
        if event.kind != .merge {
            guard original.previousAssignments.values.flatMap({ $0 }).allSatisfy({ snapshot.clusters[$0]?.retired == false }) else {
                throw ProvenanceError.staleDecision
            }
        }
        for (key, ids) in original.assignments {
            guard let memoryID = UUID(uuidString: key), snapshot.memberships[memoryID] == Set(ids) else {
                throw ProvenanceError.staleDecision
            }
        }
        var payload = ProvenancePayload()
        payload.assignments = original.previousAssignments
        payload.previousAssignments = original.assignments
        payload.parents = event.kind == .merge ? original.parents : []
        payload.referencedEventID = event.id
        payload.rationale = "You reversed this change. Later unrelated changes are preserved."
        try await appendProvenance(ProvenanceEvent(kind: .revert, origin: "user", payload: payload), expectedSequence: events.last?.sequence)
    }

    func resolveProjectSplit(id: UUID, accept: Bool) async throws {
        let events = try await provenanceEvents()
        let snapshot = try ProvenanceSnapshot.replay(events)
        guard let event = events.first(where: { $0.id == id && $0.kind == .splitProposal }),
              !snapshot.resolved.contains(id) else { throw ProvenanceError.invalidCorrection }
        var payload = try event.payload()
        payload.referencedEventID = id
        if accept {
            for (key, ids) in payload.previousAssignments {
                guard let memoryID = UUID(uuidString: key), snapshot.memberships[memoryID] == Set(ids),
                      snapshot.memories[memoryID]?.isArchived == false else { throw ProvenanceError.staleDecision }
            }
            guard let newID = payload.parents.first, let parent = payload.clusterID else { throw ProvenanceError.invalidCorrection }
            payload.clusterID = newID
            payload.parents = [parent]
        }
        try await appendProvenance(ProvenanceEvent(kind: accept ? .split : .dismiss, origin: "user", payload: payload), expectedSequence: events.last?.sequence)
    }

    func recordProjectRecap(clusterID: UUID) async throws {
        let events = try await provenanceEvents()
        let snapshot = try ProvenanceSnapshot.replay(events)
        guard let cluster = snapshot.clusters[clusterID] else { return }
        let now = Date()
        if try events.contains(where: { event in
            guard event.kind == .recap, now.timeIntervalSince(event.timestamp) < 7 * 86_400 else { return false }
            return try event.payload().clusterID == clusterID
        }) { return }
        let members = Set(snapshot.members(of: clusterID).map(\.id))
        let recent = events.filter {
            now.timeIntervalSince($0.timestamp) < 7 * 86_400 && $0.memoryID.map(members.contains) == true
                && [.capture, .revision, .restore].contains($0.kind)
        }
        var payload = ProvenancePayload()
        payload.clusterID = clusterID
        payload.title = "This week in \(cluster.title)"
        payload.citedEventIDs = recent.map(\.id)
        payload.rationale = "\(recent.filter { $0.kind == .capture }.count) captures, \(recent.filter { $0.kind == .revision }.count) revisions, and \(recent.filter { $0.kind == .restore }.count) restores this week. \(members.count) active memories."
        // The factual recap is always available; generated narration is separately grounded in these event IDs.
        if !recent.isEmpty, SystemLanguageModel.default.availability == .available {
            let evidence = recent.prefix(20).map { "\($0.id.uuidString): \($0.kind.label)" }.joined(separator: "\n")
            do {
                let response = try await LanguageModelSession(instructions: "Summarize only this activity log in one sentence; do not infer source content.")
                    .respond(to: evidence)
                payload.rationale += "\n\n" + String(response.content.prefix(800))
                payload.model = "apple-foundation-recap-v1"
            } catch is CancellationError { throw CancellationError() }
            catch { /* Factual event counts remain a complete usable recap. */ }
        }
        try await appendProvenance(ProvenanceEvent(kind: .recap, payload: payload), expectedSequence: events.last?.sequence)
    }
}
