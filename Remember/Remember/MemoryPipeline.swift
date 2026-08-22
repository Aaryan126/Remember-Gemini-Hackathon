import Foundation

actor MemoryPipeline {
    private let analyzer: any MemoryAnalyzing
    private let assistant: GemmaRememberAssistant
    private let fileStore: LibraryFileStore
    private let importer: CaptureImporter
    private let memoryStore: MemoryStore
    private let searchService: MemorySearchService
    private let speechTranscriber: any LocalSpeechTranscribing
    private let wikiCompiler: any LivingWikiCompiling
    private let wikiSearchService: WikiSearchService
    private var hasRecoveredInterruptedWork = false

    init(
        analyzer: any MemoryAnalyzing,
        assistant: GemmaRememberAssistant,
        fileStore: LibraryFileStore,
        importer: CaptureImporter,
        memoryStore: MemoryStore,
        searchService: MemorySearchService,
        speechTranscriber: any LocalSpeechTranscribing,
        wikiCompiler: any LivingWikiCompiling,
        wikiSearchService: WikiSearchService
    ) {
        self.analyzer = analyzer
        self.assistant = assistant
        self.fileStore = fileStore
        self.importer = importer
        self.memoryStore = memoryStore
        self.searchService = searchService
        self.speechTranscriber = speechTranscriber
        self.wikiCompiler = wikiCompiler
        self.wikiSearchService = wikiSearchService
    }

    static func live() throws -> MemoryPipeline {
        let memoryStore = try MemoryStore(databaseURL: MemoryStore.defaultDatabaseURL())
        let fileStore = try LibraryFileStore(directoryURL: LibraryFileStore.defaultDirectory())
        let importer = CaptureImporter(
            inbox: try CaptureInbox.appGroup(),
            fileStore: fileStore,
            memoryStore: memoryStore
        )
        let embeddingService = MLXTextEmbeddingService()
        let searchService = MemorySearchService(
            memoryStore: memoryStore,
            embeddingService: embeddingService
        )
        let wikiSearchService = WikiSearchService(
            memoryStore: memoryStore,
            embeddingService: embeddingService
        )
        let assistant = GemmaRememberAssistant(
            memoryStore: memoryStore,
            searchService: searchService,
            wikiSearchService: wikiSearchService
        )
        return MemoryPipeline(
            analyzer: GemmaMemoryAnalyzer(),
            assistant: assistant,
            fileStore: fileStore,
            importer: importer,
            memoryStore: memoryStore,
            searchService: searchService,
            speechTranscriber: OnDeviceSpeechTranscriber(),
            wikiCompiler: GemmaLivingWikiCompiler(),
            wikiSearchService: wikiSearchService
        )
    }

    func bootstrap() async throws {
        if !hasRecoveredInterruptedWork {
            try await memoryStore.recoverInterruptedProcessing()
            try await memoryStore.recoverInterruptedActivities()
            try await memoryStore.recoverInterruptedWikiCompilations()
            hasRecoveredInterruptedWork = true
        }
        try await importer.importPending()
        try await searchService.synchronizeIndex()
        try await wikiSearchService.synchronizeIndex()
    }

    func libraryItems() async throws -> [MemoryLibraryItem] {
        try await memoryStore.fetchAll().map { memory in
            MemoryLibraryItem(memory: memory, originalURL: fileStore.url(for: memory.originalFilename))
        }
    }

    func search(_ request: MemorySearchRequest) async throws -> [MemoryLibraryItem] {
        try await searchService.search(request).map { result in
            MemoryLibraryItem(
                memory: result.memory,
                originalURL: fileStore.url(for: result.memory.originalFilename)
            )
        }
    }

    func semanticSearch(_ request: MemorySearchRequest) async throws -> [MemoryLibraryItem] {
        try await assistant.semanticSearch(request).map { result in
            MemoryLibraryItem(
                memory: result.memory,
                originalURL: fileStore.url(for: result.memory.originalFilename)
            )
        }
    }

    func answer(
        question: String,
        history: [RememberConversationTurn]
    ) async throws -> RememberLibraryAssistantResponse {
        let response = try await assistant.answer(question: question, history: history)
        return RememberLibraryAssistantResponse(
            answer: response.answer,
            sources: response.sources.map { result in
                MemoryLibraryItem(
                    memory: result.memory,
                    originalURL: fileStore.url(for: result.memory.originalFilename)
                )
            },
            modelVersion: response.modelVersion
        )
    }

    func activities() async throws -> [LocalAIActivity] {
        try await memoryStore.fetchActivities()
    }

    func claimNextCaptured() async throws -> MemoryItem? {
        try await memoryStore.claimNextCaptured()
    }

    func process(_ memory: MemoryItem) async throws {
        let originalURL = fileStore.url(for: memory.originalFilename)
        var supportingText: String?
        if memory.kind == .audio {
            let transcriptionActivityID = try await memoryStore.startActivity(
                kind: .transcription,
                memoryID: memory.id,
                sourceCount: 1,
                modelVersion: OnDeviceSpeechTranscriber.modelVersion
            )
            do {
                supportingText = try await speechTranscriber.transcribe(audioURL: originalURL)
                try await memoryStore.finishActivity(
                    id: transcriptionActivityID,
                    status: .completed,
                    sourceCount: 1
                )
            } catch is CancellationError {
                try? await memoryStore.resetToCaptured(id: memory.id)
                try? await memoryStore.finishActivity(
                    id: transcriptionActivityID,
                    status: .interrupted,
                    failureCategory: "cancelled"
                )
                throw CancellationError()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? "On-device transcription could not complete."
                try await memoryStore.markFailed(id: memory.id, message: message)
                try? await memoryStore.finishActivity(
                    id: transcriptionActivityID,
                    status: .failed,
                    failureCategory: String(describing: type(of: error))
                )
                return
            }
        }

        let activityID = try await memoryStore.startActivity(
            kind: .analysis,
            memoryID: memory.id,
            sourceCount: 1
        )
        do {
            let result = try await analyzer.analyze(
                memory: memory,
                originalURL: originalURL,
                supportingText: supportingText
            )
            try await memoryStore.markIndexed(id: memory.id, analysis: result)
            if let indexedMemory = try await memoryStore.fetch(id: memory.id) {
                try await searchService.index(indexedMemory)
            }
            try await memoryStore.finishActivity(id: activityID, status: .completed, sourceCount: 1)
        } catch is CancellationError {
            try? await memoryStore.resetToCaptured(id: memory.id)
            try? await memoryStore.finishActivity(
                id: activityID,
                status: .interrupted,
                failureCategory: "cancelled"
            )
            throw CancellationError()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "On-device analysis could not complete."
            try await memoryStore.markFailed(id: memory.id, message: message)
            try? await memoryStore.finishActivity(
                id: activityID,
                status: .failed,
                failureCategory: String(describing: type(of: error))
            )
        }
    }

    func retry(id: UUID) async throws {
        try await memoryStore.resetToCaptured(id: id)
    }

    func update(id: UUID, title: String, summary: String, tags: [String]) async throws {
        try await memoryStore.updateEditableFields(id: id, title: title, summary: summary, tags: tags)
        if let updatedMemory = try await memoryStore.fetch(id: id) {
            try await searchService.index(updatedMemory)
        }
    }

    func delete(id: UUID) async throws {
        guard let memory = try await memoryStore.fetch(id: id) else {
            return
        }
        try await memoryStore.delete(id: id)
        try fileStore.remove(filename: memory.originalFilename)
    }

    func createVoiceMemory(from recordingURL: URL) async throws -> UUID {
        let id = UUID()
        let filename = try fileStore.importFile(id: id, from: recordingURL)
        let now = Date()
        let memory = MemoryItem(
            id: id,
            kind: .audio,
            createdAt: now,
            importedAt: now,
            updatedAt: now,
            state: .captured,
            originalFilename: filename,
            userCaption: nil,
            title: nil,
            summary: nil,
            extractedText: nil,
            tagsJSON: "[]",
            processingError: nil,
            modelVersion: nil
        )
        do {
            try await memoryStore.insertIfNeeded(memory)
            return id
        } catch {
            try? fileStore.remove(filename: filename)
            throw error
        }
    }

    func collectionSummaries() async throws -> [MemoryCollectionSummary] {
        try await memoryStore.fetchCollectionSummaries()
    }

    func tagSummaries() async throws -> [MemoryTagSummary] {
        try await memoryStore.fetchTagSummaries()
    }

    func createCollection(name: String) async throws {
        _ = try await memoryStore.createCollection(name: name)
    }

    func renameCollection(id: UUID, name: String) async throws {
        try await memoryStore.renameCollection(id: id, name: name)
    }

    func deleteCollection(id: UUID) async throws {
        try await memoryStore.deleteCollection(id: id)
    }

    func collectionIDs(forMemoryID memoryID: UUID) async throws -> Set<UUID> {
        try await memoryStore.collectionIDs(forMemoryID: memoryID)
    }

    func setMembership(memoryID: UUID, collectionID: UUID, isMember: Bool) async throws {
        try await memoryStore.setMembership(
            memoryID: memoryID,
            collectionID: collectionID,
            isMember: isMember
        )
    }

    func memories(inCollectionID collectionID: UUID) async throws -> [MemoryLibraryItem] {
        try await memoryStore.fetchMemories(inCollectionID: collectionID).map { memory in
            MemoryLibraryItem(memory: memory, originalURL: fileStore.url(for: memory.originalFilename))
        }
    }

    func renameTag(_ source: String, to target: String) async throws {
        for memory in try await memoryStore.renameTag(source, to: target) {
            try await searchService.index(memory)
        }
    }

    func deleteTag(_ tag: String) async throws {
        for memory in try await memoryStore.deleteTag(tag) {
            try await searchService.index(memory)
        }
    }

    func prepareWikiCompilationQueue() async throws {
        try await memoryStore.prepareWikiCompilationQueue()
    }

    func wikiPages() async throws -> [WikiPage] {
        try await memoryStore.fetchWikiPages()
    }

    func wikiQueueSummary() async throws -> WikiQueueSummary {
        try await memoryStore.fetchWikiQueueSummary()
    }

    func wikiPageSnapshot(id: UUID) async throws -> WikiPageSnapshot? {
        try await memoryStore.fetchWikiPageSnapshot(id: id)
    }

    func claimNextWikiCompilation() async throws -> MemoryItem? {
        try await memoryStore.claimNextWikiCompilation()
    }

    func processWiki(_ memory: MemoryItem) async throws {
        var activityID: UUID?
        do {
            let candidates = try await wikiSearchService.candidates(for: memory)
            activityID = try await memoryStore.startActivity(
                kind: .wikiCompilation,
                memoryID: memory.id,
                sourceCount: candidates.count,
                modelVersion: GemmaLivingWikiCompiler.modelVersion
            )
            let proposal = try await wikiCompiler.compile(memory: memory, candidates: candidates)
            try await memoryStore.applyWikiCompilation(
                memoryID: memory.id,
                sourceUpdatedAt: memory.updatedAt,
                proposal: proposal,
                allowedCandidateIDs: Set(candidates.map(\.page.id))
            )
            try await wikiSearchService.synchronizeIndex()
            if let activityID {
                try await memoryStore.finishActivity(
                    id: activityID,
                    status: .completed,
                    sourceCount: proposal.pages.count
                )
            }
        } catch is CancellationError {
            try? await memoryStore.resetWikiCompilationToPending(memoryID: memory.id)
            if let activityID {
                try? await memoryStore.finishActivity(
                    id: activityID,
                    status: .interrupted,
                    failureCategory: "cancelled"
                )
            }
            throw CancellationError()
        } catch LivingWikiError.sourceChanged {
            try? await memoryStore.resetWikiCompilationToPending(memoryID: memory.id)
            if let activityID {
                try? await memoryStore.finishActivity(
                    id: activityID,
                    status: .interrupted,
                    failureCategory: "source_changed"
                )
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Gemma could not safely compile this memory into the wiki."
            try? await memoryStore.markWikiCompilationFailed(memoryID: memory.id, message: message)
            if let activityID {
                try? await memoryStore.finishActivity(
                    id: activityID,
                    status: .failed,
                    failureCategory: String(describing: type(of: error))
                )
            }
        }
    }

    func retryFailedWikiCompilations() async throws {
        try await memoryStore.retryFailedWikiCompilations()
    }
}
