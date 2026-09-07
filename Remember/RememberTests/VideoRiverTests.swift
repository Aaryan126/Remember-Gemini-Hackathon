import AVFoundation
import Foundation
import Testing
@testable import Remember

struct VideoRiverTests {
    @Test func videoImportPreservesBytesKindAndHistoryExactlyOnce() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.mov")
        let bytes = Data("opaque movie storage fixture".utf8)
        try bytes.write(to: source)
        let inbox = CaptureInbox(containerURL: root.appendingPathComponent("Inbox"))
        let service = InAppCaptureService(inbox: inbox)
        try service.saveVideo(from: source, context: "  River waterfall  ")
        let record = try #require(inbox.records().first)
        #expect(record.kind == .video)
        #expect(record.caption == "River waterfall")
        let files = try LibraryFileStore(directoryURL: root.appendingPathComponent("Originals"))
        let store = try MemoryStore(databaseURL: root.appendingPathComponent("db.sqlite"))
        let importer = CaptureImporter(inbox: inbox, fileStore: files, memoryStore: store)
        #expect(try await importer.importPending() == 1)
        #expect(try await importer.importPending() == 0)
        let memory = try #require(await store.fetchAll().first)
        #expect(memory.kind == .video)
        #expect(try Data(contentsOf: files.url(for: memory.originalFilename)) == bytes)
        let events = try await store.provenanceEvents()
        #expect(events.count == 1)
        #expect(events.first?.riverSource?.kind == .video)
        #expect(try ProvenanceSnapshot.replay(events).memories[memory.id]?.originalFilename == memory.originalFilename)
        try await store.setArchived(id: memory.id, archived: true)
        try await store.setArchived(id: memory.id, archived: false)
        #expect(try Data(contentsOf: files.url(for: memory.originalFilename)) == bytes)
    }

    @Test func riverEmbedsOnlyOriginalEventsAndKeepsRevisionIdentity() throws {
        for kind: MemoryKind in [.image, .audio, .video, .text] {
            let original = memory(kind: kind, filename: "old.mov")
            var revised = original
            revised.originalFilename = "new.mov"
            let capture = try ProvenanceEvent(kind: .capture, memoryID: original.id, payload: ProvenancePayload(memory: original))
            let revision = try ProvenanceEvent(kind: .revision, memoryID: original.id, payload: ProvenancePayload(memory: revised))
            #expect(capture.riverSource?.originalFilename == "old.mov")
            #expect(revision.riverSource?.originalFilename == "new.mov")
            var state = ProvenanceSnapshot()
            state.memories[original.id] = revised
            #expect(capture.riverMemory(in: state)?.originalFilename == "old.mov")
            revised.title = "Updated title"
            state.memories[original.id] = revised
            #expect(revision.riverMemory(in: state)?.title == "Updated title")
            for eventKind: ProvenanceKind in [.metadata, .enrichment, .processing, .archive, .restore, .placement] {
                let event = try ProvenanceEvent(kind: eventKind, payload: ProvenancePayload(memory: revised))
                #expect(event.riverSource == nil)
            }
            #expect(try ProvenanceEvent(kind: .imported, payload: ProvenancePayload(memory: original)).riverSource != nil)
        }
    }

    @Test func videoAnalysisUsesOnlyCaptionEvenWhenCloudEnabled() async throws {
        let item = memory(kind: .video, filename: "not-read.mov", caption: "Waterfall near the trail")
        let result = try await LocalCaptureAnalyzer(
            cloudEnabled: { true }, cloudAnalyzer: RejectCloud()
        ).analyze(memory: item, originalURL: URL(fileURLWithPath: "/missing/not-read.mov"), supportingText: nil)
        #expect(result.isPartial)
        #expect(result.extractedText == "Waterfall near the trail")
        #expect(result.chunks.first?.locator == "Video caption")
        #expect(result.chunks.first?.extractionMethod == .plainText)
        let empty = try await MemoryContentExtractor().extract(
            memory: memory(kind: .video, filename: "missing.mov"),
            originalURL: URL(fileURLWithPath: "/missing.mov"), supportingText: "not a transcript"
        )
        #expect(empty.text.isEmpty && empty.chunks.isEmpty && empty.isPartial)
    }

    @Test func videoTransferCopiesToIndependentFileAndRejectsNonMovies() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.mp4")
        let bytes = Data([1, 2, 3])
        try bytes.write(to: source)
        let copy = try PhotoVideoTransfer.temporaryCopy(of: source)
        defer { try? FileManager.default.removeItem(at: copy) }
        #expect(copy != source && copy.pathExtension == "mp4")
        try FileManager.default.removeItem(at: source)
        #expect(try Data(contentsOf: copy) == bytes)
        #expect(throws: InAppCaptureError.unsupportedFile) {
            try PhotoVideoTransfer.temporaryCopy(of: root.appendingPathComponent("note.txt"))
        }
    }

    @Test func playableMovieValidationAndMissingFileFailure() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
        let frame = try #require(buffer)
        CVPixelBufferLockBaseAddress(frame, [])
        memset(CVPixelBufferGetBaseAddress(frame), 128, CVPixelBufferGetDataSize(frame))
        CVPixelBufferUnlockBaseAddress(frame, [])
        #expect(adaptor.append(frame, withPresentationTime: .zero))
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
        await writer.finishWriting()
        #expect(writer.status == .completed)
        try await LocalVideoAsset.validate(url)
        let corrupt = root.appendingPathComponent("corrupt.mov")
        try Data("not a movie".utf8).write(to: corrupt)
        await #expect(throws: Error.self) { try await LocalVideoAsset.validate(corrupt) }
        #expect(FileManager.default.fileExists(atPath: corrupt.path))
        await #expect(throws: Error.self) { try await LocalVideoAsset.validate(root.appendingPathComponent("missing.mov")) }
        await #expect(throws: VideoImportError.self) { try await LocalVideoAsset.validate(URL(string: "https://example.com/clip.mov")!) }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoRiverTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func memory(kind: MemoryKind, filename: String, caption: String? = nil) -> MemoryItem {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return MemoryItem(id: UUID(), kind: kind, createdAt: date, importedAt: date, updatedAt: date,
            state: .captured, originalFilename: filename, userCaption: caption, title: nil,
            summary: nil, extractedText: nil, tagsJSON: "[]", processingError: nil, modelVersion: nil)
    }
}

private struct RejectCloud: MemoryAnalyzing {
    func analyze(memory: MemoryItem, originalURL: URL, supportingText: String?) async throws -> MemoryAnalysisResult {
        Issue.record("Video import must not invoke a cloud analyzer")
        throw VideoImportError.unplayable
    }
}
