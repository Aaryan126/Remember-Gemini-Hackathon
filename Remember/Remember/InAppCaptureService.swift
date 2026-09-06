import Foundation
import UniformTypeIdentifiers

nonisolated enum CaptureAction: String, CaseIterable, Identifiable, Sendable {
    case note
    case camera
    case photo
    case file
    case link
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: "New Note"
        case .camera: "Take Photo"
        case .photo: "Choose Photo"
        case .file: "Import File"
        case .link: "Save Link"
        case .voice: "Record Voice"
        }
    }

    var systemImage: String {
        switch self {
        case .note: "square.and.pencil"
        case .camera: "camera"
        case .photo: "photo.on.rectangle"
        case .file: "doc.badge.plus"
        case .link: "link"
        case .voice: "mic"
        }
    }
}

nonisolated protocol InAppCaptureServing: Sendable {
    func saveNote(_ text: String) throws
    func saveLink(_ urlText: String, context: String?) throws
    func saveImage(from sourceURL: URL, context: String?) throws
    func saveImportedFile(from sourceURL: URL) throws
}

nonisolated enum InAppCaptureError: LocalizedError, Equatable {
    case emptyNote
    case invalidLink
    case unsupportedFile
    case unreadableTextFile

    var errorDescription: String? {
        switch self {
        case .emptyNote:
            "Write something before saving this note."
        case .invalidLink:
            "Enter a complete HTTP or HTTPS link."
        case .unsupportedFile:
            "Remember can import an image, PDF, or plain-text file."
        case .unreadableTextFile:
            "Remember could not read this text file."
        }
    }
}

nonisolated struct InAppCaptureService: InAppCaptureServing {
    static let maximumNoteLength = 20_000

    private let inbox: CaptureInbox

    init(inbox: CaptureInbox) {
        self.inbox = inbox
    }

    func saveNote(_ text: String) throws {
        let normalized = Self.normalized(text)
        guard !normalized.isEmpty else { throw InAppCaptureError.emptyNote }
        _ = try inbox.saveText(String(normalized.prefix(Self.maximumNoteLength)))
    }

    func saveLink(_ urlText: String, context: String?) throws {
        let normalized = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              let url = components.url else {
            throw InAppCaptureError.invalidLink
        }
        _ = try inbox.saveURL(url, caption: Self.optional(context))
    }

    func saveImage(from sourceURL: URL, context: String?) throws {
        _ = try inbox.saveImage(from: sourceURL, caption: Self.optional(context))
    }

    func saveImportedFile(from sourceURL: URL) throws {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let contentType = try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        let inferredType = contentType ?? UTType(filenameExtension: sourceURL.pathExtension)
        guard let inferredType else { throw InAppCaptureError.unsupportedFile }

        if inferredType.conforms(to: .image) {
            _ = try inbox.saveImage(from: sourceURL, caption: nil)
        } else if inferredType.conforms(to: .pdf) {
            _ = try inbox.savePDF(from: sourceURL, caption: nil)
        } else if inferredType.conforms(to: .plainText) || inferredType.conforms(to: .text) {
            guard let text = try? String(contentsOf: sourceURL, encoding: .utf8) else {
                throw InAppCaptureError.unreadableTextFile
            }
            try saveNote(text)
        } else {
            throw InAppCaptureError.unsupportedFile
        }
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func optional(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = normalized(text)
        return normalized.isEmpty ? nil : String(normalized.prefix(maximumNoteLength))
    }
}
