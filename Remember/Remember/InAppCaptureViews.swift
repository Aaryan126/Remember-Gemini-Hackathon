import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CaptureMenuButton: View {
    let onSelect: (CaptureAction) -> Void

    var body: some View {
        Menu {
            ForEach(CaptureAction.allCases) { action in
                Button(action.title, systemImage: action.systemImage) {
                    onSelect(action)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 9, y: 4)
        }
        .accessibilityLabel("Add a memory")
        .accessibilityHint("Choose a note, photo, file, link, or voice recording")
    }
}

struct NewNoteCaptureView: View {
    let viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case body
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.largeTitle.bold())
                    .lineLimit(1...3)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .title)
                    .onSubmit { focusedField = .body }

                TextEditor(text: $bodyText)
                    .font(.body)
                    .focused($focusedField, equals: .body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, -5)
                    .overlay(alignment: .topLeading) {
                        if bodyText.isEmpty {
                            Text("Start writing…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }

                if note.text.count > InAppCaptureService.maximumNoteLength {
                    Text("Note is too long")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || note.text.isEmpty || note.text.count > InAppCaptureService.maximumNoteLength)
                }
            }
            .onAppear { focusedField = .title }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var note: NoteDocument {
        NoteDocument(title: title, body: bodyText)
    }

    private func save() {
        focusedField = nil
        Task {
            isSaving = true
            let didSave = await viewModel.saveNote(note.text)
            isSaving = false
            if didSave { dismiss() }
        }
    }
}

struct LinkCaptureView: View {
    let viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var context = ""
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field { case link, context }

    var body: some View {
        NavigationStack {
            Form {
                Section("Link") {
                    TextField("https://example.com", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .link)
                }
                Section("Context (optional)") {
                    TextField("Why this matters", text: $context, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .context)
                }
            }
            .navigationTitle("Save Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focusedField = .link }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        focusedField = nil
        Task {
            isSaving = true
            let didSave = await viewModel.saveLink(link, context: context)
            isSaving = false
            if didSave { dismiss() }
        }
    }
}

struct ImageCaptureConfirmationView: View {
    let imageURL: URL
    let viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var context = ""
    @State private var isSaving = false
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LocalImageView(url: imageURL, maximumPixelSize: 1_600, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Selected photo preview")
                }
                Section("Caption") {
                    TextField("What should Remember know about this?", text: $context, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.height(500)])
        .interactiveDismissDisabled(isSaving)
        .onDisappear {
            if !didSave { try? FileManager.default.removeItem(at: imageURL) }
        }
    }

    private func save() {
        Task {
            isSaving = true
            let saved = await viewModel.saveImage(from: imageURL, context: context)
            isSaving = false
            if saved {
                didSave = true
                try? FileManager.default.removeItem(at: imageURL)
                dismiss()
            }
        }
    }
}

struct AssistantVoiceInputView: View {
    let viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var recorder = VoiceRecorder()
    @State private var isUsingRecording = false
    @State private var didUseRecording = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                    .symbolEffect(.pulse, isActive: recorder.isRecording)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2.bold())
                Text(formattedDuration)
                    .font(.system(.largeTitle, design: .rounded, weight: .medium))
                    .monospacedDigit()

                if recorder.isRecording {
                    Button("Stop Recording", systemImage: "stop.fill") { recorder.stop() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                } else {
                    Button(recorder.state == .recorded ? "Record Again" : "Start Recording", systemImage: "mic.fill") {
                        Task { await recorder.start() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if recorder.state == .recorded {
                    Button {
                        useRecording()
                    } label: {
                        if isUsingRecording {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Use as Question", systemImage: "text.bubble.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isUsingRecording)
                }

                if case .failed(let message) = recorder.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Label("This recording is transcribed locally and is not saved as a memory", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle("Speak a Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isUsingRecording)
                }
            }
        }
        .interactiveDismissDisabled(recorder.isRecording || isUsingRecording)
        .onDisappear {
            if !didUseRecording { recorder.discardRecording() }
        }
    }

    private var title: String {
        switch recorder.state {
        case .idle: "Ask naturally"
        case .requestingPermission: "Preparing microphone"
        case .recording: "Listening on this iPhone"
        case .recorded: "Question ready"
        case .failed: "Recording unavailable"
        }
    }

    private var formattedDuration: String {
        let seconds = max(0, Int(recorder.elapsedTime.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func useRecording() {
        guard let recordingURL = recorder.recordingURL else { return }
        Task {
            isUsingRecording = true
            let didTranscribe = await viewModel.transcribeAssistantQuestion(from: recordingURL)
            isUsingRecording = false
            if didTranscribe {
                didUseRecording = true
                recorder.releaseRecordingAfterSave()
                dismiss()
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            } else {
                parent.onCancel()
            }
        }
    }
}

extension PhotosPickerItem {
    func temporaryImageURL() async throws -> URL {
        guard let data = try await loadTransferable(type: Data.self) else {
            throw InAppCaptureError.unsupportedFile
        }
        let fileExtension = supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RememberPhoto-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
}

extension UIImage {
    func rememberTemporaryJPEGURL() throws -> URL {
        guard let data = jpegData(compressionQuality: 0.92) else {
            throw InAppCaptureError.unsupportedFile
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RememberCamera-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
}
