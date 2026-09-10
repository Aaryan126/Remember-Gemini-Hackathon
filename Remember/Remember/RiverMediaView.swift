import SwiftUI

/// Original media stays local and playback is always user initiated.
struct RiverMediaView: View {
    let memory: MemoryItem
    var onOpenMemory: (() -> Void)? = nil
    @State private var originalURL: URL?
    @State private var unavailable = false

    var body: some View {
        if memory.kind == .image || memory.kind == .audio || memory.kind == .video {
            Group {
                if let originalURL {
                    if memory.kind == .image {
                        if let onOpenMemory {
                            Button(action: onOpenMemory) { photo(at: originalURL) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens this memory")
                                .accessibilityIdentifier("river-open-image-\(memory.id)")
                        } else {
                            photo(at: originalURL)
                        }
                    } else if memory.kind == .video {
                        LocalVideoPlayerView(url: originalURL)
                            .accessibilityIdentifier("river-video-\(memory.id)")
                    } else {
                        AudioMemoryPlayerView(url: originalURL, onOpenMemory: onOpenMemory)
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("river-audio-\(memory.id)")
                    }
                } else if unavailable {
                    Label("Saved media is unavailable on this device", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(RememberPalette.secondaryText)
                } else {
                    ProgressView("Loading saved media…").frame(maxWidth: .infinity)
                }
            }
            .task(id: memory.originalFilename) {
                originalURL = nil
                unavailable = false
                do {
                    let url = try Self.originalURL(filename: memory.originalFilename, directory: LibraryFileStore.defaultDirectory())
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        unavailable = true
                        return
                    }
                    originalURL = url
                } catch {
                    unavailable = true
                }
            }
        }
    }

    private func photo(at url: URL) -> some View {
        LocalImageView(url: url, maximumPixelSize: 2_400, contentMode: .fit)
            .frame(maxWidth: .infinity).frame(minHeight: 120)
            .background(RememberPalette.inset)
            .clipShape(.rect(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Saved photo: \(memory.displayTitle)")
            .accessibilityIdentifier("river-image-\(memory.id)")
    }

    nonisolated static func originalURL(filename: String, directory: URL) throws -> URL {
        let root = directory.standardizedFileURL
        let url = root.appendingPathComponent(filename).standardizedFileURL
        guard !filename.isEmpty, url.deletingLastPathComponent() == root else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return url
    }
}
