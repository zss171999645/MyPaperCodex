import Foundation

public struct CodexAgentRuntime: AgentRuntime {
    public typealias ExecutableResolver = @Sendable (_ prefersWorkspaceImageOutput: Bool) throws -> String

    private let executableResolver: ExecutableResolver

    public init(
        executableResolver: @escaping ExecutableResolver = {
            try CodexCLI.findCodexExecutable(preferWorkspaceImageOutput: $0)
        }
    ) {
        self.executableResolver = executableResolver
    }

    public func runCodexTurn(
        _ request: AgentRuntimeRequest,
        runHandle: CodexRunHandle,
        onEvent: @escaping @Sendable (CodexRunEvent) -> Void
    ) async throws -> AgentRuntimeResult {
        let executable = try executableResolver(request.prefersWorkspaceImageOutput)
        let cli = CodexCLI(executablePath: executable)
        onEvent(
            CodexRunEvent(
                kind: .status,
                title: "Codex",
                detail: "Launching \(URL(fileURLWithPath: executable).lastPathComponent)"
            )
        )

        let workspaceURL = URL(fileURLWithPath: request.workspacePath, isDirectory: true)
        let imageSnapshot = try GeneratedImageCollector.snapshot(in: workspaceURL)
        let turnsURL = workspaceURL.appendingPathComponent("turns", isDirectory: true)
        try FileManager.default.createDirectory(at: turnsURL, withIntermediateDirectories: true)
        let outputURL = turnsURL.appendingPathComponent("\(request.outputFilePrefix)-codex.txt")
        let eventLogURL = outputURL.deletingPathExtension().appendingPathExtension("events.jsonl")

        let arguments: [String]
        if let existingSessionID = request.existingSessionID, !request.prefersWorkspaceImageOutput {
            arguments = cli.resumeArguments(
                sessionID: existingSessionID,
                prompt: request.prompt,
                outputLastMessagePath: outputURL.path,
                modelOverride: request.modelOverride,
                reasoningEffort: request.reasoningEffort
            )
        } else {
            arguments = cli.startArguments(
                prompt: request.prompt,
                workspacePath: request.workspacePath,
                outputLastMessagePath: outputURL.path,
                modelOverride: request.modelOverride,
                reasoningEffort: request.reasoningEffort
            )
        }

        onEvent(
            CodexRunEvent(
                kind: .status,
                title: "Codex",
                detail: request.runModeDescription
            )
        )

        let stdout = try await Task.detached(priority: .userInitiated) {
            try cli.runStreaming(
                arguments: arguments,
                eventLogURL: eventLogURL,
                currentDirectoryURL: workspaceURL,
                runHandle: runHandle,
                onEvent: onEvent
            )
        }.value
        let lastMessage = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let generatedImages = try GeneratedImageCollector.newImages(in: workspaceURL, excluding: imageSnapshot)
        return AgentRuntimeResult(
            stdout: stdout,
            lastMessage: lastMessage,
            threadID: CodexCLI.parseThreadID(from: stdout),
            generatedImages: generatedImages,
            tokenUsage: CodexCLI.aggregateTokenUsage(from: stdout)
        )
    }
}
