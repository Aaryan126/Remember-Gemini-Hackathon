import Foundation

actor CaptureImporter {
    private let inbox: CaptureInbox
    private let fileStore: LibraryFileStore
    private let memoryStore: MemoryStore

    init(inbox: CaptureInbox, fileStore: LibraryFileStore, memoryStore: MemoryStore) {
        self.inbox = inbox
        self.fileStore = fileStore
        self.memoryStore = memoryStore
    }

    @discardableResult
    func importPending() async throws -> Int {
        var importedCount = 0

        for capture in try inbox.records() {
            if try await memoryStore.contains(id: capture.id) {
                try inbox.remove(capture)
                continue
            }

            let sourceURL = try inbox.payloadURL(for: capture)
            let filename = try fileStore.importPayload(for: capture, from: sourceURL)
            let now = Date()
            let memory = MemoryItem(
                id: capture.id,
                kind: MemoryKind(rawValue: capture.kind.rawValue) ?? .text,
                createdAt: capture.createdAt,
                importedAt: now,
                updatedAt: now,
                state: .captured,
                originalFilename: filename,
                userCaption: capture.caption,
                title: nil,
                summary: nil,
                extractedText: nil,
                tagsJSON: "[]",
                processingError: nil,
                modelVersion: nil
            )
            try await memoryStore.insertIfNeeded(memory)
            try inbox.remove(capture)
            importedCount += 1
        }

        return importedCount
    }
}
