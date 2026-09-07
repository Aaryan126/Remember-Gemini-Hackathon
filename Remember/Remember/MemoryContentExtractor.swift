import Foundation
import GRDB
import PDFKit
import UIKit
import Vision

nonisolated enum MemoryExtractionMethod: String, Codable, DatabaseValueConvertible, Sendable {
    case plainText
    case transcript
    case visionClassification
    case visionOCR
    case pdfText
    case pdfOCR
}

nonisolated struct MemoryChunkDraft: Codable, Equatable, Sendable {
    let ordinal: Int
    let locator: String
    let text: String
    let extractionMethod: MemoryExtractionMethod
}

nonisolated struct ExtractedMemoryContent: Equatable, Sendable {
    let text: String
    let chunks: [MemoryChunkDraft]
    let isPartial: Bool
    let visualLabels: [VisionImageLabel]
}

nonisolated enum MemoryContentExtractionError: LocalizedError {
    case missingTranscript
    case unreadablePDF

    var errorDescription: String? {
        switch self {
        case .missingTranscript:
            "The voice recording did not produce a usable on-device transcript."
        case .unreadablePDF:
            "The saved PDF could not be read on this iPhone."
        }
    }
}

nonisolated struct MemoryTextChunker {
    static let targetLength = 800
    static let overlapLength = 120

    static func chunks(
        from text: String,
        locatorPrefix: String,
        startingOrdinal: Int = 0,
        extractionMethod: MemoryExtractionMethod
    ) -> [MemoryChunkDraft] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var result: [MemoryChunkDraft] = []
        var start = normalized.startIndex
        var ordinal = startingOrdinal

        while start < normalized.endIndex {
            let hardEnd = normalized.index(
                start,
                offsetBy: targetLength,
                limitedBy: normalized.endIndex
            ) ?? normalized.endIndex
            let end = boundary(in: normalized, start: start, hardEnd: hardEnd)
            let value = normalized[start..<end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                result.append(
                    MemoryChunkDraft(
                        ordinal: ordinal,
                        locator: result.isEmpty ? locatorPrefix : "\(locatorPrefix), part \(result.count + 1)",
                        text: value,
                        extractionMethod: extractionMethod
                    )
                )
                ordinal += 1
            }
            guard end < normalized.endIndex else { break }
            let overlapStart = normalized.index(
                end,
                offsetBy: -overlapLength,
                limitedBy: start
            ) ?? end
            start = overlapStart > start ? overlapStart : end
        }
        return result
    }

    private static func boundary(
        in text: String,
        start: String.Index,
        hardEnd: String.Index
    ) -> String.Index {
        guard hardEnd < text.endIndex else { return text.endIndex }
        let preferredStart = text.index(
            hardEnd,
            offsetBy: -min(180, text.distance(from: start, to: hardEnd)),
            limitedBy: start
        ) ?? start
        let range = preferredStart..<hardEnd
        if let paragraph = text.range(of: "\n\n", options: .backwards, range: range) {
            return paragraph.upperBound
        }
        if let sentence = text.range(of: ". ", options: .backwards, range: range) {
            return sentence.upperBound
        }
        if let newline = text.range(of: "\n", options: .backwards, range: range) {
            return newline.upperBound
        }
        if let space = text.range(of: " ", options: .backwards, range: range) {
            return space.upperBound
        }
        return hardEnd
    }
}

