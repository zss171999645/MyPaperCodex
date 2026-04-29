import Foundation

public enum SimilarityRanker {
    public static func cosine(_ left: [Double], _ right: [Double]) -> Double {
        guard !left.isEmpty, left.count == right.count else {
            return 0
        }
        var dot = 0.0
        var leftNorm = 0.0
        var rightNorm = 0.0
        for (leftValue, rightValue) in zip(left, right) {
            dot += leftValue * rightValue
            leftNorm += leftValue * leftValue
            rightNorm += rightValue * rightValue
        }
        guard leftNorm > 0, rightNorm > 0 else {
            return 0
        }
        return dot / (leftNorm.squareRoot() * rightNorm.squareRoot())
    }

    public static func meanVector(_ vectors: [[Double]]) -> [Double]? {
        guard let first = vectors.first, !first.isEmpty else {
            return nil
        }
        var totals = Array(repeating: 0.0, count: first.count)
        var count = 0
        for vector in vectors where vector.count == first.count {
            for index in vector.indices {
                totals[index] += vector[index]
            }
            count += 1
        }
        guard count > 0 else {
            return nil
        }
        return totals.map { $0 / Double(count) }
    }

    public static func rank(
        papers: [ArxivFeedPaper],
        whitelistTags: [String],
        blacklistTags: [String],
        interestVectors: [[Double]]
    ) -> [ArxivFeedPaper] {
        let whitelist = normalizedSet(whitelistTags)
        let blacklist = normalizedSet(blacklistTags)
        let validInterestVectors = interestVectors.filter { !$0.isEmpty }
        var grouped: [String: [(index: Int, paper: ArxivFeedPaper)]] = [
            "white": [],
            "neutral": [],
            "black": []
        ]

        for (index, sourcePaper) in papers.enumerated() {
            var paper = sourcePaper
            if let embedding = paper.embedding, !validInterestVectors.isEmpty {
                let scores = validInterestVectors
                    .filter { $0.count == embedding.count }
                    .map { cosine(embedding, $0) }
                paper.similarity = scores.max()
            }
            let group = filterGroup(tags: paper.tags, whitelist: whitelist, blacklist: blacklist)
            paper.filterGroup = group
            grouped[group, default: []].append((index, paper))
        }

        return ["white", "neutral", "black"].flatMap { key in
            grouped[key, default: []]
                .sorted { left, right in
                    let leftScore = left.paper.similarity ?? -Double.infinity
                    let rightScore = right.paper.similarity ?? -Double.infinity
                    if leftScore == rightScore {
                        return left.index < right.index
                    }
                    return leftScore > rightScore
                }
                .map(\.paper)
        }
    }

    private static func filterGroup(tags: [String], whitelist: Set<String>, blacklist: Set<String>) -> String {
        let paperTags = normalizedSet(tags)
        if !blacklist.isEmpty, !paperTags.isDisjoint(with: blacklist) {
            return "black"
        }
        if !whitelist.isEmpty, !paperTags.isDisjoint(with: whitelist) {
            return "white"
        }
        return "neutral"
    }

    private static func normalizedSet(_ values: [String]) -> Set<String> {
        Set(values.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
    }
}
