import PaperCodexCore
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            sessionBar
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        ContentUnavailableView(
                            "No Messages",
                            systemImage: "text.bubble",
                            description: Text("Select text in the PDF, then ask Codex in this session. The selected source is inserted into your message.")
                        )
                        .padding(.top, 80)
                    } else {
                        ForEach(model.messages) { message in
                            MessageBubble(
                                message: message,
                                isBusy: model.isSending,
                                onCitation: { citationID in
                                    model.jumpToCitation(citationID)
                                },
                                onRetryFailure: { messageID in
                                    Task {
                                        await model.retryCodexFailure(messageID: messageID)
                                    }
                                },
                                onNewSession: {
                                    model.startFreshSessionFromCurrentPaperSet()
                                }
                            )
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            composer
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sessionBar: some View {
        HStack(spacing: 10) {
            Picker("Session", selection: Binding(
                get: { model.selectedSession?.id ?? "" },
                set: { model.selectSession($0) }
            )) {
                ForEach(model.sessions) { session in
                    Text(session.title).tag(session.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button("New") {
                model.newSessionButtonTapped()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selection = model.currentSelection {
                HStack {
                    Image(systemName: "quote.opening")
                    Text("Selected p\(selection.page): \(selection.text)")
                        .lineLimit(1)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            CodexStatusLine(diagnostic: model.codexDiagnostic) {
                Task {
                    await model.refreshCodexDiagnostic()
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $draft)
                    .font(.system(size: 14))
                    .frame(minHeight: 72, maxHeight: 110)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    let message = draft
                    draft = ""
                    Task {
                        await model.sendMessage(message)
                    }
                } label: {
                    Image(systemName: model.isSending ? "hourglass.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(model.isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }
}

private struct CodexStatusLine: View {
    var diagnostic: CodexDiagnostic?
    var onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Refresh Codex Status")
        }
        .help(detail)
    }

    private var title: String {
        guard let diagnostic else {
            return "Checking Codex"
        }
        if let version = diagnostic.version {
            return "\(diagnostic.title) · \(version)"
        }
        return diagnostic.title
    }

    private var detail: String {
        diagnostic?.detail ?? "Checking local Codex CLI."
    }

    private var iconName: String {
        guard let diagnostic else {
            return "circle.dotted"
        }
        switch diagnostic.severity {
        case .ready:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        guard let diagnostic else {
            return .secondary
        }
        switch diagnostic.severity {
        case .ready:
            return .green
        case .warning:
            return .orange
        case .blocked:
            return .red
        }
    }
}

private struct MessageBubble: View {
    var message: ChatMessage
    var isBusy: Bool
    var onCitation: (String) -> Void
    var onRetryFailure: (String) -> Void
    var onNewSession: () -> Void

    private var isUser: Bool {
        message.role == .user
    }

    private var parsed: ParsedCitationText {
        CitationParser.parse(message.content)
    }

    private var failureNotice: CodexFailureNotice? {
        CodexFailureNotice.parse(message.content)
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 32)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? "You" : "Codex")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(failureNotice?.messageContent ?? parsed.displayText)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                if !parsed.citations.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(parsed.citations) { citation in
                            Button {
                                onCitation(citation.id)
                            } label: {
                                Label("[\(citation.displayIndex)]", systemImage: "scope")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(citation.id)
                        }
                    }
                    .padding(.top, 2)
                }
                if failureNotice != nil {
                    HStack(spacing: 8) {
                        Button {
                            onRetryFailure(message.id)
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy)

                        Button {
                            onNewSession()
                        } label: {
                            Label("New Session", systemImage: "plus.bubble")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(isUser ? Color.blue.opacity(0.12) : Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if !isUser {
                Spacer(minLength: 32)
            }
        }
    }
}
