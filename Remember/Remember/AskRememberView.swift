import SwiftUI

struct AskRememberView: View {
    let viewModel: LibraryViewModel
    let onClose: () -> Void
    @FocusState private var isComposerFocused: Bool
    @State private var answerTask: Task<Void, Never>?
    @State private var showsVoiceInput = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if case .unavailable(let reason) = viewModel.aiAvailability {
                            BasicModeBanner(reason: reason)
                                .padding(.horizontal, 16)
                        }
                        if viewModel.chatMessages.isEmpty {
                            introduction
                        } else {
                            ForEach(viewModel.chatMessages) { message in
                                ChatMessageView(message: message, viewModel: viewModel)
                                    .id(message.id)
                            }
                        }

                        if viewModel.isAnswering {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Checking your saved memories and their sources…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .id("answering")
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isComposerFocused = false
                    }
                )
                .onChange(of: viewModel.chatMessages.count) { _, _ in
                    if let last = viewModel.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: viewModel.isAnswering) { _, answering in
                    if answering {
                        withAnimation { proxy.scrollTo("answering", anchor: .bottom) }
                    }
                }
            }
            .navigationTitle("AI Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        close()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Label(aiStatusLabel, systemImage: "cloud.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .accessibilityLabel("AI uses the configured OpenAI service")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isComposerFocused = false
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
            }
            .sheet(isPresented: $showsVoiceInput) {
                AssistantVoiceInputView(viewModel: viewModel)
            }
            .safeAreaInset(edge: .top) {
                if let errorMessage = viewModel.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(errorMessage).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Dismiss") { viewModel.clearError() }.font(.footnote.weight(.semibold))
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
        .onDisappear {
            answerTask?.cancel()
            viewModel.resetAssistantConversation()
        }
    }

    private var aiStatusLabel: String {
        viewModel.aiAvailability.isAvailable ? "OpenAI · Grounded" : "OpenAI · Offline"
    }

    private var introduction: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Ask your memories")
                .font(.title2.bold())
            Text("AI searches your saved memories, checks quoted evidence against the originals, and shows the sources it used. Relevant excerpts are sent to the configured OpenAI service.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(AskSuggestionBuilder.questions(), id: \.self) { question in
                    suggestion(question)
                }
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 28)
        .padding(.top, 60)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            viewModel.chatInput = text
            isComposerFocused = true
        } label: {
            Label(text, systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Places this question in the message field")
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                isComposerFocused = false
                showsVoiceInput = true
            } label: {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(viewModel.isAnswering || viewModel.isTranscribingAssistantQuery)
            .accessibilityLabel("Speak a question")

            TextField("Ask about what you saved", text: Binding(
                get: { viewModel.chatInput },
                set: { viewModel.chatInput = $0 }
            ), axis: .vertical)
                .lineLimit(1...5)
                .focused($isComposerFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .disabled(viewModel.isAnswering)

            Button {
                isComposerFocused = false
                answerTask = Task { await viewModel.askRemember() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
            }
            .disabled(
                viewModel.isAnswering
                    || viewModel.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityLabel("Ask Remember")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func close() {
        answerTask?.cancel()
        answerTask = nil
        viewModel.resetAssistantConversation()
        onClose()
    }
}

nonisolated enum AskSuggestionBuilder {
    private static let fallbackQuestions = [
        "What are the most important project decisions?",
        "Which constraints should I know about?",
        "What is still unresolved?",
    ]

    static func questions(limit: Int = 3) -> [String] {
        Array(fallbackQuestions.prefix(max(0, limit)))
    }
}

private struct ChatMessageView: View {
    let message: RememberChatMessage
    let viewModel: LibraryViewModel

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
            Text(renderedText)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .background(
                    message.role == .user ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .frame(maxWidth: 600, alignment: message.role == .user ? .trailing : .leading)

            if !message.sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sources from your memories")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(message.sources.enumerated()), id: \.element.id) { index, source in
                        NavigationLink {
                            MemoryDetailView(memoryID: source.id, viewModel: viewModel)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: sourceIcon(for: source.memory.kind))
                                    .frame(width: 26)
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("M\(index + 1) · \(source.memory.displayTitle)")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    if let summary = source.memory.displaySummary {
                                        Text(summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(11)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
            }

            if !message.citations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verified excerpts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(message.citations) { citation in
                        if let source = message.sources.first(where: { $0.id == citation.memoryID }) {
                            NavigationLink {
                                MemoryDetailView(memoryID: source.id, viewModel: viewModel)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(citation.locator)
                                        .font(.caption.weight(.semibold))
                                    Text("“\(citation.excerpt)”")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(11)
                                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the original saved memory")
                        }
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
            }

            if message.modelVersion != nil {
                Label(answerStatus, systemImage: message.mode == .grounded ? "checkmark.shield.fill" : "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Model details are available in Settings")
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 16)
    }

    private var answerStatus: String {
        switch message.mode {
        case .grounded: "Verified against saved excerpts"
        case .partial: "Partially verified; unsupported claims were removed"
        case .sourcesOnly: "Sources only; no answer was trusted"
        case .noEvidence: "No supporting memory found"
        case nil: "Answered locally"
        }
    }

    private var renderedText: AttributedString {
        guard message.role == .assistant else {
            return AttributedString(message.text)
        }
        return ChatMarkdownRenderer.render(message.text)
    }

    private func sourceIcon(for kind: MemoryKind) -> String {
        switch kind {
        case .audio: "waveform"
        case .image: "photo"
        case .link: "link"
        case .pdf: "doc.richtext"
        case .text: "text.quote"
        }
    }

}

private struct BasicModeBanner: View {
    let reason: LocalAIUnavailableReason

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("OpenAI unavailable")
                    .font(.subheadline.weight(.semibold))
                Text("\(reason.detail) AI Help will return matching sources without inventing an answer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "sparkles.slash")
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

nonisolated enum ChatMarkdownRenderer {
    static func render(_ markdown: String) -> AttributedString {
        let normalizedLists = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(normalizeListMarker)
            .joined(separator: "\n")

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: normalizedLists, options: options))
            ?? AttributedString(markdown)
    }

    private static func normalizeListMarker(_ line: Substring) -> String {
        let value = String(line)
        let indentation = value.prefix { $0 == " " || $0 == "\t" }
        let content = value.dropFirst(indentation.count)
        guard content.hasPrefix("* ") || content.hasPrefix("- ") || content.hasPrefix("+ ") else {
            return value
        }
        return String(indentation) + "• " + content.dropFirst(2)
    }
}
