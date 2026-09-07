import Foundation
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
                case .video: "Saved video"
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
        guard let openingBrace = response.firstIndex(of: "{"),
              let closingBrace = response.lastIndex(of: "}"),
              openingBrace <= closingBrace else { return nil }
        return Data(response[openingBrace...closingBrace].utf8)
    }

    private static func firstUsefulLine(in value: String?) -> String? {
        value?
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func normalized(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maximumLength))
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        let encoded = MemoryItem.encodeTags(tags.map { $0.lowercased() })
        return (try? JSONDecoder().decode([String].self, from: Data(encoded.utf8))) ?? []
    }
}
