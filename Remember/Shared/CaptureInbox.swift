import Foundation

nonisolated enum RememberAppGroup {
    static let identifier = "group.SimpleStudio.Remember"
}

nonisolated enum CaptureKind: String, Codable, Sendable {
    case image
    case video
    case link
    case pdf
    case text
}

nonisolated enum CaptureState: String, Codable, Sendable {
    case captured
}

nonisolated struct CapturedItemRecord: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let kind: CaptureKind
    let state: CaptureState
    let caption: String?
    let payloadFilename: String
}

nonisolated enum CaptureInboxError: LocalizedError, Equatable {
    case appGroupUnavailable(String)
    case emptyText
    case missingPayload(UUID)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let identifier):
            return "The shared container \(identifier) is unavailable. Check that the App Groups capability is enabled for both targets."
        case .emptyText:
            return "There is no photo or text to save."
        case .missingPayload(let id):
            return "The captured item \(id.uuidString) is missing its saved content."
        }
    }
}

nonisolated struct CaptureInbox: Sendable {
    private static let schemaVersion = 1
    private static let inboxDirectoryName = "CaptureInbox"
    private static let metadataFilename = "metadata.json"
    private static let maximumCaptionLength = 20_000

    private let containerURL: URL
    private var fileManager: FileManager { .default }

    init(containerURL: URL) {
        self.containerURL = containerURL
    }

    static func appGroup(fileManager: FileManager = .default) throws -> CaptureInbox {
        if let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: RememberAppGroup.identifier
        ) {
            return CaptureInbox(containerURL: containerURL)
        }

        #if targetEnvironment(simulator)
        // Command-line simulator builds may be installed without signed App Group
        // entitlements. Keep in-app capture usable instead of failing at launch.
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let fallbackURL = applicationSupportURL
            .appendingPathComponent("Remember", isDirectory: true)
            .appendingPathComponent("SimulatorCaptureContainer", isDirectory: true)
        return CaptureInbox(containerURL: fallbackURL)
        #else
        throw CaptureInboxError.appGroupUnavailable(RememberAppGroup.identifier)
        #endif
    }

    @discardableResult
    func saveImage(from sourceURL: URL, caption: String?) throws -> CapturedItemRecord {
        try saveFile(from: sourceURL, kind: .image, caption: caption)
    }

    @discardableResult
    func saveVideo(from sourceURL: URL, caption: String?) throws -> CapturedItemRecord {
        try saveFile(from: sourceURL, kind: .video, caption: caption)
    }

    @discardableResult
    func savePDF(from sourceURL: URL, caption: String?) throws -> CapturedItemRecord {
        try saveFile(from: sourceURL, kind: .pdf, caption: caption, preferredExtension: "pdf")
    }

    @discardableResult
    func saveURL(_ url: URL, caption: String?) throws -> CapturedItemRecord {
        try saveTextPayload(
            url.absoluteString,
            kind: .link,
            caption: Self.normalizedText(caption) ?? url.absoluteString,
            payloadFilename: "content.url.txt"
        )
    }

    private func saveFile(
        from sourceURL: URL,
        kind: CaptureKind,
        caption: String?,
        preferredExtension: String? = nil
    ) throws -> CapturedItemRecord {
        let id = UUID()
        let payloadFilename = "content.\(preferredExtension ?? Self.safeExtension(for: sourceURL))"
        let record = CapturedItemRecord(
            schemaVersion: Self.schemaVersion,
            id: id,
            createdAt: Date(),
            kind: kind,
            state: .captured,
            caption: Self.normalizedText(caption),
            payloadFilename: payloadFilename
        )

        return try persist(record: record) { payloadURL in
            try fileManager.copyItem(at: sourceURL, to: payloadURL)
            try fileManager.setAttributes(Self.protectedAttributes, ofItemAtPath: payloadURL.path)
        }
    }

    @discardableResult
    func saveText(_ text: String) throws -> CapturedItemRecord {
        guard let normalizedText = Self.normalizedText(text) else {
            throw CaptureInboxError.emptyText
        }

        return try saveTextPayload(
            normalizedText,
            kind: .text,
            caption: normalizedText,
            payloadFilename: "content.txt"
        )
    }

    private func saveTextPayload(
        _ text: String,
        kind: CaptureKind,
        caption: String?,
        payloadFilename: String
    ) throws -> CapturedItemRecord {
        let record = CapturedItemRecord(
            schemaVersion: Self.schemaVersion,
            id: UUID(),
            createdAt: Date(),
            kind: kind,
            state: .captured,
            caption: caption,
            payloadFilename: payloadFilename
        )

        return try persist(record: record) { payloadURL in
            try Data(text.utf8).write(
                to: payloadURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        }
    }

    func records() throws -> [CapturedItemRecord] {
        let inboxURL = try ensureInboxDirectory()
        let candidateURLs = try fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return candidateURLs.compactMap { directoryURL in
            guard
                (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                !directoryURL.lastPathComponent.hasSuffix(".staging"),
                let record = try? decodeRecord(in: directoryURL),
                isValid(record: record, in: directoryURL)
            else {
                return nil
            }
            return record
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func payloadURL(for record: CapturedItemRecord) throws -> URL {
        let directoryURL = try ensureInboxDirectory()
            .appendingPathComponent(record.id.uuidString, isDirectory: true)
        guard isValid(record: record, in: directoryURL) else {
            throw CaptureInboxError.missingPayload(record.id)
        }
        return directoryURL.appendingPathComponent(record.payloadFilename, isDirectory: false)
    }

    func remove(_ record: CapturedItemRecord) throws {
        let inboxURL = try ensureInboxDirectory().standardizedFileURL
        let directoryURL = inboxURL
            .appendingPathComponent(record.id.uuidString, isDirectory: true)
            .standardizedFileURL
        guard directoryURL.deletingLastPathComponent() == inboxURL else {
            throw CaptureInboxError.missingPayload(record.id)
        }
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }
        try fileManager.removeItem(at: directoryURL)
    }

    private func persist(
        record: CapturedItemRecord,
        writePayload: (URL) throws -> Void
    ) throws -> CapturedItemRecord {
        let inboxURL = try ensureInboxDirectory()
        let stagingURL = inboxURL.appendingPathComponent(
            ".\(record.id.uuidString).staging",
            isDirectory: true
        )
        let finalURL = inboxURL.appendingPathComponent(record.id.uuidString, isDirectory: true)

        try fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false,
            attributes: Self.protectedAttributes
        )

        do {
            let payloadURL = stagingURL.appendingPathComponent(record.payloadFilename, isDirectory: false)
            try writePayload(payloadURL)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let metadata = try encoder.encode(record)
            try metadata.write(
                to: stagingURL.appendingPathComponent(Self.metadataFilename),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )

            try fileManager.moveItem(at: stagingURL, to: finalURL)
            return record
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private func ensureInboxDirectory() throws -> URL {
        let inboxURL = containerURL.appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true,
            attributes: Self.protectedAttributes
        )
        return inboxURL
    }

    private func decodeRecord(in directoryURL: URL) throws -> CapturedItemRecord {
        let metadataURL = directoryURL.appendingPathComponent(Self.metadataFilename, isDirectory: false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CapturedItemRecord.self, from: Data(contentsOf: metadataURL))
    }

    private func isValid(record: CapturedItemRecord, in directoryURL: URL) -> Bool {
        guard
            record.schemaVersion == Self.schemaVersion,
            directoryURL.lastPathComponent == record.id.uuidString,
            Self.isSafeFilename(record.payloadFilename)
        else {
            return false
        }

        let payloadURL = directoryURL.appendingPathComponent(record.payloadFilename, isDirectory: false)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: payloadURL.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private static var protectedAttributes: [FileAttributeKey: Any] {
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(maximumCaptionLength))
    }

    private static func safeExtension(for sourceURL: URL) -> String {
        let candidate = sourceURL.pathExtension.lowercased()
        let allowed = CharacterSet.alphanumerics
        guard
            !candidate.isEmpty,
            candidate.count <= 10,
            candidate.unicodeScalars.allSatisfy(allowed.contains)
        else {
            return "bin"
        }
        return candidate
    }

    private static func isSafeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename == URL(fileURLWithPath: filename).lastPathComponent
            && filename != "."
            && filename != ".."
    }
}
