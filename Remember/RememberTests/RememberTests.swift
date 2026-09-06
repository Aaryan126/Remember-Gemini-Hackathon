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

    @Test func noteDocumentSeparatesAHeadlineFromItsBody() {
        let note = NoteDocument(text: "Trip ideas\nVisit Kyoto\nBook a hotel")

        #expect(note.title == "Trip ideas")
        #expect(note.body == "Visit Kyoto\nBook a hotel")
        #expect(note.text == "Trip ideas\nVisit Kyoto\nBook a hotel")
        #expect(NoteDocument(title: "  Trip ideas  ", body: "  Visit Kyoto  ").text == "Trip ideas\nVisit Kyoto")
    }

    @Test func chunksLongDocumentsWithStableLocatorsAndOverlap() {
        let paragraphs = (1...18).map { index in
            "Paragraph \(index). " + String(repeating: "useful project evidence ", count: 8)
        }.joined(separator: "\n\n")

        let chunks = MemoryTextChunker.chunks(
            from: paragraphs,
            locatorPrefix: "PDF page 7",
            extractionMethod: .pdfText
        )

        #expect(chunks.count > 1)
        #expect(chunks.map(\.ordinal) == Array(chunks.indices))
        #expect(chunks.allSatisfy { $0.locator.hasPrefix("PDF page 7") })
        #expect(chunks.allSatisfy { !$0.text.isEmpty && $0.text.count <= 1_200 })
    }

    @Test func imageClassificationBecomesSearchableEvidenceAndBasicModeMetadata() {
        let labels = VisionImageClassifier.normalizedLabels([
            VisionImageLabel(identifier: " pet ", confidence: 0.72),
            VisionImageLabel(identifier: "cat, true cat", confidence: 0.96),
            VisionImageLabel(identifier: "CAT, TRUE CAT", confidence: 0.80),
            VisionImageLabel(identifier: "", confidence: 0.99),
            VisionImageLabel(identifier: "noise", confidence: .nan),
        ])
        #expect(labels.map(\.identifier) == ["cat, true cat", "pet"])

        let extracted = MemoryContentExtractor.imageContent(
            recognizedText: "Milo",
            visualLabels: labels
        )
        #expect(extracted.text.contains("cat, true cat"))
        #expect(extracted.text.contains("Milo"))
        #expect(extracted.chunks.map(\.locator) == ["Image labels", "Image text"])
        #expect(extracted.chunks.map(\.extractionMethod) == [.visionClassification, .visionOCR])

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let memory = MemoryItem(
            id: UUID(),
            kind: .image,
            createdAt: now,
            importedAt: now,
            updatedAt: now,
            state: .processing,
            originalFilename: "cat.jpg",
            userCaption: nil,
            title: nil,
            summary: nil,
            extractedText: nil,
            tagsJSON: "[]",
            processingError: nil,
            modelVersion: nil
        )
        let result = DeterministicMemoryAnalyzer.result(memory: memory, extracted: extracted)
        #expect(result.title == "Cat")
        #expect(result.tags == ["cat", "pet"])
    }

    @Test func citationVerifierRequiresAnExactSourceExcerpt() {
        let source = "The approved primary brand color is cobalt blue."

        #expect(GroundedEvidenceVerifier.quoteAppears("primary brand color is cobalt blue", in: source))
        #expect(!GroundedEvidenceVerifier.quoteAppears("Primary brand color is cobalt blue", in: source))
        #expect(!GroundedEvidenceVerifier.quoteAppears("primary brand color is orange", in: source))
        #expect(!GroundedEvidenceVerifier.quoteAppears("the", in: source))
    }


    @Test func openAIGroundedQuoteParserRequiresStructuredClaims() {
        let response = #"{"claims":[{"evidence_id":"e2","evidence_quote":"The chosen color is cobalt blue."}]}"#
        #expect(OpenAIGroundedQuoteParser.parse(response: response) == [
            OpenAIGroundedQuoteParser.Claim(
                evidenceID: "E2",
                evidenceQuote: "The chosen color is cobalt blue."
            ),
        ])
        #expect(OpenAIGroundedQuoteParser.parse(response: "not json").isEmpty)
    }
    @Test func openAIExtractiveFallbackRequiresOneSourceAndStrongQuestionOverlap() {
        let match = OpenAIExtractiveFallback.bestMatch(
            question: "Which room is the workshop in?",
            sourceTexts: ["DESIGN WORKSHOP — ROOM B-214 — 2:30 PM"]
        )
        #expect(match == OpenAIExtractiveFallback.Match(
            sourceIndex: 0,
            quote: "DESIGN WORKSHOP — ROOM B-214 — 2:30 PM"
        ))

        #expect(OpenAIExtractiveFallback.bestMatch(
            question: "What does appendix C require?",
            sourceTexts: ["The document was only partially extracted. Appendix C was not readable."]
        ) == nil)
        #expect(OpenAIExtractiveFallback.bestMatch(
            question: "What price did we settle on?",
            sourceTexts: ["The price was $9.", "The price was later changed to $12."]
        ) == nil)
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

    @Test func inAppCaptureTrimsAndBoundsNotes() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let inbox = CaptureInbox(containerURL: container)
        let service = InAppCaptureService(inbox: inbox)
        let oversized = "  " + String(repeating: "a", count: InAppCaptureService.maximumNoteLength + 50) + "  "

        try service.saveNote(oversized)

        let record = try #require(inbox.records().first)
        let savedText = try String(contentsOf: inbox.payloadURL(for: record), encoding: .utf8)
        #expect(record.kind == .text)
        #expect(savedText.count == InAppCaptureService.maximumNoteLength)
        #expect(savedText.allSatisfy { $0 == "a" })
    }

    @Test func inAppCaptureRejectsEmptyNotesAndNonWebLinks() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let service = InAppCaptureService(inbox: CaptureInbox(containerURL: container))

        #expect(throws: InAppCaptureError.emptyNote) {
            try service.saveNote(" \n ")
        }
        #expect(throws: InAppCaptureError.invalidLink) {
            try service.saveLink("javascript:alert(1)", context: nil)
        }
    }

    @Test func inAppCaptureImportsPlainTextFiles() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let source = container.appendingPathComponent("project-notes.txt")
        try Data("  Decision: keep capture local.  ".utf8).write(to: source)
        let inbox = CaptureInbox(containerURL: container)
        let service = InAppCaptureService(inbox: inbox)

        try service.saveImportedFile(from: source)

        let record = try #require(inbox.records().first)
        #expect(record.kind == .text)
        #expect(record.caption == "Decision: keep capture local.")
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

    @Test func memoryStorePersistsEditedNoteContentAndRefreshesItsChunks() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("remember.sqlite"))
        let id = UUID()
        let now = Date()
        let item = MemoryItem(
            id: id,
            kind: .text,
            createdAt: now,
            importedAt: now,
            updatedAt: now,
            state: .indexed,
            originalFilename: "\(id.uuidString).txt",
            userCaption: "Old note",
            title: "Old note",
            summary: "Old note",
            extractedText: "Old note",
            tagsJSON: "[]",
            processingError: nil,
            modelVersion: "test-model"
        )
        try await store.insertIfNeeded(item)

        let document = NoteDocument(
            title: "Trip ideas",
            body: "Visit Kyoto\nBook a hotel"
        )
        try await store.updateNoteContent(id: id, document: document)

        let updated = try await store.fetch(id: id)
        #expect(updated?.title == "Trip ideas")
        #expect(updated?.summary == "Visit Kyoto\nBook a hotel")
        #expect(updated?.userCaption == document.text)
        #expect(updated?.extractedText == document.text)
        #expect(updated?.state == .indexed)

        let chunks = try await store.fetchChunks(memoryID: id)
        #expect(chunks.count == 1)
        #expect(chunks.first?.text == document.text)
        #expect(chunks.first?.locator == "Saved note")
    }

    @Test func parsesMemoryAnalysisJSONEvenWhenWrappedInMarkdown() {
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

    @Test func expandedSearchRanksRelevantMemoryAndPersistsProviderNeutralIndex() async throws {
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
        #expect(records.allSatisfy { $0.embeddingModel == "remember-memory-fields-v2" })
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

    @Test func parsesOpenAIQueryExpansionAndBoundsTerms() {
        let terms = OpenAIQueryExpansionParser.parse(
            response: #"{"terms":["Lecture room","seminar","University","seminar",""]}"#,
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
