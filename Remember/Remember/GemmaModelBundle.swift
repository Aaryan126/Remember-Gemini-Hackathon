//
//  GemmaModelBundle.swift
//  Remember
//

import Foundation

enum GemmaModelBundle {
    nonisolated static let directoryName = "gemma-4-e2b-vision"

    nonisolated static let requiredFiles = [
        "chat_template.jinja",
        "config.json",
        "model.safetensors",
        "processor_config.json",
        "tokenizer.json",
        "tokenizer_config.json",
    ]

    nonisolated static func directory(
        in bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let directory = bundle.url(
            forResource: directoryName,
            withExtension: nil
        ) else {
            throw GemmaInferenceError.modelDirectoryNotFound(directoryName)
        }

        try validate(directory: directory, fileManager: fileManager)
        return directory
    }

    nonisolated static func validate(
        directory: URL,
        fileManager: FileManager = .default
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GemmaInferenceError.modelDirectoryNotFound(directory.lastPathComponent)
        }

        for filename in requiredFiles {
            let file = directory.appendingPathComponent(filename, isDirectory: false)
            guard fileManager.fileExists(atPath: file.path) else {
                throw GemmaInferenceError.missingModelFile(filename)
            }
        }
    }
}

enum GemmaInferenceError: LocalizedError {
    case modelDirectoryNotFound(String)
    case missingModelFile(String)
    case emptyResponse
    case unreadablePDF

    var errorDescription: String? {
        switch self {
        case .modelDirectoryNotFound(let name):
            "The bundled model folder “\(name)” was not found. Check the app target’s Copy Bundle Resources phase."
        case .missingModelFile(let filename):
            "The bundled model is missing \(filename)."
        case .emptyResponse:
            "Gemma completed without generating any text."
        case .unreadablePDF:
            "The saved PDF could not be opened on this iPhone."
        }
    }
}
