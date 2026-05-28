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
        let imageSnapshot = try GeneratedImageCollector.snapshot(
            in: workspaceURL,
            codexThreadID: request.existingSessionID
        )
        let turnsURL = workspaceURL.appendingPathComponent("turns", isDirectory: true)
        try FileManager.default.createDirectory(at: turnsURL, withIntermediateDirectories: true)
        let outputURL = turnsURL.appendingPathComponent("\(request.outputFilePrefix)-codex.txt")
        let eventLogURL = outputURL.deletingPathExtension().appendingPathExtension("events.jsonl")

        let arguments: [String]
        let imagePaths = request.imageAttachments.map(\.path)
        if let existingSessionID = request.existingSessionID, !request.prefersWorkspaceImageOutput {
            arguments = cli.resumeArguments(
                sessionID: existingSessionID,
                prompt: request.prompt,
                outputLastMessagePath: outputURL.path,
                modelOverride: request.modelOverride,
                reasoningEffort: request.reasoningEffort,
                accessMode: request.accessMode,
                additionalWritableDirectories: request.additionalWritableDirectories,
                imagePaths: request.imageAttachments.map(\.path)
            )
        } else {
            arguments = cli.startArguments(
                prompt: request.prompt,
                workspacePath: request.workspacePath,
                outputLastMessagePath: outputURL.path,
                modelOverride: request.modelOverride,
                reasoningEffort: request.reasoningEffort,
                accessMode: request.accessMode,
                additionalWritableDirectories: request.additionalWritableDirectories,
                imagePaths: imagePaths
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
        let threadID = CodexCLI.parseThreadID(from: stdout)
        let generatedImages = try GeneratedImageCollector.newImages(
            in: workspaceURL,
            excluding: imageSnapshot,
            codexThreadID: threadID ?? request.existingSessionID
        )
        return AgentRuntimeResult(
            stdout: stdout,
            lastMessage: lastMessage,
            threadID: threadID,
            generatedImages: generatedImages,
            tokenUsage: CodexCLI.aggregateTokenUsage(from: stdout)
        )
    }
}
