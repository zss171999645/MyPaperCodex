import Foundation

public struct ObsidianPaperSearchResult: Equatable, Sendable {
    public var paperID: String
    public var score: Int
    public var reasons: [String]

    public init(paperID: String, score: Int, reasons: [String]) {
        self.paperID = paperID
        self.score = score
        self.reasons = reasons
    }
}

public struct ObsidianPaperSearchIndex: Sendable {
    private var records: [IndexedObsidianSearchRecord]

    public init(records: [ObsidianPaperRecord]) {
        self.records = records.map { ObsidianPaperSearch.indexedRecord(for: $0) }
    }

    public func rank(query: String, candidateIDs: Set<String>? = nil) -> [ObsidianPaperSearchResult] {
        ObsidianPaperSearch.rank(indexedRecords: records, query: query, candidateIDs: candidateIDs)
    }
}

public enum ObsidianPaperSearch {
    public static func rank(records: [ObsidianPaperRecord], query: String) -> [ObsidianPaperSearchResult] {
        rank(indexedRecords: records.map { indexedRecord(for: $0) }, query: query)
    }

    fileprivate static func indexedRecord(for record: ObsidianPaperRecord) -> IndexedObsidianSearchRecord {
        IndexedObsidianSearchRecord(paperID: record.paper.id, fields: searchFields(for: record).map(IndexedObsidianSearchField.init(field:)))
    }

