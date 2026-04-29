import Foundation

public struct LocalEnrichmentPreferences: Codable, Equatable, Sendable {
    public var autoEnrichOnOpen: Bool
    public var autoEnrichOnSave: Bool

    public init(autoEnrichOnOpen: Bool = false, autoEnrichOnSave: Bool = false) {
        self.autoEnrichOnOpen = autoEnrichOnOpen
        self.autoEnrichOnSave = autoEnrichOnSave
    }
}

public struct EmbeddingProviderSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var baseURL: String
    public var model: String

    public init(enabled: Bool = false, baseURL: String = "", model: String = "") {
        self.enabled = enabled
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalized: EmbeddingProviderSettings {
        EmbeddingProviderSettings(enabled: enabled, baseURL: baseURL, model: model)
    }
}

public struct LocalDiscoverPreferences: Codable, Equatable, Sendable {
    public var categories: [String]
    public var whitelistTags: [String]
    public var blacklistTags: [String]
    public var similaritySourceTagIDs: [String]
    public var enrichment: LocalEnrichmentPreferences
    public var embedding: EmbeddingProviderSettings

    public init(
        categories: [String] = LocalArxivClient.defaultCategories,
        whitelistTags: [String] = [],
        blacklistTags: [String] = [],
        similaritySourceTagIDs: [String] = [],
        enrichment: LocalEnrichmentPreferences = LocalEnrichmentPreferences(),
        embedding: EmbeddingProviderSettings = EmbeddingProviderSettings()
    ) {
        self.categories = categories
        self.whitelistTags = whitelistTags
        self.blacklistTags = blacklistTags
        self.similaritySourceTagIDs = similaritySourceTagIDs
        self.enrichment = enrichment
        self.embedding = embedding
    }

    public var normalized: LocalDiscoverPreferences {
        LocalDiscoverPreferences(
            categories: Self.normalizedList(categories),
            whitelistTags: Self.normalizedList(whitelistTags),
            blacklistTags: Self.normalizedList(blacklistTags),
            similaritySourceTagIDs: Self.normalizedList(similaritySourceTagIDs),
            enrichment: enrichment,
            embedding: embedding.normalized
        )
    }

    public static func normalizedList(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }
}
