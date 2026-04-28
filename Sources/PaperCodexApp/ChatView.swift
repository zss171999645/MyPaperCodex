import PaperCodexCore
import SwiftUI
import WebKit

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var isSendButtonHovered = false

    var body: some View {
        VStack(spacing: 0) {
            sessionBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty && model.activeCodexRun == nil {
                        ContentUnavailableView(
                            "No Messages",
                            systemImage: "text.bubble",
                            description: Text("Select text in the PDF, then ask Codex in this session. The selected source appears as a quoted reply.")
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
                        if let activeCodexRun = visibleActiveCodexRun {
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

    private var visibleActiveCodexRun: ActiveCodexRun? {
        guard let run = model.activeCodexRun,
              run.sessionID == model.selectedSession?.id else {
            return nil
        }
        return run
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
                CurrentSelectionReplyCard(selection: selection) {
                    model.clearCurrentSelection()
                }
            }

            QuickPromptLine(
                prompts: model.quickPrompts,
                diagnostic: model.codexDiagnostic,
                modelOverride: model.codexModelOverride,
                reasoningEffort: model.codexReasoningEffort,
                onPrompt: { model.sendQuickPrompt($0) },
                onModelOverride: { model.setCodexModelOverride($0) },
                onReasoningEffort: { model.setCodexReasoningEffort($0) }
            ) {
                Task {
                    await model.refreshCodexDiagnostic()
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ComposerTextView(
                    text: $draft,
                    isEnabled: !model.isSending,
                    onSubmit: sendDraft
                )
                    .frame(minHeight: 72, maxHeight: 110)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    if model.isSending {
                        model.cancelActiveCodexRun()
                    } else {
                        sendDraft()
                    }
                } label: {
                    Image(systemName: sendButtonIcon)
                        .font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .foregroundStyle(sendButtonColor)
                .disabled(!model.isSending && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .onHover { isSendButtonHovered = $0 }
                .help(model.isSending ? "Stop Codex" : "Send")
            }
        }
        .padding(14)
    }

    private var sendButtonIcon: String {
        if model.isSending {
            return isSendButtonHovered ? "xmark.circle.fill" : "hourglass.circle.fill"
        }
        return "arrow.up.circle.fill"
    }

    private var sendButtonColor: Color {
        model.isSending && isSendButtonHovered ? .red : .blue
    }

    private func sendDraft() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isSending, !message.isEmpty else {
            return
        }
        draft = ""
        Task {
            await model.sendMessage(message)
        }
    }
}

private struct QuickPromptLine: View {
    var prompts: [QuickPrompt]
    var diagnostic: CodexDiagnostic?
    var modelOverride: String
    var reasoningEffort: CodexReasoningEffort
    var onPrompt: (QuickPrompt) -> Void
    var onModelOverride: (String) -> Void
    var onReasoningEffort: (CodexReasoningEffort) -> Void
    var onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(prompts) { prompt in
                    Button(prompt.title) {
                        onPrompt(prompt)
                    }
                }
            } label: {
                Label("Quick Prompt", systemImage: "text.bubble")
                    .frame(minWidth: 138, alignment: .leading)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            CodexStatusLine(
                diagnostic: diagnostic,
                modelOverride: modelOverride,
                reasoningEffort: reasoningEffort,
                onModelOverride: onModelOverride,
                onReasoningEffort: onReasoningEffort,
                onRefresh: onRefresh
            )
            .frame(maxWidth: 360)
        }
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
        Array(run.events.filter { $0.kind == .thinking || $0.kind == .answer }.suffix(8))
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
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !visibleEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleEvents) { event in
                            CodexRunEventRow(event: event)
                        }
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

    private var statusText: String {
        visibleEvents.isEmpty ? "Working" : "\(visibleEvents.count) update\(visibleEvents.count == 1 ? "" : "s")"
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
            Text(event.displayTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if event.kind == .terminal, !isExpanded {
                Text(event.previewDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        CitationParser.parse(message.content, maxVisibleCitations: isUser ? nil : 3)
    }

    private var parsedUserSource: ParsedUserSourceMessage {
        UserSourceAttachmentParser.parse(message.content)
    }

    private var userSourceAttachment: UserSourceAttachment? {
        isUser ? parsedUserSource.attachment : nil
    }

    private var failureNotice: CodexFailureNotice? {
        CodexFailureNotice.parse(message.content)
    }

    private var renderedMarkdown: String {
        if let failureNotice {
            return failureNotice.messageContent
        }
        if isUser {
            return parsedUserSource.visibleContent
        }
        return parsed.displayMarkdown
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
                if let userSourceAttachment {
                    UserSourceReplyView(attachment: userSourceAttachment, onOpen: onCitation)
                }
                if !renderedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownMessageView(messageID: message.id, markdown: renderedMarkdown, onCitation: onCitation)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct CurrentSelectionReplyCard: View {
    var selection: PDFSelectionInfo
    var onClear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text("Replying to source · p\(selection.page)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(selection.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove source")
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.65))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct UserSourceReplyView: View {
    var attachment: UserSourceAttachment
    var onOpen: (String) -> Void

    var body: some View {
        Button {
            onOpen(attachment.anchorID)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "quote.opening")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quoted source · p\(attachment.page)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(attachment.selectedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Open quoted source")
    }
}

private struct MarkdownMessageView: View {
    var messageID: String
    var markdown: String
    var onCitation: (String) -> Void
    @State private var height: CGFloat = 24

    var body: some View {
        MarkdownWebView(
            html: ChatMarkdownRenderer.renderDocument(markdown: markdown),
            height: $height,
            onCitation: onCitation
        )
        .id("\(messageID)-\(markdown.hashValue)")
        .frame(minHeight: 24)
        .frame(height: max(24, height))
        .onChange(of: markdown) {
            height = 24
        }
    }
}

private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = SendingTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = context.coordinator.submit
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.string = text
        textView.minSize = NSSize(width: 0, height: 72)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        guard let textView = scrollView.documentView as? SendingTextView else {
            return
        }
        textView.onSubmit = context.coordinator.submit
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }

        func submit() {
            onSubmit()
        }
    }

    final class SendingTextView: NSTextView {
        var onSubmit: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            if isReturn, !event.modifierFlags.contains(.shift) {
                onSubmit?()
                return
            }
            super.keyDown(with: event)
        }
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
        let webView = ScrollForwardingWebView(frame: .zero, configuration: configuration)
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

    final class ScrollForwardingWebView: WKWebView {
        override func scrollWheel(with event: NSEvent) {
            if let outerScrollView = findOuterScrollView() {
                outerScrollView.scrollWheel(with: event)
                return
            }
            super.scrollWheel(with: event)
        }

        private func findOuterScrollView() -> NSScrollView? {
            var view = superview
            while let current = view {
                if let scrollView = current.enclosingScrollView {
                    return scrollView
                }
                view = current.superview
            }
            return nil
        }
    }
}
