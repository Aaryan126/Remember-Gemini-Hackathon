import Foundation
import Vision

nonisolated struct VisionImageLabel: Equatable, Sendable {
    let identifier: String
    let confidence: Float

    var displayName: String {
        identifier.split(separator: ",", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? identifier
    }

    var evidenceText: String {
        let percentage = Int((confidence * 100).rounded())
        return "\(identifier) (\(percentage)% confidence)"
    }
}

nonisolated struct VisionImageClassifier: Sendable {
    static let maximumLabels = 8

    func classifyImage(at imageURL: URL) async throws -> [VisionImageLabel] {
        let request = ClassifyImageRequest()
        let observations = try await request.perform(on: imageURL)
            .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
            .map { VisionImageLabel(identifier: $0.identifier, confidence: $0.confidence) }
        return Self.normalizedLabels(observations)
    }

    static func normalizedLabels(_ labels: [VisionImageLabel]) -> [VisionImageLabel] {
        let sorted = labels
            .filter { $0.confidence.isFinite && $0.confidence > 0 }
            .sorted {
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending
            }

        var result: [VisionImageLabel] = []
        var identifiers = Set<String>()
        for label in sorted {
            let identifier = label.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else { continue }
            let bounded = String(identifier.prefix(80))
            guard identifiers.insert(bounded.lowercased()).inserted else { continue }
            result.append(VisionImageLabel(identifier: bounded, confidence: label.confidence))
            if result.count == maximumLabels { break }
        }
        return result
    }
}
