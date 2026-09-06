import SwiftUI

struct VoiceCaptureView: View {
    let viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var recorder = VoiceRecorder()
    @State private var isSaving = false
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                    .symbolEffect(.pulse, isActive: recorder.isRecording)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text(formattedDuration)
                    .font(.system(.largeTitle, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .accessibilityLabel("Recording length \(formattedDuration)")

                recordControl

                if case .recorded = recorder.state {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Save Voice Memory", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSaving)
                }

                if case .failed(let message) = recorder.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                Label("Audio stays local; its transcript may be analyzed by OpenAI", systemImage: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(24)
            .navigationTitle("Voice Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(recorder.isRecording || isSaving)
        .onDisappear {
            if !didSave {
                recorder.discardRecording()
            }
        }
    }

    private var title: String {
        switch recorder.state {
        case .idle: "Capture a thought"
        case .requestingPermission: "Preparing microphone"
        case .recording: "Listening on this iPhone"
        case .recorded: "Recording ready"
        case .failed: "Recording unavailable"
        }
    }

    private var statusMessage: String {
        switch recorder.state {
        case .idle:
            "Speak naturally. Remember transcribes locally, then uses the configured OpenAI service to summarize and tag it."
        case .requestingPermission:
            "You may be asked for microphone and speech-recognition access."
        case .recording:
            "Tap stop when you’re finished."
        case .recorded:
            "Save it to start local transcription and OpenAI analysis."
        case .failed:
            "Check the message below, then try again."
        }
    }

    @ViewBuilder
    private var recordControl: some View {
        if recorder.isRecording {
            Button {
                recorder.stop()
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        } else {
            Button {
                Task { await recorder.start() }
            } label: {
                Label(recorder.state == .recorded ? "Record Again" : "Start Recording", systemImage: "mic.fill")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(recorder.state == .requestingPermission || isSaving)
        }
    }

    private var formattedDuration: String {
        let totalSeconds = max(0, Int(recorder.elapsedTime.rounded(.down)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func save() {
        guard let url = recorder.recordingURL else { return }
        Task {
            isSaving = true
            let saved = await viewModel.saveVoiceRecording(from: url)
            isSaving = false
            if saved {
                didSave = true
                recorder.releaseRecordingAfterSave()
                dismiss()
            }
        }
    }
}
