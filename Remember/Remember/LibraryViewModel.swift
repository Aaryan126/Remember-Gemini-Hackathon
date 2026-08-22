import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private static let livingWikiDefaultsKey = "remember.livingWiki.enabled"

    private(set) var items: [MemoryLibraryItem] = []
    private(set) var isSynchronizing = false
    private(set) var isSearching = false
    private(set) var isGemmaSearching = false
    private(set) var isAnswering = false
    private(set) var usedGemmaForCurrentSearch = false
    private(set) var errorMessage: String?
    private(set) var livingWikiEnabled: Bool
    private(set) var isCompilingWiki = false

    var searchQuery = ""
    var selectedKind: MemoryKind?
    var selectedDateRange: MemoryDateRange = .anytime
    var selectedTag: String?
    var chatInput = ""
    var wikiSearchQuery = ""

    private(set) var searchResults: [MemoryLibraryItem] = []
    private(set) var chatMessages: [RememberChatMessage] = []
    private(set) var activities: [LocalAIActivity] = []
    private(set) var collections: [MemoryCollectionSummary] = []
    private(set) var tagSummaries: [MemoryTagSummary] = []
    private(set) var wikiPages: [WikiPage] = []
    private(set) var wikiQueueSummary = WikiQueueSummary(pending: 0, processing: 0, failed: 0)

    private var pipeline: MemoryPipeline?
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let storedValue = userDefaults.object(forKey: Self.livingWikiDefaultsKey) as? Bool {
            livingWikiEnabled = storedValue
        } else {
            livingWikiEnabled = true
        }
    }

    func synchronize() async {
        guard !isSynchronizing else {
            return
        }

        isSynchronizing = true
        errorMessage = nil
        defer { isSynchronizing = false }

        do {
            let pipeline = try livePipeline()
            try await pipeline.bootstrap()
            try await reload(using: pipeline)
            try await reloadActivities(using: pipeline)
            try await reloadOrganization(using: pipeline)

            while let memory = try await pipeline.claimNextCaptured() {
                try await reload(using: pipeline)
                try await pipeline.process(memory)
                try await reload(using: pipeline)
                try await reloadActivities(using: pipeline)
                try await reloadOrganization(using: pipeline)
            }

            if livingWikiEnabled {
                try await pipeline.prepareWikiCompilationQueue()
                try await reloadWiki(using: pipeline)
                if wikiQueueSummary.pending > 0 {
                    isCompilingWiki = true
                    defer { isCompilingWiki = false }
                    try await compileWikiQueue(using: pipeline)
                }
            }
        } catch is CancellationError {
            // The pipeline returns an in-flight record to Captured before propagating cancellation.
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func retry(id: UUID) async {
        await performMutation { pipeline in
            try await pipeline.retry(id: id)
        }
        await synchronize()
    }

    var searchRequest: MemorySearchRequest {
        MemorySearchRequest(
            query: searchQuery,
            kind: selectedKind,
            dateRange: selectedDateRange,
            tag: selectedTag
        )
    }

    var visibleItems: [MemoryLibraryItem] {
        searchRequest.isActive ? searchResults : items
    }

    var availableTags: [String] {
        items
            .flatMap(\.memory.tags)
            .reduce(into: [String]()) { result, tag in
                guard !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
                    return
                }
                result.append(tag)
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func search() async {
        let request = searchRequest
        guard request.isActive else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        isGemmaSearching = false
        usedGemmaForCurrentSearch = false
        do {
            let results = try await livePipeline().search(request)
            try Task.checkCancellation()
            guard request == searchRequest else {
                return
            }
            searchResults = results
            isSearching = false
        } catch is CancellationError {
            if request == searchRequest {
                isSearching = false
            }
        } catch {
            if request == searchRequest {
                isSearching = false
                errorMessage = Self.message(for: error)
            }
        }
    }

    func searchWithGemma() async {
        let request = searchRequest
        guard !request.normalizedQuery.isEmpty else {
            await search()
            return
        }

        isSearching = true
        isGemmaSearching = true
        errorMessage = nil
        do {
            let results = try await livePipeline().semanticSearch(request)
            try Task.checkCancellation()
            guard request == searchRequest else {
                return
            }
            searchResults = results
            usedGemmaForCurrentSearch = true
            isSearching = false
            isGemmaSearching = false
            try await reloadActivities(using: livePipeline())
        } catch is CancellationError {
            if request == searchRequest {
                isSearching = false
                isGemmaSearching = false
            }
        } catch {
            if request == searchRequest {
                isSearching = false
                isGemmaSearching = false
                usedGemmaForCurrentSearch = false
                errorMessage = Self.message(for: error)
            }
        }
    }

    func askRemember() async {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else {
            return
        }

        let history = chatMessages.map {
            RememberConversationTurn(role: $0.role, text: $0.text)
        }
        chatInput = ""
        chatMessages.append(
            RememberChatMessage(role: .user, text: question, sources: [], modelVersion: nil)
        )
        isAnswering = true
        errorMessage = nil

        do {
            let pipeline = try livePipeline()
            let response = try await pipeline.answer(question: question, history: history)
            chatMessages.append(
                RememberChatMessage(
                    role: .assistant,
                    text: response.answer,
                    sources: response.sources,
                    modelVersion: response.modelVersion
                )
            )
            try await reloadActivities(using: pipeline)
        } catch is CancellationError {
            chatInput = question
        } catch {
            chatMessages.append(
                RememberChatMessage(
                    role: .assistant,
                    text: "I couldn't answer from your saved memories. \(Self.message(for: error))",
                    sources: [],
                    modelVersion: nil
                )
            )
            errorMessage = Self.message(for: error)
        }
        isAnswering = false
    }

    func refreshActivities() async {
        do {
            try await reloadActivities(using: livePipeline())
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    var filteredWikiPages: [WikiPage] {
        let query = wikiSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return wikiPages }
        return wikiPages.filter { LivingWikiCandidateIndex.matches(query: query, page: $0) }
    }

    func setLivingWikiEnabled(_ enabled: Bool) {
        guard livingWikiEnabled != enabled else { return }
        livingWikiEnabled = enabled
        userDefaults.set(enabled, forKey: Self.livingWikiDefaultsKey)
        if enabled {
            Task { await synchronize() }
        }
    }

    func compileNextWikiMemory(retryFailures: Bool = false) async {
        guard livingWikiEnabled, !isCompilingWiki else { return }
        isCompilingWiki = true
        errorMessage = nil
        defer { isCompilingWiki = false }

        do {
            let pipeline = try livePipeline()
            try await pipeline.prepareWikiCompilationQueue()
            if retryFailures {
                try await pipeline.retryFailedWikiCompilations()
            }
            try await compileWikiQueue(using: pipeline)
        } catch is CancellationError {
            // The pipeline returns an interrupted compilation to the local queue.
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func wikiPageSnapshot(id: UUID) async -> WikiPageSnapshot? {
        do {
            return try await livePipeline().wikiPageSnapshot(id: id)
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    func projectMemoryHistory() async -> [ProjectMemoryRunSnapshot] {
        do {
            return try await livePipeline().projectMemoryHistory()
        } catch {
            errorMessage = Self.message(for: error)
            return []
        }
    }

    func projectMemoryExportDocument() async -> ProjectMemoryExportDocument? {
        do {
            return try await livePipeline().projectMemoryExportDocument()
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    func reportProjectMemoryExportFailure(_ error: Error) {
        let cocoaError = error as NSError
        guard cocoaError.domain != NSCocoaErrorDomain || cocoaError.code != NSUserCancelledError else {
            return
        }
        errorMessage = "Remember could not export the Project Memory Markdown file. Please choose another location and try again."
    }

    private func compileWikiQueue(using pipeline: MemoryPipeline) async throws {
        var processedAtLeastOneMemory = false
        while let memory = try await pipeline.claimNextWikiCompilation() {
            try Task.checkCancellation()
            try await pipeline.processWiki(memory)
            processedAtLeastOneMemory = true
            try await reloadWiki(using: pipeline)
            try await reloadActivities(using: pipeline)
            await Task.yield()
        }
        if processedAtLeastOneMemory {
            try await pipeline.runProjectMemoryLint()
        }
    }

    func clearSearch() {
        searchQuery = ""
        selectedKind = nil
        selectedDateRange = .anytime
        selectedTag = nil
        searchResults = []
        isSearching = false
        isGemmaSearching = false
        usedGemmaForCurrentSearch = false
    }

    func update(id: UUID, title: String, summary: String, tagsText: String) async -> Bool {
        let tags = tagsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return await performMutation { pipeline in
            try await pipeline.update(id: id, title: title, summary: summary, tags: tags)
        }
    }

    func delete(id: UUID) async -> Bool {
        await performMutation { pipeline in
            try await pipeline.delete(id: id)
        }
    }

    func saveVoiceRecording(from recordingURL: URL) async -> Bool {
        let saved = await performMutation { pipeline in
            _ = try await pipeline.createVoiceMemory(from: recordingURL)
        }
        if saved {
            Task { await self.synchronize() }
        }
        return saved
    }

    func createCollection(name: String) async -> Bool {
        await performMutation { pipeline in
            try await pipeline.createCollection(name: name)
        }
    }

    func renameCollection(id: UUID, name: String) async -> Bool {
        await performMutation { pipeline in
            try await pipeline.renameCollection(id: id, name: name)
        }
    }

    func deleteCollection(id: UUID) async -> Bool {
        await performMutation { pipeline in
            try await pipeline.deleteCollection(id: id)
        }
    }

    func collectionItems(id: UUID) async -> [MemoryLibraryItem] {
        do {
            return try await livePipeline().memories(inCollectionID: id)
        } catch {
            errorMessage = Self.message(for: error)
            return []
        }
    }

    func collectionIDs(forMemoryID memoryID: UUID) async -> Set<UUID> {
        do {
            return try await livePipeline().collectionIDs(forMemoryID: memoryID)
        } catch {
            errorMessage = Self.message(for: error)
            return []
        }
    }

    func setMembership(memoryID: UUID, collectionID: UUID, isMember: Bool) async -> Bool {
        await performMutation { pipeline in
            try await pipeline.setMembership(
                memoryID: memoryID,
                collectionID: collectionID,
                isMember: isMember
            )
        }
    }

    func renameTag(_ tag: String, to newName: String) async -> Bool {
        await performMutation { pipeline in
            try await pipeline.renameTag(tag, to: newName)
        }
    }

    func deleteTag(_ tag: String) async -> Bool {
        await performMutation { pipeline in
            try await pipeline.deleteTag(tag)
        }
    }

    func item(id: UUID) -> MemoryLibraryItem? {
        items.first(where: { $0.id == id })
    }

    func clearError() {
        errorMessage = nil
    }

    @discardableResult
    private func performMutation(
        _ mutation: (MemoryPipeline) async throws -> Void
    ) async -> Bool {
        errorMessage = nil
        do {
            let pipeline = try livePipeline()
            try await mutation(pipeline)
            try await reload(using: pipeline)
            try await reloadOrganization(using: pipeline)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private func reload(using pipeline: MemoryPipeline) async throws {
        items = try await pipeline.libraryItems()
        if searchRequest.isActive {
            searchResults = try await pipeline.search(searchRequest)
        } else {
            searchResults = []
        }
    }

    private func reloadActivities(using pipeline: MemoryPipeline) async throws {
        activities = try await pipeline.activities()
    }

    private func reloadOrganization(using pipeline: MemoryPipeline) async throws {
        collections = try await pipeline.collectionSummaries()
        tagSummaries = try await pipeline.tagSummaries()
    }

    private func reloadWiki(using pipeline: MemoryPipeline) async throws {
        wikiPages = try await pipeline.wikiPages()
        wikiQueueSummary = try await pipeline.wikiQueueSummary()
    }

    private func livePipeline() throws -> MemoryPipeline {
        if let pipeline {
            return pipeline
        }
        let newPipeline = try MemoryPipeline.live()
        pipeline = newPipeline
        return newPipeline
    }

    nonisolated private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return "Remember could not update your library. Please try again."
    }
}

nonisolated struct RememberChatMessage: Equatable, Identifiable, Sendable {
    let id: UUID
    let role: RememberConversationRole
    let text: String
    let sources: [MemoryLibraryItem]
    let modelVersion: String?

    init(
        id: UUID = UUID(),
        role: RememberConversationRole,
        text: String,
        sources: [MemoryLibraryItem],
        modelVersion: String?
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.sources = sources
        self.modelVersion = modelVersion
    }
}
