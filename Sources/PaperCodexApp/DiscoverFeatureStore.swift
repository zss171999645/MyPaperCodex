import Foundation
import PaperCodexCore

@MainActor
final class DiscoverFeatureStore: ObservableObject {
    @Published var arxivDates: [String] = []
    @Published var selectedArxivDate: String?
    @Published var arxivFeed: ArxivFeedResponse?
    @Published var selectedArxivPaper: ArxivFeedPaper?
    @Published var discoverKeyword = ""
    @Published var arxivSearchQuery = ""
    @Published var arxivSearchFeed: ArxivFeedResponse?
    @Published var arxivSearchSortRawValue = ArxivAPISort.relevance.rawValue
    @Published var arxivSearchSortOrderRawValue = ArxivAPISortOrder.descending.rawValue
    @Published var discoverStartDate: String
    @Published var discoverEndDate: String
    @Published var discoverSelectedCategories: [String] = ["cs.CV"]
    @Published var discoverSelectedSimilaritySourceIDs: [String] = []
    @Published var discoverResultIDs: [String] = []
    @Published var discoverEnrichmentsByID: [String: DiscoverPaperEnrichment] = [:]
    @Published var isSearchingDiscover = false
    @Published var isCancellingDiscoverSearch = false
    @Published var isSearchingArxivSearch = false
    @Published var isCancellingArxivSearch = false
    @Published var isProcessingDiscoverResults = false
    @Published var discoverProcessingProgress: ArxivCacheProgress?
    @Published var isCachingDiscoverPDFs = false
    @Published var discoverPDFCacheProgress: ArxivCacheProgress?
    @Published var arxivAssetURLs: [String: URL] = [:]
    @Published var arxivPDFThumbnailURLsByID: [String: [URL]] = [:]
    @Published var discoverPaperInteractionStateByID: [String: DiscoverPaperInteractionState] = [:]
    @Published var discoverScrollPositionPaperID: String?
    @Published var isLoadingArxivFeed = false
    @Published var isRefreshingArxivDates = false
    @Published var isPreloadingArxivAssets = false
    @Published var isAddingArxivPaper = false
    @Published var arxivDownloadingPaperIDs: Set<String> = []
    @Published var arxivDownloadProgressByID: [String: Double] = [:]
    @Published var arxivCacheProgress: ArxivCacheProgress?
    @Published var pendingArxivLibraryImportIDs: Set<String> = []
    @Published var failedArxivLibraryImportMessagesByID: [String: String] = [:]

    init(
        startDate: String,
        endDate: String,
        scrollPositionPaperID: String?
    ) {
        discoverStartDate = startDate
        discoverEndDate = endDate
        discoverScrollPositionPaperID = scrollPositionPaperID
    }
}
