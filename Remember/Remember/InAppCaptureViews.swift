import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CaptureMenuButton: View {
    @Binding var isExpanded: Bool
    let onSelect: (CaptureAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var dialPosition = CGFloat.zero
    @State private var lastDragLocation: CGPoint?
    @State private var motion = CaptureDialMomentum()
    @State private var coaster = CaptureDialCoaster()
    @GestureState private var isDragging = false

    private let dialRadius = CGFloat(135)
    private let visibleActionCount = 4
    private let menuSide = CGFloat(245)
    private let hubSize = CGFloat(56)
    private let trailingInset = CGFloat(18)
    private let bottomInset = CGFloat(28)

    private var dialCenter: CGPoint {
        CGPoint(x: menuSide - trailingInset - hubSize / 2, y: menuSide - bottomInset - hubSize / 2)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                dialActions
            }

            Button {
                setExpanded(!isExpanded)
            } label: {
                Image(systemName: isExpanded ? "xmark" : "plus")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: hubSize, height: hubSize)
                    .contentTransition(.symbolEffect(.replace))
                    .glassEffect(.regular.tint(Color.accentColor).interactive(), in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            // The hub is separate from the rotating actions and their gesture recognizer.
            .zIndex(10)
            .frame(width: hubSize, height: hubSize)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityActivationPoint(.center)
            .accessibilityAction { setExpanded(!isExpanded) }
            .accessibilityIdentifier("capture-menu-toggle")
            .accessibilityLabel(isExpanded ? "Close add menu" : "Add a memory")
            .accessibilityHint(
                isExpanded
                    ? "Closes the capture dial. Swipe over the dial to rotate capture types."
                    : "Shows capture types"
            )
            .padding(.trailing, trailingInset)
            .padding(.bottom, bottomInset)
        }
        .frame(width: menuSide, height: menuSide, alignment: .bottomTrailing)
        .coordinateSpace(name: "capture-dial")
        .accessibilityAction(.escape) { setExpanded(false) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isExpanded)
        .onChange(of: isDragging) { _, dragging in
            if !dragging { lastDragLocation = nil }
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { stopCoasting() }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { stopCoasting() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopCoasting() }
        }
        .onDisappear { stopCoasting(); isExpanded = false }
    }

    private var dialActions: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Capture dial")
                .accessibilityValue("Four capture types visible")
                .accessibilityHint("Swipe up or down to rotate through capture types")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: rotateDial(by: 1)
                    case .decrement: rotateDial(by: -1)
                    @unknown default: break
                    }
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
                .accessibilityHidden(visibility < 0.5)
                .allowsHitTesting(visibility >= 0.72)
                .offset(dialOffset(for: relativePosition))
                .opacity(visibility)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .zIndex(Double(visibility))
                .padding(.trailing, trailingInset)
                .padding(.bottom, bottomInset)
            }
        }
        .frame(width: menuSide, height: menuSide)
        .highPriorityGesture(dialDragGesture)
        .transition(.opacity)
    }

    private func select(_ action: CaptureAction) {
        // Dismissing buttons can remain in the transition hierarchy. Ignore any
        // trailing action delivered after the hub closed the menu or during rotation.
        guard isExpanded, !isDragging else { return }
        setExpanded(false)
        onSelect(action)
    }

    private func setExpanded(_ expanded: Bool) {
        stopCoasting()
        motion = CaptureDialMomentum()
        lastDragLocation = nil
        if expanded { dialPosition = 0 }
        if reduceMotion {
            isExpanded = expanded
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                isExpanded = expanded
            }
        }
    }

    private var dialDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("capture-dial"))
            .updating($isDragging) { _, state, transaction in
                transaction.animation = nil
                state = true
            }
            .onChanged { value in
                stopCoasting()
                if lastDragLocation == nil { motion = CaptureDialMomentum() }
                dialPosition += CaptureDialDrag.progress(
                    from: lastDragLocation ?? value.startLocation,
                    to: value.location,
                    center: dialCenter
                )
                lastDragLocation = value.location
                motion.record(position: dialPosition, time: value.time.timeIntervalSinceReferenceDate)
            }
            .onEnded { value in
                let velocity = motion.releaseVelocity(at: value.time.timeIntervalSinceReferenceDate)
                dialPosition = dialPosition.truncatingRemainder(dividingBy: CGFloat(CaptureAction.allCases.count))
                lastDragLocation = nil
                startCoasting(velocity: velocity)
            }
    }

    private func stopCoasting() {
        coaster.stop()
    }

    private func startCoasting(velocity: CGFloat) {
        stopCoasting()
        guard !reduceMotion, isExpanded, abs(velocity) > CaptureDialMomentum.stopSpeed else { return }
        coaster.start(velocity: velocity) { distance in
            dialPosition = (dialPosition + distance).truncatingRemainder(dividingBy: CGFloat(CaptureAction.allCases.count))
        }
    }

    private func rotateDial(by step: Int) {
        stopCoasting()
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

    private func relativePosition(for actionIndex: Int) -> CGFloat {
        let actionCount = CGFloat(CaptureAction.allCases.count)
        var position = CGFloat(actionIndex) - dialPosition
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
        Image(systemName: action.systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .glassEffect(.regular, in: .circle)
            .frame(width: hubSize, height: hubSize)
            .contentShape(Circle())
            .overlay(alignment: .bottom) {
                Text(action.compactTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .offset(y: 18)
            }
    }
}

nonisolated enum CaptureDialDrag {
    static func progress(from start: CGPoint, to end: CGPoint, center: CGPoint) -> CGFloat {
        let a = CGPoint(x: start.x - center.x, y: start.y - center.y)
        let b = CGPoint(x: end.x - center.x, y: end.y - center.y)
        // Rotation is undefined at the hub. Ignore crossings instead of jumping half a turn.
        guard hypot(a.x, a.y) >= 24, hypot(b.x, b.y) >= 24 else { return 0 }
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }
        let nearest = min(1, max(0, -(a.x * dx + a.y * dy) / lengthSquared))
        guard hypot(a.x + nearest * dx, a.y + nearest * dy) >= 24 else { return 0 }
        let delta = atan2(b.y, b.x) - atan2(a.y, a.x)
        return atan2(sin(delta), cos(delta)) / (.pi / 6)
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
    var kind: MemoryKind = .image
    let viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var context = ""
    @State private var isSaving = false
    @FocusState private var isCaptionFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        if kind == .video {
                            LocalVideoPlayerView(url: imageURL)
                        } else {
                            LocalImageView(url: imageURL, maximumPixelSize: 1_600, contentMode: .fit)
                        }
                    }
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Section("Caption") {
                    TextField("What should Remember know about this?", text: $context, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isCaptionFocused)
                }
                if kind == .video {
                    Text("The original video stays on this device. Only your caption is indexed; video scenes and speech are not analyzed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .navigationTitle(kind == .video ? "Add Video" : "Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        isCaptionFocused = false
        Task {
            isSaving = true
            let saved: Bool
            if kind == .video {
                saved = await viewModel.saveVideo(from: imageURL, context: context)
            } else {
                saved = await viewModel.saveImage(from: imageURL, context: context)
            }
            isSaving = false
            if saved {
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
