import Foundation

nonisolated struct LibraryFileStore: Sendable {
    let directoryURL: URL
    private var fileManager: FileManager { .default }

    init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: Self.protectedAttributes
        )
    }

    func importPayload(for record: CapturedItemRecord, from sourceURL: URL) throws -> String {
        try importFile(id: record.id, from: sourceURL)
    }

    func importFile(id: UUID, from sourceURL: URL) throws -> String {
        let fileExtension = Self.safeExtension(sourceURL.pathExtension)
        let filename = fileExtension.isEmpty
            ? id.uuidString
            : "\(id.uuidString).\(fileExtension)"
        let finalURL = directoryURL.appendingPathComponent(filename, isDirectory: false)

        if fileManager.fileExists(atPath: finalURL.path) {
            return filename
        }

        let stagingURL = directoryURL.appendingPathComponent(".\(filename).staging")
        do {
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            try fileManager.setAttributes(Self.protectedAttributes, ofItemAtPath: stagingURL.path)
            try fileManager.moveItem(at: stagingURL, to: finalURL)
            return filename
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    func url(for filename: String) -> URL {
        directoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    func remove(filename: String) throws {
        let root = directoryURL.standardizedFileURL
        let target = url(for: filename).standardizedFileURL
        guard target.deletingLastPathComponent() == root else {
            return
        }
        guard fileManager.fileExists(atPath: target.path) else {
            return
        }
        try fileManager.removeItem(at: target)
    }

    static func defaultDirectory(fileManager: FileManager = .default) throws -> URL {
        let databaseURL = try MemoryStore.defaultDatabaseURL(fileManager: fileManager)
        return databaseURL.deletingLastPathComponent().appendingPathComponent("Originals", isDirectory: true)
    }

    private static var protectedAttributes: [FileAttributeKey: Any] {
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    }

    private static func safeExtension(_ value: String) -> String {
        let candidate = value.lowercased()
        guard
            candidate.count <= 10,
            candidate.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
        else {
            return ""
        }
        return candidate
    }
}
