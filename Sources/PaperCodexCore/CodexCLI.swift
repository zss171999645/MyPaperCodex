import Foundation

public enum CodexCLIError: Error, CustomStringConvertible, Equatable {
    case executableNotFound
    case processFailed(status: Int32, stderr: String)

    public var description: String {
        switch self {
        case .executableNotFound:
            "Could not find the codex executable in PATH"
        case let .processFailed(status, stderr):
            "Codex process failed with status \(status): \(stderr)"
        }
    }
}

public final class CodexRunHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    public init() {}

    func setProcess(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel, process.isRunning {
            process.terminate()
        }
    }

    func clearProcess(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }

    public func cancel() {
        lock.lock()
        isCancelled = true
        let runningProcess = process
        lock.unlock()
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }
}

public struct CodexCapabilities: Equatable, Sendable {
    public var supportsJSONOutput: Bool
    public var supportsOutputLastMessage: Bool
    public var supportsResume: Bool

    public init(supportsJSONOutput: Bool, supportsOutputLastMessage: Bool, supportsResume: Bool) {
        self.supportsJSONOutput = supportsJSONOutput
        self.supportsOutputLastMessage = supportsOutputLastMessage
        self.supportsResume = supportsResume
    }
}

public struct CodexExecutableCandidate: Equatable, Sendable {
    public var path: String
    public var version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}

public enum CodexReasoningEffort: String, Codable, CaseIterable, Sendable {
    case `default`
    case low
    case medium
    case high
    case xhigh

    public var codexConfigValue: String? {
        self == .default ? nil : rawValue
    }

    public var displayName: String {
        switch self {
        case .default:
            "Default"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .xhigh:
            "XHigh"
        }
    }
}

public enum CodexRunEventKind: String, Codable, Equatable, Sendable {
    case status
    case thinking
    case tool
    case terminal
    case answer
    case usage
    case warning
    case error
    case raw
}

public struct CodexTokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningOutputTokens: Int

    public init(
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningOutputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }

    public var isEmpty: Bool {
        inputTokens == 0 && cachedInputTokens == 0 && outputTokens == 0 && reasoningOutputTokens == 0
    }

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    public mutating func add(_ usage: CodexTokenUsage) {
        inputTokens += usage.inputTokens
        cachedInputTokens += usage.cachedInputTokens
        outputTokens += usage.outputTokens
        reasoningOutputTokens += usage.reasoningOutputTokens
    }

    public func adding(_ usage: CodexTokenUsage) -> CodexTokenUsage {
        var copy = self
        copy.add(usage)
        return copy
    }

    public var compactSummary: String {
        var parts = [
            "\(Self.compact(inputTokens)) in",
            "\(Self.compact(outputTokens)) out"
        ]
        if reasoningOutputTokens > 0 {
            parts.append("\(Self.compact(reasoningOutputTokens)) reasoning")
        }
        if cachedInputTokens > 0 {
            parts.append("\(Self.compact(cachedInputTokens)) cached")
        }
        return parts.joined(separator: " · ")
    }

    private static func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fm", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

public struct CodexRunEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: CodexRunEventKind
    public var title: String
    public var detail: String
    public var tokenUsage: CodexTokenUsage?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        kind: CodexRunEventKind,
        title: String,
        detail: String,
        tokenUsage: CodexTokenUsage? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.tokenUsage = tokenUsage
        self.createdAt = createdAt
    }

    public var displayTitle: String {
        firstLine(title, limit: 96)
    }

    public var previewDetail: String {
        firstLine(detail, limit: 96)
    }

    private func firstLine(_ value: String, limit: Int) -> String {
        let normalized = value
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        guard normalized.count > limit else {
            return normalized
        }
        let end = normalized.index(normalized.startIndex, offsetBy: max(0, limit - 1))
        return String(normalized[..<end]) + "…"
    }
}

