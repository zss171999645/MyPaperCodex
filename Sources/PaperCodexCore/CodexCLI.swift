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

    public func startArguments(prompt: String, workspacePath: String, outputLastMessagePath: String? = nil) -> [String] {
        var arguments = ["exec", "--json", "-C", workspacePath]
        if let outputLastMessagePath {
            arguments += ["--output-last-message", outputLastMessagePath]
        }
        arguments.append(prompt)
        return arguments
    }

    public func resumeArguments(sessionID: String, prompt: String, outputLastMessagePath: String? = nil) -> [String] {
        var arguments = ["exec", "resume", "--json"]
        if let outputLastMessagePath {
            arguments += ["--output-last-message", outputLastMessagePath]
        }
        arguments += [sessionID, prompt]
        return arguments
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
