import Foundation
import HuggingFace
import MLX
import MLXEmbedders
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

nonisolated protocol TextEmbedding: Sendable {
    var modelIdentifier: String { get }

    func embed(_ texts: [String]) async throws -> [[Float]]
}

nonisolated enum EmbeddingVectorCodec {
    static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBytes { Data($0) }
    }

    static func decode(_ data: Data?) -> [Float]? {
        guard let data, !data.isEmpty,
              data.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            return nil
        }
        return data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }

    static func cosineSimilarity(_ left: [Float], _ right: [Float]) -> Double? {
        guard !left.isEmpty, left.count == right.count else { return nil }
        var dot = 0.0
        var leftMagnitude = 0.0
        var rightMagnitude = 0.0
        for index in left.indices {
            let lhs = Double(left[index])
            let rhs = Double(right[index])
            dot += lhs * rhs
            leftMagnitude += lhs * lhs
            rightMagnitude += rhs * rhs
        }
        guard leftMagnitude > 0, rightMagnitude > 0 else { return nil }
        return dot / (leftMagnitude.squareRoot() * rightMagnitude.squareRoot())
    }
}

enum BGEEmbeddingModelBundle {
    nonisolated static let directoryName = "bge-micro-v2"
    nonisolated static let modelIdentifier = "TaylorAI/bge-micro-v2-384d-v1"

    nonisolated private static let requiredFiles = [
        "config.json",
        "model.safetensors",
        "tokenizer.json",
        "tokenizer_config.json",
        "1_Pooling/config.json",
    ]

    nonisolated static func directory(
        in bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let directory = bundle.url(forResource: directoryName, withExtension: nil) else {
            throw LocalEmbeddingError.modelDirectoryNotFound(directoryName)
        }
        for relativePath in requiredFiles {
            let file = directory.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: file.path) else {
                throw LocalEmbeddingError.missingModelFile(relativePath)
            }
        }
        return directory
    }
}

actor MLXTextEmbeddingService: TextEmbedding {
    nonisolated let modelIdentifier = BGEEmbeddingModelBundle.modelIdentifier

    private static let cacheLimit = 8 * 1024 * 1024
    private static let maximumTokens = 256
    private let executionGate: GemmaExecutionGate

    init(executionGate: GemmaExecutionGate = .shared) {
        self.executionGate = executionGate
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        let boundedTexts = texts.map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6_000))
        }
        guard !boundedTexts.isEmpty else { return [] }

        return try await executionGate.withPermit {
            MLX.Memory.cacheLimit = Self.cacheLimit
            let directory = try BGEEmbeddingModelBundle.directory()
            let container = try await EmbedderModelFactory.shared.loadContainer(
                from: directory,
                using: #huggingFaceTokenizerLoader()
            )
            defer { MLX.Memory.clearCache() }

            return await container.perform { context in
                let tokenizer = context.tokenizer
                let encoded = boundedTexts.map { text in
                    Array(tokenizer.encode(text: text, addSpecialTokens: true).prefix(Self.maximumTokens))
                }
                let maximumLength = encoded.map(\.count).max() ?? 1
                let padded = stacked(encoded.map { tokens in
                    MLXArray(tokens + Array(repeating: 0, count: maximumLength - tokens.count))
                })
                let mask = padded .!= 0
                let tokenTypes = MLXArray.zeros(like: padded)
                let output = context.model(
                    padded,
                    positionIds: nil,
                    tokenTypeIds: tokenTypes,
                    attentionMask: mask
                )
                let pooled = context.pooling(output, mask: mask, normalize: true)
                pooled.eval()
                return pooled.map { $0.asArray(Float.self) }
            }
        }
    }
}

nonisolated enum LocalEmbeddingError: LocalizedError {
    case modelDirectoryNotFound(String)
    case missingModelFile(String)
    case invalidVectorCount

    var errorDescription: String? {
        switch self {
        case .modelDirectoryNotFound(let name):
            "The bundled semantic-search model folder “\(name)” was not found."
        case .missingModelFile(let filename):
            "The bundled semantic-search model is missing \(filename)."
        case .invalidVectorCount:
            "The semantic-search model returned an unexpected number of vectors."
        }
    }
}
