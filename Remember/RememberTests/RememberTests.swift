//
//  RememberTests.swift
//  RememberTests
//
//  Created by Aaryan Kandiah on 21/8/26.
//

import Foundation
import Testing
@testable import Remember

struct RememberTests {

    @Test func validatesCompleteModelDirectory() throws {
        let directory = try makeTemporaryModelDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try GemmaModelBundle.validate(directory: directory)
    }

    @Test func reportsMissingRequiredModelFile() throws {
        let directory = try makeTemporaryModelDirectory(excluding: "model.safetensors")
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try GemmaModelBundle.validate(directory: directory)
            Issue.record("Expected validation to reject the incomplete model directory")
        } catch GemmaInferenceError.missingModelFile(let filename) {
            #expect(filename == "model.safetensors")
        }
    }

    @Test func assistantMarkdownRendersEmphasisAndListMarkers() throws {
        let rendered = ChatMarkdownRenderer.render(
            "Deadlines:\n\n* **September 4th:** Assignment 1 [M1]."
        )
        let visibleText = String(rendered.characters)

        #expect(visibleText.contains("• September 4th:"))
        #expect(!visibleText.contains("**"))
        #expect(rendered.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        })
    }

    @Test func savesImageAndMetadataToCaptureInbox() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let source = container.appendingPathComponent("shared-photo.jpg")
        let imageBytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try imageBytes.write(to: source)

        let inbox = CaptureInbox(containerURL: container)
        let saved = try inbox.saveImage(from: source, caption: "  A useful receipt  ")
        let records = try inbox.records()

        #expect(records.count == 1)
        let reloaded = try #require(records.first)
        #expect(reloaded.id == saved.id)
        #expect(reloaded.schemaVersion == saved.schemaVersion)
        #expect(reloaded.kind == saved.kind)
        #expect(reloaded.state == saved.state)
        #expect(reloaded.caption == saved.caption)
        #expect(reloaded.payloadFilename == saved.payloadFilename)
        #expect(abs(reloaded.createdAt.timeIntervalSince(saved.createdAt)) < 1)
        #expect(saved.kind == .image)
        #expect(saved.state == .captured)
        #expect(saved.caption == "A useful receipt")
        #expect(try Data(contentsOf: inbox.payloadURL(for: saved)) == imageBytes)
    }

    @Test func savesPlainTextCapture() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let inbox = CaptureInbox(containerURL: container)
        let saved = try inbox.saveText("  Call the dentist tomorrow.  ")

        #expect(saved.kind == .text)
        #expect(saved.caption == "Call the dentist tomorrow.")
        #expect(try String(contentsOf: inbox.payloadURL(for: saved), encoding: .utf8) == saved.caption)
    }

    @Test func savesLinkCaptureWithoutFetchingIt() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = CaptureInbox(containerURL: container)
        let url = try #require(URL(string: "https://example.com/private-reading"))

        let saved = try inbox.saveURL(url, caption: "Read later")

        #expect(saved.kind == .link)
        #expect(saved.caption == "Read later")
        #expect(try String(contentsOf: inbox.payloadURL(for: saved), encoding: .utf8) == url.absoluteString)
    }

    @Test func savesPDFCaptureAsAnAtomicLocalFile() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }
        let source = container.appendingPathComponent("notes.pdf")
        let bytes = Data("%PDF-1.4 test".utf8)
        try bytes.write(to: source)
        let inbox = CaptureInbox(containerURL: container)

        let saved = try inbox.savePDF(from: source, caption: "Lecture notes")

        #expect(saved.kind == .pdf)
        #expect(saved.payloadFilename == "content.pdf")
        #expect(try Data(contentsOf: inbox.payloadURL(for: saved)) == bytes)
    }

    @Test func ignoresIncompleteCaptureDirectories() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let inboxDirectory = container.appendingPathComponent("CaptureInbox", isDirectory: true)
        let incompleteDirectory = inboxDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: incompleteDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: incompleteDirectory.appendingPathComponent("metadata.json")
        )

        #expect(try CaptureInbox(containerURL: container).records().isEmpty)
    }

    @Test func removesCompletedCapture() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let inbox = CaptureInbox(containerURL: container)
        let saved = try inbox.saveText("A temporary reminder")

        try inbox.remove(saved)

        #expect(try inbox.records().isEmpty)
        #expect(throws: CaptureInboxError.missingPayload(saved.id)) {
            try inbox.payloadURL(for: saved)
        }
    }

    @Test func importsCaptureExactlyOnce() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let inbox = CaptureInbox(containerURL: root.appendingPathComponent("AppGroup", isDirectory: true))
        let library = try LibraryFileStore(
            directoryURL: root.appendingPathComponent("Originals", isDirectory: true)
        )
        let store = try MemoryStore(
            databaseURL: root.appendingPathComponent("Database/remember.sqlite", isDirectory: false)
        )
        let importer = CaptureImporter(inbox: inbox, fileStore: library, memoryStore: store)
        let saved = try inbox.saveText("Call the dentist tomorrow")

        #expect(try await importer.importPending() == 1)
        #expect(try await importer.importPending() == 0)

        let memories = try await store.fetchAll()
        #expect(memories.count == 1)
        #expect(memories.first?.id == saved.id)
        #expect(memories.first?.state == .captured)
        #expect(try inbox.records().isEmpty)
        if let memory = memories.first {
            #expect(try String(contentsOf: library.url(for: memory.originalFilename), encoding: .utf8) == "Call the dentist tomorrow")
        }
    }

    @Test func memoryStorePersistsProcessingAndEdits() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let id = UUID()
        let now = Date()
        let item = MemoryItem(
            id: id,
            kind: .image,
            createdAt: now,
            importedAt: now,
            updatedAt: now,
            state: .captured,
            originalFilename: "\(id.uuidString).jpg",
            userCaption: "Receipt",
            title: nil,
            summary: nil,
            extractedText: nil,
            tagsJSON: "[]",
            processingError: nil,
            modelVersion: nil
        )
        try await store.insertIfNeeded(item)

        let claimed = try await store.claimNextCaptured()
        #expect(claimed?.id == id)
        #expect(claimed?.state == .processing)

        try await store.markIndexed(
            id: id,
            analysis: MemoryAnalysisResult(
                title: "Lunch receipt",
                summary: "A saved lunch receipt.",
                tags: ["receipt", "food"],
                extractedText: "$12.00",
                modelVersion: "test-model"
            )
        )
        try await store.updateEditableFields(
            id: id,
            title: "Team lunch",
            summary: "Lunch with the team.",
            tags: ["Work", "food", "work"]
        )

        let updated = try await store.fetch(id: id)
        #expect(updated?.state == .indexed)
        #expect(updated?.title == "Team lunch")
        #expect(updated?.summary == "Lunch with the team.")
        #expect(updated?.tags == ["Work", "food"])
        #expect(updated?.extractedText == "$12.00")
    }

    @Test func parsesGemmaJSONEvenWhenWrappedInMarkdown() {
        let result = MemoryAnalysisParser.parse(
            response: """
                ```json
                {"title":"Video hackathon","summary":"An event poster for an AI video hackathon.","tags":["AI","event","hackathon"]}
                ```
                """,
            kind: .image,
            userCaption: "Save for later",
            extractedText: "Future in Motion",
            modelVersion: "test-model"
        )

        #expect(result.title == "Video hackathon")
        #expect(result.summary == "An event poster for an AI video hackathon.")
        #expect(result.tags == ["ai", "event", "hackathon"])
    }

    @Test func parserFallsBackWithoutValidJSON() {
        let result = MemoryAnalysisParser.parse(
            response: "not valid JSON",
            kind: .image,
            userCaption: "  Conference poster  ",
            extractedText: "Conference 2026",
            modelVersion: "test-model"
        )

        #expect(result.title == "Conference poster")
        #expect(result.summary == "Conference poster")
        #expect(result.tags.isEmpty)
    }

    @Test func gemmaExpandedSearchRanksRelevantMemoryAndPersistsIndex() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let restaurant = indexedMemory(
            kind: .image,
            createdAt: now.addingTimeInterval(-3_600),
            title: "Sushi restaurant",
            summary: "Dinner at a quiet Japanese place near the river.",
            tags: ["food", "restaurant"]
        )
        let lecture = indexedMemory(
            kind: .text,
            createdAt: now.addingTimeInterval(-60 * 86_400),
            title: "Swift lecture",
            summary: "Notes from a seminar about actors and concurrency.",
            tags: ["study", "swift"]
        )
        try await store.insertIfNeeded(restaurant)
        try await store.insertIfNeeded(lecture)

        let service = MemorySearchService(
            memoryStore: store,
            now: { now }
        )
        try await service.synchronizeIndex()

        let results = try await service.search(
            MemorySearchRequest(query: "Where did we have dinner?"),
            expandedTerms: ["sushi", "japanese restaurant"]
        )
        #expect(results.first?.memory.id == restaurant.id)
        #expect(results.allSatisfy { $0.memory.id != lecture.id })

        let records = try await store.fetchSearchIndexRecords()
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.embeddingData == nil })
        #expect(records.allSatisfy { $0.embeddingModel.contains("gemma-4") })
    }

    @Test func searchFiltersByTypeDateAndTagWithoutAQuery() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recentImage = indexedMemory(
            kind: .image,
            createdAt: now.addingTimeInterval(-3_600),
            title: "Event poster",
            summary: "A video hackathon poster.",
            tags: ["event"]
        )
        let olderText = indexedMemory(
            kind: .text,
            createdAt: now.addingTimeInterval(-60 * 86_400),
            title: "Project note",
            summary: "Ideas for a private memory app.",
            tags: ["project"]
        )
        try await store.insertIfNeeded(recentImage)
        try await store.insertIfNeeded(olderText)

        let service = MemorySearchService(
            memoryStore: store,
            now: { now }
        )

        let recent = try await service.search(
            MemorySearchRequest(query: "", dateRange: .pastWeek)
        )
        #expect(recent.map(\.memory.id) == [recentImage.id])

        let text = try await service.search(
            MemorySearchRequest(query: "", kind: .text)
        )
        #expect(text.map(\.memory.id) == [olderText.id])

        let event = try await service.search(
            MemorySearchRequest(query: "", tag: "EVENT")
        )
        #expect(event.map(\.memory.id) == [recentImage.id])
    }

    @Test func searchFallsBackToLocalTextMatchingWithoutEmbeddings() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let memory = indexedMemory(
            kind: .image,
            createdAt: Date(),
            title: "Seminar room",
            summary: "The lecture is in room AS1-02-07.",
            tags: ["university"]
        )
        try await store.insertIfNeeded(memory)
        let service = MemorySearchService(memoryStore: store)

        let results = try await service.search(MemorySearchRequest(query: "AS1-02-07"))

        #expect(results.map(\.memory.id) == [memory.id])
    }

    @Test func semanticSearchPersistsVectorsAndFindsAParaphrase() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let restaurant = indexedMemory(
            kind: .image,
            createdAt: Date(),
            title: "Sushi reservation",
            summary: "A quiet omakase restaurant near the river.",
            tags: ["food"]
        )
        let lecture = indexedMemory(
            kind: .text,
            createdAt: Date().addingTimeInterval(-1),
            title: "Concurrency lecture",
            summary: "Actor isolation and structured tasks.",
            tags: ["swift"]
        )
        try await store.insertIfNeeded(restaurant)
        try await store.insertIfNeeded(lecture)
        let embedder = StubTextEmbedding { text in
            let text = text.lowercased()
            return text.contains("sushi") || text.contains("omakase") || text.contains("evening meal")
                ? [1, 0]
                : [0, 1]
        }
        let service = MemorySearchService(memoryStore: store, embeddingService: embedder)

        let results = try await service.search(
            MemorySearchRequest(query: "the place for our evening meal"),
            useSemanticSimilarity: true
        )

        #expect(results.first?.memory.id == restaurant.id)
        #expect(try await store.fetchSearchIndexRecords().allSatisfy { $0.embeddingData != nil })
    }

    @Test func embeddingVectorCodecRoundTripsAndScoresCosine() throws {
        let vector: [Float] = [0.25, -0.5, 0.75]
        let decoded = try #require(EmbeddingVectorCodec.decode(EmbeddingVectorCodec.encode(vector)))

        #expect(decoded == vector)
        #expect(abs((EmbeddingVectorCodec.cosineSimilarity(vector, vector) ?? 0) - 1) < 0.000_1)
        #expect(EmbeddingVectorCodec.cosineSimilarity([1, 0], [0, 1]) == 0)
    }

    @Test func parsesGemmaQueryExpansionAndBoundsTerms() {
        let terms = GemmaQueryExpansionParser.parse(
            response: """
                ```json
                {"terms":["Lecture room","seminar","University","seminar",""]}
                ```
                """,
            fallbackQuery: "where is class"
        )

        #expect(terms == ["lecture room", "seminar", "university"])
    }

    @Test func localAIActivityLogStoresMetadataAndRecoversInterruptedWork() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))

        let completedID = try await store.startActivity(kind: .search)
        try await store.finishActivity(id: completedID, status: .completed, sourceCount: 3)
        _ = try await store.startActivity(kind: .chat)
        try await store.recoverInterruptedActivities()

        let activities = try await store.fetchActivities()
        #expect(activities.count == 2)
        #expect(activities.first(where: { $0.id == completedID })?.status == .completed)
        #expect(activities.first(where: { $0.id == completedID })?.sourceCount == 3)
        #expect(activities.first(where: { $0.kind == .chat })?.status == .interrupted)
        #expect(activities.allSatisfy { $0.failureCategory?.contains("where is class") != true })
    }

    @Test func collectionsGroupMemoriesWithoutOwningOrDeletingThem() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let first = indexedMemory(
            kind: .text,
            createdAt: Date(),
            title: "Project idea",
            summary: "A private memory app.",
            tags: ["project"]
        )
        let second = indexedMemory(
            kind: .image,
            createdAt: Date().addingTimeInterval(-10),
            title: "Reference image",
            summary: "A visual reference.",
            tags: ["reference"]
        )
        try await store.insertIfNeeded(first)
        try await store.insertIfNeeded(second)

        let collection = try await store.createCollection(name: "  Hackathon  ")
        try await store.setMembership(memoryID: first.id, collectionID: collection.id, isMember: true)

        let summaries = try await store.fetchCollectionSummaries()
        #expect(summaries.count == 1)
        #expect(summaries.first?.id == collection.id)
        #expect(summaries.first?.collection.name == "Hackathon")
        #expect(summaries.first?.memoryCount == 1)
        #expect(try await store.collectionIDs(forMemoryID: first.id) == [collection.id])
        #expect(try await store.fetchMemories(inCollectionID: collection.id).map(\.id) == [first.id])

        try await store.deleteCollection(id: collection.id)
        #expect(try await store.fetchAll().count == 2)
        #expect(try await store.collectionIDs(forMemoryID: first.id).isEmpty)
    }

    @Test func collectionNamesAreCaseInsensitivelyUnique() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        _ = try await store.createCollection(name: "Recipes")

        await #expect(throws: MemoryOrganizationError.duplicateCollectionName) {
            _ = try await store.createCollection(name: "recipes")
        }
    }

    @Test func renamingAndDeletingTagsUpdatesEveryMatchingMemory() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let first = indexedMemory(
            kind: .text,
            createdAt: Date(),
            title: "First",
            summary: "First note.",
            tags: ["Work", "important"]
        )
        let second = indexedMemory(
            kind: .text,
            createdAt: Date().addingTimeInterval(-1),
            title: "Second",
            summary: "Second note.",
            tags: ["work", "archive"]
        )
        try await store.insertIfNeeded(first)
        try await store.insertIfNeeded(second)

        let renamed = try await store.renameTag("WORK", to: "projects")
        #expect(renamed.count == 2)
        #expect(try await store.fetchTagSummaries().first(where: { $0.name == "projects" })?.memoryCount == 2)

        let changed = try await store.deleteTag("projects")
        #expect(changed.count == 2)
        #expect(try await store.fetchAll().allSatisfy { !$0.tags.contains("projects") })
    }

    @Test func voiceMemoryAnalysisUsesTranscriptAsSearchableText() {
        let result = MemoryAnalysisParser.parse(
            response: """
                {"title":"Dentist reminder","summary":"Call the dentist on Monday.","tags":["health","reminder"]}
                """,
            kind: .audio,
            userCaption: nil,
            extractedText: "Call the dentist on Monday.",
            modelVersion: "test-model"
        )

        #expect(result.title == "Dentist reminder")
        #expect(result.extractedText == "Call the dentist on Monday.")
        #expect(result.tags == ["health", "reminder"])
    }

    @Test func importsRecordedAudioIntoProtectedLibraryFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("voice.m4a")
        let bytes = Data([0x00, 0x01, 0x02, 0x03])
        try bytes.write(to: source)
        let store = try LibraryFileStore(directoryURL: root.appendingPathComponent("Originals"))
        let id = UUID()

        let filename = try store.importFile(id: id, from: source)

        #expect(filename == "\(id.uuidString).m4a")
        #expect(try Data(contentsOf: store.url(for: filename)) == bytes)
    }

    @Test func livingWikiCandidateIndexPrioritizesNamesAliasesAndEvidenceOverlap() {
        let now = Date()
        let memory = indexedMemory(
            kind: .text,
            createdAt: now,
            title: "Remember iPhone architecture",
            summary: "The Remember project uses private on-device AI and Gemma.",
            tags: ["mlx", "privacy"]
        )
        let remember = wikiPage(
            kind: .project,
            title: "Remember",
            summary: "A private memory app for iPhone.",
            aliases: ["Remember app"],
            updatedAt: now
        )
        let localAI = wikiPage(
            kind: .concept,
            title: "On-device AI",
            summary: "Models that process data locally.",
            aliases: ["local AI"],
            updatedAt: now.addingTimeInterval(-1)
        )
        let restaurant = wikiPage(
            kind: .concept,
            title: "Sushi restaurants",
            summary: "Places to eat dinner.",
            aliases: [],
            updatedAt: now
        )
        let thermalBudget = wikiPage(
            kind: .constraint,
            title: "Thermal budget",
            summary: "A device execution constraint.",
            aliases: [],
            updatedAt: now
        )
        let graphLink = WikiPageLink(
            sourcePageID: localAI.id,
            targetPageID: thermalBudget.id,
            rationale: "Local inference is constrained by sustained device load.",
            createdAt: now
        )

        let candidates = LivingWikiCandidateIndex.candidates(
            for: memory,
            from: [restaurant, thermalBudget, localAI, remember],
            links: [graphLink]
        )

        #expect(candidates.first?.page.id == localAI.id)
        #expect(candidates.contains(where: { $0.page.id == remember.id }))
        #expect(candidates.contains(where: { $0.page.id == thermalBudget.id }))
        #expect(!candidates.contains(where: { $0.page.id == restaurant.id }))
    }

    @Test func livingWikiCandidateIndexUsesSemanticsWithoutLosingExactSignals() {
        let now = Date()
        let memory = indexedMemory(
            kind: .text,
            createdAt: now,
            title: "Inference architecture",
            summary: "All personal processing remains inside the handset.",
            tags: []
        )
        let onDevice = wikiPage(
            kind: .concept,
            title: "On-device AI",
            summary: "Private local model execution.",
            aliases: ["local inference"],
            updatedAt: now
        )
        let unrelated = wikiPage(
            kind: .concept,
            title: "Restaurant ideas",
            summary: "Places to eat.",
            aliases: [],
            updatedAt: now
        )

        let candidates = LivingWikiCandidateIndex.candidates(
            for: memory,
            from: [unrelated, onDevice],
            semanticScores: [onDevice.id: 0.91, unrelated.id: 0.08]
        )

        #expect(candidates.map(\.page.id) == [onDevice.id])
    }

    @Test func livingWikiParserRejectsInventedCandidateIDs() throws {
        let allowedID = UUID()
        let inventedID = UUID()
        let response = """
            ```json
            {"pages":[
              {"candidate_id":"\(allowedID.uuidString)","type":"project","title":"Remember","summary":"An on-device memory app.","aliases":["Remember app"],"effect":"updated","rationale":"Adds an implementation detail.","related_candidate_ids":[]},
              {"candidate_id":"\(inventedID.uuidString)","type":"concept","title":"Invented","summary":"Must be discarded.","aliases":[],"effect":"updated","rationale":"Unsafe reference.","related_candidate_ids":[]}
            ]}
            ```
            """

        let proposal = try WikiCompilationParser.parse(
            response: response,
            allowedCandidateIDs: [allowedID]
        )

        #expect(proposal.pages.count == 1)
        #expect(proposal.pages.first?.candidateID == allowedID)
    }

    @Test func livingWikiCompilationIsVersionedLinkedAndIdempotentlyQueued() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = indexedMemory(
            kind: .text,
            createdAt: now.addingTimeInterval(-10),
            title: "Remember plan",
            summary: "Build a private on-device memory app.",
            tags: ["project"]
        )
        let second = indexedMemory(
            kind: .text,
            createdAt: now,
            title: "Remember model choice",
            summary: "Use Gemma instead of a hosted API.",
            tags: ["decision"]
        )
        try await store.insertIfNeeded(first)
        try await store.insertIfNeeded(second)
        try await store.prepareWikiCompilationQueue()
        #expect(try await store.fetchWikiQueueSummary().pending == 2)

        #expect(try await store.claimNextWikiCompilation()?.id == first.id)
        let initial = WikiCompilationProposal(pages: [
            WikiPageProposal(
                candidateID: nil,
                kind: .project,
                title: "Remember",
                summary: "A private on-device memory app.",
                aliases: ["Remember app"],
                effect: .introduced,
                rationale: "The source establishes the project and its goal.",
                relatedCandidateIDs: []
            ),
            WikiPageProposal(
                candidateID: nil,
                kind: .concept,
                title: "On-device AI",
                summary: "AI processing that remains on the user's device.",
                aliases: ["local AI"],
                effect: .introduced,
                rationale: "The project depends on local inference.",
                relatedCandidateIDs: []
            ),
        ])
        try await store.applyWikiCompilation(
            memoryID: first.id,
            sourceUpdatedAt: first.updatedAt,
            proposal: initial,
            allowedCandidateIDs: []
        )

        let createdPages = try await store.fetchWikiPages()
        let project = try #require(createdPages.first(where: { $0.kind == .project }))
        let concept = try #require(createdPages.first(where: { $0.kind == .concept }))
        #expect(try await store.claimNextWikiCompilation()?.id == second.id)
        let update = WikiCompilationProposal(pages: [
            WikiPageProposal(
                candidateID: project.id,
                kind: .project,
                title: "Remember",
                summary: "A private on-device memory app using Gemma rather than a hosted model.",
                aliases: [],
                effect: .updated,
                rationale: "The source records the model architecture decision.",
                relatedCandidateIDs: [concept.id]
            ),
        ])
        try await store.applyWikiCompilation(
            memoryID: second.id,
            sourceUpdatedAt: second.updatedAt,
            proposal: update,
            allowedCandidateIDs: [project.id, concept.id]
        )

        let snapshot = try #require(try await store.fetchWikiPageSnapshot(id: project.id))
        #expect(snapshot.page.revisionNumber == 2)
        #expect(snapshot.evidence.count == 2)
        #expect(snapshot.revisions.map(\.revisionNumber) == [2, 1])
        #expect(snapshot.linkedPages.map(\.page.id) == [concept.id])
        #expect(try await store.fetchWikiEvidenceMemories(pageIDs: [project.id]).map(\.id) == [second.id, first.id])
        #expect(try await store.fetchWikiQueueSummary().pending == 0)

        try await store.prepareWikiCompilationQueue()
        #expect(try await store.fetchWikiQueueSummary().pending == 0)
    }

    @Test func projectMemoryProgramExposesProjectSpecificSchema() {
        let program = ProjectMemoryProgram.current

        #expect(program.name == "Private Project Memory")
        #expect(program.pageKinds.contains(.decision))
        #expect(program.pageKinds.contains(.experiment))
        #expect(program.pageKinds.contains(.feedback))
        #expect(program.pageKinds.contains(.person))
        #expect(program.promptTypeList.contains("open_question"))
    }

    @Test func protectedPatchEvaluatorKeepsSafePatchAndDiscardsDuplicateTargets() {
        let validPage = WikiPageProposal(
            candidateID: nil,
            kind: .decision,
            title: "Use local inference",
            summary: "The project uses local Gemma inference.",
            aliases: [],
            effect: .introduced,
            rationale: "The source explicitly records the model choice.",
            relatedCandidateIDs: []
        )

        let kept = ProjectMemoryPatchEvaluator.evaluate(
            proposal: WikiCompilationProposal(pages: [validPage]),
            allowedCandidateIDs: []
        )
        let discarded = ProjectMemoryPatchEvaluator.evaluate(
            proposal: WikiCompilationProposal(pages: [validPage, validPage]),
            allowedCandidateIDs: []
        )

        #expect(kept.status == .kept)
        #expect(kept.proposalToApply.pages.count == 1)
        #expect(kept.checks.allSatisfy { $0.passed })
        #expect(discarded.status == .discarded)
        #expect(discarded.proposalToApply.pages.isEmpty)
        #expect(discarded.checks.contains { $0.checkID == "patch.unique_targets" && !$0.passed })
    }

    @Test func projectMemoryLinterReportsTraceabilityAndRevisionIntegrity() {
        let page = wikiPage(
            kind: .project,
            title: "Remember",
            summary: "A private project memory.",
            aliases: [],
            updatedAt: Date()
        )

        let checks = ProjectMemoryLinter.checks(
            pages: [page],
            evidence: [],
            revisions: [],
            links: []
        )

        #expect(checks.contains { $0.checkID == "wiki.source_traceability" && !$0.passed })
        #expect(checks.contains { $0.checkID == "wiki.revision_integrity" && !$0.passed })
        #expect(checks.contains { $0.checkID == "wiki.link_integrity" && $0.passed })
    }

    @Test func researchHistoryLinksAcceptedPatchChecksAndOpenMarkdown() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let memory = indexedMemory(
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            title: "Model choice",
            summary: "Use Gemma locally instead of a hosted API.",
            tags: ["decision"]
        )
        try await store.insertIfNeeded(memory)
        try await store.prepareWikiCompilationQueue()
        _ = try await store.claimNextWikiCompilation()
        let proposal = WikiCompilationProposal(pages: [
            WikiPageProposal(
                candidateID: nil,
                kind: .decision,
                title: "Use Gemma on-device",
                summary: "The project uses Gemma on-device rather than a hosted API.",
                aliases: [],
                effect: .introduced,
                rationale: "The source records the privacy architecture decision.",
                relatedCandidateIDs: []
            ),
        ])
        let decision = ProjectMemoryPatchEvaluator.evaluate(proposal: proposal, allowedCandidateIDs: [])
        let runID = try await store.startProjectMemoryRun(
            operation: .compile,
            memoryID: memory.id,
            modelVersion: "test-model",
            promptVersion: "test-prompt"
        )
        try await store.applyWikiCompilation(
            memoryID: memory.id,
            sourceUpdatedAt: memory.updatedAt,
            proposal: decision.proposalToApply,
            allowedCandidateIDs: [],
            runID: runID
        )
        try await store.finishProjectMemoryRun(
            id: runID,
            status: decision.status,
            proposedPageCount: proposal.pages.count,
            acceptedPageCount: decision.proposalToApply.pages.count,
            rationale: decision.rationale,
            checks: decision.checks
        )

        let history = try await store.fetchProjectMemoryHistory()
        let run = try #require(history.first)
        #expect(run.run.status == .kept)
        #expect(run.memoryTitle == "Model choice")
        #expect(run.checks.count == 5)
        #expect(run.changes.first?.pageTitle == "Use Gemma on-device")

        let markdown = ProjectMemoryMarkdownRenderer.render(
            pages: try await store.fetchAllWikiPageSnapshots(),
            history: history,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        #expect(markdown.contains("format: remember-project-memory"))
        #expect(markdown.contains("# Project Memory"))
        #expect(markdown.contains("Use Gemma on-device"))
        #expect(markdown.contains("## Research History"))
        #expect(markdown.contains("test-prompt"))
    }

    private func makeTemporaryModelDirectory(excluding excludedFilename: String? = nil) throws -> URL {
        let directory = try makeTemporaryDirectory()

        for filename in GemmaModelBundle.requiredFiles where filename != excludedFilename {
            let file = directory.appendingPathComponent(filename, isDirectory: false)
            try Data().write(to: file)
        }

        return directory
    }

    private func indexedMemory(
        kind: MemoryKind,
        createdAt: Date,
        title: String,
        summary: String,
        tags: [String]
    ) -> MemoryItem {
        let id = UUID()
        return MemoryItem(
            id: id,
            kind: kind,
            createdAt: createdAt,
            importedAt: createdAt,
            updatedAt: createdAt,
            state: .indexed,
            originalFilename: "\(id.uuidString).dat",
            userCaption: nil,
            title: title,
            summary: summary,
            extractedText: summary,
            tagsJSON: MemoryItem.encodeTags(tags),
            processingError: nil,
            modelVersion: "test-model"
        )
    }

    private func wikiPage(
        kind: WikiPageKind,
        title: String,
        summary: String,
        aliases: [String],
        updatedAt: Date
    ) -> WikiPage {
        WikiPage(
            id: UUID(),
            kind: kind,
            title: title,
            normalizedTitle: title.lowercased(),
            summary: summary,
            aliasesJSON: WikiPage.encodeAliases(aliases),
            createdAt: updatedAt,
            updatedAt: updatedAt,
            revisionNumber: 1
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

}

private nonisolated struct StubTextEmbedding: TextEmbedding {
    let modelIdentifier = "stub-embedding-v1"
    let vector: @Sendable (String) -> [Float]

    init(vector: @escaping @Sendable (String) -> [Float]) {
        self.vector = vector
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map(vector)
    }
}
