import Foundation

public struct CodexFailureNotice: Equatable, Sendable {
    public static let prefix = "Codex failed:"

    public var detail: String

    public init(detail: String) {
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var messageContent: String {
        if detail.isEmpty {
            return Self.prefix
        }
        return "\(Self.prefix)\n\(detail)"
    }

    public static func parse(_ content: String) -> CodexFailureNotice? {
        guard content.hasPrefix(prefix) else {
            return nil
        }
        let detail = content
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexFailureNotice(detail: detail)
    }
}
