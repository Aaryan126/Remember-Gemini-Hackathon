import SwiftUI

struct AskRememberView: View {
    let viewModel: LibraryViewModel
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
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
                                Text("Gemma is checking your wiki and its sources…")
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
            .navigationTitle("Ask Remember")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Label("Gemma · On-device", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .accessibilityLabel("Gemma runs on this iPhone")
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
        }
    }

    private var introduction: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Ask your memories")
                .font(.title2.bold())
            Text("Gemma searches your Living Wiki first, verifies its answer against the original memories, and shows the sources it used. Nothing is sent off this iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                suggestion("Where is my next lecture?")
                suggestion("What did I save about the hackathon?")
                suggestion("Find the restaurant I wanted to try")
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 28)
        .padding(.top, 60)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            viewModel.chatInput = text
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
                Task { await viewModel.askRemember() }
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

            if let modelVersion = message.modelVersion {
                Label("Answered locally by \(modelVersion)", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 16)
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
