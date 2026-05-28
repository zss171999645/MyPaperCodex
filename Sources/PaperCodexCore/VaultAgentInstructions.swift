import Foundation

public struct VaultAgentInstructions: Equatable, Sendable {
    public static let candidateFilenames = ["AGENTS.md", "agents.md", "agent.md"]
    public static let workspaceFilename = "AGENTS.md"

    public var sourceURL: URL
    public var text: String

    public init(sourceURL: URL, text: String) {
        self.sourceURL = sourceURL.standardizedFileURL
        self.text = text
    }

    public static func load(
        vaultRoot: URL,
        fileManager: FileManager = .default
    ) throws -> VaultAgentInstructions? {
        let root = vaultRoot.standardizedFileURL
        let entries = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        let filename = matchingFilename(in: entries)
        guard let filename else {
            return nil
        }
        let sourceURL = root.appendingPathComponent(filename, isDirectory: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        let text = try String(contentsOf: sourceURL, encoding: .utf8)
        return VaultAgentInstructions(sourceURL: sourceURL, text: text)
    }

    public static func writeWorkspaceCopy(
        _ instructions: VaultAgentInstructions,
        workspaceRoot: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = workspaceRoot.standardizedFileURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(workspaceFilename, isDirectory: false)
        try instructions.text.write(to: destination, atomically: true, encoding: .utf8)
        return destination.standardizedFileURL
    }

    private static func matchingFilename(in entries: [String]) -> String? {
        for candidate in candidateFilenames {
            if entries.contains(candidate) {
                return candidate
            }
        }
        for candidate in candidateFilenames {
            if let match = entries.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return match
            }
        }
        return nil
    }
}
