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
            try await memoryStore.recoverInterruptedProjectMemoryRuns()
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

    func projectMemoryHistory() async throws -> [ProjectMemoryRunSnapshot] {
        try await memoryStore.fetchProjectMemoryHistory()
    }

    func projectMemoryPageSnapshots() async throws -> [WikiPageSnapshot] {
        try await memoryStore.fetchAllWikiPageSnapshots()
    }

    func projectMemoryExportDocument() async throws -> ProjectMemoryExportDocument {
        let pages = try await memoryStore.fetchAllWikiPageSnapshots()
        let history = try await memoryStore.fetchProjectMemoryHistory(limit: 2_000)
        return ProjectMemoryExportDocument(
            content: ProjectMemoryMarkdownRenderer.render(pages: pages, history: history)
        )
    }

    func claimNextWikiCompilation() async throws -> MemoryItem? {
        try await memoryStore.claimNextWikiCompilation()
    }

    func processWiki(_ memory: MemoryItem) async throws {
        var activityID: UUID?
        var researchRunID: UUID?
        do {
            let candidates = try await wikiSearchService.candidates(for: memory)
            activityID = try await memoryStore.startActivity(
                kind: .wikiCompilation,
                memoryID: memory.id,
                sourceCount: candidates.count,
                modelVersion: GemmaLivingWikiCompiler.modelVersion
            )
            researchRunID = try await memoryStore.startProjectMemoryRun(
                operation: .compile,
                memoryID: memory.id,
                modelVersion: GemmaLivingWikiCompiler.modelVersion,
                promptVersion: GemmaLivingWikiCompiler.promptVersion
            )
            let compilationResult = try await wikiCompiler.compile(memory: memory, candidates: candidates)
            let proposal = compilationResult.proposal
            let decision = ProjectMemoryPatchEvaluator.evaluate(
                proposal: proposal,
                allowedCandidateIDs: Set(candidates.map(\.page.id)),
                candidates: candidates
            )
            let completion: ProjectMemoryRunCompletion
            switch compilationResult.recovery {
            case .noChange:
                completion = ProjectMemoryRunCompletion(
                    status: .discarded,
                    proposedPageCount: 0,
                    acceptedPageCount: 0,
                    rationale: "Gemma's repaired output was still malformed, so Remember safely made no Project Memory change. The original memory remains available.",
                    checks: decision.checks + [
                        ProjectMemoryCheckDraft(
                            checkID: "run.output_recovery",
                            label: "Malformed output contained",
                            severity: .information,
                            passed: true,
                            message: "Invalid model output was converted to a safe no-change result; no project page was mutated."
                        ),
                    ]
                )
            case .linkedAfterMalformedOutput:
                completion = ProjectMemoryRunCompletion(
                    status: decision.status,
                    proposedPageCount: proposal.pages.count,
                    acceptedPageCount: decision.proposalToApply.pages.count,
                    rationale: decision.status == .kept
                        ? "Gemma's repaired output was still malformed. Remember safely connected the source to the strongest retrieved page without rewriting its synthesis."
                        : decision.rationale,
                    checks: decision.checks + [
                        ProjectMemoryCheckDraft(
                            checkID: "run.output_recovery",
                            label: "Malformed output contained",
                            severity: .information,
                            passed: true,
                            message: "The source was linked to one strong, locally retrieved match; the existing page text was preserved."
                        ),
                    ]
                )
            case .linkedAfterNoChange:
                completion = ProjectMemoryRunCompletion(
                    status: decision.status,
                    proposedPageCount: proposal.pages.count,
                    acceptedPageCount: decision.proposalToApply.pages.count,
                    rationale: decision.status == .kept
                        ? "Gemma found no synthesis change, but Remember connected the source to the strongest relevant page as supporting evidence."
                        : decision.rationale,
                    checks: decision.checks + [
                        ProjectMemoryCheckDraft(
                            checkID: "run.no_change_evidence_recovery",
                            label: "Relevant evidence preserved",
                            severity: .information,
                            passed: true,
                            message: "The source was attached to one strong, locally retrieved match without rewriting the existing page."
                        ),
                    ]
                )
            case .none:
                completion = ProjectMemoryRunCompletion(
                    status: decision.status,
                    proposedPageCount: proposal.pages.count,
                    acceptedPageCount: decision.proposalToApply.pages.count,
                    rationale: decision.rationale,
                    checks: decision.checks
                )
            }
            try await memoryStore.applyWikiCompilation(
                memoryID: memory.id,
                sourceUpdatedAt: memory.updatedAt,
                proposal: decision.proposalToApply,
                allowedCandidateIDs: Set(candidates.map(\.page.id)),
                runID: researchRunID,
                runCompletion: completion
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
            if let researchRunID {
                try? await memoryStore.finishProjectMemoryRun(
                    id: researchRunID,
                    status: .failed,
                    proposedPageCount: 0,
                    acceptedPageCount: 0,
                    rationale: "The app interrupted this run before a patch could be evaluated.",
                    checks: []
                )
            }
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
            if let researchRunID {
                try? await memoryStore.finishProjectMemoryRun(
                    id: researchRunID,
                    status: .discarded,
                    proposedPageCount: 0,
                    acceptedPageCount: 0,
                    rationale: "The source memory changed during compilation, so the stale patch was discarded and rescheduled.",
                    checks: []
                )
            }
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
            if let researchRunID {
                try? await memoryStore.finishProjectMemoryRun(
                    id: researchRunID,
                    status: .failed,
                    proposedPageCount: 0,
                    acceptedPageCount: 0,
                    rationale: message,
                    checks: [
                        ProjectMemoryCheckDraft(
                            checkID: "run.execution",
                            label: "Local compiler completed",
                            severity: .blocking,
                            passed: false,
                            message: "The local compiler did not produce an evaluable patch."
                        ),
                    ]
                )
            }
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

    func runProjectMemoryLint() async throws {
        let runID = try await memoryStore.startProjectMemoryRun(
            operation: .lint,
            memoryID: nil,
            modelVersion: "deterministic-local-checks-v1",
            promptVersion: "none"
        )
        do {
            let input = try await memoryStore.fetchProjectMemoryLintInput()
            let checks = ProjectMemoryLinter.checks(
                pages: input.pages,
                evidence: input.evidence,
                revisions: input.revisions,
                links: input.links
            )
            let needsAttention = checks.contains { !$0.passed && $0.severity != .information }
            try await memoryStore.finishProjectMemoryRun(
                id: runID,
                status: needsAttention ? .attention : .passed,
                proposedPageCount: 0,
                acceptedPageCount: 0,
                rationale: needsAttention
                    ? "The protected evaluator found one or more structural warnings. No content was changed."
                    : "The project memory passed every deterministic structural check. No content was changed.",
                checks: checks
            )
        } catch {
            try? await memoryStore.finishProjectMemoryRun(
                id: runID,
                status: .failed,
                proposedPageCount: 0,
                acceptedPageCount: 0,
                rationale: "The local health check could not complete.",
                checks: []
            )
            throw error
        }
    }
}
