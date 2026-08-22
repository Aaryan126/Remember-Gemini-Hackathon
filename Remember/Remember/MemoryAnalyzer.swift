import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import PDFKit
import Tokenizers
import Vision

nonisolated protocol MemoryAnalyzing: Sendable {
    func analyze(memory: MemoryItem, originalURL: URL, supportingText: String?) async throws -> MemoryAnalysisResult
}

nonisolated struct VisionTextRecognizer: Sendable {
    func recognizeText(in imageURL: URL) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: imageURL)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor GemmaMemoryAnalyzer: MemoryAnalyzing {
    nonisolated static let modelVersion = "gemma-4-e2b-it-4bit vision-only / mlx-swift-lm 68947ccd"
    private static let mlxCacheLimit = 20 * 1024 * 1024

    private let textRecognizer: VisionTextRecognizer

    init(textRecognizer: VisionTextRecognizer = VisionTextRecognizer()) {
        self.textRecognizer = textRecognizer
    }

    func analyze(memory: MemoryItem, originalURL: URL, supportingText: String? = nil) async throws -> MemoryAnalysisResult {
        MLX.Memory.cacheLimit = Self.mlxCacheLimit
        defer { MLX.Memory.clearCache() }

        let extractedText: String
        switch memory.kind {
        case .audio:
            guard let supportingText, !supportingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GemmaInferenceError.emptyResponse
            }
            extractedText = supportingText
        case .image:
            extractedText = try await textRecognizer.recognizeText(in: originalURL)
        case .link, .text:
            extractedText = try String(contentsOf: originalURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .pdf:
            extractedText = try Self.extractText(fromPDF: originalURL)
        }

        return try await GemmaExecutionGate.shared.withPermit {
            try await Self.generateAnalysis(
                memory: memory,
                originalURL: originalURL,
                extractedText: extractedText
            )
        }
    }

    nonisolated private static func generateAnalysis(
        memory: MemoryItem,
        originalURL: URL,
        extractedText: String
    ) async throws -> MemoryAnalysisResult {
        let image: UserInput.Image? = memory.kind == .image ? .url(originalURL) : nil

        let directory = try GemmaModelBundle.directory()
        let container = try await VLMModelFactory.shared.loadContainer(
            from: directory,
            using: #huggingFaceTokenizerLoader()
        )
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: 280, temperature: 0),
            processing: .init(resize: nil)
        )
        let prompt = makePrompt(
            kind: memory.kind,
            userCaption: memory.userCaption,
            extractedText: extractedText
        )
        let response = try await session.respond(to: prompt, image: image)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else {
            throw GemmaInferenceError.emptyResponse
        }

        return MemoryAnalysisParser.parse(
            response: response,
            kind: memory.kind,
            userCaption: memory.userCaption,
            extractedText: extractedText,
            modelVersion: modelVersion
        )
    }

    nonisolated private static func makePrompt(
        kind: MemoryKind,
        userCaption: String?,
        extractedText: String
    ) -> String {
        let note = limited(userCaption, maximumLength: 2_000) ?? "None"
        let ocr = limited(extractedText, maximumLength: 8_000) ?? "None"
        let mediaInstruction: String
        switch kind {
        case .audio:
            mediaInstruction = "Use the on-device voice transcript as the primary source. Do not add words or details that are not in the transcript."
        case .image:
            mediaInstruction = "Use the attached image as the primary source. OCR may contain mistakes."
        case .link:
            mediaInstruction = "Use the saved URL and user note as the source. Do not claim to have opened or fetched the webpage."
        case .pdf:
            mediaInstruction = "Use the locally extracted PDF text as the primary source. It may omit text from scanned pages."
        case .text:
            mediaInstruction = "Use the saved text as the primary source."
        }

        return """
            You organize one item in a private personal memory library.
            \(mediaInstruction)

            User note:
            \(note)

            Extracted text:
            \(ocr)

            Return only one valid JSON object with this exact shape:
            {"title":"short concrete title","summary":"one or two factual sentences","tags":["tag"]}

            Requirements:
            - Title: at most 8 words.
            - Summary: at most 45 words.
            - Tags: 2 to 6 concise lowercase tags.
            - Do not invent names, dates, or facts that are not visible or provided.
            - Do not wrap the JSON in Markdown.
            """
    }

    nonisolated private static func limited(_ value: String?, maximumLength: Int) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maximumLength))
    }

    nonisolated private static func extractText(fromPDF url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw GemmaInferenceError.unreadablePDF
        }
        let text = (0 ..< min(document.pageCount, 40))
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty
            ? "This PDF has no selectable text. It may contain scanned pages."
            : String(text.prefix(50_000))
    }
}

nonisolated enum MemoryAnalysisParser {
    private struct Payload: Decodable {
        let title: String?
        let summary: String?
        let tags: [String]?
    }

    static func parse(
        response: String,
        kind: MemoryKind,
        userCaption: String?,
        extractedText: String,
        modelVersion: String
    ) -> MemoryAnalysisResult {
        let payload = jsonData(in: response).flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        let fallbackTitle = firstUsefulLine(in: userCaption)
            ?? firstUsefulLine(in: extractedText)
            ?? {
                switch kind {
                case .audio: "Voice memory"
                case .image: "Saved image"
                case .link: "Saved link"
                case .pdf: "Saved PDF"
                case .text: "Saved note"
                }
            }()
        let title = normalized(payload?.title, maximumLength: 120) ?? String(fallbackTitle.prefix(120))
        let fallbackSummary = normalized(userCaption, maximumLength: 1_000)
            ?? normalized(extractedText, maximumLength: 1_000)
            ?? normalized(response, maximumLength: 1_000)
            ?? "Saved locally in Remember."
        let summary = normalized(payload?.summary, maximumLength: 1_000) ?? fallbackSummary
        let tags = normalizedTags(payload?.tags ?? [])

        return MemoryAnalysisResult(
            title: title,
            summary: summary,
            tags: tags,
            extractedText: String(extractedText.prefix(50_000)),
            modelVersion: modelVersion
        )
    }

    private static func jsonData(in response: String) -> Data? {
        guard let openingBrace = response.firstIndex(of: "{"), let closingBrace = response.lastIndex(of: "}"), openingBrace <= closingBrace else {
            return nil
        }
        return Data(response[openingBrace...closingBrace].utf8)
    }

    private static func firstUsefulLine(in value: String?) -> String? {
        value?
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func normalized(_ value: String?, maximumLength: Int) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maximumLength))
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        let encoded = MemoryItem.encodeTags(tags.map { $0.lowercased() })
        return (try? JSONDecoder().decode([String].self, from: Data(encoded.utf8))) ?? []
    }
}