public enum CodexJSONEventParser {
    public static func parseLine(_ line: String) throws -> CodexRunEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let data = trimmed.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CodexRunEvent(kind: .raw, title: "Codex", detail: trimmed)
        }

        let payload = json["payload"] as? [String: Any]
        let item = json["item"] as? [String: Any]
        let effective = payload ?? item ?? json
        let type = stringValue(named: "type", in: effective)
            ?? stringValue(named: "type", in: json)
            ?? "event"
        let lowerType = type.lowercased()

        if lowerType.contains("turn.completed"),
           let usage = tokenUsage(in: effective) ?? tokenUsage(in: json) {
            return CodexRunEvent(
                kind: .usage,
                title: "Token usage",
                detail: usage.compactSummary,
                tokenUsage: usage
            )
        }
        if lowerType.contains("thread.started") {
            let threadID = stringValue(named: "thread_id", in: effective)
                ?? stringValue(named: "thread_id", in: json)
                ?? "unknown"
            return CodexRunEvent(kind: .status, title: "Session", detail: "Codex session \(threadID) started")
        }
        if lowerType.contains("turn.started") {
            return CodexRunEvent(kind: .status, title: "Turn", detail: "Codex turn started")
        }
        if lowerType.contains("reasoning") || lowerType.contains("thinking") {
            let detail = summaryText(in: effective)
                ?? stringValue(named: "text", in: effective)
                ?? stringValue(named: "message", in: effective)
                ?? type
            return CodexRunEvent(kind: .thinking, title: "Thinking", detail: detail)
        }
        if lowerType.contains("exec_command") || lowerType.contains("terminal") || lowerType.contains("command") {
            let command = stringValue(named: "cmd", in: effective)
                ?? stringValue(named: "command", in: effective)
            let output = stringValue(named: "stdout", in: effective)
                ?? stringValue(named: "stderr", in: effective)
                ?? stringValue(named: "output", in: effective)
                ?? stringValue(named: "text", in: effective)
            if let command {
                return CodexRunEvent(kind: .terminal, title: command, detail: "Running command")
            }
            return CodexRunEvent(kind: .terminal, title: "Command output", detail: output ?? compactJSONString(effective) ?? type)
        }
        if lowerType.contains("tool") || lowerType.contains("function_call") {
            let name = stringValue(named: "name", in: effective)
                ?? stringValue(named: "tool_name", in: effective)
                ?? stringValue(named: "call_id", in: effective)
                ?? "Tool"
            let arguments = compactJSONString(effective["arguments"])
                ?? compactJSONString(effective["args"])
                ?? stringValue(named: "arguments", in: effective)
                ?? stringValue(named: "input", in: effective)
                ?? name
            return CodexRunEvent(kind: .tool, title: name, detail: arguments)
        }
        if lowerType.contains("message") || lowerType.contains("answer") {
            let detail = stringValue(named: "text", in: effective)
                ?? stringValue(named: "message", in: effective)
                ?? summaryText(in: effective)
                ?? compactJSONString(effective)
                ?? type
            return CodexRunEvent(kind: .answer, title: "Answer", detail: detail)
        }
        if lowerType.contains("error") || lowerType.contains("failed") {
            let detail = stringValue(named: "message", in: effective)
                ?? stringValue(named: "error", in: effective)
                ?? compactJSONString(effective)
                ?? type
            return CodexRunEvent(kind: .error, title: "Error", detail: detail)
        }
        if lowerType.contains("warning") || lowerType.contains("warn") {
            let detail = stringValue(named: "message", in: effective)
                ?? stringValue(named: "detail", in: effective)
                ?? compactJSONString(effective)
                ?? type
            return CodexRunEvent(kind: .warning, title: "Warning", detail: detail)
        }

        return CodexRunEvent(kind: .raw, title: type, detail: compactJSONString(effective) ?? trimmed)
    }

    private static func tokenUsage(in value: Any?) -> CodexTokenUsage? {
        guard let dictionary = value as? [String: Any],
              let usage = dictionary["usage"] as? [String: Any] else {
            return nil
        }
        let tokenUsage = CodexTokenUsage(
            inputTokens: integerValue(named: "input_tokens", in: usage),
            cachedInputTokens: integerValue(named: "cached_input_tokens", in: usage),
            outputTokens: integerValue(named: "output_tokens", in: usage),
            reasoningOutputTokens: integerValue(named: "reasoning_output_tokens", in: usage)
        )
        return tokenUsage.isEmpty ? nil : tokenUsage
    }

    private static func integerValue(named key: String, in value: Any?) -> Int {
        guard let dictionary = value as? [String: Any],
              let raw = dictionary[key] else {
            return 0
        }
        if let int = raw as? Int {
            return int
        }
        if let double = raw as? Double {
            return Int(double)
        }
        if let string = raw as? String {
            return Int(string) ?? 0
        }
        return 0
    }

    private static func summaryText(in value: Any?) -> String? {
        guard let value else {
            return nil
        }
        if let dictionary = value as? [String: Any],
           let summary = dictionary["summary"] {
            return summaryText(in: summary)
        }
        if let array = value as? [Any] {
            let parts = array.compactMap { item -> String? in
                if let text = item as? String {
                    return text
                }
                if let dictionary = item as? [String: Any] {
                    return stringValue(named: "text", in: dictionary)
                        ?? stringValue(named: "summary_text", in: dictionary)
                }
                return nil
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
        return nil
    }

    private static func stringValue(named key: String, in value: Any?) -> String? {
        guard let value else {
            return nil
        }
        if let dictionary = value as? [String: Any] {
            if let string = dictionary[key] as? String, !string.isEmpty {
                return string
            }
            for nested in dictionary.values {
                if let found = stringValue(named: key, in: nested) {
                    return found
                }
            }
        }
        if let array = value as? [Any] {
            for nested in array {
                if let found = stringValue(named: key, in: nested) {
                    return found
                }
            }
        }
        return nil
    }

    private static func compactJSONString(_ value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}

private final class CodexStreamBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutRemainder = ""
    private var stderrRemainder = ""

    func appendStdout(_ data: Data) -> [CodexRunEvent] {
        guard !data.isEmpty else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        let lines: [String]
        lock.lock()
        stdoutData.append(data)
        stdoutRemainder += text
        lines = Self.consumeLines(from: &stdoutRemainder)
        lock.unlock()
        return lines.compactMap { try? CodexJSONEventParser.parseLine($0) }
    }

    func appendStderr(_ data: Data) -> [CodexRunEvent] {
        guard !data.isEmpty else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        let lines: [String]
        lock.lock()
        stderrData.append(data)
        stderrRemainder += text
        lines = Self.consumeLines(from: &stderrRemainder)
        lock.unlock()
        return lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { CodexRunEvent(kind: .terminal, title: "Codex log", detail: $0) }
    }

    func finish() -> (stdout: String, stderr: String, events: [CodexRunEvent]) {
        let stdoutRemainderSnapshot: String
        let stderrRemainderSnapshot: String
        let stdout: String
        let stderr: String
        lock.lock()
        stdoutRemainderSnapshot = stdoutRemainder
        stderrRemainderSnapshot = stderrRemainder
        stdout = String(decoding: stdoutData, as: UTF8.self)
        stderr = String(decoding: stderrData, as: UTF8.self)
        lock.unlock()

        var events: [CodexRunEvent] = []
        if let event = try? CodexJSONEventParser.parseLine(stdoutRemainderSnapshot) {
            events.append(event)
        }
        let trimmedStderrRemainder = stderrRemainderSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStderrRemainder.isEmpty {
            events.append(CodexRunEvent(kind: .terminal, title: "Codex log", detail: trimmedStderrRemainder))
        }
        return (stdout, stderr, events)
    }

    private static func consumeLines(from buffer: inout String) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(where: { $0.isNewline }) {
            lines.append(String(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        return lines
    }
}

public enum CodexDiagnosticSeverity: String, Codable, Equatable, Sendable {
    case ready
    case warning
    case blocked
}

public struct CodexDiagnostic: Equatable, Sendable {
    public var severity: CodexDiagnosticSeverity
    public var title: String
    public var detail: String
    public var executablePath: String?
    public var version: String?
    public var capabilities: CodexCapabilities?

    public static func ready(
        executablePath: String,
        version: String?,
        capabilities: CodexCapabilities,
        modelOverride: String? = nil
    ) -> CodexDiagnostic {
        let trimmedModel = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelDetail = trimmedModel.map { " Using app model override \($0)." } ?? ""
        return CodexDiagnostic(
            severity: .ready,
            title: "Codex ready",
            detail: "CLI \(version ?? "unknown version") supports Paper Codex sessions.\(modelDetail)",
            executablePath: executablePath,
            version: version,
            capabilities: capabilities
        )
    }

    public static func warning(
        executablePath: String,
        version: String?,
        capabilities: CodexCapabilities,
        missing: [String]
    ) -> CodexDiagnostic {
        CodexDiagnostic(
            severity: .warning,
            title: "Codex needs attention",
            detail: "CLI \(version ?? "unknown version") is missing: \(missing.joined(separator: ", ")).",
            executablePath: executablePath,
            version: version,
            capabilities: capabilities
        )
    }

    public static func blocked(_ detail: String, title: String = "Codex unavailable") -> CodexDiagnostic {
        CodexDiagnostic(
            severity: .blocked,
            title: title,
            detail: detail,
            executablePath: nil,
            version: nil,
            capabilities: nil
        )
    }
}

public struct CodexCLI: Sendable {
    public var executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    public static func sanitizedProcessEnvironment(
        workingDirectoryURL: URL,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["PWD"] = workingDirectoryURL.standardizedFileURL.path
        environment.removeValue(forKey: "OLDPWD")
        return environment
    }

    public static func findCodexExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferWorkspaceImageOutput: Bool = false
    ) throws -> String {
        let pathValue = environment["PATH"] ?? ""
        let candidatePaths = pathValue
            .split(separator: ":")
            .map { String($0) + "/codex" }
            + [
                "/Applications/Codex.app/Contents/Resources/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex"
            ]

        var seen: Set<String> = []
        let candidates = candidatePaths.compactMap { path -> CodexExecutableCandidate? in
            guard !seen.contains(path) else {
                return nil
            }
            seen.insert(path)
            guard FileManager.default.isExecutableFile(atPath: path) else {
                return nil
            }
            let version = try? CodexCLI(executablePath: path).version()
            return CodexExecutableCandidate(path: path, version: version)
        }

        if let selected = selectBestExecutable(
            candidates: candidates,
            preferWorkspaceImageOutput: preferWorkspaceImageOutput
        ) {
            return selected.path
        }
        throw CodexCLIError.executableNotFound
    }

    public static func selectBestExecutable(
        candidates: [CodexExecutableCandidate],
        preferWorkspaceImageOutput: Bool = false
    ) -> CodexExecutableCandidate? {
        if preferWorkspaceImageOutput,
           let imageCandidate = candidates.first(where: { supportsWorkspaceImageOutput(version: $0.version) }) {
            return imageCandidate
        }
        guard var best = candidates.first else {
            return nil
        }
        for candidate in candidates.dropFirst() {
            switch (candidate.version, best.version) {
            case let (candidateVersion?, bestVersion?):
                if compareVersion(candidateVersion, bestVersion) == .orderedDescending {
                    best = candidate
                }
            case (_?, nil):
                best = candidate
            case (nil, _?):
                continue
            case (nil, nil):
                continue
            }
        }
        return best
    }

    private static func supportsWorkspaceImageOutput(version: String?) -> Bool {
        guard let version else {
            return false
        }
        return compareVersion(version, "0.120.0") == .orderedAscending
    }

    public func startArguments(
        prompt: String,
        workspacePath: String,
        outputLastMessagePath: String? = nil,
        modelOverride: String? = nil,
        reasoningEffort: CodexReasoningEffort = .default
    ) -> [String] {
        var arguments = ["exec", "--skip-git-repo-check", "--json", "--enable", "image_generation"]
        if let modelOverride = Self.normalizedModelOverride(modelOverride) {
            arguments += ["--model", modelOverride]
        }
        if let reasoningEffort = reasoningEffort.codexConfigValue {
            arguments += ["-c", "model_reasoning_effort=\"\(reasoningEffort)\""]
        }
        arguments += ["-C", workspacePath]
        if let outputLastMessagePath {
            arguments += ["--output-last-message", outputLastMessagePath]
        }
        arguments.append(prompt)
        return arguments
    }

    public func resumeArguments(
        sessionID: String,
        prompt: String,
        outputLastMessagePath: String? = nil,
        modelOverride: String? = nil,
        reasoningEffort: CodexReasoningEffort = .default
    ) -> [String] {
        var arguments = ["exec", "resume", "--skip-git-repo-check", "--json", "--enable", "image_generation"]
        if let modelOverride = Self.normalizedModelOverride(modelOverride) {
            arguments += ["--model", modelOverride]
        }
        if let reasoningEffort = reasoningEffort.codexConfigValue {
            arguments += ["-c", "model_reasoning_effort=\"\(reasoningEffort)\""]
        }
        if let outputLastMessagePath {
            arguments += ["--output-last-message", outputLastMessagePath]
        }
        arguments += [sessionID, prompt]
        return arguments
    }

    public func version() throws -> String? {
        try Self.parseVersion(from: run(arguments: ["--version"]))
    }

    public func capabilities() throws -> CodexCapabilities {
        try Self.parseCapabilities(fromExecHelp: run(arguments: ["exec", "--help"]))
    }

    public static func diagnose(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configText: String? = nil,
        modelOverride: String? = nil
    ) -> CodexDiagnostic {
        do {
            let executable = try findCodexExecutable(environment: environment)
            let cli = CodexCLI(executablePath: executable)
            let version = try cli.version()
            let capabilities = try cli.capabilities()
            return diagnostic(
                executablePath: executable,
                version: version,
                capabilities: capabilities,
                configText: configText ?? readDefaultConfig(environment: environment),
                modelOverride: modelOverride
            )
        } catch {
            return .blocked(String(describing: error))
        }
    }

    public static func diagnostic(
        executablePath: String,
        version: String?,
        capabilities: CodexCapabilities,
        configText: String?,
        modelOverride: String? = nil
    ) -> CodexDiagnostic {
        let normalizedOverride = normalizedModelOverride(modelOverride)
        if normalizedOverride == nil,
           let issue = configuredModelIssue(configText: configText, cliVersion: version) {
            return .blocked(issue, title: "Codex model incompatible")
        }

        var missing: [String] = []
        if !capabilities.supportsJSONOutput {
            missing.append("--json")
        }
        if !capabilities.supportsOutputLastMessage {
            missing.append("--output-last-message")
        }
        if !capabilities.supportsResume {
            missing.append("exec resume")
        }
        if missing.isEmpty {
            return .ready(
                executablePath: executablePath,
                version: version,
                capabilities: capabilities,
                modelOverride: normalizedOverride
            )
        }
        return .warning(executablePath: executablePath, version: version, capabilities: capabilities, missing: missing)
    }

    public static func parseConfiguredModel(from configText: String) -> String? {
        for rawLine in configText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                return nil
            }
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0] == "model" else {
                continue
            }
            return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    public static func configuredDefaultModelID(
        configText: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let config = configText ?? readDefaultConfig(environment: environment)
        return config.flatMap(parseConfiguredModel(from:))
    }

    public static func configuredModelIssue(configText: String?, cliVersion: String?) -> String? {
        guard let configText,
              parseConfiguredModel(from: configText) == "gpt-5.5" else {
            return nil
        }
        guard let cliVersion else {
            return "Default Codex model gpt-5.5 is configured, but the CLI version could not be read. Run `codex --version`, upgrade Codex, or choose a supported model in ~/.codex/config.toml."
        }
        guard compareVersion(cliVersion, "0.114.0") != .orderedDescending else {
            return nil
        }
        return "Default Codex model gpt-5.5 requires a newer Codex CLI than \(cliVersion). Upgrade Codex or choose a supported model in ~/.codex/config.toml."
    }

    public func availableModelIDs(configText: String? = nil) throws -> [String] {
        let version = try version()
        let data = try Data(contentsOf: URL(fileURLWithPath: executablePath))
        let embeddedText = String(decoding: data, as: UTF8.self)
        return Self.availableModelIDs(
            cliVersion: version,
            embeddedText: embeddedText,
            configText: configText ?? Self.readDefaultConfig(environment: ProcessInfo.processInfo.environment)
        )
    }

    public static func availableModelIDs(
        cliVersion: String?,
        embeddedText: String?,
        configText: String?
    ) -> [String] {
        var models: Set<String> = []
        for fallback in fallbackModelIDs {
            models.insert(fallback)
        }
        if let configured = configText.flatMap(parseConfiguredModel(from:)) {
            models.insert(configured)
        }
        if let embeddedText {
            for model in extractEmbeddedModelIDs(from: embeddedText) {
                models.insert(model)
            }
        }
        return models
            .filter { isSupportedModelID($0, cliVersion: cliVersion) }
            .sorted(by: compareModelIDs)
    }

    private static func readDefaultConfig(environment: [String: String]) -> String? {
        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        let configURL = URL(fileURLWithPath: home)
            .appendingPathComponent(".codex/config.toml")
        return try? String(contentsOf: configURL, encoding: .utf8)
    }

    private static let fallbackModelIDs = [
        "gpt-5.4",
        "gpt-5.3-codex",
        "gpt-5.2",
        "gpt-5.1-codex",
        "gpt-5-codex"
    ]

    private static func extractEmbeddedModelIDs(from text: String) -> [String] {
        let pattern = #"\bgpt-(?:oss-\d+b|\d+[a-z]?(?:\.\d+)*(?:-(?:codex|max|mini|nano|latest))*)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen: Set<String> = []
        var result: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let modelRange = Range(match.range, in: text) else {
                continue
            }
            let model = String(text[modelRange])
            guard !seen.contains(model) else {
                continue
            }
            seen.insert(model)
            result.append(model)
        }
        return result
    }

    private static func isSupportedModelID(_ modelID: String, cliVersion: String?) -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == trimmed.lowercased(),
              trimmed.hasPrefix("gpt-") else {
            return false
        }
        if trimmed == "gpt-5.5" {
            return configuredModelIssue(configText: #"model = "gpt-5.5""#, cliVersion: cliVersion) == nil
        }
        return true
    }

    private static func compareModelIDs(_ left: String, _ right: String) -> Bool {
        if left == right {
            return false
        }
        let leftCodex = left.contains("codex")
        let rightCodex = right.contains("codex")
        if leftCodex != rightCodex {
            return leftCodex
        }
        return left.localizedStandardCompare(right) == .orderedDescending
    }

    private static func compareVersion(_ left: String, _ right: String) -> ComparisonResult {
        let leftNumbers = left.split(separator: ".").map { Int($0) ?? 0 }
        let rightNumbers = right.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(leftNumbers.count, rightNumbers.count)
        for index in 0..<count {
            let leftValue = index < leftNumbers.count ? leftNumbers[index] : 0
            let rightValue = index < rightNumbers.count ? rightNumbers[index] : 0
            if leftValue < rightValue {
                return .orderedAscending
            }
            if leftValue > rightValue {
                return .orderedDescending
            }
        }
        return .orderedSame
    }

    private static func normalizedModelOverride(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func run(arguments: [String], currentDirectoryURL: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        configureProcessDirectory(process, currentDirectoryURL: currentDirectoryURL)

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus != 0 {
            throw CodexCLIError.processFailed(status: process.terminationStatus, stderr: stderr)
        }
        return stdout
    }

    public func runStreaming(
        arguments: [String],
        eventLogURL: URL? = nil,
        currentDirectoryURL: URL? = nil,
        runHandle: CodexRunHandle? = nil,
        onEvent: @escaping @Sendable (CodexRunEvent) -> Void
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        configureProcessDirectory(process, currentDirectoryURL: currentDirectoryURL)

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        let streamBuffer = CodexStreamBuffer()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            while true {
                let data = output.fileHandleForReading.availableData
                if data.isEmpty {
                    break
                }
                for event in streamBuffer.appendStdout(data) {
                    onEvent(event)
                }
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            while true {
                let data = error.fileHandleForReading.availableData
                if data.isEmpty {
                    break
                }
                for event in streamBuffer.appendStderr(data) {
                    onEvent(event)
                }
            }
            group.leave()
        }

        try process.run()
        runHandle?.setProcess(process)
        process.waitUntilExit()
        runHandle?.clearProcess(process)
        group.wait()

        let result = streamBuffer.finish()
        for event in result.events {
            onEvent(event)
        }
        if let eventLogURL {
            try result.stdout.write(to: eventLogURL, atomically: true, encoding: .utf8)
        }
        if process.terminationStatus != 0 {
            throw CodexCLIError.processFailed(status: process.terminationStatus, stderr: result.stderr)
        }
        return result.stdout
    }

    private func configureProcessDirectory(_ process: Process, currentDirectoryURL: URL?) {
        let workingDirectoryURL = (currentDirectoryURL ?? Self.defaultProcessWorkingDirectory()).standardizedFileURL
        process.currentDirectoryURL = workingDirectoryURL
        process.environment = Self.sanitizedProcessEnvironment(workingDirectoryURL: workingDirectoryURL)
    }

    private static func defaultProcessWorkingDirectory() -> URL {
        FileManager.default.temporaryDirectory.standardizedFileURL
    }

    public static func parseThreadID(from jsonl: String) -> String? {
        for line in jsonl.split(separator: "\n") {
            guard line.contains(#""type":"thread.started""#) || line.contains(#""type": "thread.started""#) else {
                continue
            }
            if let threadID = extractJSONStringValue(named: "thread_id", from: String(line)) {
                return threadID
            }
        }
        return nil
    }

    public static func aggregateTokenUsage(from jsonl: String) -> CodexTokenUsage? {
        var aggregate = CodexTokenUsage()
        for line in jsonl.split(separator: "\n") {
            guard let event = try? CodexJSONEventParser.parseLine(String(line)),
                  let usage = event.tokenUsage else {
                continue
            }
            aggregate.add(usage)
        }
        return aggregate.isEmpty ? nil : aggregate
    }

    public static func parseVersion(from output: String) -> String? {
        let tokens = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        return tokens.last
    }

    public static func parseCapabilities(fromExecHelp output: String) -> CodexCapabilities {
        CodexCapabilities(
            supportsJSONOutput: output.contains("--json"),
            supportsOutputLastMessage: output.contains("--output-last-message"),
            supportsResume: output.contains("resume")
        )
    }

    private static func extractJSONStringValue(named key: String, from line: String) -> String? {
        let compactPrefix = #""\#(key)":"#
        let spacedPrefix = #""\#(key)": "#
        guard let prefixRange = line.range(of: compactPrefix) ?? line.range(of: spacedPrefix) else {
            return nil
        }
        var cursor = prefixRange.upperBound
        guard cursor < line.endIndex, line[cursor] == "\"" else {
            return nil
        }
        cursor = line.index(after: cursor)
        guard let end = line[cursor...].firstIndex(of: "\"") else {
            return nil
        }
        return String(line[cursor..<end])
    }
}
