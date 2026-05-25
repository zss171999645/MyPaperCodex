import Foundation

public struct PaperLibraryDerivedState: Equatable, Sendable {
    public static let empty = PaperLibraryDerivedState(
        categoryPaperCountsByID: [:],
        tagPaperCountsByID: [:],
        paperIDsByCategoryID: [:],
        paperIDsByTagID: [:],
        descendantCategoryIDsByID: [:],
        searchTextByPaperID: [:]
    )

    public var categoryPaperCountsByID: [String: Int]
    public var tagPaperCountsByID: [String: Int]
    public var paperIDsByCategoryID: [String: Set<String>]
    public var paperIDsByTagID: [String: Set<String>]
    public var descendantCategoryIDsByID: [String: Set<String>]
    public var searchTextByPaperID: [String: String]

    public static func build(
        papers: [Paper],
        categories: [Category],
        categoryIDsByPaperID: [String: [String]],
        tagsByPaperID: [String: [PaperTag]]
    ) -> PaperLibraryDerivedState {
        let categoryNamesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let descendantCategoryIDsByID = makeDescendantCategoryIDsByID(categories: categories)
        var categoryCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var paperIDsByCategoryID: [String: Set<String>] = [:]
        var paperIDsByTagID: [String: Set<String>] = [:]
        var searchText: [String: String] = [:]

        for paper in papers {
            let categoryIDs = categoryIDsByPaperID[paper.id, default: []]
            let paperTags = tagsByPaperID[paper.id, default: []]
            for categoryID in Set(categoryIDs) {
                categoryCounts[categoryID, default: 0] += 1
                paperIDsByCategoryID[categoryID, default: []].insert(paper.id)
            }
            for tagID in Set(paperTags.map(\.id)) {
                tagCounts[tagID, default: 0] += 1
                paperIDsByTagID[tagID, default: []].insert(paper.id)
            }

            let categoryNames = categoryIDs.compactMap { categoryNamesByID[$0] }
            let components = [
                paper.id,
                paper.title,
                paper.authors.joined(separator: " "),
                paper.year.map(String.init) ?? "",
                paper.sourceURL ?? "",
                categoryNames.joined(separator: " "),
                paperTags.map(\.name).joined(separator: " ")
            ]
            searchText[paper.id] = components
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
        }

        return PaperLibraryDerivedState(
            categoryPaperCountsByID: categoryCounts,
            tagPaperCountsByID: tagCounts,
            paperIDsByCategoryID: paperIDsByCategoryID,
            paperIDsByTagID: paperIDsByTagID,
            descendantCategoryIDsByID: descendantCategoryIDsByID,
            searchTextByPaperID: searchText
        )
    }

    public func categoryIDsForFilter(_ categoryID: String, includeDescendants: Bool) -> Set<String> {
        guard includeDescendants else {
            return [categoryID]
        }
        return Set([categoryID]).union(descendantCategoryIDsByID[categoryID, default: []])
    }

    public func paperIDsForCategoryFilter(_ categoryID: String, includeDescendants: Bool) -> Set<String> {
        categoryIDsForFilter(categoryID, includeDescendants: includeDescendants)
            .reduce(into: Set<String>()) { paperIDs, categoryID in
                paperIDs.formUnion(paperIDsByCategoryID[categoryID, default: []])
            }
    }

    public func paperIDsForTag(_ tagID: String) -> Set<String> {
        paperIDsByTagID[tagID, default: []]
    }

    public func matchesSearch(paperID: String, query: String) -> Bool {
        let terms = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else {
            return true
        }
        guard let haystack = searchTextByPaperID[paperID] else {
            return true
        }
        return terms.allSatisfy { haystack.contains($0) }
    }

    private static func makeDescendantCategoryIDsByID(categories: [Category]) -> [String: Set<String>] {
        let childrenByParentID = Dictionary(grouping: categories, by: \.parentID)
        var descendantsByID: [String: Set<String>] = [:]

        func collectDescendants(of categoryID: String, visited: Set<String>) -> Set<String> {
            guard !visited.contains(categoryID) else {
                return []
            }
            let nextVisited = visited.union([categoryID])
            let children = childrenByParentID[categoryID, default: []]
            return children.reduce(into: Set<String>()) { descendants, child in
                descendants.insert(child.id)
                descendants.formUnion(collectDescendants(of: child.id, visited: nextVisited))
            }
        }

        for category in categories {
            descendantsByID[category.id] = collectDescendants(of: category.id, visited: [])
        }
        return descendantsByID
    }
}
