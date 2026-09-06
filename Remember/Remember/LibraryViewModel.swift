import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private(set) var items: [MemoryLibraryItem] = []
    private(set) var isSynchronizing = false
    private(set) var isSearching = false
    private(set) var isAISearching = false
    private(set) var isAnswering = false
    private(set) var usedAIForCurrentSearch = false
    private(set) var errorMessage: String?
    private(set) var isTranscribingAssistantQuery = false

    var searchQuery = ""
    var selectedKind: MemoryKind?
    var selectedDateRange: MemoryDateRange = .anytime
    var selectedTag: String?
    var chatInput = ""

    private(set) var searchResults: [MemoryLibraryItem] = []
    private(set) var chatMessages: [RememberChatMessage] = []
    private(set) var activities: [LocalAIActivity] = []
    private(set) var collections: [MemoryCollectionSummary] = []
    private(set) var tagSummaries: [MemoryTagSummary] = []
    private(set) var aiAvailability: LocalAIAvailability = OpenAIAvailability().availability()
    private(set) var aiModelDescriptor = OpenAIAvailability().descriptor

    private var pipeline: MemoryPipeline?
    private var assistantConversationID = UUID()
    private let captureServiceFactory: @Sendable () throws -> any InAppCaptureServing
    private let speechTranscriber: any LocalSpeechTranscribing

    init(
        captureServiceFactory: @escaping @Sendable () throws -> any InAppCaptureServing = {
            InAppCaptureService(inbox: try CaptureInbox.appGroup())
        },
        speechTranscriber: any LocalSpeechTranscribing = OnDeviceSpeechTranscriber()
    ) {
        self.captureServiceFactory = captureServiceFactory
        self.speechTranscriber = speechTranscriber
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
            refreshAIStatus(using: pipeline)
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
        isAISearching = false
        usedAIForCurrentSearch = false
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

    func searchWithAI() async {
        let request = searchRequest
        guard !request.normalizedQuery.isEmpty else {
            await search()
            return
        }

        isSearching = true
        isAISearching = true
        errorMessage = nil
        do {
            let results = try await livePipeline().semanticSearch(request)
            try Task.checkCancellation()
            guard request == searchRequest else {
                return
            }
            searchResults = results
            usedAIForCurrentSearch = true
            isSearching = false
            isAISearching = false
            try await reloadActivities(using: livePipeline())
        } catch is CancellationError {
            if request == searchRequest {
                isSearching = false
                isAISearching = false
            }
        } catch {
            if request == searchRequest {
                isSearching = false
                isAISearching = false
                usedAIForCurrentSearch = false
                errorMessage = Self.message(for: error)
            }
        }
    }

    func askRemember() async {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else {
            return
        }

        let conversationID = assistantConversationID
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
            try Task.checkCancellation()
            guard assistantConversationID == conversationID else { return }
            chatMessages.append(
                RememberChatMessage(
                    role: .assistant,
                    text: response.answer,
                    sources: response.sources,
                    modelVersion: response.modelVersion,
                    citations: response.citations,
                    mode: response.mode
                )
            )
            try await reloadActivities(using: pipeline)
        } catch is CancellationError {
            if assistantConversationID == conversationID {
                chatInput = question
            }
        } catch {
            guard assistantConversationID == conversationID else { return }
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
        if assistantConversationID == conversationID {
            isAnswering = false
        }
    }

    func resetAssistantConversation() {
        assistantConversationID = UUID()
        chatInput = ""
        chatMessages = []
        isAnswering = false
        isTranscribingAssistantQuery = false
    }

    func transcribeAssistantQuestion(from recordingURL: URL) async -> Bool {
        guard !isTranscribingAssistantQuery else { return false }
        let conversationID = assistantConversationID
        isTranscribingAssistantQuery = true
        errorMessage = nil
        defer {
            if assistantConversationID == conversationID {
                isTranscribingAssistantQuery = false
            }
        }
        do {
            let transcript = try await speechTranscriber.transcribe(audioURL: recordingURL)
            try Task.checkCancellation()
            guard assistantConversationID == conversationID else { return false }
            chatInput = transcript
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard assistantConversationID == conversationID else { return false }
            errorMessage = Self.message(for: error)
            return false
        }
    }

    func refreshActivities() async {
        do {
            try await reloadActivities(using: livePipeline())
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func clearSearch() {
        searchQuery = ""
        selectedKind = nil
        selectedDateRange = .anytime
        selectedTag = nil
        searchResults = []
        isSearching = false
        isAISearching = false
        usedAIForCurrentSearch = false
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

    func updateNote(id: UUID, title: String, body: String) async -> Bool {
        await performMutation { pipeline in
            try await pipeline.updateNote(id: id, title: title, body: body)
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

    func saveNote(_ text: String) async -> Bool {
        await saveCapture { try $0.saveNote(text) }
    }

    func saveLink(_ urlText: String, context: String?) async -> Bool {
        await saveCapture { try $0.saveLink(urlText, context: context) }
    }

    func saveImage(from sourceURL: URL, context: String?) async -> Bool {
        await saveCapture { try $0.saveImage(from: sourceURL, context: context) }
    }

    func saveImportedFile(from sourceURL: URL) async -> Bool {
        await saveCapture { try $0.saveImportedFile(from: sourceURL) }
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

    func reportError(_ error: Error) {
        errorMessage = Self.message(for: error)
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

    @discardableResult
    private func saveCapture(
        _ capture: (any InAppCaptureServing) throws -> Void
    ) async -> Bool {
        errorMessage = nil
        do {
            try capture(captureServiceFactory())
            Task { await self.synchronize() }
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


    private func livePipeline() throws -> MemoryPipeline {
        if let pipeline {
            return pipeline
        }
        let newPipeline = try MemoryPipeline.live()
        pipeline = newPipeline
        refreshAIStatus(using: newPipeline)
        return newPipeline
    }

    private func refreshAIStatus(using pipeline: MemoryPipeline) {
        aiAvailability = pipeline.aiAvailability()
        aiModelDescriptor = pipeline.aiModelDescriptor()
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
    let citations: [GroundedCitation]
    let mode: RememberAnswerMode?

    init(
        id: UUID = UUID(),
        role: RememberConversationRole,
        text: String,
        sources: [MemoryLibraryItem],
        modelVersion: String?,
        citations: [GroundedCitation] = [],
        mode: RememberAnswerMode? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.sources = sources
        self.modelVersion = modelVersion
        self.citations = citations
        self.mode = mode
    }
}
