import Foundation

public enum PaperCodexPaths {
    public static let supportRootEnvironmentKey = "PAPER_CODEX_SUPPORT_ROOT"
    public static let obsidianVaultRootEnvironmentKey = "PAPER_CODEX_OBSIDIAN_VAULT_ROOT"
    public static let defaultObsidianVaultPath = "~/Documents/Obsidian-Main/世界模型"

    public static func supportRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = environment[supportRootEnvironmentKey],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }

        return fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperCodex", isDirectory: true)
            .standardizedFileURL
    }

    public static func obsidianVaultRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment[obsidianVaultRootEnvironmentKey] {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return URL(
                fileURLWithPath: (trimmed as NSString).expandingTildeInPath,
                isDirectory: true
            ).standardizedFileURL
        }

        let expandedDefault = (defaultObsidianVaultPath as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: expandedDefault) else {
            return nil
        }
        return URL(fileURLWithPath: expandedDefault, isDirectory: true).standardizedFileURL
    }
}
