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
                            MessageBubble(message: message)
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

private struct MessageBubble: View {
    var message: ChatMessage

    private var isUser: Bool {
        message.role == .user
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
                Text(message.content)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
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