actor MemoryContentExtractor {
    static let maximumPages = 500
    static let maximumCharacters = 1_000_000
    static let maximumChunks = 512

    private let textRecognizer: VisionTextRecognizer
    private let imageClassifier: VisionImageClassifier

    init(
        textRecognizer: VisionTextRecognizer = VisionTextRecognizer(),
        imageClassifier: VisionImageClassifier = VisionImageClassifier()
    ) {
        self.textRecognizer = textRecognizer
        self.imageClassifier = imageClassifier
    }

    func extract(
        memory: MemoryItem,
        originalURL: URL,
        supportingText: String?
    ) async throws -> ExtractedMemoryContent {
        switch memory.kind {
        case .video:
            // Index only what the user supplied, never imply the movie was transcribed or watched.
            let caption = Self.nonempty(memory.userCaption) ?? ""
            return ExtractedMemoryContent(
                text: caption,
                chunks: MemoryTextChunker.chunks(from: caption, locatorPrefix: "Video caption", extractionMethod: .plainText),
                isPartial: true,
                visualLabels: []
            )
        case .audio:
            guard let transcript = Self.nonempty(supportingText) else {
                throw MemoryContentExtractionError.missingTranscript
            }
            return Self.singleDocument(
                transcript,
                locator: "Transcript",
                method: .transcript
            )
        case .image:
            async let recognizedTextTask: String? = try? textRecognizer.recognizeText(in: originalURL)
            async let visualLabelsTask: [VisionImageLabel]? = try? imageClassifier.classifyImage(at: originalURL)
            let (recognizedText, visualLabels) = await (recognizedTextTask, visualLabelsTask)
            return Self.imageContent(
                recognizedText: recognizedText ?? "",
                visualLabels: visualLabels ?? []
            )
        case .link, .text:
            let text = try String(contentsOf: originalURL, encoding: .utf8)
            return Self.singleDocument(
                text,
                locator: memory.kind == .link ? "Saved link" : "Saved note",
                method: .plainText
            )
        case .pdf:
            return try await extractPDF(at: originalURL)
        }
    }

    private func extractPDF(at url: URL) async throws -> ExtractedMemoryContent {
        guard let document = PDFDocument(url: url) else {
            throw MemoryContentExtractionError.unreadablePDF
        }

        var chunks: [MemoryChunkDraft] = []
        var pageTexts: [String] = []
        var characterCount = 0
        var partial = document.pageCount > Self.maximumPages

        for pageIndex in 0..<min(document.pageCount, Self.maximumPages) {
            try Task.checkCancellation()
            guard chunks.count < Self.maximumChunks,
                  characterCount < Self.maximumCharacters,
                  let page = document.page(at: pageIndex) else {
                partial = true
                break
            }

            let selectable = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let method: MemoryExtractionMethod
            let pageText: String
            if selectable.count >= 20 {
                method = .pdfText
                pageText = selectable
            } else {
                let recognized = try await recognizeText(on: page)
                method = .pdfOCR
                pageText = recognized.isEmpty ? selectable : recognized
            }
            guard !pageText.isEmpty else { continue }

            let remaining = Self.maximumCharacters - characterCount
            let bounded = String(pageText.prefix(remaining))
            if bounded.count < pageText.count { partial = true }
            pageTexts.append(bounded)
            characterCount += bounded.count

            let pageChunks = MemoryTextChunker.chunks(
                from: bounded,
                locatorPrefix: "Page \(pageIndex + 1)",
                startingOrdinal: chunks.count,
                extractionMethod: method
            )
            let capacity = Self.maximumChunks - chunks.count
            chunks.append(contentsOf: pageChunks.prefix(capacity))
            if pageChunks.count > capacity { partial = true }
        }

        let text = pageTexts.joined(separator: "\n\n")
        if text.isEmpty {
            return ExtractedMemoryContent(
                text: "This PDF has no readable text.",
                chunks: [],
                isPartial: partial,
                visualLabels: []
            )
        }
        return ExtractedMemoryContent(
            text: text,
            chunks: chunks,
            isPartial: partial,
            visualLabels: []
        )
    }

    private func recognizeText(on page: PDFPage) async throws -> String {
        let image = page.thumbnail(of: CGSize(width: 1_600, height: 2_200), for: .mediaBox)
        guard let data = image.pngData() else { return "" }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remember-pdf-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        return try await textRecognizer.recognizeText(in: temporaryURL)
    }

    private nonisolated static func singleDocument(
        _ value: String,
        locator: String,
        method: MemoryExtractionMethod
    ) -> ExtractedMemoryContent {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let bounded = String(normalized.prefix(maximumCharacters))
        let drafts = MemoryTextChunker.chunks(
            from: bounded,
            locatorPrefix: locator,
            extractionMethod: method
        )
        return ExtractedMemoryContent(
            text: bounded,
            chunks: Array(drafts.prefix(maximumChunks)),
            isPartial: normalized.count > bounded.count || drafts.count > maximumChunks,
            visualLabels: []
        )
    }

    nonisolated static func imageContent(
        recognizedText: String,
        visualLabels: [VisionImageLabel]
    ) -> ExtractedMemoryContent {
        let labels = VisionImageClassifier.normalizedLabels(visualLabels)
        let normalizedText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedText = String(normalizedText.prefix(maximumCharacters))
        var chunks: [MemoryChunkDraft] = []
        var sections: [String] = []

        if !labels.isEmpty {
            let labelText = "Possible Apple Vision labels; classifications may be incorrect:\n"
                + labels.map { "- \($0.evidenceText)" }.joined(separator: "\n")
            sections.append(labelText)
            chunks.append(
                MemoryChunkDraft(
                    ordinal: chunks.count,
                    locator: "Image labels",
                    text: labelText,
                    extractionMethod: .visionClassification
                )
            )
        }

        if !boundedText.isEmpty {
            sections.append("Text found in image:\n\(boundedText)")
            chunks.append(
                contentsOf: MemoryTextChunker.chunks(
                    from: boundedText,
                    locatorPrefix: "Image text",
                    startingOrdinal: chunks.count,
                    extractionMethod: .visionOCR
                )
            )
        }

        return ExtractedMemoryContent(
            text: sections.joined(separator: "\n\n"),
            chunks: Array(chunks.prefix(maximumChunks)),
            isPartial: normalizedText.count > boundedText.count || chunks.count > maximumChunks,
            visualLabels: labels
        )
    }

    private nonisolated static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
