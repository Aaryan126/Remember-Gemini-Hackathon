//
//  ShareViewController.swift
//  RememberShareExtension
//
//  Created by Aaryan Kandiah on 21/8/26.
//

import Social
import UniformTypeIdentifiers
import UIKit

@MainActor
final class ShareViewController: SLComposeServiceViewController {
    private var isSaving = false

    override func isContentValid() -> Bool {
        !isSaving && (normalizedContentText != nil || sharedProviders.contains(where: isSupportedProvider))
    }

    override func didSelectPost() {
        guard !isSaving else {
            return
        }

        isSaving = true
        validateContent()

        Task {
            do {
                try await saveSharedContent()
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                isSaving = false
                validateContent()
                presentSaveError(error)
            }
        }
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    private var sharedProviders: [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
    }

    private var normalizedContentText: String? {
        Self.normalizedText(contentText)
    }

    private func isSupportedProvider(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
    }

    private func saveSharedContent() async throws {
        let inbox = try CaptureInbox.appGroup()
        let providers = sharedProviders
        let composeCaption = normalizedContentText

        if let imageProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) {
            let caption: String?
            if let composeCaption {
                caption = composeCaption
            } else {
                caption = try await loadFirstSharedText(from: providers)
            }
            try await saveFile(from: imageProvider, type: .image) { sourceURL in
                try inbox.saveImage(from: sourceURL, caption: caption)
            }
            return
        }

        if let pdfProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }) {
            try await saveFile(from: pdfProvider, type: .pdf) { sourceURL in
                try inbox.savePDF(from: sourceURL, caption: composeCaption)
            }
            return
        }

        if let sharedURL = try await loadFirstSharedURL(from: providers) {
            try inbox.saveURL(sharedURL, caption: composeCaption)
            return
        }

        let sharedText: String?
        if let composeCaption {
            sharedText = composeCaption
        } else {
            sharedText = try await loadFirstSharedText(from: providers)
        }
        guard let sharedText else {
            throw CaptureInboxError.emptyText
        }
        try inbox.saveText(sharedText)
    }

    private func saveFile(
        from provider: NSItemProvider,
        type: UTType,
        operation: @escaping @Sendable (URL) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { sourceURL, error in
                do {
                    if let error {
                        throw error
                    }
                    guard let sourceURL else {
                        throw ShareCaptureError.missingSharedFile
                    }
                    try operation(sourceURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadFirstSharedURL(from providers: [NSItemProvider]) async throws -> URL? {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                switch item {
                case let url as URL:
                    continuation.resume(returning: url)
                case let string as String:
                    continuation.resume(returning: URL(string: string))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadFirstSharedText(from providers: [NSItemProvider]) async throws -> String? {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.text.identifier)
        }) else {
            return nil
        }

        let typeIdentifier = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            ? UTType.plainText.identifier
            : UTType.text.identifier

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let text: String?
                switch item {
                case let string as String:
                    text = string
                case let attributedString as NSAttributedString:
                    text = attributedString.string
                case let data as Data:
                    text = String(data: data, encoding: .utf8)
                default:
                    text = nil
                }
                continuation.resume(returning: Self.normalizedText(text))
            }
        }
    }

    private func presentSaveError(_ error: Error) {
        let description = (error as? LocalizedError)?.errorDescription
            ?? "Remember could not save this item. Please try again."
        let alert = UIAlertController(
            title: "Couldn’t Save to Remember",
            message: description,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    nonisolated private static func normalizedText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

}

private enum ShareCaptureError: LocalizedError {
    case missingSharedFile

    var errorDescription: String? {
        "The shared file could not be read. Please try sharing it again."
    }
}
