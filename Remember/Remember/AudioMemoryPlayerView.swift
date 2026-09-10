import AVFAudio
import Observation
import SwiftUI

struct AudioMemoryPlayerView: View {
    let url: URL
    var onOpenMemory: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = AudioMemoryPlayer()

    var body: some View {
        HStack(spacing: 16) {
            Button {
                player.toggle(url: url)
            } label: {
                Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
            }
            .accessibilityLabel(player.isPlaying ? "Stop voice memory" : "Play voice memory")

            if let onOpenMemory {
                Button(action: onOpenMemory) { recordingLabel }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open voice memory")
            } else {
                recordingLabel
            }
            Spacer()
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(RememberPalette.secondaryText)
                .accessibilityHidden(true)
        }
        .padding()
        .rememberCard(radius: 20, dark: Color.accentColor.opacity(0.1))
        .onDisappear { player.stop() }
        .onChange(of: url) { _, _ in player.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.stop() }
        }
    }

    private var recordingLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Voice memory").font(.headline)
            Text(player.statusText).font(.caption).foregroundStyle(RememberPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

@MainActor
@Observable
private final class AudioMemoryPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var statusText = "Stored on this iPhone"
    private var audioPlayer: AVAudioPlayer?

    func toggle(url: URL) {
        if isPlaying {
            stop()
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { throw AudioMemoryPlayerError.couldNotPlay }
            audioPlayer = player
            isPlaying = true
            statusText = "Playing locally"
        } catch {
            isPlaying = false
            statusText = "Could not play this recording"
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        statusText = "Stored on this iPhone"
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayer = nil
        isPlaying = false
        statusText = flag ? "Finished" : "Playback stopped"
    }
}

nonisolated private enum AudioMemoryPlayerError: Error {
    case couldNotPlay
}
