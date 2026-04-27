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

    public static func findCodexExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let pathValue = environment["PATH"] ?? ""
        let candidates = pathValue
            .split(separator: ":")
            .map { String($0) + "/codex" }
            + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw CodexCLIError.executableNotFound
    }

    public func startArguments(
        prompt: String,
        workspacePath: String,
        outputLastMessagePath: String? = nil,
        modelOverride: String? = nil
    ) -> [String] {
        var arguments = ["exec", "--skip-git-repo-check", "--json"]
        if let modelOverride = Self.normalizedModelOverride(modelOverride) {
            arguments += ["--model", modelOverride]
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
        modelOverride: String? = nil
    ) -> [String] {
        var arguments = ["exec", "resume", "--skip-git-repo-check", "--json"]
        if let modelOverride = Self.normalizedModelOverride(modelOverride) {
            arguments += ["--model", modelOverride]
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

    private static func readDefaultConfig(environment: [String: String]) -> String? {
        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        let configURL = URL(fileURLWithPath: home)
            .appendingPathComponent(".codex/config.toml")
        return try? String(contentsOf: configURL, encoding: .utf8)
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

    public func run(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

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
