import Foundation
import PaperCodexCore

struct SearchCheckFailure: Error, CustomStringConvertible {
    var description: String
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SearchCheckFailure(description: message)
    }
}

do {
    let categoryAndYearQuery = try LocalArxivClient.composedUserSearchQuery(
        "diffusion models",
        requiredCategories: ["cs.CV", "cs.LG", "cs.CV"],
        fromYear: 2022,
        throughYear: 2024
    )
    try check(
        categoryAndYearQuery == "(all:diffusion models) AND (cat:cs.CV OR cat:cs.LG) AND submittedDate:[202201010000 TO 202412312359]",
        "arXiv search should combine user query, required categories, and closed year range"
    )

    let filterOnlyQuery = try LocalArxivClient.composedUserSearchQuery(
        "",
        requiredCategories: ["cs.CV"],
        fromYear: 2020,
        throughYear: nil
    )
    try check(
        filterOnlyQuery == "cat:cs.CV AND submittedDate:[202001010000 TO 999912312359]",
        "arXiv search should allow category/year-only searches"
    )

    do {
        _ = try LocalArxivClient.composedUserSearchQuery(
            "all:diffusion",
            requiredCategories: [],
            fromYear: 2025,
            throughYear: 2020
        )
        throw SearchCheckFailure(description: "arXiv search should reject inverted year ranges")
    } catch is LocalArxivClientError {
        // Expected.
    }

    print("search-filters: pass")
} catch {
    fputs("check failed: \(error)\n", stderr)
    exit(1)
}
