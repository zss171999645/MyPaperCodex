import PaperCodexCore
import SwiftUI
import WebKit

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            sessionBar
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty && model.activeCodexRun == nil {
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
                        if let activeCodexRun = model.activeCodexRun {
                            CodexRunBubble(run: activeCodexRun)
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

            CodexStatusLine(
                diagnostic: model.codexDiagnostic,
                modelOverride: model.codexModelOverride,
                reasoningEffort: model.codexReasoningEffort,
                onModelOverride: { model.setCodexModelOverride($0) },
                onReasoningEffort: { model.setCodexReasoningEffort($0) }
            ) {
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
    var modelOverride: String
    var reasoningEffort: CodexReasoningEffort
    var onModelOverride: (String) -> Void
    var onReasoningEffort: (CodexReasoningEffort) -> Void
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
            if shouldOfferCompatibleModel {
                Button("Use gpt-5.4-mini") {
                    onModelOverride("gpt-5.4-mini")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Menu {
                Button("Default") {
                    onModelOverride("")
                }
                Divider()
                Button("gpt-5.4-mini") {
                    onModelOverride("gpt-5.4-mini")
                }
                Button("gpt-5.4") {
                    onModelOverride("gpt-5.4")
                }
                Button("gpt-5.3-codex") {
                    onModelOverride("gpt-5.3-codex")
                }
            } label: {
                Label(modelLabel, systemImage: "slider.horizontal.3")
                    .labelStyle(.titleAndIcon)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .controlSize(.small)
            Menu {
                ForEach(CodexReasoningEffort.allCases, id: \.self) { effort in
                    Button {
                        onReasoningEffort(effort)
                    } label: {
                        if effort == reasoningEffort {
                            Label(effort.displayName, systemImage: "checkmark")
                        } else {
                            Text(effort.displayName)
                        }
                    }
                }
            } label: {
                Label(reasoningLabel, systemImage: "brain.head.profile")
                    .labelStyle(.titleAndIcon)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .controlSize(.small)
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

    private var modelLabel: String {
        let trimmed = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Default" : trimmed
    }

    private var reasoningLabel: String {
        "Think \(reasoningEffort.displayName)"
    }

    private var shouldOfferCompatibleModel: Bool {
        diagnostic?.title == "Codex model incompatible"
            && modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

private struct CodexRunBubble: View {
    var run: ActiveCodexRun

    private var visibleEvents: [CodexRunEvent] {
        Array(run.events.suffix(16))
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Codex")
                        .font(.caption.weight(.semibold))
                    Text("Running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(run.events.count) events")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleEvents) { event in
                        CodexRunEventRow(event: event)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 32)
        }
    }
}

private struct CodexRunEventRow: View {
    var event: CodexRunEvent
    @State private var isExpanded = false

    var body: some View {
        if event.kind == .terminal {
            DisclosureGroup(isExpanded: $isExpanded) {
                Text(event.detail)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } label: {
                eventHeader
            }
            .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                eventHeader
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(event.kind == .tool ? 3 : 2)
            }
        }
    }

    private var eventHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(event.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            if event.kind == .terminal, !isExpanded {
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var iconName: String {
        switch event.kind {
        case .status:
            "circle.dotted"
        case .thinking:
            "brain.head.profile"
        case .tool:
            "wrench.and.screwdriver"
        case .terminal:
            "terminal"
        case .answer:
            "text.bubble"
        case .warning:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        case .raw:
            "doc.plaintext"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .status:
            .blue
        case .thinking:
            .purple
        case .tool:
            .indigo
        case .terminal:
            .gray
        case .answer:
            .green
        case .warning:
            .orange
        case .error:
            .red
        case .raw:
            .secondary
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

    private var renderedMarkdown: String {
        failureNotice?.messageContent ?? parsed.displayMarkdown
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
                MarkdownMessageView(markdown: renderedMarkdown, onCitation: onCitation)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

private struct MarkdownMessageView: View {
    var markdown: String
    var onCitation: (String) -> Void
    @State private var height: CGFloat = 24

    var body: some View {
        MarkdownWebView(
            html: ChatMarkdownRenderer.renderDocument(markdown: markdown),
            height: $height,
            onCitation: onCitation
        )
        .frame(minHeight: 24)
        .frame(height: max(24, height))
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    var html: String
    @Binding var height: CGFloat
    var onCitation: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, onCitation: onCitation)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "height")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        context.coordinator.currentHTML = html
        webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: "/"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCitation = onCitation
        if context.coordinator.currentHTML != html {
            context.coordinator.currentHTML = html
            webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: "/"))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var onCitation: (String) -> Void
        var currentHTML: String?

        init(height: Binding<CGFloat>, onCitation: @escaping (String) -> Void) {
            _height = height
            self.onCitation = onCitation
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "height" else {
                return
            }
            let value: CGFloat?
            if let number = message.body as? NSNumber {
                value = CGFloat(truncating: number)
            } else if let double = message.body as? Double {
                value = CGFloat(double)
            } else {
                value = nil
            }
            if let value, value > 0, abs(value - height) > 1 {
                DispatchQueue.main.async {
                    self.height = value
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)") { [weak self] result, _ in
                guard let self else {
                    return
                }
                let value: CGFloat?
                if let number = result as? NSNumber {
                    value = CGFloat(truncating: number)
                } else if let double = result as? Double {
                    value = CGFloat(double)
                } else {
                    value = nil
                }
                if let value, value > 0 {
                    DispatchQueue.main.async {
                        self.height = value
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               let citationID = CitationParser.citationID(from: url) {
                onCitation(citationID)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
        webView.navigationDelegate = nil
    }
}
