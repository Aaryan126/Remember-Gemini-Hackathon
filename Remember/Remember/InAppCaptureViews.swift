import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CaptureMenuButton: View {
    @Binding var isExpanded: Bool
    let onSelect: (CaptureAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dialPosition = CGFloat.zero
    @GestureState private var dialDragProgress = CGFloat.zero

    private let dialRadius = CGFloat(135)
    private let visibleActionCount = 4

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Capture dial")
                    .accessibilityValue("Four capture types visible")
                    .accessibilityHint("Swipe up or down to rotate through capture types")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            rotateDial(by: 1)
                        case .decrement:
                            rotateDial(by: -1)
                        @unknown default:
                            break
                        }
                    }
                    .transition(.opacity)
            }

            ForEach(Array(CaptureAction.allCases.enumerated()), id: \.element.id) { index, action in
                let relativePosition = relativePosition(for: index)
                let visibility = visibility(for: relativePosition)
                Button {
                    select(action)
                } label: {
                    fanLabel(for: action)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
                .accessibilityHidden(!isExpanded || visibility < 0.5)
                .allowsHitTesting(isExpanded && visibility >= 0.72)
                .offset(isExpanded ? dialOffset(for: relativePosition) : .zero)
                .scaleEffect(isExpanded ? 0.78 + (0.12 * visibility) : 0.35)
                .opacity(isExpanded ? visibility : 0)
                .animation(actionAnimation(for: min(index, visibleActionCount - 1)), value: isExpanded)
                .zIndex(Double(visibility))
                .padding(.trailing, 18)
                .padding(.bottom, 12)
            }

            Button {
                setExpanded(!isExpanded)
            } label: {
                Image(systemName: isExpanded ? "xmark" : "plus")
                    .font(.system(size: 23, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(Color.accentColor)
            .padding(.trailing, 18)
            .padding(.bottom, 12)
            .accessibilityLabel(isExpanded ? "Close add menu" : "Add a memory")
            .accessibilityHint(
                isExpanded
                    ? "Closes the capture dial. Swipe over the dial to rotate capture types."
                    : "Shows capture types"
            )
        }
        .frame(width: 225, height: 225, alignment: .bottomTrailing)
        .simultaneousGesture(dialDragGesture, including: isExpanded ? .all : .none)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isExpanded)
        .onDisappear { isExpanded = false }
    }

    private func select(_ action: CaptureAction) {
        setExpanded(false)
        onSelect(action)
    }

    private func setExpanded(_ expanded: Bool) {
        if expanded { dialPosition = 0 }
        if reduceMotion {
            isExpanded = expanded
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                isExpanded = expanded
            }
        }
    }

    private func actionAnimation(for index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let order = isExpanded ? index : visibleActionCount - index - 1
        return .spring(response: 0.36, dampingFraction: 0.76)
            .delay(Double(order) * 0.035)
    }

    private var dialDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dialDragProgress) { value, progress, transaction in
                transaction.animation = nil
                progress = dialProgress(for: value.translation)
            }
            .onEnded { value in
                let currentProgress = dialProgress(for: value.translation)
                let projectedProgress = dialProgress(for: value.predictedEndTranslation)
                let momentum = min(0.75, max(-0.75, projectedProgress - currentProgress))
                let targetPosition = dialPosition + currentProgress + momentum
                if reduceMotion {
                    dialPosition = targetPosition
                } else {
                    withAnimation(.smooth(duration: 0.28)) {
                        dialPosition = targetPosition
                    }
                }
            }
    }

    private func rotateDial(by step: Int) {
        let newPosition = dialPosition + CGFloat(step)
        if reduceMotion {
            dialPosition = newPosition
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                dialPosition = newPosition
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private var displayedDialPosition: CGFloat {
        dialPosition + dialDragProgress
    }

    private func dialProgress(for translation: CGSize) -> CGFloat {
        let dominantDistance = abs(translation.width) > abs(translation.height)
            ? -translation.width
            : -translation.height
        return dominantDistance / 76
    }

    private func relativePosition(for actionIndex: Int) -> CGFloat {
        let actionCount = CGFloat(CaptureAction.allCases.count)
        var position = CGFloat(actionIndex) - displayedDialPosition
        while position < -1 { position += actionCount }
        while position > CGFloat(visibleActionCount) { position -= actionCount }
        return position
    }

    private func visibility(for relativePosition: CGFloat) -> CGFloat {
        let leadingVisibility = max(0, relativePosition + 1)
        let trailingVisibility = max(0, CGFloat(visibleActionCount) - relativePosition)
        return min(1, min(leadingVisibility, trailingVisibility))
    }

    private func dialOffset(for relativePosition: CGFloat) -> CGSize {
        let angle = relativePosition * (.pi / 6)
        return CGSize(
            width: -dialRadius * sin(angle),
            height: -dialRadius * cos(angle)
        )
    }

    private func fanLabel(for action: CaptureAction) -> some View {
        VStack(spacing: 5) {
            Image(systemName: action.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.2), radius: 7, y: 3)

            Text(action.compactTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 52)
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
