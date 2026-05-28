import Foundation

public struct AgentRuntimeRequest: Sendable {
    public var prompt: String
    public var workspacePath: String
    public var existingSessionID: String?
    public var outputFilePrefix: String
    public var modelOverride: String
    public var reasoningEffort: CodexReasoningEffort
    public var accessMode: CodexAccessMode
    public var additionalWritableDirectories: [String]
    public var imageAttachments: [PromptImageAttachment]
    public var prefersWorkspaceImageOutput: Bool
    public var runModeDescription: String

    public init(
        prompt: String,
        workspacePath: String,
        existingSessionID: String?,
        outputFilePrefix: String = UUID().uuidString.lowercased(),
        modelOverride: String,
        reasoningEffort: CodexReasoningEffort,
        accessMode: CodexAccessMode = .fullAccess,
        additionalWritableDirectories: [String] = [],
        imageAttachments: [PromptImageAttachment] = [],
        prefersWorkspaceImageOutput: Bool,
        runModeDescription: String
    ) {
        self.prompt = prompt
        self.workspacePath = workspacePath
        self.existingSessionID = existingSessionID
        self.outputFilePrefix = outputFilePrefix
        self.modelOverride = modelOverride
        self.reasoningEffort = reasoningEffort
        self.accessMode = accessMode
        self.additionalWritableDirectories = additionalWritableDirectories
        self.imageAttachments = imageAttachments
        self.prefersWorkspaceImageOutput = prefersWorkspaceImageOutput
        self.runModeDescription = runModeDescription
    }
}

public struct AgentRuntimeResult: Sendable {
    public var stdout: String
    public var lastMessage: String
    public var threadID: String?
    public var generatedImages: [URL]
    public var tokenUsage: CodexTokenUsage?

    public init(
        stdout: String,
        lastMessage: String,
        threadID: String?,
        generatedImages: [URL],
        tokenUsage: CodexTokenUsage?
    ) {
        self.stdout = stdout
        self.lastMessage = lastMessage
        self.threadID = threadID
        self.generatedImages = generatedImages
        self.tokenUsage = tokenUsage
    }
}

public protocol AgentRuntime: Sendable {
    func runCodexTurn(
        _ request: AgentRuntimeRequest,
        runHandle: CodexRunHandle,
        onEvent: @escaping @Sendable (CodexRunEvent) -> Void
    ) async throws -> AgentRuntimeResult
}
