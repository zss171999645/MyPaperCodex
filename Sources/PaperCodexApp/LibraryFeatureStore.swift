import Foundation
import PaperCodexCore

@MainActor
final class LibraryFeatureStore: ObservableObject {
    @Published var papers: [Paper] = []
    @Published var categories: [PaperCodexCore.Category] = []
    @Published var tags: [PaperTag] = []
    @Published var watchedFolders: [WatchedFolder] = []
    @Published var paperCategoryIDsByID: [String: [String]] = [:]
    @Published var paperTagsByID: [String: [PaperTag]] = [:]
    @Published var libraryDerivedState: PaperLibraryDerivedState = .empty
    @Published var selectedLibraryPaper: Paper?
    @Published var selectedLibrarySurface: LibrarySurface = .papers
    @Published var librarySearchText = ""
    @Published var librarySelectedCategoryID: String?
    @Published var librarySelectedTagID: String?
    @Published var paperThumbnailURLsByID: [String: [URL]] = [:]
    @Published var paperNotesByID: [String: [PaperNote]] = [:]

    func applySnapshot(
        papers: [Paper],
        categories: [PaperCodexCore.Category],
        tags: [PaperTag],
        watchedFolders: [WatchedFolder],
        categoryIDsByPaperID: [String: [String]],
        tagsByPaperID: [String: [PaperTag]]
    ) {
        let selectedPaperID = selectedLibraryPaper?.id
        self.papers = papers
        self.categories = categories
        self.tags = tags
        self.watchedFolders = watchedFolders
        self.paperCategoryIDsByID = categoryIDsByPaperID
        self.paperTagsByID = tagsByPaperID
        libraryDerivedState = PaperLibraryDerivedState.build(
            papers: papers,
            categories: categories,
            categoryIDsByPaperID: categoryIDsByPaperID,
            tagsByPaperID: tagsByPaperID
        )
        if let selectedPaperID {
            selectedLibraryPaper = papers.first { $0.id == selectedPaperID }
        }
    }
}