    fileprivate static func rank(
        indexedRecords: [IndexedObsidianSearchRecord],
        query: String,
        candidateIDs: Set<String>? = nil
    ) -> [ObsidianPaperSearchResult] {
        let normalizedQuery = SearchTextNormalizer.normalize(query)
        let terms = SearchTextNormalizer.terms(in: normalizedQuery)
        guard !terms.isEmpty else {
            return indexedRecords.compactMap { record in
                guard candidateIDs?.contains(record.paperID) ?? true else {
                    return nil
                }
                return ObsidianPaperSearchResult(paperID: record.paperID, score: 0, reasons: [])
            }
        }

        return indexedRecords.compactMap { record in
            guard candidateIDs?.contains(record.paperID) ?? true else {
                return nil
            }
            let fields = record.fields
            var score = 0
            var reasons: [String] = []

            for field in fields {
                let fieldText = field.normalizedText
                guard !fieldText.isEmpty else {
                    continue
                }
                let fieldTerms = field.terms

                if fieldText == normalizedQuery {
                    score += field.weight * 10
                    reasons.append(field.label)
                } else if fieldText.contains(normalizedQuery) {
                    score += field.weight * 6
                    reasons.append(field.label)
                }

                for term in terms {
                    if fieldTerms.contains(term) {
                        score += field.weight * 4
                        reasons.append(field.label)
                    } else if fieldTerms.contains(where: { $0.hasPrefix(term) }) {
                        score += field.weight * 3
                        reasons.append(field.label)
                    } else if fieldText.contains(term) {
                        score += field.weight * 2
                        reasons.append(field.label)
                    } else if fuzzyContains(term, in: fieldTerms) {
                        score += field.weight
                        reasons.append(field.label)
                    }
                }

                if let acronym = field.acronym,
                   !acronym.isEmpty,
                   acronym == normalizedQuery.replacingOccurrences(of: " ", with: "") {
                    score += field.weight * 5
                    reasons.append(field.label)
                }
            }

            guard score > 0, terms.allSatisfy({ termMatches($0, in: fields) }) else {
                return nil
            }
            let uniqueReasons = (NSOrderedSet(array: reasons).array as? [String] ?? [])
            return ObsidianPaperSearchResult(
                paperID: record.paperID,
                score: score,
                reasons: Array(uniqueReasons.prefix(4))
            )
        }
        .sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.paperID < $1.paperID
        }
    }

    fileprivate struct SearchField {
        var label: String
        var text: String
        var weight: Int
    }

    private static func searchFields(for record: ObsidianPaperRecord) -> [SearchField] {
        var fields: [SearchField] = []

        func append(_ label: String, _ value: String?, weight: Int) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            fields.append(SearchField(label: label, text: value, weight: weight))
        }

        func append(_ label: String, _ values: [String], weight: Int) {
            for value in values where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fields.append(SearchField(label: label, text: value, weight: weight))
            }
        }

        append("title", record.paper.title, weight: 12)
        append("short title", record.shortTitle, weight: 11)
        append("alias", record.aliases, weight: 10)
        append("author", record.paper.authors, weight: 8)
        append("first author", record.firstAuthor, weight: 9)
        append("arXiv", record.arxiv, weight: 9)
        append("year", record.paper.year.map(String.init), weight: 6)
        append("status", record.discussionStatus, weight: 8)
        append("venue", record.venue, weight: 5)
        append("primary direction", record.primaryDirection, weight: 9)
        append("direction", record.directions, weight: 8)
        append("primary task", record.primaryTask, weight: 8)
        append("task", record.tasks, weight: 7)
        append("keyword", record.keywords, weight: 9)
        append("method", record.methods, weight: 7)
        append("dataset", record.datasets, weight: 6)
        append("metric", record.metrics, weight: 5)
        append("related paper", record.relatedPapers, weight: 7)
        append("relation", record.relationTypes, weight: 6)
        append("world-model role", record.worldModelRole, weight: 6)
        append("summary", record.summary, weight: 5)
        append("open question", record.openQuestions, weight: 5)
        append("note path", record.relativeNotePath, weight: 4)
        append("source", record.paper.sourceURL, weight: 3)
        append("project", record.projectURL?.absoluteString, weight: 3)
        append("code", record.codeURL?.absoluteString, weight: 3)
        append("doi", record.doi, weight: 3)
        return fields
    }

    private static func termMatches(_ term: String, in fields: [IndexedObsidianSearchField]) -> Bool {
        fields.contains { field in
            let fieldText = field.normalizedText
            let fieldTerms = field.terms
            return fieldText.contains(term)
                || fieldTerms.contains(where: { $0.hasPrefix(term) })
                || fuzzyContains(term, in: fieldTerms)
        }
    }

    private static func fuzzyContains(_ needle: String, in haystackTerms: [String]) -> Bool {
        guard needle.count >= 3 else {
            return false
        }
        return haystackTerms.contains { term in
            guard term.count >= needle.count else {
                return false
            }
            return editDistanceWithinOne(needle, term) || isSubsequence(needle, of: term)
        }
    }

    private static func editDistanceWithinOne(_ left: String, _ right: String) -> Bool {
        let left = Array(left)
        let right = Array(right)
        guard abs(left.count - right.count) <= 1 else {
            return false
        }
        var i = 0
        var j = 0
        var edits = 0
        while i < left.count, j < right.count {
            if left[i] == right[j] {
                i += 1
                j += 1
            } else {
                edits += 1
                guard edits <= 1 else {
                    return false
                }
                if left.count > right.count {
                    i += 1
                } else if right.count > left.count {
                    j += 1
                } else {
                    i += 1
                    j += 1
                }
            }
        }
        return edits + (left.count - i) + (right.count - j) <= 1
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var index = needle.startIndex
        for character in haystack where index < needle.endIndex && character == needle[index] {
            index = needle.index(after: index)
        }
        return index == needle.endIndex
    }

    fileprivate static func acronym(for text: String) -> String? {
        let words = SearchTextNormalizer.terms(in: SearchTextNormalizer.normalize(text))
        guard words.count > 1 else {
            return nil
        }
        return words.compactMap(\.first).map(String.init).joined()
    }
}

private struct IndexedObsidianSearchRecord: Sendable {
    var paperID: String
    var fields: [IndexedObsidianSearchField]
}

private struct IndexedObsidianSearchField: Sendable {
    var label: String
    var normalizedText: String
    var terms: [String]
    var acronym: String?
    var weight: Int

    init(field: ObsidianPaperSearch.SearchField) {
        label = field.label
        normalizedText = SearchTextNormalizer.normalize(field.text)
        terms = SearchTextNormalizer.terms(in: normalizedText)
        acronym = ObsidianPaperSearch.acronym(for: field.text)
        weight = field.weight
    }
}

private enum SearchTextNormalizer {
    static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: ".", with: " ")
    }

    static func terms(in text: String) -> [String] {
        text
            .split { character in
                character.isWhitespace || character.isPunctuation || character.isSymbol
            }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
