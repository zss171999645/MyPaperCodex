import AppKit
import Foundation
import PaperCodexCore
import Security
import SwiftUI

enum AppRoute {
    case library
    case discover
    case settings
    case reader
}

enum ArxivSaveOrganization: String, CaseIterable, Identifiable {
    case primaryCategory = "primary-category"
    case firstTag = "first-tag"
    case date = "date"
    case flat = "flat"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primaryCategory:
            "Primary category"
        case .firstTag:
            "First tag"
        case .date:
            "Feed date"
        case .flat:
            "Flat library"
        }
    }
}

enum DiscoverProcessAction: String, CaseIterable, Identifiable {
    case translate
    case summarize
    case cachePDFThumbnails = "cache-pdf-thumbnails"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translate:
            "Translate"
        case .summarize:
            "Summarize"
        case .cachePDFThumbnails:
            "Download & Thumbnails"
        }
    }

    var detail: String {
        switch self {
        case .translate:
            "Chinese title translation for each result"
        case .summarize:
            "Chinese summary, contribution, tags, and useful links"
        case .cachePDFThumbnails:
            "Cache the PDF and render preview thumbnails"
        }
    }

    var systemImage: String {
        switch self {
        case .translate:
            "character.book.closed"
        case .summarize:
            "text.alignleft"
        case .cachePDFThumbnails:
            "doc.richtext"
        }
    }
}

struct PDFSelectionInfo: Equatable {
    var text: String
    var page: Int
    var bboxList: [BoundingBox]
}

struct PDFJumpTarget: Equatable {
    var id: String
    var paperID: String
    var page: Int
    var bboxList: [BoundingBox]
    var label: String
}

struct ActiveCodexRun: Identifiable, Equatable {
    var id: String
    var sessionID: String
    var title: String
    var startedAt: Date
    var events: [CodexRunEvent]
}

struct ArxivCacheProgress: Equatable {
    var date: String
    var title: String
    var detail: String
    var completed: Int
    var total: Int

    var fraction: Double? {
        guard total > 0 else {
            return nil
        }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

enum LibraryArxivImportOutcomeState: Equatable {
    case imported
    case alreadyInLibrary
    case failed
}

struct LibraryArxivImportOutcome: Equatable {
    var requestedID: String
    var canonicalID: String
    var title: String
    var state: LibraryArxivImportOutcomeState
    var message: String
}

private enum DiscoverPaperProcessingState: Sendable {
    case processed
    case cached
    case failed
    case cancelled
}

private struct DiscoverPaperProcessingResult: Sendable {
    var paperID: String
    var state: DiscoverPaperProcessingState
    var tokenUsage: CodexTokenUsage? = nil
}

private struct DiscoverSimilarityCategorySource {
    var categoryID: String
    var papers: [Paper]
}

private struct SessionPaperContext {
    var papers: [Paper]
    var pagesByPaperID: [String: [PageIndex]]
    var spansByPaperID: [String: [Span]]
    var anchorsByPaperID: [String: [PaperCodexCore.Anchor]]

    var spans: [Span] {
        papers.flatMap { spansByPaperID[$0.id] ?? [] }
    }
}

private let codexModelOverrideDefaultsKey = "PaperCodexCodexModelOverride"
private let codexReasoningEffortDefaultsKey = "PaperCodexCodexReasoningEffort"
private let codexSystemPromptDefaultsKey = "PaperCodexCodexSystemPrompt"
private let globalLanguageModeDefaultsKey = "PaperCodexGlobalLanguageMode"
private let discoverCodexModelOverrideDefaultsKey = "PaperCodexDiscoverCodexModelOverride"
private let discoverCodexConcurrencyDefaultsKey = "PaperCodexDiscoverCodexConcurrency"
private let localDiscoverPreferencesDefaultsKey = "PaperCodexLocalDiscoverPreferences"
private let embeddingProviderAPIKeyService = "PaperCodexEmbeddingProvider"
private let embeddingProviderAPIKeyAccount = "default"
private let arxivSaveOrganizationDefaultsKey = "PaperCodexArxivSaveOrganization"
private let quickPromptsDefaultsKey = "PaperCodexQuickPrompts"
private let librarySidebarWidthDefaultsKey = "PaperCodexLibrarySidebarWidth"
private let discoverScrollPositionPaperIDDefaultsKey = "PaperCodexDiscoverScrollPositionPaperID"
private let defaultDiscoverCodexConcurrency = 10

private func loadDiscoverCodexConcurrencyFromDefaults() -> Int {
    let stored = UserDefaults.standard.integer(forKey: discoverCodexConcurrencyDefaultsKey)
    return stored == 0 ? defaultDiscoverCodexConcurrency : min(max(stored, 1), 20)
}

private func loadQuickPromptsFromDefaults() -> [QuickPrompt] {
    guard let data = UserDefaults.standard.data(forKey: quickPromptsDefaultsKey),
          let prompts = try? JSONDecoder().decode([QuickPrompt].self, from: data),
          !prompts.isEmpty else {
        return [
            QuickPrompt(id: "summary", title: "Summary", content: "Summarize the paper's main contribution, method, and evidence."),
            QuickPrompt(id: "limitations", title: "Limitations", content: "Identify the most important limitations, hidden assumptions, and missing experiments."),
            QuickPrompt(id: "related", title: "Related Work", content: "Compare this paper with closely related work and explain what is genuinely new.")
        ]
    }
    return prompts
}

private func saveQuickPromptsToDefaults(_ prompts: [QuickPrompt]) {
    if let data = try? JSONEncoder().encode(prompts) {
        UserDefaults.standard.set(data, forKey: quickPromptsDefaultsKey)
    }
}

private func loadDiscoverScrollPositionPaperIDFromDefaults() -> String? {
    let value = UserDefaults.standard.string(forKey: discoverScrollPositionPaperIDDefaultsKey)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.isEmpty == false ? value : nil
}

private func loadCodexSystemPromptFromDefaults(languageMode: PaperCodexLanguageMode) -> String {
    guard let stored = UserDefaults.standard.string(forKey: codexSystemPromptDefaultsKey),
          !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return PromptBuilder.defaultSystemPrompt(for: languageMode)
    }
    if PromptBuilder.isBuiltInSystemPrompt(stored) {
        UserDefaults.standard.removeObject(forKey: codexSystemPromptDefaultsKey)
        return PromptBuilder.defaultSystemPrompt(for: languageMode)
    }
    return stored
}

private func loadGlobalLanguageModeFromDefaults() -> PaperCodexLanguageMode {
    guard let stored = UserDefaults.standard.string(forKey: globalLanguageModeDefaultsKey),
          let mode = PaperCodexLanguageMode(rawValue: stored) else {
        return .automatic
    }
    return mode
}

private func loadLocalDiscoverPreferencesFromDefaults() -> LocalDiscoverPreferences {
    guard let data = UserDefaults.standard.data(forKey: localDiscoverPreferencesDefaultsKey),
          let preferences = try? JSONDecoder().decode(LocalDiscoverPreferences.self, from: data) else {
        return LocalDiscoverPreferences()
    }
    return preferences.normalized
}

private func saveLocalDiscoverPreferencesToDefaults(_ preferences: LocalDiscoverPreferences) {
    if let data = try? JSONEncoder().encode(preferences.normalized) {
        UserDefaults.standard.set(data, forKey: localDiscoverPreferencesDefaultsKey)
    }
}

private func loadEmbeddingProviderAPIKeyFromKeychain() -> String {
    var query = embeddingProviderAPIKeyQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
        return ""
    }
    return value
}

private func saveEmbeddingProviderAPIKeyToKeychain(_ value: String) throws {
    let data = Data(value.utf8)
    let baseQuery = embeddingProviderAPIKeyQuery()
    if data.isEmpty {
        SecItemDelete(baseQuery as CFDictionary)
        return
    }

    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if updateStatus == errSecSuccess {
        return
    }
    if updateStatus != errSecItemNotFound {
        throw AppModelError.keychainFailure(updateStatus)
    }

    var addQuery = baseQuery
    addQuery[kSecValueData as String] = data
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
        throw AppModelError.keychainFailure(addStatus)
    }
}

private func embeddingProviderAPIKeyQuery() -> [String: Any] {
    [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: embeddingProviderAPIKeyService,
        kSecAttrAccount as String: embeddingProviderAPIKeyAccount,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
}

private func isCancellationError(_ error: any Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if let urlError = error as? URLError, urlError.code == .cancelled {
        return true
    }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
}

private func latestCompleteArxivSubmissionISODate() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    let calendar = Calendar(identifier: .gregorian)
    let date = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    return formatter.string(from: date)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var route: AppRoute = .library
    @Published var papers: [Paper] = []
    @Published var categories: [PaperCodexCore.Category] = []
    @Published var tags: [PaperTag] = []
    @Published var watchedFolders: [WatchedFolder] = []
    @Published var paperCategoryIDsByID: [String: [String]] = [:]
    @Published var paperTagsByID: [String: [PaperTag]] = [:]
    @Published var selectedLibraryPaper: Paper?
    @Published var librarySearchText = ""
    @Published var librarySelectedCategoryID: String?
    @Published var librarySelectedTagID: String?
    @Published var readerReturnRoute: AppRoute = .library
    @Published var selectedPaper: Paper?
    @Published var readerTabState = ReaderTabState()
    @Published var selectedSession: PaperSession?
    @Published var sessions: [PaperSession] = []
    @Published var recentSessions: [PaperSession] = []
    @Published var recentSessionPapersByID: [String: [Paper]] = [:]
    @Published var selectedSessionPanelTab: SessionPanelTab = .chat
    @Published var messages: [ChatMessage] = []
    @Published var currentSelection: PDFSelectionInfo?
    @Published var pdfJumpTarget: PDFJumpTarget?
    @Published var readerPosition: PaperReaderPosition?
    @Published var codexDiagnostic: CodexDiagnostic?
    @Published var codexModelOverride: String = UserDefaults.standard.string(forKey: codexModelOverrideDefaultsKey) ?? ""
    @Published var codexReasoningEffort: CodexReasoningEffort = {
        let stored = UserDefaults.standard.string(forKey: codexReasoningEffortDefaultsKey)
        return stored.flatMap(CodexReasoningEffort.init(rawValue:)) ?? .default
    }()
    @Published var codexSystemPrompt: String = PromptBuilder.defaultSystemPrompt
    @Published var globalLanguageMode: PaperCodexLanguageMode = .automatic
    @Published var activeCodexRunsBySessionID: [String: ActiveCodexRun] = [:]
    @Published var errorMessage: String?
    @Published var notices: [InteractionNotice] = []
    @Published var discoverCodexModelOverride: String = UserDefaults.standard.string(forKey: discoverCodexModelOverrideDefaultsKey) ?? ""
    @Published var discoverCodexConcurrency: Int = loadDiscoverCodexConcurrencyFromDefaults()
    @Published var availableCodexModelIDs: [String] = []
    @Published var codexDefaultModelID: String = CodexCLI.configuredDefaultModelID() ?? ""
    @Published var isRefreshingCodexModels = false
    @Published var isScanningWatchedFolders = false
    @Published var localDiscoverPreferences: LocalDiscoverPreferences = loadLocalDiscoverPreferencesFromDefaults()
    @Published var embeddingProviderAPIKey: String = loadEmbeddingProviderAPIKeyFromKeychain()
    @Published var arxivSaveOrganization: ArxivSaveOrganization = {
        let stored = UserDefaults.standard.string(forKey: arxivSaveOrganizationDefaultsKey)
        return stored.flatMap(ArxivSaveOrganization.init(rawValue:)) ?? .primaryCategory
    }()
    @Published var quickPrompts: [QuickPrompt] = loadQuickPromptsFromDefaults()
    @Published var arxivDates: [String] = []
    @Published var selectedArxivDate: String?
    @Published var arxivFeed: ArxivFeedResponse?
    @Published var selectedArxivPaper: ArxivFeedPaper?
    @Published var discoverKeyword = ""
    @Published var discoverStartDate: String = latestCompleteArxivSubmissionISODate()
    @Published var discoverEndDate: String = latestCompleteArxivSubmissionISODate()
    @Published var discoverSelectedCategories: [String] = ["cs.CV"]
    @Published var discoverSelectedSimilaritySourceIDs: [String] = []
    @Published var discoverResultIDs: [String] = []
    @Published var discoverEnrichmentsByID: [String: DiscoverPaperEnrichment] = [:]
    @Published var isSearchingDiscover = false
    @Published var isCancellingDiscoverSearch = false
    @Published var isProcessingDiscoverResults = false
    @Published var discoverProcessingProgress: ArxivCacheProgress?
    @Published var isCachingDiscoverPDFs = false
    @Published var discoverPDFCacheProgress: ArxivCacheProgress?
    @Published var arxivAssetURLs: [String: URL] = [:]
    @Published var arxivPDFThumbnailURLsByID: [String: [URL]] = [:]
    @Published var discoverPaperInteractionStateByID: [String: DiscoverPaperInteractionState] = [:]
    @Published var discoverScrollPositionPaperID: String? = loadDiscoverScrollPositionPaperIDFromDefaults()
    @Published var isLoadingArxivFeed = false
    @Published var isRefreshingArxivDates = false
    @Published var isPreloadingArxivAssets = false
    @Published var isAddingArxivPaper = false
    @Published var arxivDownloadingPaperIDs: Set<String> = []
    @Published var arxivDownloadProgressByID: [String: Double] = [:]
    @Published var arxivCacheProgress: ArxivCacheProgress?
    @Published var paperThumbnailURLsByID: [String: [URL]] = [:]
    @Published var cacheStorageSummary = CacheStorageSummary()
    @Published var paperNotesByID: [String: [PaperNote]] = [:]
    @Published var citationReturnPoint: CitationReturnPoint?
    @Published var pdfKitCommand: PDFKitCommand?
    @Published var pdfDocumentStatus: PDFDocumentStatus?
    @Published var pendingArxivLibraryImportIDs: Set<String> = []
    @Published var failedArxivLibraryImportMessagesByID: [String: String] = [:]
    @Published var embeddingProviderTestStatus: String?
    @Published var isTestingEmbeddingProvider = false
    @Published var librarySidebarWidth: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: librarySidebarWidthDefaultsKey)
        return stored > 0 ? CGFloat(stored) : 280
    }()

    private var repository: PaperRepository?
    private let supportRoot: URL
    private let arxivCache: ArxivFeedCache
    private let localDiscoverCache: LocalDiscoverCache
    private let thumbnailCache: PDFThumbnailCache
    private let workspaceManager = SessionWorkspaceManager()
    private var watchedFolderAutoScanTask: Task<Void, Never>?
    private var activeDiscoverSearchTask: Task<Void, Never>?
    private var activeDiscoverPDFCacheTask: Task<Void, Never>?
    private var activeCodexRunHandlesBySessionID: [String: CodexRunHandle] = [:]
    private var activeDiscoverCodexRunHandles: [CodexRunHandle] = []
    private var cancellingCodexRunSessionIDs: Set<String> = []
    private var isCancellingDiscoverProcessing = false
    private var isCancellingDiscoverPDFCache = false

    var activeCodexRun: ActiveCodexRun? {
        activeCodexRun(for: selectedSession?.id)
    }

    var isSending: Bool {
        !activeCodexRunsBySessionID.isEmpty
    }

    var isCancellingCodexRun: Bool {
        !cancellingCodexRunSessionIDs.isEmpty
    }

    var arxivDisposableCachePath: String {
        supportRoot.appendingPathComponent("cache", isDirectory: true).path
    }

    var paperLibraryRootPath: String {
        supportRoot.appendingPathComponent("papers", isDirectory: true).path
    }

    var globalOperationStatus: AppOperationStatus? {
        if isSearchingDiscover {
            return AppOperationStatus(
                title: isCancellingDiscoverSearch ? "Stopping Discover Search" : "Searching Discover",
                detail: arxivCacheProgress?.detail ?? "\(discoverStartDate)...\(discoverEndDate)",
                systemImage: "magnifyingglass",
                tint: .blue
            )
        }
        if isProcessingDiscoverResults {
            return AppOperationStatus(
                title: isCancellingDiscoverProcessing ? "Stopping Discover Processing" : "Processing Discover Results",
                detail: discoverProcessingProgress?.detail ?? "\(discoverCodexConcurrency) workers",
                systemImage: "sparkles",
                tint: .indigo
            )
        }
        if isCachingDiscoverPDFs {
            return AppOperationStatus(
                title: isCancellingDiscoverPDFCache ? "Stopping PDF Cache" : "Caching PDFs",
                detail: discoverPDFCacheProgress?.detail ?? "Downloading arXiv PDFs",
                systemImage: "tray.and.arrow.down",
                tint: .green
            )
        }
        if isScanningWatchedFolders {
            return AppOperationStatus(
                title: "Scanning Watched Folders",
                detail: "\(watchedFolders.count) folder\(watchedFolders.count == 1 ? "" : "s")",
                systemImage: "folder.badge.gearshape",
                tint: .orange
            )
        }
        if isSending {
            let activeRuns = activeCodexRunsBySessionID.values.sorted { $0.startedAt < $1.startedAt }
            return AppOperationStatus(
                title: isCancellingCodexRun ? "Stopping Codex" : "Codex Running",
                detail: activeRuns.count == 1
                    ? (activeRuns.first?.title ?? "Current session")
                    : "\(activeRuns.count) sessions running",
                systemImage: "brain.head.profile",
                tint: .purple
            )
        }
        return nil
    }

    func activeCodexRun(for sessionID: String?) -> ActiveCodexRun? {
        guard let sessionID else {
            return nil
        }
        return activeCodexRunsBySessionID[sessionID]
    }

    func isSessionSending(_ sessionID: String?) -> Bool {
        activeCodexRun(for: sessionID) != nil
    }

    var readerPositionContextID: String? {
        guard let session = selectedSession, let paper = selectedPaper else {
            return nil
        }
        return "\(session.id)|\(paper.id)"
    }

    var currentSessionPapers: [Paper] {
        guard let session = selectedSession else {
            return selectedPaper.map { [$0] } ?? []
        }
        let linkedPapers = papersForSession(session)
        if linkedPapers.isEmpty, let selectedPaper {
            return [selectedPaper]
        }
        return linkedPapers
    }

    init() {
        let storedLanguageMode = loadGlobalLanguageModeFromDefaults()
        globalLanguageMode = storedLanguageMode
        codexSystemPrompt = loadCodexSystemPromptFromDefaults(languageMode: storedLanguageMode)

        let root = PaperCodexPaths.supportRoot()
        supportRoot = root
        arxivCache = ArxivFeedCache(root: root.appendingPathComponent("arxiv-cache", isDirectory: true))
        localDiscoverCache = LocalDiscoverCache(root: root.appendingPathComponent("discover-cache", isDirectory: true))
        thumbnailCache = PDFThumbnailCache(root: root.appendingPathComponent("thumbnails", isDirectory: true))
        discoverSelectedCategories = localDiscoverPreferences.categories.isEmpty ? ["cs.CV"] : [localDiscoverPreferences.categories[0]]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = try PaperRepository(databasePath: root.appendingPathComponent("store.sqlite").path)
            try store.migrate()
            repository = store
            try reloadLibrary()
            loadCachedArxivState()
            refreshCacheStorageSummary()
            Task {
                scanWatchedFolders()
                await refreshCodexDiagnostic()
                await refreshAvailableCodexModels()
            }
            startWatchedFolderAutoScan()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    deinit {
        watchedFolderAutoScanTask?.cancel()
        activeDiscoverPDFCacheTask?.cancel()
    }

    func postNotice(
        kind: InteractionNoticeKind,
        title: String,
        message: String = "",
        autoDismissAfter: TimeInterval? = 4
    ) {
        let notice = InteractionNotice(
            kind: kind,
            title: title,
            message: message,
            autoDismissAfter: autoDismissAfter
        )
        notices.append(notice)
        if let autoDismissAfter {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
                await MainActor.run {
                    self?.dismissNotice(id: notice.id)
                }
            }
        }
    }

    func dismissNotice(id: InteractionNotice.ID) {
        notices.removeAll { $0.id == id }
    }

    func refreshCacheStorageSummary() {
        let libraryRoot = supportRoot.appendingPathComponent("papers", isDirectory: true)
        let disposableCacheRoot = supportRoot.appendingPathComponent("cache", isDirectory: true)
        let arxivCacheRoot = supportRoot.appendingPathComponent("arxiv-cache", isDirectory: true)
        let thumbnailRoot = supportRoot.appendingPathComponent("thumbnails", isDirectory: true)
        cacheStorageSummary = CacheStorageSummary(
            libraryBytes: directorySize(libraryRoot),
            disposableCacheBytes: directorySize(disposableCacheRoot),
            arxivCacheBytes: directorySize(arxivCacheRoot),
            thumbnailBytes: directorySize(thumbnailRoot),
            refreshedAt: Date()
        )
    }

    func revealPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    private func directorySize(_ root: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    func reloadLibrary() throws {
        guard let repository else {
            return
        }
        let selectedLibraryPaperID = selectedLibraryPaper?.id
        papers = try repository.fetchPapers()
        categories = try repository.fetchCategories()
        tags = try repository.fetchTags()
        watchedFolders = try repository.fetchWatchedFolders()
        paperCategoryIDsByID = try Dictionary(uniqueKeysWithValues: papers.map { paper in
            (paper.id, try repository.fetchCategoryIDs(forPaperID: paper.id))
        })
        paperTagsByID = try Dictionary(uniqueKeysWithValues: papers.map { paper in
            (paper.id, try repository.fetchTags(forPaperID: paper.id))
        })
        try refreshRecentSessions(repository: repository)
        refreshLibraryThumbnails()
        if let selectedLibraryPaperID {
            selectedLibraryPaper = papers.first { $0.id == selectedLibraryPaperID }
        }
    }

    func refreshRecentSessions() {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            try refreshRecentSessions(repository: repository)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func refreshRecentSessions(repository: PaperRepository) throws {
        let sessions = try repository.fetchRecentSessions(limit: 8)
        recentSessions = sessions
        recentSessionPapersByID = try Dictionary(uniqueKeysWithValues: sessions.map { session in
            (session.id, try repository.fetchPapers(ids: session.paperIDs))
        })
    }

    func papersForSession(_ session: PaperSession) -> [Paper] {
        let visiblePapers = recentSessionPapersByID[session.id, default: []]
        return session.paperIDs.compactMap { paperID in
            papers.first(where: { $0.id == paperID })
                ?? visiblePapers.first(where: { $0.id == paperID })
        }
    }

    func importPDF(from sourceURL: URL) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = try PaperLibraryImporter(repository: repository, supportRoot: supportRoot)
                .importPDF(from: sourceURL)
            try reloadLibrary()
            refreshCacheStorageSummary()
            postNotice(
                kind: result.didImport ? .success : .info,
                title: result.didImport ? "PDF Imported" : "Already in Library",
                message: result.paper.title
            )
            openPaper(result.paper)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func importPDFs(from sourceURLs: [URL]) {
        let pdfURLs = sourceURLs.filter { $0.pathExtension.compare("pdf", options: [.caseInsensitive]) == .orderedSame }
        guard !pdfURLs.isEmpty else {
            postNotice(kind: .warning, title: "No PDFs Found", message: "Drop or choose PDF files to import.")
            return
        }
        var imported = 0
        var existing = 0
        var lastPaper: Paper?
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let importer = PaperLibraryImporter(repository: repository, supportRoot: supportRoot)
            for sourceURL in pdfURLs {
                let accessed = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                let result = try importer.importPDF(from: sourceURL)
                if result.didImport {
                    imported += 1
                } else {
                    existing += 1
                }
                lastPaper = result.paper
            }
            try reloadLibrary()
            refreshCacheStorageSummary()
            if let lastPaper {
                selectedLibraryPaper = papers.first { $0.id == lastPaper.id } ?? lastPaper
            }
            postNotice(
                kind: imported > 0 ? .success : .info,
                title: "PDF Import Finished",
                message: "\(imported) imported · \(existing) already in Library"
            )
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func addWatchedFolder(from sourceURL: URL) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let path = sourceURL.standardizedFileURL.path
            let folder = watchedFolders.first { $0.path == path } ?? WatchedFolder(
                id: makeManualID(prefix: "watch", name: sourceURL.lastPathComponent),
                path: path,
                createdAt: Date(),
                lastScannedAt: nil
            )
            try repository.upsertWatchedFolder(folder)
            try reloadLibrary()
            try scanWatchedFolder(folder)
            try reloadLibrary()
            postNotice(kind: .success, title: "Watched Folder Added", message: sourceURL.lastPathComponent)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func scanWatchedFolders() {
        do {
            guard !isScanningWatchedFolders else {
                return
            }
            guard !watchedFolders.isEmpty else {
                return
            }
            isScanningWatchedFolders = true
            defer {
                isScanningWatchedFolders = false
            }

            let results = try scanAllWatchedFolders()
            try reloadLibrary()
            let imported = results.flatMap(\.importedPapers).count
            let existing = results.flatMap(\.existingPapers).count
            postNotice(
                kind: imported > 0 ? .success : .info,
                title: "Folder Scan Finished",
                message: "\(imported) imported · \(existing) already known"
            )
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func removeWatchedFolder(_ folder: WatchedFolder) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            try repository.deleteWatchedFolder(id: folder.id)
            try reloadLibrary()
            postNotice(kind: .success, title: "Watched Folder Removed", message: URL(fileURLWithPath: folder.path).lastPathComponent)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectLibraryPaper(_ paper: Paper) {
        selectedLibraryPaper = paper
        loadPaperNotes(for: paper)
    }

    func showDiscover() {
        route = .discover
        clearReaderContext()
    }

    func recordDiscoverScrollPosition(_ paperID: String?) {
        let trimmed = paperID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = trimmed.isEmpty ? nil : trimmed
        guard discoverScrollPositionPaperID != normalized else {
            return
        }
        discoverScrollPositionPaperID = normalized
        if let normalized {
            UserDefaults.standard.set(normalized, forKey: discoverScrollPositionPaperIDDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: discoverScrollPositionPaperIDDefaultsKey)
        }
    }

    func showSettings() {
        route = .settings
        clearReaderContext()
    }

    func setLocalArxivCategories(_ categories: [String]) {
        var preferences = localDiscoverPreferences
        preferences.categories = categories
        localDiscoverPreferences = preferences.normalized
        saveLocalDiscoverPreferencesToDefaults(localDiscoverPreferences)
        postNotice(kind: .success, title: "arXiv Categories Saved", message: localDiscoverPreferences.categories.joined(separator: ", "))
    }

    func setLocalTagFilters(whitelist: [String], blacklist: [String]) {
        var preferences = localDiscoverPreferences
        preferences.whitelistTags = whitelist
        preferences.blacklistTags = blacklist
        localDiscoverPreferences = preferences.normalized
        saveLocalDiscoverPreferencesToDefaults(localDiscoverPreferences)
        if let feed = arxivFeed {
            arxivFeed = applyLocalDiscoverPreferences(to: feed)
        }
        postNotice(kind: .success, title: "Ranking Filters Saved")
    }

    func similarityCategoryIDsForSettings() -> [String] {
        let configured = localDiscoverPreferences.normalized.similarityCategoryIDs ?? categories.map(\.id)
        return normalizedIdentifiers(configured).filter { categoryID in
            categories.contains { $0.id == categoryID }
        }
    }

    func setLocalSimilarityCategoryIDs(_ categoryIDs: [String]) {
        var preferences = localDiscoverPreferences
        preferences.similarityCategoryIDs = normalizedIdentifiers(categoryIDs)
        localDiscoverPreferences = preferences.normalized
        saveLocalDiscoverPreferencesToDefaults(localDiscoverPreferences)
        postNotice(kind: .success, title: "Similarity Categories Saved")
    }

    private func includeCategoryInSimilarityDefaults(_ categoryID: String) {
        var preferences = localDiscoverPreferences
        guard var categoryIDs = preferences.similarityCategoryIDs else {
            return
        }
        if !categoryIDs.contains(categoryID) {
            categoryIDs.append(categoryID)
            preferences.similarityCategoryIDs = categoryIDs
            localDiscoverPreferences = preferences.normalized
            saveLocalDiscoverPreferencesToDefaults(localDiscoverPreferences)
        }
    }

    func setLocalEnrichmentPreferences(autoOpen: Bool, autoSave: Bool) {
        var preferences = localDiscoverPreferences
        preferences.enrichment = LocalEnrichmentPreferences(autoEnrichOnOpen: autoOpen, autoEnrichOnSave: autoSave)
        localDiscoverPreferences = preferences.normalized
        saveLocalDiscoverPreferencesToDefaults(localDiscoverPreferences)
        postNotice(kind: .success, title: "Enrichment Preferences Saved")
    }

    func setEmbeddingProviderSettings(enabled: Bool, baseURL: String, apiKey: String, model: String) {
        do {
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try saveEmbeddingProviderAPIKeyToKeychain(trimmedAPIKey)
            embeddingProviderAPIKey = trimmedAPIKey
            var preferences = localDiscoverPreferences
            preferences.embedding = EmbeddingProviderSettings(enabled: enabled, baseURL: baseURL, model: model)
            localDiscoverPreferences = preferences.normalized
            saveLocalDiscoverPreferencesToDefaults(localDiscoverPreferences)
            postNotice(kind: .success, title: "Embedding Provider Saved")
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func testEmbeddingProvider(baseURL: String, apiKey: String, model: String) async {
        guard !isTestingEmbeddingProvider else {
            return
        }
        isTestingEmbeddingProvider = true
        embeddingProviderTestStatus = "Testing..."
        defer {
            isTestingEmbeddingProvider = false
        }
        do {
            let settings = EmbeddingProviderSettings(enabled: true, baseURL: baseURL, model: model)
            let client = try OpenAICompatibleEmbeddingClient(settings: settings, apiKey: apiKey)
            let vectors = try await client.embed(texts: ["Paper Codex embedding connection test."])
            let dimensions = vectors.first?.count ?? 0
            embeddingProviderTestStatus = "Connected · \(dimensions) dimensions"
            postNotice(kind: .success, title: "Embedding Test Passed", message: "\(dimensions) dimensions")
        } catch {
            embeddingProviderTestStatus = "Failed: \(error)"
            postNotice(kind: .error, title: "Embedding Test Failed", message: String(describing: error), autoDismissAfter: nil)
        }
    }

    func setDiscoverCodexSettings(modelOverride: String, concurrency: Int) {
        let trimmedModel = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        discoverCodexModelOverride = trimmedModel
        discoverCodexConcurrency = min(max(concurrency, 1), 20)
        if trimmedModel.isEmpty {
            UserDefaults.standard.removeObject(forKey: discoverCodexModelOverrideDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmedModel, forKey: discoverCodexModelOverrideDefaultsKey)
        }
        UserDefaults.standard.set(discoverCodexConcurrency, forKey: discoverCodexConcurrencyDefaultsKey)
        mergeAvailableCodexModelIDs([trimmedModel])
        postNotice(kind: .success, title: "Discover Processing Saved", message: "\(discoverCodexConcurrency) workers")
    }

    func setCodexSystemPrompt(_ prompt: String) {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || PromptBuilder.isBuiltInSystemPrompt(normalized) {
            resetCodexSystemPrompt()
            return
        }
        codexSystemPrompt = normalized
        UserDefaults.standard.set(normalized, forKey: codexSystemPromptDefaultsKey)
        postNotice(kind: .success, title: "System Prompt Saved")
    }

    func resetCodexSystemPrompt() {
        codexSystemPrompt = PromptBuilder.defaultSystemPrompt(for: globalLanguageMode)
        UserDefaults.standard.removeObject(forKey: codexSystemPromptDefaultsKey)
        postNotice(kind: .success, title: "System Prompt Reset")
    }

    func setGlobalLanguageMode(_ mode: PaperCodexLanguageMode) {
        let shouldSwitchSystemPrompt = PromptBuilder.isBuiltInSystemPrompt(codexSystemPrompt)
        globalLanguageMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: globalLanguageModeDefaultsKey)
        if shouldSwitchSystemPrompt {
            codexSystemPrompt = PromptBuilder.defaultSystemPrompt(for: mode)
            UserDefaults.standard.removeObject(forKey: codexSystemPromptDefaultsKey)
        }
        let promptMessage = shouldSwitchSystemPrompt ? "System prompt switched" : "Custom prompt preserved"
        postNotice(kind: .success, title: "Language Saved", message: "\(mode.title(appLanguage: mode)) · \(promptMessage)")
    }

    func setArxivSaveOrganization(_ organization: ArxivSaveOrganization) {
        arxivSaveOrganization = organization
        UserDefaults.standard.set(organization.rawValue, forKey: arxivSaveOrganizationDefaultsKey)
        postNotice(kind: .success, title: "Storage Rule Saved", message: organization.title)
    }

    func setLibrarySidebarWidth(_ width: CGFloat) {
        let clamped = min(max(width, 220), 420)
        librarySidebarWidth = clamped
        UserDefaults.standard.set(Double(clamped), forKey: librarySidebarWidthDefaultsKey)
    }

    func addQuickPrompt(title: String, content: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            errorMessage = AppModelError.emptyName.description
            return
        }
        quickPrompts.append(
            QuickPrompt(
                id: "prompt-\(makeSlug(from: trimmedTitle))-\(UUID().uuidString.prefix(8).lowercased())",
                title: trimmedTitle,
                content: trimmedContent
            )
        )
        saveQuickPromptsToDefaults(quickPrompts)
        postNotice(kind: .success, title: "Prompt Added", message: trimmedTitle)
    }

    func updateQuickPrompt(_ prompt: QuickPrompt, title: String, content: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            errorMessage = AppModelError.emptyName.description
            return
        }
        guard let index = quickPrompts.firstIndex(where: { $0.id == prompt.id }) else {
            return
        }
        quickPrompts[index] = QuickPrompt(id: prompt.id, title: trimmedTitle, content: trimmedContent)
        saveQuickPromptsToDefaults(quickPrompts)
        postNotice(kind: .success, title: "Prompt Updated", message: trimmedTitle)
    }

    func moveQuickPrompt(_ prompt: QuickPrompt, direction: Int) {
        guard let index = quickPrompts.firstIndex(where: { $0.id == prompt.id }) else {
            return
        }
        let target = index + direction
        guard quickPrompts.indices.contains(target) else {
            return
        }
        quickPrompts.swapAt(index, target)
        saveQuickPromptsToDefaults(quickPrompts)
        postNotice(kind: .success, title: "Prompt Reordered", message: prompt.title)
    }

    func deleteQuickPrompt(_ prompt: QuickPrompt) {
        quickPrompts.removeAll { $0.id == prompt.id }
        saveQuickPromptsToDefaults(quickPrompts)
        postNotice(kind: .success, title: "Prompt Deleted", message: prompt.title)
    }

    func sendQuickPrompt(_ prompt: QuickPrompt) {
        Task {
            await sendMessage(prompt.content)
        }
    }

    func applyDiscoverQuickRange(_ preset: DiscoverQuickRange) {
        do {
            let range = try preset.dateRange(endingAt: discoverEndDate)
            discoverStartDate = range.start
            discoverEndDate = range.end
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func startDiscoverSearch() {
        guard activeDiscoverSearchTask == nil, !isSearchingDiscover else {
            return
        }
        activeDiscoverSearchTask = Task { [weak self] in
            await self?.searchDiscover()
            await MainActor.run {
                self?.activeDiscoverSearchTask = nil
            }
        }
    }

    func cancelDiscoverSearch() {
        isCancellingDiscoverSearch = true
        activeDiscoverSearchTask?.cancel()
    }

    func rerankCurrentDiscoverResults() async {
        guard let currentFeed = arxivFeed,
              !isSearchingDiscover,
              !isProcessingDiscoverResults else {
            return
        }
        do {
            let range = try DiscoverDateRange(start: discoverStartDate, end: discoverEndDate)
            let categories = discoverSelectedCategories.isEmpty ? [localDiscoverPreferences.normalized.categories.first ?? "cs.CV"] : discoverSelectedCategories
            let similaritySourceIDs = effectiveDiscoverSimilaritySourceIDs()
            let query = DiscoverQuery(
                keyword: discoverKeyword,
                dateRange: range,
                categories: categories,
                similaritySourceIDs: similaritySourceIDs,
                rankingVersion: discoverRankingVersion()
            ).normalized
            let rankedFeed = try await applyDiscoverRanking(to: resetDiscoverRanking(in: currentFeed), query: query)
            let filteredFeed = filterDiscoverFeed(rankedFeed, keyword: query.keyword)
            try displayDiscoverFeed(
                filteredFeed,
                query: query,
                progressTitle: similaritySourceIDs.isEmpty ? "Similarity cleared" : "Similarity ranking ready",
                cacheRangeFeed: false
            )
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func searchDiscover() async {
        do {
            isSearchingDiscover = true
            isCancellingDiscoverSearch = false
            defer {
                isSearchingDiscover = false
                isCancellingDiscoverSearch = false
            }

            let range = try DiscoverDateRange(start: discoverStartDate, end: discoverEndDate)
            let categories = discoverSelectedCategories.isEmpty ? [localDiscoverPreferences.normalized.categories.first ?? "cs.CV"] : discoverSelectedCategories
            let similaritySourceIDs = effectiveDiscoverSimilaritySourceIDs()
            let query = DiscoverQuery(
                keyword: discoverKeyword,
                dateRange: range,
                categories: categories,
                similaritySourceIDs: similaritySourceIDs,
                rankingVersion: discoverRankingVersion()
            ).normalized
            discoverStartDate = query.dateRange.start
            discoverEndDate = query.dateRange.end
            discoverSelectedCategories = query.categories
            discoverPaperInteractionStateByID = [:]

            arxivCacheProgress = ArxivCacheProgress(
                date: "\(range.start)...\(range.end)",
                title: "Searching arXiv",
                detail: categories.joined(separator: ", "),
                completed: 0,
                total: 0
            )

            let client = makeLocalArxivClient(categories: categories)
            let liveFeed = try await client.fetchFeed(range: range)
            let rankedFeed = try await applyDiscoverRanking(to: liveFeed, query: query)
            try arxivCache.saveFeed(rankedFeed)
            try mergeAndSaveArxivDate(rankedFeed.date)
            let filteredFeed = filterDiscoverFeed(rankedFeed, keyword: query.keyword)
            try displayDiscoverFeed(filteredFeed, query: query, progressTitle: "Search results cached", cacheRangeFeed: false)
        } catch {
            if isCancellationError(error) || isCancellingDiscoverSearch || Task.isCancelled {
                arxivCacheProgress = nil
            } else if (try? loadCachedDiscoverSearch()) == true {
                errorMessage = "Using cached Discover results. Search failed: \(error)"
            } else {
                errorMessage = String(describing: error)
            }
        }
    }

    func processCurrentDiscoverResults(_ papers: [ArxivFeedPaper], actions: Set<DiscoverProcessAction> = Set(DiscoverProcessAction.allCases)) async {
        guard !isProcessingDiscoverResults else {
            return
        }
        let visiblePapers = uniqueArxivPapers(papers)
        guard !visiblePapers.isEmpty, !actions.isEmpty else {
            return
        }
        isProcessingDiscoverResults = true
        isCancellingDiscoverProcessing = false
        defer {
            isProcessingDiscoverResults = false
            isCancellingDiscoverProcessing = false
            activeDiscoverCodexRunHandles.removeAll()
            discoverProcessingProgress = nil
        }

        for paper in visiblePapers {
            discoverPaperInteractionStateByID[paper.id] = .queued
        }

        if actions.contains(.translate) || actions.contains(.summarize) {
            let total = visiblePapers.count
            var completed = 0
            var cached = 0
            var failed = 0
            var aggregateTokenUsage = CodexTokenUsage()
            discoverProcessingProgress = ArxivCacheProgress(
                date: selectedArxivDate ?? "\(discoverStartDate)...\(discoverEndDate)",
                title: "Processing results",
                detail: "0/\(total) processed",
                completed: completed,
                total: total
            )

            let workerCount = min(max(discoverCodexConcurrency, 1), max(total, 1))
            var nextIndex = 0

            await withTaskGroup(of: DiscoverPaperProcessingResult.self) { group in
                for _ in 0..<workerCount {
                    guard nextIndex < visiblePapers.count else {
                        break
                    }
                    let paper = visiblePapers[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await self.processDiscoverPaperForEnrichment(paper, actions: actions)
                    }
                }

                while let result = await group.next() {
                    if result.state == .cancelled {
                        group.cancelAll()
                        break
                    }
                    completed += 1
                    switch result.state {
                    case .processed:
                        break
                    case .cached:
                        cached += 1
                    case .failed:
                        failed += 1
                    case .cancelled:
                        break
                    }
                    if let tokenUsage = result.tokenUsage {
                        aggregateTokenUsage.add(tokenUsage)
                    }
                    updateDiscoverProcessingProgress(
                        completed: completed,
                        cached: cached,
                        failed: failed,
                        total: total,
                        tokenUsage: aggregateTokenUsage.isEmpty ? nil : aggregateTokenUsage
                    )
                    if isCancellingDiscoverProcessing || Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    if nextIndex < visiblePapers.count {
                        let paper = visiblePapers[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            await self.processDiscoverPaperForEnrichment(paper, actions: actions)
                        }
                    }
                }
            }
            if !aggregateTokenUsage.isEmpty {
                postNotice(
                    kind: .info,
                    title: "Process Tokens",
                    message: aggregateTokenUsage.compactSummary,
                    autoDismissAfter: 8
                )
            }
        }

        if actions.contains(.cachePDFThumbnails),
           !isCancellingDiscoverProcessing,
           !Task.isCancelled {
            discoverProcessingProgress = nil
            await cacheDiscoverPDFs(visiblePapers)
        }
    }

    func cancelDiscoverProcessing() {
        isCancellingDiscoverProcessing = true
        for runHandle in activeDiscoverCodexRunHandles {
            runHandle.cancel()
        }
    }

    private func cacheDiscoverPDFs(_ papers: [ArxivFeedPaper]) async {
        guard !papers.isEmpty else {
            return
        }
        isCachingDiscoverPDFs = true
        isCancellingDiscoverPDFCache = false
        defer {
            isCachingDiscoverPDFs = false
            isCancellingDiscoverPDFCache = false
            discoverPDFCacheProgress = nil
        }

        let client = makeLocalArxivClient()
        let total = papers.count
        var completed = 0
        var cached = 0
        var failed = 0
        updateDiscoverPDFCacheProgress(completed: completed, cached: cached, failed: failed, total: total)

        for paper in papers {
            if isCancellingDiscoverPDFCache || Task.isCancelled {
                break
            }
            arxivDownloadingPaperIDs.insert(paper.id)
            discoverPaperInteractionStateByID[paper.id] = .downloading
            arxivDownloadProgressByID[paper.id] = 0.08
            do {
                let wasCached = try cachedArxivPDFURL(for: paper) != nil
                let pdfURL = try await ensureArxivPDFCached(paper, client: client)
                arxivDownloadProgressByID[paper.id] = 0.84
                _ = try refreshDiscoverPDFThumbnails(for: paper, pdfURL: pdfURL)
                if wasCached {
                    cached += 1
                }
                arxivDownloadProgressByID[paper.id] = 1
                discoverPaperInteractionStateByID[paper.id] = .pdfCached
            } catch {
                arxivDownloadingPaperIDs.remove(paper.id)
                arxivDownloadProgressByID.removeValue(forKey: paper.id)
                if isCancellationError(error) || isCancellingDiscoverPDFCache || Task.isCancelled {
                    discoverPaperInteractionStateByID[paper.id] = .cancelled
                    break
                }
                discoverPaperInteractionStateByID[paper.id] = .failed
                failed += 1
            }
            completed += 1
            arxivDownloadingPaperIDs.remove(paper.id)
            arxivDownloadProgressByID.removeValue(forKey: paper.id)
            updateDiscoverPDFCacheProgress(completed: completed, cached: cached, failed: failed, total: total)
        }
    }

    private func processDiscoverPaperForEnrichment(_ paper: ArxivFeedPaper, actions: Set<DiscoverProcessAction>) async -> DiscoverPaperProcessingResult {
        if isCancellingDiscoverProcessing || Task.isCancelled {
            discoverPaperInteractionStateByID[paper.id] = .cancelled
            return DiscoverPaperProcessingResult(paperID: paper.id, state: .cancelled)
        }

        let existing = try? localDiscoverCache.loadEnrichment(arxivID: paper.id)
        if let existing,
           discoverEnrichment(existing, satisfies: actions) {
            discoverEnrichmentsByID[paper.id] = existing
            discoverPaperInteractionStateByID[paper.id] = .cached
            return DiscoverPaperProcessingResult(paperID: paper.id, state: .cached)
        }

        do {
            discoverPaperInteractionStateByID[paper.id] = .processing
            let runResult = try await runDiscoverCodexEnrichment(for: paper, actions: actions, existing: existing)
            try localDiscoverCache.saveEnrichment(runResult.enrichment)
            discoverEnrichmentsByID[paper.id] = runResult.enrichment
            discoverPaperInteractionStateByID[paper.id] = .processed
            return DiscoverPaperProcessingResult(paperID: paper.id, state: .processed, tokenUsage: runResult.tokenUsage)
        } catch {
            if isCancellingDiscoverProcessing || Task.isCancelled || isCancellationError(error) {
                discoverPaperInteractionStateByID[paper.id] = .cancelled
                return DiscoverPaperProcessingResult(paperID: paper.id, state: .cancelled)
            }
            let failedEnrichment = DiscoverPaperEnrichment(
                arxivID: paper.id,
                processorVersion: DiscoverPaperEnrichment.currentProcessorVersion,
                promptVersion: DiscoverPaperEnrichment.currentPromptVersion,
                modelIdentity: "codex",
                titleZH: "",
                summaryZH: "",
                contribution: "",
                tags: [],
                links: [:],
                generatedAt: Date(),
                error: String(describing: error)
            )
            try? localDiscoverCache.saveEnrichment(failedEnrichment)
            discoverEnrichmentsByID[paper.id] = failedEnrichment
            discoverPaperInteractionStateByID[paper.id] = .failed
            return DiscoverPaperProcessingResult(paperID: paper.id, state: .failed)
        }
    }

    private func discoverEnrichment(_ enrichment: DiscoverPaperEnrichment, satisfies actions: Set<DiscoverProcessAction>) -> Bool {
        guard enrichment.isCurrent, enrichment.error == nil else {
            return false
        }
        if actions.contains(.translate),
           enrichment.titleZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if actions.contains(.summarize) {
            let hasSummary = !enrichment.summaryZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasContribution = !enrichment.contribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasSummary || !hasContribution || enrichment.tags.isEmpty {
                return false
            }
        }
        return true
    }

    func discoverEnrichment(for paper: ArxivFeedPaper) -> DiscoverPaperEnrichment? {
        discoverEnrichmentsByID[paper.id]
    }

    func refreshArxivDatesAndFeed() async {
        do {
            isLoadingArxivFeed = true
            isRefreshingArxivDates = true
            defer {
                isLoadingArxivFeed = false
                isRefreshingArxivDates = false
            }
            let client = makeLocalArxivClient()
            let feed = try await client.fetchLatestFeed()
            try cacheAndDisplayArxivFeed(feed, title: "Metadata cached")
            try await preloadArxivAssets(includeLarge: false, feed: feed)
        } catch {
            if let date = selectedArxivDate,
               (try? loadCachedArxivFeed(date: date)) == true {
                errorMessage = "Using cached arXiv feed for \(date). Refresh failed: \(error)"
            } else {
                errorMessage = String(describing: error)
            }
        }
    }

    func refreshArxivDates() async {
        do {
            isRefreshingArxivDates = true
            defer {
                isRefreshingArxivDates = false
            }
            let client = makeLocalArxivClient()
            let feed = try await client.fetchLatestFeed()
            try cacheAndDisplayArxivFeed(feed, title: "Latest arXiv date cached")
            if selectedArxivDate == nil {
                selectedArxivDate = feed.date
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadArxivFeed(date: String) async {
        do {
            isLoadingArxivFeed = true
            defer {
                isLoadingArxivFeed = false
            }
            selectedArxivDate = date
            arxivFeed = nil
            arxivCacheProgress = ArxivCacheProgress(
                date: date,
                title: "Loading feed",
                detail: "Fetching metadata",
                completed: 0,
                total: 0
            )
            let latestCachedDate = arxivDates.sorted().last
            if latestCachedDate != date,
               (try? loadCachedArxivFeed(date: date)) == true {
                return
            }
            let client = makeLocalArxivClient()
            let feed = try await client.fetchFeed(date: date)
            try cacheAndDisplayArxivFeed(feed, title: "Metadata cached")
            try await preloadArxivAssets(includeLarge: false, feed: feed)
        } catch {
            if (try? loadCachedArxivFeed(date: date)) == true {
                errorMessage = "Using cached arXiv feed for \(date). Refresh failed: \(error)"
            } else {
                errorMessage = String(describing: error)
            }
        }
    }

    func preloadArxivAssets(includeLarge: Bool) async {
        do {
            guard let arxivFeed else {
                return
            }
            try await preloadArxivAssets(includeLarge: includeLarge, feed: arxivFeed)
        } catch {
            if isCancellationError(error) {
                return
            }
            errorMessage = String(describing: error)
        }
    }

    func ensureArxivAssetCached(_ asset: ArxivFeedAsset?) async {
        do {
            guard let asset else {
                return
            }
            if let url = try arxivCache.cachedAssetURL(path: asset.path) {
                arxivAssetURLs[asset.path] = url
                return
            }
            let data = try await fetchArxivAsset(asset)
            arxivAssetURLs[asset.path] = try arxivCache.saveAsset(data, path: asset.path)
        } catch {
            if isCancellationError(error) {
                return
            }
            errorMessage = String(describing: error)
        }
    }

    func cachedArxivAssetURL(for asset: ArxivFeedAsset?) -> URL? {
        guard let asset else {
            return nil
        }
        if let url = arxivAssetURLs[asset.path] {
            return url
        }
        return try? arxivCache.cachedAssetURL(path: asset.path)
    }

    func cachedArxivPDFThumbnailURLs(for paper: ArxivFeedPaper) -> [URL] {
        arxivPDFThumbnailURLsByID[paper.id, default: []]
    }

    func isDownloadingArxivPaper(_ paper: ArxivFeedPaper) -> Bool {
        arxivDownloadingPaperIDs.contains(paper.id)
    }

    func arxivDownloadProgress(for paper: ArxivFeedPaper) -> Double? {
        arxivDownloadProgressByID[paper.id]
    }

    func startCachingDiscoverPDFs(_ papers: [ArxivFeedPaper]) {
        let uniquePapers = uniqueArxivPapers(papers)
        guard !uniquePapers.isEmpty,
              activeDiscoverPDFCacheTask == nil,
              !isCachingDiscoverPDFs else {
            return
        }
        activeDiscoverPDFCacheTask = Task { [weak self] in
            await self?.cacheDiscoverPDFs(uniquePapers)
            await MainActor.run {
                self?.activeDiscoverPDFCacheTask = nil
            }
        }
    }

    func cancelDiscoverPDFCache() {
        isCancellingDiscoverPDFCache = true
        activeDiscoverPDFCacheTask?.cancel()
    }

    func libraryPaper(for arxivPaper: ArxivFeedPaper, includePlaceholders: Bool = true) -> Paper? {
        let absURL = arxivPaper.links.abs
        return papers.first { paper in
            if !includePlaceholders, paper.isArxivImportPlaceholder {
                return false
            }
            return paper.sourceURL == absURL || paper.sourceURL?.contains(arxivPaper.id) == true
        }
    }

    func arxivImportPlaceholderDetail(for paper: Paper) -> String {
        guard let canonicalID = paper.arxivImportPlaceholderCanonicalID else {
            return paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", ")
        }
        if let failure = failedArxivLibraryImportMessagesByID[canonicalID] {
            return globalLanguageMode == .chinese ? "导入失败 · \(failure)" : "Import failed · \(failure)"
        }
        if pendingArxivLibraryImportIDs.contains(canonicalID) {
            return globalLanguageMode == .chinese ? "正在缓存 arXiv 元数据和 PDF..." : "Caching arXiv metadata and PDF..."
        }
        return globalLanguageMode == .chinese ? "已加入 arXiv 导入队列" : "Queued for arXiv import"
    }

    func openArxivPaper(_ arxivPaper: ArxivFeedPaper) async {
        if let pendingPaper = paper(matchingArxivCanonicalID: arxivPaper.id, includePlaceholders: true),
           pendingPaper.isArxivImportPlaceholder,
           pendingArxivLibraryImportIDs.contains(arxivPaper.id) {
            route = .library
            selectedLibraryPaper = pendingPaper
            postNotice(kind: .info, title: "arXiv Import Running", message: arxivPaper.id)
            return
        }
        if let existing = libraryPaper(for: arxivPaper, includePlaceholders: false) {
            openPaper(existing)
            return
        }
        do {
            let paper = try await importArxivPaper(arxivPaper, isSaved: false)
            try reloadLibrary()
            openPaper(paper)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func suggestedCategoryIDsForDiscoverSave() -> [String] {
        normalizedSimilaritySourceIDs(discoverSelectedSimilaritySourceIDs).compactMap { sourceID in
            guard sourceID.hasPrefix("category:") else {
                return nil
            }
            let categoryID = String(sourceID.dropFirst("category:".count))
            return categories.contains(where: { $0.id == categoryID }) ? categoryID : nil
        }
    }

    func addArxivPaperToLibrary(
        _ arxivPaper: ArxivFeedPaper,
        selectedCategoryIDs: [String] = [],
        newCategoryNames: [String] = []
    ) async {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if let pendingPaper = paper(matchingArxivCanonicalID: arxivPaper.id, includePlaceholders: true),
               pendingPaper.isArxivImportPlaceholder,
               pendingArxivLibraryImportIDs.contains(arxivPaper.id) {
                selectedLibraryPaper = pendingPaper
                postNotice(kind: .info, title: "arXiv Import Already Queued", message: arxivPaper.id)
                return
            }
            if let existing = libraryPaper(for: arxivPaper, includePlaceholders: false) {
                try assignCategories(
                    categoryIDs: selectedCategoryIDs,
                    newCategoryNames: newCategoryNames,
                    to: existing,
                    repository: repository
                )
                try reloadLibrary()
                openPaper(existing)
                return
            }
            let paper = try await importArxivPaper(arxivPaper, isSaved: true)
            try assignCategories(
                categoryIDs: selectedCategoryIDs,
                newCategoryNames: newCategoryNames,
                to: paper,
                repository: repository
            )
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func enqueueArxivIDsForLibrary(_ versionedIDs: [String], categoryID: String?) {
        let ids = uniqueVersionedArxivIDs(versionedIDs)
        guard !ids.isEmpty else {
            return
        }
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            var queuedIDs: [String] = []
            var placeholderPaperIDs: [String] = []
            var alreadyAvailableCount = 0
            for versionedID in ids {
                let canonicalID = ArxivIDExtractor.canonicalID(from: versionedID)
                if let existing = paper(matchingArxivCanonicalID: canonicalID, includePlaceholders: false) {
                    try transferAndDeleteArxivImportPlaceholder(canonicalID: canonicalID, toPaperID: existing.id, categoryID: categoryID, repository: repository)
                    alreadyAvailableCount += 1
                    continue
                }

                let placeholder = makeArxivImportPlaceholderPaper(canonicalID: canonicalID)
                try repository.upsertPaper(placeholder)
                if let categoryID {
                    try repository.assignPaper(placeholder.id, toCategory: categoryID)
                }
                placeholderPaperIDs.append(placeholder.id)
                failedArxivLibraryImportMessagesByID.removeValue(forKey: canonicalID)
                if !pendingArxivLibraryImportIDs.contains(canonicalID) {
                    pendingArxivLibraryImportIDs.insert(canonicalID)
                    queuedIDs.append(versionedID)
                }
            }

            try reloadLibrary()
            route = .library
            if let firstPlaceholderID = placeholderPaperIDs.first,
               let placeholder = papers.first(where: { $0.id == firstPlaceholderID }) {
                selectedLibraryPaper = placeholder
            }
            if !queuedIDs.isEmpty {
                postNotice(
                    kind: .info,
                    title: "arXiv Import Started",
                    message: "\(queuedIDs.count) queued\(alreadyAvailableCount > 0 ? " · \(alreadyAvailableCount) already ready" : "")"
                )
                Task { [weak self] in
                    await self?.completeQueuedArxivLibraryImports(queuedIDs, categoryID: categoryID)
                }
            } else if alreadyAvailableCount > 0 {
                postNotice(kind: .info, title: "Already in Library", message: "\(alreadyAvailableCount) paper\(alreadyAvailableCount == 1 ? "" : "s")")
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func addArxivIDToLibrary(_ versionedID: String, categoryID: String?) async -> LibraryArxivImportOutcome {
        let canonicalID = ArxivIDExtractor.canonicalID(from: versionedID)
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let client = makeLocalArxivClient()
            let metadataPapers = try await client.fetchPapers(ids: [versionedID])
            guard let arxivPaper = metadataPapers.first(where: { $0.id == canonicalID }) ?? metadataPapers.first else {
                throw AppModelError.arxivMetadataNotFound(versionedID)
            }

            if let existing = libraryPaper(for: arxivPaper, includePlaceholders: false) {
                try transferAndDeleteArxivImportPlaceholder(canonicalID: canonicalID, toPaperID: existing.id, categoryID: categoryID, repository: repository)
                try reloadLibrary()
                selectedLibraryPaper = papers.first { $0.id == existing.id } ?? existing
                return LibraryArxivImportOutcome(
                    requestedID: versionedID,
                    canonicalID: canonicalID,
                    title: existing.title,
                    state: .alreadyInLibrary,
                    message: categoryID == nil ? "Already in Library" : "Already in Library · folder updated"
                )
            }

            let importedPaper = try await importArxivPaper(arxivPaper, isSaved: true)
            try transferAndDeleteArxivImportPlaceholder(canonicalID: canonicalID, toPaperID: importedPaper.id, categoryID: categoryID, repository: repository)
            try reloadLibrary()
            selectedLibraryPaper = papers.first { $0.id == importedPaper.id } ?? importedPaper
            return LibraryArxivImportOutcome(
                requestedID: versionedID,
                canonicalID: canonicalID,
                title: importedPaper.title,
                state: .imported,
                message: categoryID == nil ? "Imported" : "Imported to folder"
            )
        } catch {
            let message = String(describing: error)
            errorMessage = message
            return LibraryArxivImportOutcome(
                requestedID: versionedID,
                canonicalID: canonicalID,
                title: "",
                state: .failed,
                message: message
            )
        }
    }

    private func completeQueuedArxivLibraryImports(_ versionedIDs: [String], categoryID: String?) async {
        var readyCount = 0
        for versionedID in versionedIDs {
            let outcome = await addArxivIDToLibrary(versionedID, categoryID: categoryID)
            pendingArxivLibraryImportIDs.remove(outcome.canonicalID)
            switch outcome.state {
            case .imported:
                failedArxivLibraryImportMessagesByID.removeValue(forKey: outcome.canonicalID)
                readyCount += 1
            case .alreadyInLibrary:
                failedArxivLibraryImportMessagesByID.removeValue(forKey: outcome.canonicalID)
            case .failed:
                failedArxivLibraryImportMessagesByID[outcome.canonicalID] = outcome.message
                postNotice(kind: .error, title: "arXiv Import Failed", message: "\(outcome.canonicalID) · \(outcome.message)", autoDismissAfter: nil)
            }
        }
        if readyCount > 0 {
            postNotice(kind: .success, title: "arXiv Import Finished", message: "\(readyCount) paper\(readyCount == 1 ? "" : "s") ready")
        }
    }

    private func uniqueVersionedArxivIDs(_ versionedIDs: [String]) -> [String] {
        var seenCanonicalIDs: Set<String> = []
        var result: [String] = []
        for versionedID in versionedIDs {
            let canonicalID = ArxivIDExtractor.canonicalID(from: versionedID)
            guard seenCanonicalIDs.insert(canonicalID).inserted else {
                continue
            }
            result.append(versionedID)
        }
        return result
    }

    private func makeArxivImportPlaceholderPaper(canonicalID: String) -> Paper {
        let now = Date()
        return Paper(
            id: Paper.makeArxivImportPlaceholderID(for: canonicalID),
            filePath: "",
            fileHash: Paper.arxivImportPlaceholderFileHash(canonicalID: canonicalID),
            title: canonicalID,
            authors: [],
            year: nil,
            sourceURL: "https://arxiv.org/abs/\(canonicalID)",
            isSaved: true,
            importedAt: now,
            updatedAt: now
        )
    }

    private func paper(matchingArxivCanonicalID canonicalID: String, includePlaceholders: Bool) -> Paper? {
        papers.first { paper in
            if !includePlaceholders, paper.isArxivImportPlaceholder {
                return false
            }
            return paper.arxivImportPlaceholderCanonicalID == canonicalID
                || paper.sourceURL == "https://arxiv.org/abs/\(canonicalID)"
                || paper.sourceURL?.contains(canonicalID) == true
        }
    }

    private func transferAndDeleteArxivImportPlaceholder(
        canonicalID: String,
        toPaperID paperID: String,
        categoryID: String?,
        repository: PaperRepository
    ) throws {
        let placeholderID = Paper.makeArxivImportPlaceholderID(for: canonicalID)
        if let categoryID {
            try repository.assignPaper(paperID, toCategory: categoryID)
        }
        guard placeholderID != paperID,
              try repository.fetchPapers(ids: [placeholderID]).first != nil else {
            return
        }
        let placeholderCategoryIDs = try repository.fetchCategoryIDs(forPaperID: placeholderID)
        let placeholderTags = try repository.fetchTags(forPaperID: placeholderID)
        for categoryID in placeholderCategoryIDs {
            try repository.assignPaper(paperID, toCategory: categoryID)
        }
        for tag in placeholderTags {
            try repository.assignPaper(paperID, toTag: tag.id)
        }
        try repository.deletePapers(ids: [placeholderID])
    }

    func saveCachedPaperToLibrary(
        _ paper: Paper,
        selectedCategoryIDs: [String] = [],
        newCategoryNames: [String] = []
    ) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard !paper.isSaved else {
                return
            }
            let metadata = PaperImportMetadata(
                title: paper.title,
                authors: paper.authors,
                year: paper.year,
                sourceURL: paper.sourceURL
            )
            let result = try PaperLibraryImporter(repository: repository, supportRoot: supportRoot)
                .importPDF(
                    from: URL(fileURLWithPath: paper.filePath),
                    metadata: metadata,
                    isSaved: true,
                    storageSubpath: arxivStorageSubpath(forCachedPaper: paper)
                )
            try reloadLibrary()
            try assignCategories(
                categoryIDs: selectedCategoryIDs,
                newCategoryNames: newCategoryNames,
                to: result.paper,
                repository: repository
            )
            try reloadLibrary()
            let savedPaper = papers.first { $0.id == result.paper.id } ?? result.paper
            selectedLibraryPaper = savedPaper
            selectedPaper = savedPaper
            replaceReaderTab(oldPaperID: paper.id, with: savedPaper)
            if let session = selectedSession {
                let context = try loadSessionPaperContext(session: session, fallbackPaper: savedPaper, repository: repository)
                try workspaceManager.writeWorkspace(
                    session: session,
                    papers: context.papers,
                    pagesByPaperID: context.pagesByPaperID,
                    spansByPaperID: context.spansByPaperID,
                    anchorsByPaperID: context.anchorsByPaperID
                )
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func clearArxivCaches() {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            try repository.deleteUnsavedPapers()
            try removeDirectoryIfExists(supportRoot.appendingPathComponent("cache", isDirectory: true))
            try removeDirectoryIfExists(supportRoot.appendingPathComponent("arxiv-cache", isDirectory: true))
            arxivFeed = nil
            selectedArxivPaper = nil
            arxivAssetURLs = [:]
            arxivPDFThumbnailURLsByID = [:]
            discoverPDFCacheProgress = nil
            try reloadLibrary()
            refreshCacheStorageSummary()
            postNotice(kind: .success, title: "arXiv Cache Cleared", message: "Temporary feeds, PDFs, and previews were removed.")
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func createCategory(name: String, parentID: String?) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppModelError.emptyName
            }
            let nextSortOrder = (categories.map(\.sortOrder).max() ?? 0) + 1
            let category = PaperCodexCore.Category(
                id: makeManualID(prefix: "cat", name: trimmed),
                parentID: parentID,
                name: trimmed,
                sortOrder: nextSortOrder
            )
            try repository.upsertCategory(category)
            includeCategoryInSimilarityDefaults(category.id)
            try reloadLibrary()
            postNotice(kind: .success, title: "Category Created", message: trimmed)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func updateCategory(_ categoryID: String, name: String, parentID: String?) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard var category = categories.first(where: { $0.id == categoryID }) else {
                throw AppModelError.categoryNotFound(categoryID)
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppModelError.emptyName
            }
            if parentID == categoryID || categoryDescendantIDs(of: categoryID).contains(parentID ?? "") {
                throw AppModelError.invalidCategoryMove
            }
            category.name = trimmed
            category.parentID = parentID
            try repository.upsertCategory(category)
            try reloadLibrary()
            postNotice(kind: .success, title: "Category Updated", message: trimmed)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func moveCategory(_ categoryID: String, toParent parentID: String?) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard var category = categories.first(where: { $0.id == categoryID }) else {
                throw AppModelError.categoryNotFound(categoryID)
            }
            if parentID == categoryID || categoryDescendantIDs(of: categoryID).contains(parentID ?? "") {
                throw AppModelError.invalidCategoryMove
            }
            guard category.parentID != parentID else {
                return
            }
            category.parentID = parentID
            try repository.upsertCategory(category)
            try reloadLibrary()
            postNotice(kind: .success, title: "Category Moved", message: category.name)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func deleteCategory(_ categoryID: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let name = categories.first { $0.id == categoryID }?.name ?? "Category"
            try repository.deleteCategory(id: categoryID)
            try reloadLibrary()
            postNotice(kind: .success, title: "Category Deleted", message: name)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func createTag(name: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppModelError.emptyName
            }
            if tags.contains(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                postNotice(kind: .info, title: "Tag Already Exists", message: trimmed)
                return
            }
            try repository.upsertTag(PaperTag(id: makeManualID(prefix: "tag", name: trimmed), name: trimmed))
            try reloadLibrary()
            postNotice(kind: .success, title: "Tag Created", message: trimmed)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func updateTag(_ tagID: String, name: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppModelError.emptyName
            }
            try repository.upsertTag(PaperTag(id: tagID, name: trimmed))
            try reloadLibrary()
            postNotice(kind: .success, title: "Tag Updated", message: trimmed)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func deleteTag(_ tagID: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let name = tags.first { $0.id == tagID }?.name ?? "Tag"
            try repository.deleteTag(id: tagID)
            try reloadLibrary()
            postNotice(kind: .success, title: "Tag Deleted", message: name)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func categoryDescendantIDs(of categoryID: String) -> Set<String> {
        var descendants: Set<String> = []
        var didChange = true
        while didChange {
            didChange = false
            for category in categories where category.parentID.map({ $0 == categoryID || descendants.contains($0) }) == true && !descendants.contains(category.id) {
                descendants.insert(category.id)
                didChange = true
            }
        }
        return descendants
    }

    func setCategory(_ categoryID: String, assigned: Bool, for paper: Paper) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if assigned {
                try repository.assignPaper(paper.id, toCategory: categoryID)
            } else {
                try repository.removePaper(paper.id, fromCategory: categoryID)
            }
            try reloadLibrary()
            postNotice(kind: .success, title: assigned ? "Category Assigned" : "Category Removed", message: paper.title)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func assignPapers(_ paperIDs: [String], toCategory categoryID: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard categories.contains(where: { $0.id == categoryID }) else {
                throw AppModelError.categoryNotFound(categoryID)
            }
            let validPaperIDs = Set(papers.map(\.id))
            var assignedPaperIDs = Set<String>()
            for paperID in paperIDs where validPaperIDs.contains(paperID) && !assignedPaperIDs.contains(paperID) {
                try repository.assignPaper(paperID, toCategory: categoryID)
                assignedPaperIDs.insert(paperID)
            }
            guard !assignedPaperIDs.isEmpty else {
                return
            }
            try reloadLibrary()
            postNotice(kind: .success, title: "Papers Assigned", message: "\(assignedPaperIDs.count) moved into category")
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func movePapers(_ paperIDs: [String], toCategory categoryID: String?) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if let categoryID, !categories.contains(where: { $0.id == categoryID }) {
                throw AppModelError.categoryNotFound(categoryID)
            }
            let validPaperIDs = Set(papers.map(\.id))
            var movedPaperIDs = Set<String>()
            for paperID in paperIDs where validPaperIDs.contains(paperID) && !movedPaperIDs.contains(paperID) {
                for existingCategoryID in paperCategoryIDsByID[paperID, default: []] {
                    try repository.removePaper(paperID, fromCategory: existingCategoryID)
                }
                if let categoryID {
                    try repository.assignPaper(paperID, toCategory: categoryID)
                }
                movedPaperIDs.insert(paperID)
            }
            guard !movedPaperIDs.isEmpty else {
                return
            }
            try reloadLibrary()
            postNotice(kind: .success, title: "Papers Moved", message: "\(movedPaperIDs.count) updated")
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func assignPapers(_ paperIDs: [String], toTags tagIDs: [String]) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let validPaperIDs = Set(papers.map(\.id))
            let validTagIDs = Set(tags.map(\.id))
            let assignableTagIDs = Array(Set(tagIDs).intersection(validTagIDs)).sorted()
            guard !assignableTagIDs.isEmpty else {
                return
            }
            var assignedPaperIDs = Set<String>()
            for paperID in paperIDs where validPaperIDs.contains(paperID) && !assignedPaperIDs.contains(paperID) {
                for tagID in assignableTagIDs {
                    try repository.assignPaper(paperID, toTag: tagID)
                }
                assignedPaperIDs.insert(paperID)
            }
            guard !assignedPaperIDs.isEmpty else {
                return
            }
            try reloadLibrary()
            postNotice(kind: .success, title: "Tags Applied", message: "\(assignableTagIDs.count) tag\(assignableTagIDs.count == 1 ? "" : "s") · \(assignedPaperIDs.count) paper\(assignedPaperIDs.count == 1 ? "" : "s")")
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func deletePapers(_ paperIDs: [String]) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let requestedIDs = Set(paperIDs)
            let papersToDelete = papers.filter { requestedIDs.contains($0.id) }
            guard !papersToDelete.isEmpty else {
                return
            }
            let deletedIDs = Set(papersToDelete.map(\.id))
            try repository.deletePapers(ids: Array(deletedIDs))
            for paper in papersToDelete {
                try removeManagedPaperStorage(for: paper)
            }
            if let selectedLibraryPaper, deletedIDs.contains(selectedLibraryPaper.id) {
                self.selectedLibraryPaper = nil
            }
            if let selectedPaper, deletedIDs.contains(selectedPaper.id) {
                self.selectedPaper = nil
                selectedSession = nil
                sessions = []
                messages = []
                currentSelection = nil
                pdfJumpTarget = nil
                readerPosition = nil
                clearActiveCodexRunIfIdle()
                if route == .reader {
                    route = .library
                }
            }
            var tabState = readerTabState
            for paperID in deletedIDs {
                _ = tabState.close(paperID)
            }
            readerTabState = tabState
            try reloadLibrary()
            refreshCacheStorageSummary()
            postNotice(kind: .success, title: "Papers Deleted", message: "\(deletedIDs.count) removed")
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setTag(_ tagID: String, assigned: Bool, for paper: Paper) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if assigned {
                try repository.assignPaper(paper.id, toTag: tagID)
            } else {
                try repository.removePaper(paper.id, fromTag: tagID)
            }
            try reloadLibrary()
            postNotice(kind: .success, title: assigned ? "Tag Assigned" : "Tag Removed", message: paper.title)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func togglePaperStar(_ paper: Paper) {
        setPaperStarred(!paper.isStarred, for: paper)
    }

    func setPaperStarred(_ isStarred: Bool, for paper: Paper) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            try repository.setPaperStarred(isStarred, paperID: paper.id)
            try reloadLibrary()
            if selectedPaper?.id == paper.id {
                selectedPaper = papers.first { $0.id == paper.id } ?? selectedPaper
            }
            postNotice(kind: .success, title: isStarred ? "Paper Starred" : "Paper Unstarred", message: paper.title)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadPaperNotes(for paper: Paper) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            paperNotesByID[paper.id] = try repository.fetchNotes(paperID: paper.id)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func saveNote(paperID: String, noteID: String?, title: String, bodyMarkdown: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBody = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else {
                throw AppModelError.emptyName
            }
            let existing = noteID.flatMap { id in paperNotesByID[paperID, default: []].first { $0.id == id } }
            let now = Date()
            let note = PaperNote(
                id: existing?.id ?? "note-\(UUID().uuidString.lowercased())",
                paperID: paperID,
                anchorID: existing?.anchorID,
                title: trimmedTitle.isEmpty ? "Untitled note" : trimmedTitle,
                bodyMarkdown: trimmedBody,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                deletedAt: nil,
                syncRevision: (existing?.syncRevision ?? 0) + 1
            )
            try repository.upsertNote(note)
            paperNotesByID[paperID] = try repository.fetchNotes(paperID: paperID)
            postNotice(kind: .success, title: existing == nil ? "Note Added" : "Note Updated", message: note.title)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func deleteNote(_ note: PaperNote) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            try repository.deleteNote(id: note.id)
            paperNotesByID[note.paperID] = try repository.fetchNotes(paperID: note.paperID)
            postNotice(kind: .success, title: "Note Deleted", message: note.title)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func openOrUpdateReaderTab(_ paper: Paper) {
        var tabState = readerTabState
        tabState.open(ReaderPaperTab(paper: paper))
        readerTabState = tabState
    }

    private func selectOrOpenReaderTab(_ paper: Paper) {
        var tabState = readerTabState
        if tabState.tabs.contains(where: { $0.paperID == paper.id }) {
            _ = tabState.select(paper.id)
        } else {
            tabState.open(ReaderPaperTab(paper: paper))
        }
        readerTabState = tabState
    }

    private func replaceReaderTab(oldPaperID: String, with paper: Paper) {
        var tabState = readerTabState
        tabState.replace(oldPaperID, with: ReaderPaperTab(paper: paper))
        readerTabState = tabState
    }

    private func loadReaderPositionForSelectedContext(repository: PaperRepository) throws {
        guard let session = selectedSession, let paper = selectedPaper else {
            readerPosition = nil
            return
        }
        readerPosition = try repository.fetchReaderPosition(sessionID: session.id, paperID: paper.id)
    }

    func updateReaderPosition(_ viewportPosition: PDFViewportPosition) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard let session = selectedSession, let paper = selectedPaper else {
                readerPosition = nil
                return
            }
            guard viewportPosition.pageIndex >= 0,
                  viewportPosition.pagePointX.isFinite,
                  viewportPosition.pagePointY.isFinite,
                  viewportPosition.scaleFactor.isFinite,
                  viewportPosition.scaleFactor > 0 else {
                return
            }
            let position = PaperReaderPosition(
                sessionID: session.id,
                paperID: paper.id,
                pageIndex: viewportPosition.pageIndex,
                pagePointX: viewportPosition.pagePointX,
                pagePointY: viewportPosition.pagePointY,
                scaleFactor: viewportPosition.scaleFactor,
                updatedAt: Date()
            )
            try repository.upsertReaderPosition(position)
            readerPosition = position
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func updatePDFDocumentStatus(_ status: PDFDocumentStatus) {
        pdfDocumentStatus = status
    }

    func sendPDFKitCommand(_ kind: PDFKitCommandKind) {
        pdfKitCommand = PDFKitCommand(kind: kind)
    }

    private func paperForReaderTab(_ tab: ReaderPaperTab) throws -> Paper? {
        if selectedPaper?.id == tab.paperID {
            return selectedPaper
        }
        if let paper = papers.first(where: { $0.id == tab.paperID }) {
            return paper
        }
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        return try repository.fetchPapers(ids: [tab.paperID]).first
    }

    private func focusPaperForReader(_ paper: Paper, opensReaderTab: Bool) throws {
        try openPaperSet([paper.id], focusedPaperID: paper.id, opensReaderTabs: opensReaderTab, panelTab: selectedSessionPanelTab)
    }

    private func sessionsForPaperSet(paperIDs: [String], repository: PaperRepository) throws -> [PaperSession] {
        guard let firstPaperID = paperIDs.first else {
            return []
        }
        return try repository.fetchSessions(paperID: firstPaperID).filter { session in
            session.paperIDs.count == paperIDs.count && Set(session.paperIDs) == Set(paperIDs)
        }
    }

    private func reloadSessionsForVisibleContext(repository: PaperRepository) throws {
        let paperIDs = currentReaderPaperIDs()
        sessions = try sessionsForPaperSet(paperIDs: paperIDs, repository: repository)
    }

    private func currentReaderPaperIDs() -> [String] {
        if let selectedSession, !selectedSession.paperIDs.isEmpty {
            return uniqueIDs(selectedSession.paperIDs)
        }
        if let selectedPaper {
            return [selectedPaper.id]
        }
        return []
    }

    private func focusPaperInCurrentReaderSession(_ paper: Paper) throws {
        openOrUpdateReaderTab(paper)
        selectedLibraryPaper = paper
        selectedPaper = paper
        currentSelection = nil
        pdfJumpTarget = nil
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        if let selectedSession, selectedSession.paperIDs.contains(paper.id) {
            try reloadSessionsForVisibleContext(repository: repository)
            try loadReaderPositionForSelectedContext(repository: repository)
            return
        }
        try focusPaperForReader(paper, opensReaderTab: false)
    }

    private func openPaperSet(
        _ paperIDs: [String],
        focusedPaperID: String? = nil,
        opensReaderTabs: Bool,
        panelTab: SessionPanelTab
    ) throws {
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        let uniquePaperIDs = uniqueIDs(paperIDs)
        let paperSet = try repository.fetchPapers(ids: uniquePaperIDs).filter { !$0.isArxivImportPlaceholder }
        guard let firstPaper = paperSet.first else {
            throw AppModelError.noSelectedPaper
        }
        let focusID = focusedPaperID.flatMap { id in
            paperSet.first(where: { $0.id == id })?.id
        } ?? firstPaper.id
        let focusedPaper = paperSet.first(where: { $0.id == focusID }) ?? firstPaper

        selectedSessionPanelTab = panelTab
        selectedLibraryPaper = focusedPaper
        selectedPaper = focusedPaper
        currentSelection = nil
        pdfJumpTarget = nil
        citationReturnPoint = nil
        if opensReaderTabs {
            for paper in paperSet {
                openOrUpdateReaderTab(paper)
            }
        }
        selectOrOpenReaderTab(focusedPaper)

        sessions = try sessionsForPaperSet(paperIDs: paperSet.map(\.id), repository: repository)
        if let latestSession = sessions.last {
            selectedSession = latestSession
            messages = try repository.fetchMessages(sessionID: latestSession.id)
        } else {
            try createSession(paperIDs: paperSet.map(\.id))
        }
        try loadReaderPositionForSelectedContext(repository: repository)
        clearActiveCodexRunIfIdle()
        route = .reader
    }

    func openPaper(_ paper: Paper) {
        do {
            if route == .discover {
                readerReturnRoute = .discover
            } else if route == .library {
                readerReturnRoute = .library
            }
            try openPaperSet([paper.id], focusedPaperID: paper.id, opensReaderTabs: true, panelTab: .chat)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func openPapersForReading(_ paperIDs: [String]) {
        do {
            readerReturnRoute = .library
            try openPaperSet(paperIDs, opensReaderTabs: true, panelTab: .chat)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func openPapersForChat(_ paperIDs: [String]) {
        do {
            readerReturnRoute = .library
            try openPaperSet(paperIDs, opensReaderTabs: true, panelTab: .chat)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func openRecentSession(_ session: PaperSession) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard let storedSession = try repository.fetchSession(id: session.id) else {
                refreshRecentSessions()
                return
            }
            let paperSet = try repository.fetchPapers(ids: storedSession.paperIDs).filter { !$0.isArxivImportPlaceholder }
            guard let firstPaper = paperSet.first else {
                throw AppModelError.noSelectedPaper
            }
            readerReturnRoute = .library
            selectedSessionPanelTab = .chat
            for paper in paperSet {
                openOrUpdateReaderTab(paper)
            }
            selectOrOpenReaderTab(firstPaper)
            selectedLibraryPaper = firstPaper
            selectedPaper = firstPaper
            selectedSession = storedSession
            sessions = try sessionsForPaperSet(paperIDs: storedSession.paperIDs, repository: repository)
            messages = try repository.fetchMessages(sessionID: storedSession.id)
            currentSelection = nil
            pdfJumpTarget = nil
            citationReturnPoint = nil
            try loadReaderPositionForSelectedContext(repository: repository)
            route = .reader
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectReaderTab(_ tab: ReaderPaperTab) {
        do {
            guard let paper = try paperForReaderTab(tab) else {
                closeReaderTab(tab)
                return
            }
            if selectedSession?.paperIDs.contains(paper.id) == true {
                try focusPaperInCurrentReaderSession(paper)
            } else {
                try focusPaperForReader(paper, opensReaderTab: false)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func closeReaderTab(_ tab: ReaderPaperTab) {
        do {
            let wasActive = readerTabState.activePaperID == tab.paperID
            var tabState = readerTabState
            let nextPaperID = tabState.close(tab.paperID)
            readerTabState = tabState

            guard wasActive else {
                return
            }
            guard let nextPaperID,
                  let nextTab = readerTabState.tabs.first(where: { $0.paperID == nextPaperID }),
                  let paper = try paperForReaderTab(nextTab) else {
                selectedPaper = nil
                selectedSession = nil
                sessions = []
                messages = []
                currentSelection = nil
                pdfJumpTarget = nil
                readerPosition = nil
                clearActiveCodexRunIfIdle()
                route = .library
                return
            }
            if selectedSession?.paperIDs.contains(paper.id) == true {
                try focusPaperInCurrentReaderSession(paper)
            } else {
                try focusPaperForReader(paper, opensReaderTab: false)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func createSession(paperIDs requestedPaperIDs: [String]? = nil) throws {
        guard let fallbackPaper = selectedPaper else {
            throw AppModelError.noSelectedPaper
        }
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        let sessionPaperIDs = uniqueIDs(requestedPaperIDs ?? [fallbackPaper.id])
        let sessionPapers = try repository.fetchPapers(ids: sessionPaperIDs)
        guard !sessionPapers.isEmpty else {
            throw AppModelError.noSelectedPaper
        }
        let now = Date()
        let sessionID = UUID().uuidString.lowercased()
        let workspacePath = supportRoot.appendingPathComponent("sessions/\(sessionID)", isDirectory: true).path
        let session = PaperSession(
            id: sessionID,
            title: sessionTitle(for: sessionPapers),
            paperIDs: sessionPaperIDs,
            codexSessionID: nil,
            workspacePath: workspacePath,
            createdAt: now,
            updatedAt: now
        )
        try repository.upsertSession(session)
        let context = try loadSessionPaperContext(session: session, fallbackPaper: fallbackPaper, repository: repository)
        try workspaceManager.writeWorkspace(
            session: session,
            papers: context.papers,
            pagesByPaperID: context.pagesByPaperID,
            spansByPaperID: context.spansByPaperID,
            anchorsByPaperID: context.anchorsByPaperID
        )
        sessions = try sessionsForPaperSet(paperIDs: sessionPaperIDs, repository: repository)
        selectedSession = session
        messages = []
        readerPosition = nil
        try refreshRecentSessions(repository: repository)
        clearActiveCodexRunIfIdle()
    }

    func newSessionButtonTapped() {
        do {
            try createSession(paperIDs: currentReaderPaperIDs())
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func renameSession(_ session: PaperSession, title: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppModelError.emptyName
            }
            var updated = session
            updated.title = trimmed
            updated.updatedAt = Date()
            try repository.upsertSession(updated)
            if selectedSession?.id == session.id {
                selectedSession = updated
            }
            try reloadSessionsForVisibleContext(repository: repository)
            try refreshRecentSessions(repository: repository)
            postNotice(kind: .success, title: "Session Renamed", message: trimmed)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func startFreshSessionFromCurrentPaperSet() {
        do {
            try createSession(paperIDs: currentReaderPaperIDs())
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectSession(_ sessionID: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard let session = sessions.first(where: { $0.id == sessionID }) else {
                return
            }
            selectedSession = session
            messages = try repository.fetchMessages(sessionID: session.id)
            if let selectedPaper, !session.paperIDs.contains(selectedPaper.id),
               let firstPaper = try repository.fetchPapers(ids: session.paperIDs).first {
                try focusPaperInCurrentReaderSession(firstPaper)
            }
            try loadReaderPositionForSelectedContext(repository: repository)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectReaderPaper(_ paper: Paper) {
        do {
            try focusPaperInCurrentReaderSession(paper)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setPaper(_ paper: Paper, includedInCurrentSession included: Bool) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if included {
                try addPaperToCurrentSession(paper, repository: repository)
            } else if selectedPaper?.id == paper.id {
                try removePaperFromCurrentSession(paper.id, repository: repository)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func addPaperToCurrentSession(_ paper: Paper) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            try addPaperToCurrentSession(paper, repository: repository)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func addPaperToCurrentSession(_ paper: Paper, repository: PaperRepository) throws {
        guard var session = selectedSession else {
            try openPaperSet([paper.id], focusedPaperID: paper.id, opensReaderTabs: true, panelTab: selectedSessionPanelTab)
            return
        }
        guard !paper.isArxivImportPlaceholder else {
            return
        }
        var paperIDs = uniqueIDs(session.paperIDs)
        guard !paperIDs.contains(paper.id) else {
            try focusPaperInCurrentReaderSession(paper)
            return
        }
        paperIDs.append(paper.id)
        session.paperIDs = paperIDs
        session.updatedAt = Date()
        try repository.upsertSession(session)
        let context = try loadSessionPaperContext(session: session, fallbackPaper: paper, repository: repository)
        try workspaceManager.writeWorkspace(
            session: session,
            papers: context.papers,
            pagesByPaperID: context.pagesByPaperID,
            spansByPaperID: context.spansByPaperID,
            anchorsByPaperID: context.anchorsByPaperID
        )
        openOrUpdateReaderTab(paper)
        selectedSession = session
        selectedPaper = paper
        selectedLibraryPaper = paper
        sessions = try sessionsForPaperSet(paperIDs: paperIDs, repository: repository)
        messages = try repository.fetchMessages(sessionID: session.id)
        try loadReaderPositionForSelectedContext(repository: repository)
        try refreshRecentSessions(repository: repository)
        postNotice(kind: .success, title: "Paper Added", message: paper.title)
    }

    func removePaperFromCurrentSession(_ paperID: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            try removePaperFromCurrentSession(paperID, repository: repository)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func removePaperFromCurrentSession(_ paperID: String, repository: PaperRepository) throws {
        guard var session = selectedSession else {
            return
        }
        let nextPaperIDs = session.paperIDs.filter { $0 != paperID }
        guard nextPaperIDs.count != session.paperIDs.count else {
            return
        }
        guard let fallbackPaper = selectedPaper else {
            throw AppModelError.noSelectedPaper
        }
        if nextPaperIDs.isEmpty {
            throw AppModelError.noSelectedPaper
        }
        session.paperIDs = nextPaperIDs
        session.updatedAt = Date()
        try repository.upsertSession(session)
        let nextPapers = try repository.fetchPapers(ids: nextPaperIDs)
        let nextFocusedPaper = selectedPaper?.id == paperID ? (nextPapers.first ?? fallbackPaper) : fallbackPaper
        let context = try loadSessionPaperContext(session: session, fallbackPaper: nextFocusedPaper, repository: repository)
        try workspaceManager.writeWorkspace(
            session: session,
            papers: context.papers,
            pagesByPaperID: context.pagesByPaperID,
            spansByPaperID: context.spansByPaperID,
            anchorsByPaperID: context.anchorsByPaperID
        )
        var tabState = readerTabState
        _ = tabState.close(paperID)
        readerTabState = tabState
        selectedSession = session
        sessions = try sessionsForPaperSet(paperIDs: nextPaperIDs, repository: repository)
        messages = try repository.fetchMessages(sessionID: session.id)
        try focusPaperInCurrentReaderSession(nextFocusedPaper)
        try refreshRecentSessions(repository: repository)
        postNotice(kind: .success, title: "Paper Removed", message: nextFocusedPaper.title)
    }

    private func sessionTitle(for papers: [Paper]) -> String {
        guard let firstPaper = papers.first else {
            return "Paper Notes"
        }
        guard papers.count > 1 else {
            return "\(firstPaper.title) Notes"
        }
        return "\(firstPaper.title) + \(papers.count - 1) Notes"
    }

    func updateSelection(_ selection: PDFSelectionInfo?) {
        currentSelection = selection
    }

    func clearCurrentSelection() {
        currentSelection = nil
    }

    func refreshCodexDiagnostic() async {
        codexDiagnostic = nil
        codexDefaultModelID = CodexCLI.configuredDefaultModelID() ?? ""
        let modelOverride = codexModelOverride
        let diagnostic = await Task.detached(priority: .utility) {
            CodexCLI.diagnose(modelOverride: modelOverride)
        }.value
        codexDiagnostic = diagnostic
    }

    func refreshAvailableCodexModels() async {
        guard !isRefreshingCodexModels else {
            return
        }
        isRefreshingCodexModels = true
        defer {
            isRefreshingCodexModels = false
        }
        do {
            let result = try await Task.detached(priority: .utility) {
                let defaultModelID = CodexCLI.configuredDefaultModelID()
                let executable = try CodexCLI.findCodexExecutable()
                let models = try CodexCLI(executablePath: executable).availableModelIDs()
                return (models: models, defaultModelID: defaultModelID)
            }.value
            codexDefaultModelID = result.defaultModelID ?? ""
            availableCodexModelIDs = uniqueCodexModelIDs(
                result.models + [codexModelOverride, discoverCodexModelOverride]
            )
        } catch {
            codexDefaultModelID = CodexCLI.configuredDefaultModelID() ?? ""
            mergeAvailableCodexModelIDs([codexModelOverride, discoverCodexModelOverride])
            errorMessage = String(describing: error)
        }
    }

    func setCodexModelOverride(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        codexModelOverride = trimmed
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: codexModelOverrideDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: codexModelOverrideDefaultsKey)
        }
        Task {
            await refreshCodexDiagnostic()
        }
        mergeAvailableCodexModelIDs([trimmed])
    }

    func setCodexReasoningEffort(_ effort: CodexReasoningEffort) {
        codexReasoningEffort = effort
        if effort == .default {
            UserDefaults.standard.removeObject(forKey: codexReasoningEffortDefaultsKey)
        } else {
            UserDefaults.standard.set(effort.rawValue, forKey: codexReasoningEffortDefaultsKey)
        }
    }

    func cancelActiveCodexRun() {
        let targetSessionID = selectedSession?.id ?? activeCodexRunsBySessionID.values.sorted { $0.startedAt < $1.startedAt }.first?.sessionID
        guard let targetSessionID,
              let run = activeCodexRunsBySessionID[targetSessionID] else {
            return
        }
        cancellingCodexRunSessionIDs.insert(targetSessionID)
        activeCodexRunHandlesBySessionID[targetSessionID]?.cancel()
        postNotice(kind: .info, title: "Stopping Codex", message: run.title)
    }

    func jumpToCitation(_ citationID: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if let selectedPaper, let readerPosition {
                citationReturnPoint = CitationReturnPoint(
                    paperID: selectedPaper.id,
                    paperTitle: selectedPaper.title,
                    position: readerPosition,
                    label: "Before citation jump"
                )
            }
            if let span = try repository.fetchSpan(id: citationID) {
                if selectedPaper?.id != span.paperID, let paper = papers.first(where: { $0.id == span.paperID }) {
                    try focusPaperInCurrentReaderSession(paper)
                }
                pdfJumpTarget = PDFJumpTarget(
                    id: span.id,
                    paperID: span.paperID,
                    page: span.page,
                    bboxList: [span.bbox],
                    label: span.text
                )
                return
            }
            if let baseSpanID = CitationParser.baseSpanCitationID(for: citationID),
               baseSpanID != citationID,
               let span = try repository.fetchSpan(id: baseSpanID) {
                if selectedPaper?.id != span.paperID, let paper = papers.first(where: { $0.id == span.paperID }) {
                    try focusPaperInCurrentReaderSession(paper)
                }
                pdfJumpTarget = PDFJumpTarget(
                    id: citationID,
                    paperID: span.paperID,
                    page: span.page,
                    bboxList: [span.bbox],
                    label: span.text
                )
                return
            }
            if let anchor = try repository.fetchAnchor(id: citationID) {
                if selectedPaper?.id != anchor.paperID, let paper = papers.first(where: { $0.id == anchor.paperID }) {
                    try focusPaperInCurrentReaderSession(paper)
                }
                pdfJumpTarget = PDFJumpTarget(
                    id: anchor.id,
                    paperID: anchor.paperID,
                    page: anchor.page,
                    bboxList: anchor.bboxList,
                    label: anchor.selectedText
                )
                return
            }
            throw AppModelError.sourceNotFound(citationID)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func returnFromCitationJump() {
        do {
            guard let returnPoint = citationReturnPoint else {
                return
            }
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            if selectedPaper?.id != returnPoint.paperID,
               let paper = try repository.fetchPapers(ids: [returnPoint.paperID]).first {
                try focusPaperInCurrentReaderSession(paper)
            }
            var position = returnPoint.position
            position.updatedAt = Date()
            readerPosition = position
            sendPDFKitCommand(.restorePosition(position))
            pdfJumpTarget = nil
            citationReturnPoint = nil
            postNotice(kind: .info, title: "Returned to Previous Reading Position", message: returnPoint.paperTitle)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        var runSessionID: String?
        defer {
            if let runSessionID {
                finishCodexRun(sessionID: runSessionID)
            }
        }

        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard let paper = selectedPaper else {
                throw AppModelError.noSelectedPaper
            }
            guard var session = selectedSession else {
                throw AppModelError.noSelectedSession
            }
            guard session.paperIDs.contains(paper.id) else {
                throw AppModelError.sessionPaperMismatch
            }
            let sessionID = session.id
            guard !isSessionSending(sessionID) else {
                return
            }
            runSessionID = sessionID

            let context = try loadSessionPaperContext(session: session, fallbackPaper: paper, repository: repository)
            let focusedSpans = context.spansByPaperID[paper.id] ?? []
            var content = trimmed
            if let selection = currentSelection {
                let anchorID = PaperCodexCore.Anchor.makeID(paperID: paper.id, page: selection.page, suffix: UUID().uuidString.lowercased())
                guard let anchor = AnchorResolver().resolve(
                    paperID: paper.id,
                    page: selection.page,
                    selectedText: selection.text,
                    bboxList: selection.bboxList,
                    spans: focusedSpans,
                    anchorID: anchorID,
                    sessionID: session.id,
                    createdAt: Date()
                ) else {
                    throw AppModelError.anchorMatchFailed
                }
                let nearbySpans = anchor.matchedSpanIDs.isEmpty ? "none" : anchor.matchedSpanIDs.joined(separator: ", ")
                let beforeContext = anchor.beforeContext.isEmpty ? "none" : anchor.beforeContext
                let afterContext = anchor.afterContext.isEmpty ? "none" : anchor.afterContext
                content += """

                [selected source]
                anchor_id: \(anchor.id)
                paper_id: \(anchor.paperID)
                page: \(anchor.page)
                text: "\(anchor.selectedText)"
                nearby_spans: \(nearbySpans)
                before: "\(beforeContext)"
                after: "\(afterContext)"
                """
                try repository.upsertAnchor(anchor)
                currentSelection = nil
            }

            let message = ChatMessage(
                id: UUID().uuidString.lowercased(),
                sessionID: session.id,
                role: .user,
                content: content,
                createdAt: Date()
            )
            try repository.appendMessage(message)
            session.updatedAt = Date()
            try repository.upsertSession(session)
            try refreshVisibleSessionState(session: session, paperID: paper.id, repository: repository)
            try refreshRecentSessions(repository: repository)

            let updatedSession = try await runCodexTurn(
                content: content,
                session: session,
                fallbackPaper: paper,
                repository: repository
            )
            try refreshVisibleSessionState(session: updatedSession, paperID: paper.id, repository: repository)
            try refreshRecentSessions(repository: repository)
        } catch AppModelError.anchorMatchFailed {
            errorMessage = AppModelError.anchorMatchFailed.description
        } catch {
            if let runSessionID, cancellingCodexRunSessionIDs.contains(runSessionID) {
                await appendCodexCancellationMessage(sessionID: runSessionID)
                return
            }
            if let runSessionID {
                await appendCodexFailureMessage(String(describing: error), sessionID: runSessionID)
            } else {
                errorMessage = String(describing: error)
            }
        }
    }

    func retryCodexFailure(messageID: String) async {
        var runSessionID: String?
        defer {
            if let runSessionID {
                finishCodexRun(sessionID: runSessionID)
            }
        }

        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard let session = selectedSession else {
                throw AppModelError.noSelectedSession
            }
            let sessionID = session.id
            guard !isSessionSending(sessionID) else {
                return
            }
            runSessionID = sessionID
            guard let failureIndex = messages.firstIndex(where: { $0.id == messageID }),
                  CodexFailureNotice.parse(messages[failureIndex].content) != nil else {
                throw AppModelError.noRecoverableCodexTurn
            }
            guard let userMessage = messages[..<failureIndex].last(where: { $0.role == .user }) else {
                throw AppModelError.noRecoverableCodexTurn
            }

            let fallbackPaper = try fallbackPaper(for: session, repository: repository)
            let updatedSession = try await runCodexTurn(
                content: userMessage.content,
                session: session,
                fallbackPaper: fallbackPaper,
                repository: repository
            )
            try refreshVisibleSessionState(session: updatedSession, paperID: fallbackPaper.id, repository: repository)
            try refreshRecentSessions(repository: repository)
        } catch {
            if let runSessionID, cancellingCodexRunSessionIDs.contains(runSessionID) {
                await appendCodexCancellationMessage(sessionID: runSessionID)
                return
            }
            if let runSessionID {
                await appendCodexFailureMessage(String(describing: error), sessionID: runSessionID)
            } else {
                errorMessage = String(describing: error)
            }
        }
    }

    func goToLibrary() {
        route = .library
        clearReaderContext()
    }

    func returnFromReader() {
        let destination = readerReturnRoute
        clearReaderContext()
        switch destination {
        case .discover:
            route = .discover
        case .library, .settings, .reader:
            route = .library
        }
    }

    private func clearReaderContext() {
        selectedPaper = nil
        selectedSession = nil
        sessions = []
        messages = []
        currentSelection = nil
        pdfJumpTarget = nil
        readerPosition = nil
        citationReturnPoint = nil
        pdfDocumentStatus = nil
        clearActiveCodexRunIfIdle()
    }

    private func clearActiveCodexRunIfIdle() {
        if !isSending {
            activeCodexRunsBySessionID.removeAll()
            activeCodexRunHandlesBySessionID.removeAll()
            cancellingCodexRunSessionIDs.removeAll()
        }
    }

    private func refreshVisibleSessionState(
        session: PaperSession,
        paperID: String,
        repository: PaperRepository
    ) throws {
        if selectedPaper?.id == paperID {
            sessions = try sessionsForPaperSet(paperIDs: session.paperIDs, repository: repository)
        }
        guard selectedSession?.id == session.id else {
            return
        }
        selectedSession = session
        messages = try repository.fetchMessages(sessionID: session.id)
    }

    private func loadSessionPaperContext(
        session: PaperSession,
        fallbackPaper: Paper,
        repository: PaperRepository
    ) throws -> SessionPaperContext {
        let paperIDs = session.paperIDs.isEmpty ? [fallbackPaper.id] : uniqueIDs(session.paperIDs)
        let fetchedPapers = try repository.fetchPapers(ids: paperIDs)
        let papers = fetchedPapers.isEmpty ? [fallbackPaper] : fetchedPapers
        var pagesByPaperID: [String: [PageIndex]] = [:]
        var spansByPaperID: [String: [Span]] = [:]
        var anchorsByPaperID: [String: [PaperCodexCore.Anchor]] = [:]
        for paper in papers {
            pagesByPaperID[paper.id] = try repository.fetchPages(paperID: paper.id)
            spansByPaperID[paper.id] = try repository.fetchSpans(paperID: paper.id)
            anchorsByPaperID[paper.id] = try repository.fetchAnchors(paperID: paper.id)
        }
        return SessionPaperContext(
            papers: papers,
            pagesByPaperID: pagesByPaperID,
            spansByPaperID: spansByPaperID,
            anchorsByPaperID: anchorsByPaperID
        )
    }

    private func anchorsReferenced(in content: String, context: SessionPaperContext) -> [PaperCodexCore.Anchor] {
        let allAnchors = context.anchorsByPaperID.values.flatMap { $0 }
        let anchorIDs = content
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("anchor_id:") else {
                    return nil
                }
                return trimmed
                    .dropFirst("anchor_id:".count)
                    .trimmingCharacters(in: .whitespaces)
            }
        return anchorIDs.compactMap { anchorID in
            allAnchors.first { $0.id == anchorID }
        }
    }

    private func uniqueIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    private func mergeAvailableCodexModelIDs(_ ids: [String]) {
        availableCodexModelIDs = uniqueCodexModelIDs(availableCodexModelIDs + ids)
    }

    private func uniqueCodexModelIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private func mergeAndSaveArxivDate(_ date: String) throws {
        let merged = Array(Set(arxivDates + [date])).sorted()
        arxivDates = merged
        try arxivCache.saveDates(ArxivFeedDateIndex(dates: merged, latest: merged.last))
    }

    private func cacheAndDisplayArxivFeed(_ liveFeed: ArxivFeedResponse, title: String) throws {
        let feed = applyLocalDiscoverPreferences(to: liveFeed)
        try arxivCache.saveFeed(feed)
        try mergeAndSaveArxivDate(feed.date)
        selectedArxivDate = feed.date
        arxivFeed = feed
        let summary = try arxivCache.assetCacheSummary(for: feed, includeLarge: false)
        arxivCacheProgress = ArxivCacheProgress(
            date: feed.date,
            title: title,
            detail: "Preview images \(summary.cached)/\(summary.total)",
            completed: summary.cached,
            total: summary.total
        )
        if let selected = selectedArxivPaper,
           feed.papers.contains(where: { $0.id == selected.id }) {
            selectedArxivPaper = selected
        } else {
            selectedArxivPaper = feed.papers.first
        }
        reloadCachedArxivAssets()
    }

    private func displayDiscoverFeed(
        _ liveFeed: ArxivFeedResponse,
        query: DiscoverQuery,
        progressTitle: String,
        cacheRangeFeed: Bool = true
    ) throws {
        let feed = applyLocalDiscoverPreferences(to: liveFeed)
        if cacheRangeFeed {
            try arxivCache.saveFeed(feed)
        }
        try mergeAndSaveArxivDate(feed.date)
        try localDiscoverCache.saveQueryResult(
            DiscoverQueryResult(query: query.normalized, arxivIDs: feed.papers.map(\.id), generatedAt: Date())
        )
        selectedArxivDate = feed.date
        arxivFeed = feed
        discoverResultIDs = feed.papers.map(\.id)
        selectedArxivPaper = feed.papers.first
        try loadDiscoverEnrichments(for: feed.papers)
        arxivCacheProgress = ArxivCacheProgress(
            date: feed.date,
            title: progressTitle,
            detail: "\(feed.papers.count) papers",
            completed: feed.papers.count,
            total: feed.papers.count
        )
        reloadCachedArxivAssets()
    }

    private func resetDiscoverRanking(in feed: ArxivFeedResponse) -> ArxivFeedResponse {
        let papers = feed.papers.map { paper -> ArxivFeedPaper in
            var resetPaper = paper
            resetPaper.similarity = nil
            resetPaper.filterGroup = nil
            return resetPaper
        }
        return ArxivFeedResponse(
            date: feed.date,
            count: papers.count,
            papers: papers,
            groups: feed.groups,
            tagOptions: feed.tagOptions
        )
    }

    private func filterDiscoverFeed(_ feed: ArxivFeedResponse, keyword: String) -> ArxivFeedResponse {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return feed
        }
        let terms = query.lowercased().split(separator: " ").map(String.init)
        let papers = feed.papers.filter { paper in
            let haystack = [
                paper.id,
                paper.title.en,
                paper.title.zh,
                paper.abstract.en,
                paper.abstract.zh,
                paper.summary.en,
                paper.summary.zh,
                paper.authors.joined(separator: " "),
                paper.categories.joined(separator: " "),
                paper.listCategories.joined(separator: " "),
                paper.tags.joined(separator: " ")
            ]
                .joined(separator: " ")
                .lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
        return ArxivFeedResponse(
            date: feed.date,
            count: papers.count,
            papers: papers,
            groups: feed.groups,
            tagOptions: feed.tagOptions
        )
    }

    @discardableResult
    private func loadCachedDiscoverSearch() throws -> Bool {
        let range = try DiscoverDateRange(start: discoverStartDate, end: discoverEndDate)
        let categories = discoverSelectedCategories.isEmpty ? [localDiscoverPreferences.normalized.categories.first ?? "cs.CV"] : discoverSelectedCategories
        let similaritySourceIDs = effectiveDiscoverSimilaritySourceIDs()
        let query = DiscoverQuery(
            keyword: discoverKeyword,
            dateRange: range,
            categories: categories,
            similaritySourceIDs: similaritySourceIDs,
            rankingVersion: discoverRankingVersion()
        ).normalized
        guard let cachedFeed = try arxivCache.loadFeed(date: "\(range.start)...\(range.end)") else {
            return false
        }
        let filteredFeed = filterDiscoverFeed(cachedFeed, keyword: query.keyword)
        try displayDiscoverFeed(filteredFeed, query: query, progressTitle: "Cached search", cacheRangeFeed: false)
        return true
    }

    private func loadDiscoverEnrichments(for papers: [ArxivFeedPaper]) throws {
        var enrichments = discoverEnrichmentsByID
        for paper in papers {
            if let enrichment = try localDiscoverCache.loadEnrichment(arxivID: paper.id) {
                enrichments[paper.id] = enrichment
            }
        }
        discoverEnrichmentsByID = enrichments.filter { entry in
            papers.contains { $0.id == entry.key }
        }
    }

    private func updateDiscoverProcessingProgress(
        completed: Int,
        cached: Int,
        failed: Int,
        total: Int,
        tokenUsage: CodexTokenUsage? = nil
    ) {
        let processed = max(completed - cached - failed, 0)
        var detail = "\(processed) processed · \(cached) cached · \(failed) failed · \(completed)/\(total)"
        if let tokenUsage {
            detail += " · \(tokenUsage.compactSummary)"
        }
        discoverProcessingProgress = ArxivCacheProgress(
            date: selectedArxivDate ?? "\(discoverStartDate)...\(discoverEndDate)",
            title: isCancellingDiscoverProcessing ? "Stopping processing" : "Processing results",
            detail: detail,
            completed: completed,
            total: total
        )
    }

    private func updateDiscoverPDFCacheProgress(completed: Int, cached: Int, failed: Int, total: Int) {
        let downloaded = max(completed - cached - failed, 0)
        discoverPDFCacheProgress = ArxivCacheProgress(
            date: selectedArxivDate ?? "\(discoverStartDate)...\(discoverEndDate)",
            title: isCancellingDiscoverPDFCache ? "Stopping PDF cache" : "Caching PDFs",
            detail: "\(downloaded) downloaded · \(cached) already cached · \(failed) failed · \(completed)/\(total)",
            completed: completed,
            total: total
        )
    }

    private func uniqueArxivPapers(_ papers: [ArxivFeedPaper]) -> [ArxivFeedPaper] {
        var seen: Set<String> = []
        var result: [ArxivFeedPaper] = []
        for paper in papers where !seen.contains(paper.id) {
            seen.insert(paper.id)
            result.append(paper)
        }
        return result
    }

    private func cachedArxivPDFURL(for paper: ArxivFeedPaper) throws -> URL? {
        if let url = try arxivCache.cachedPDFURL(arxivID: paper.id, date: arxivPDFCacheDate(for: paper)) {
            return url
        }
        return try arxivCache.cachedPDFURL(arxivID: paper.id)
    }

    private func arxivPDFCacheDate(for paper: ArxivFeedPaper) -> String {
        paper.listDate ?? selectedArxivDate ?? arxivFeed?.date ?? latestCompleteArxivSubmissionISODate()
    }

    private func ensureArxivPDFCached(_ paper: ArxivFeedPaper, client: LocalArxivClient? = nil) async throws -> URL {
        if let cachedURL = try cachedArxivPDFURL(for: paper) {
            return cachedURL
        }
        let data = try await (client ?? makeLocalArxivClient()).fetchPDF(for: paper)
        guard data.starts(with: Data("%PDF-".utf8)) else {
            throw AppModelError.downloadedFileIsNotPDF(paper.id)
        }
        return try arxivCache.savePDF(data, arxivID: paper.id, date: arxivPDFCacheDate(for: paper))
    }

    @discardableResult
    private func refreshDiscoverPDFThumbnails(for paper: ArxivFeedPaper, pdfURL: URL) throws -> [URL] {
        let urls = try thumbnailCache.thumbnails(
            forPDFAt: pdfURL,
            cacheID: "arxiv-\(paper.id)",
            pageLimit: 5,
            size: CGSize(width: 164, height: 212)
        )
        arxivPDFThumbnailURLsByID[paper.id] = urls
        return urls
    }

    @discardableResult
    private func loadCachedArxivFeed(date: String) throws -> Bool {
        guard let cachedFeed = try arxivCache.loadFeed(date: date) else {
            return false
        }
        selectedArxivDate = date
        let feed = applyLocalDiscoverPreferences(to: cachedFeed)
        arxivFeed = feed
        if let selected = selectedArxivPaper,
           feed.papers.contains(where: { $0.id == selected.id }) {
            selectedArxivPaper = selected
        } else {
            selectedArxivPaper = feed.papers.first
        }
        reloadCachedArxivAssets()
        let summary = try arxivCache.assetCacheSummary(for: feed, includeLarge: false)
        arxivCacheProgress = ArxivCacheProgress(
            date: date,
            title: "Offline cache",
            detail: "Preview images \(summary.cached)/\(summary.total)",
            completed: summary.cached,
            total: summary.total
        )
        return true
    }

    private func preloadArxivAssets(includeLarge: Bool, feed: ArxivFeedResponse) async throws {
        let assets = feed.uniqueAssets(includeLarge: includeLarge)
        guard !assets.isEmpty else {
            arxivCacheProgress = ArxivCacheProgress(
                date: feed.date,
                title: includeLarge ? "Full images ready" : "Preview images ready",
                detail: "No preview assets in this feed",
                completed: 0,
                total: 0
            )
            return
        }

        isPreloadingArxivAssets = true
        defer {
            isPreloadingArxivAssets = false
        }

        var cachedPaths: Set<String> = []
        for asset in assets where try arxivCache.cachedAssetURL(path: asset.path) != nil {
            cachedPaths.insert(asset.path)
        }
        var completed = cachedPaths.count
        arxivCacheProgress = ArxivCacheProgress(
            date: feed.date,
            title: includeLarge ? "Caching full images" : "Caching preview images",
            detail: "\(completed)/\(assets.count) already cached",
            completed: completed,
            total: assets.count
        )

        for asset in assets {
            if cachedPaths.contains(asset.path) {
                continue
            }
            let data = try await fetchArxivAsset(asset)
            arxivAssetURLs[asset.path] = try arxivCache.saveAsset(data, path: asset.path)
            completed += 1
            arxivCacheProgress = ArxivCacheProgress(
                date: feed.date,
                title: includeLarge ? "Caching full images" : "Caching preview images",
                detail: "\(completed)/\(assets.count) cached",
                completed: completed,
                total: assets.count
            )
        }

        reloadCachedArxivAssets()
        arxivCacheProgress = ArxivCacheProgress(
            date: feed.date,
            title: includeLarge ? "Full images ready" : "Preview images ready",
            detail: "\(completed)/\(assets.count) cached",
            completed: completed,
            total: assets.count
        )
    }

    private func loadCachedArxivState() {
        if let cachedDates = try? arxivCache.loadDates() {
            arxivDates = cachedDates.dates
            selectedArxivDate = cachedDates.latest ?? cachedDates.dates.last
        }
        if let date = selectedArxivDate {
            _ = try? loadCachedArxivFeed(date: date)
        }
    }

    private func reloadCachedArxivAssets() {
        guard let arxivFeed else {
            return
        }
        var urls = arxivAssetURLs
        for paper in arxivFeed.papers {
            for asset in [paper.assets.small, paper.assets.large].compactMap({ $0 }) {
                if let url = try? arxivCache.cachedAssetURL(path: asset.path) {
                    urls[asset.path] = url
                }
            }
        }
        arxivAssetURLs = urls
        reloadCachedArxivPDFThumbnails()
    }

    private func reloadCachedArxivPDFThumbnails() {
        guard let arxivFeed else {
            arxivPDFThumbnailURLsByID = [:]
            return
        }
        var urlsByID = arxivPDFThumbnailURLsByID
        let visibleIDs = Set(arxivFeed.papers.map(\.id))
        for paper in arxivFeed.papers where urlsByID[paper.id]?.isEmpty != false {
            guard let pdfURL = try? cachedArxivPDFURL(for: paper),
                  let urls = try? thumbnailCache.thumbnails(
                    forPDFAt: pdfURL,
                    cacheID: "arxiv-\(paper.id)",
                    pageLimit: 5,
                    size: CGSize(width: 164, height: 212)
                  ),
                  !urls.isEmpty else {
                continue
            }
            urlsByID[paper.id] = urls
        }
        arxivPDFThumbnailURLsByID = urlsByID.filter { visibleIDs.contains($0.key) }
    }

    private func importArxivPaper(_ arxivPaper: ArxivFeedPaper, isSaved: Bool) async throws -> Paper {
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        isAddingArxivPaper = true
        arxivDownloadingPaperIDs.insert(arxivPaper.id)
        arxivDownloadProgressByID[arxivPaper.id] = 0.1
        defer {
            isAddingArxivPaper = false
            arxivDownloadingPaperIDs.remove(arxivPaper.id)
            arxivDownloadProgressByID.removeValue(forKey: arxivPaper.id)
        }

        let client = makeLocalArxivClient()
        let pdfURL = try await ensureArxivPDFCached(arxivPaper, client: client)
        arxivDownloadProgressByID[arxivPaper.id] = 0.65
        _ = try refreshDiscoverPDFThumbnails(for: arxivPaper, pdfURL: pdfURL)

        let metadata = PaperImportMetadata(
            title: arxivPaper.displayTitle(language: globalLanguageMode.metadataLanguageCode),
            authors: arxivPaper.authors,
            year: arxivPaper.publishedYear,
            sourceURL: arxivPaper.links.abs
        )
        let result = try PaperLibraryImporter(repository: repository, supportRoot: supportRoot)
            .importPDF(
                from: pdfURL,
                metadata: metadata,
                isSaved: isSaved,
                storageSubpath: isSaved ? arxivStorageSubpath(for: arxivPaper) : nil
            )
        arxivDownloadProgressByID[arxivPaper.id] = 1
        return result.paper
    }

    private func refreshLibraryThumbnails() {
        var urlsByID = paperThumbnailURLsByID
        for paper in papers where urlsByID[paper.id] == nil {
            if let urls = try? thumbnailCache.thumbnails(for: paper) {
                urlsByID[paper.id] = urls
            }
        }
        paperThumbnailURLsByID = urlsByID.filter { entry in
            papers.contains { $0.id == entry.key }
        }
    }

    private func ensureCategory(named name: String, repository: PaperRepository) throws -> PaperCodexCore.Category {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppModelError.emptyName
        }
        let existingCategories = try repository.fetchCategories()
        if let existing = existingCategories.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let category = PaperCodexCore.Category(
            id: makeManualID(prefix: "cat", name: trimmed),
            parentID: nil,
            name: trimmed,
            sortOrder: (existingCategories.map(\.sortOrder).max() ?? 0) + 1
        )
        try repository.upsertCategory(category)
        includeCategoryInSimilarityDefaults(category.id)
        return category
    }

    private func assignCategories(
        categoryIDs: [String],
        newCategoryNames: [String],
        to paper: Paper,
        repository: PaperRepository
    ) throws {
        let existingCategoryIDs = Set(try repository.fetchCategories().map(\.id))
        for categoryID in normalizedIdentifiers(categoryIDs) where existingCategoryIDs.contains(categoryID) {
            try repository.assignPaper(paper.id, toCategory: categoryID)
        }
        for categoryName in normalizedNames(newCategoryNames) {
            let category = try ensureCategory(named: categoryName, repository: repository)
            try repository.assignPaper(paper.id, toCategory: category.id)
        }
    }

    private func normalizedIdentifiers(_ values: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private func normalizedNames(_ values: [String]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
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
            names.append(trimmed)
        }
        return names
    }

    private func arxivStorageSubpath(for paper: ArxivFeedPaper) -> String? {
        switch arxivSaveOrganization {
        case .primaryCategory:
            return paper.primaryCategory ?? paper.categories.first ?? "arxiv"
        case .firstTag:
            return paper.tags.first ?? paper.primaryCategory ?? "arxiv"
        case .date:
            return paper.listDate ?? selectedArxivDate ?? "arxiv"
        case .flat:
            return nil
        }
    }

    private func arxivStorageSubpath(forCachedPaper paper: Paper) -> String? {
        guard arxivSaveOrganization != .flat else {
            return nil
        }
        if let arxivPaper = arxivFeed?.papers.first(where: { candidate in
            paper.sourceURL == candidate.links.abs || paper.sourceURL?.contains(candidate.id) == true
        }) {
            return arxivStorageSubpath(for: arxivPaper)
        }
        return "arxiv"
    }

    private func removeDirectoryIfExists(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func removeManagedPaperStorage(for paper: Paper) throws {
        let paperDirectory = URL(fileURLWithPath: paper.filePath)
            .standardizedFileURL
            .deletingLastPathComponent()
        let managedRoots = [
            supportRoot.appendingPathComponent("papers", isDirectory: true).standardizedFileURL,
            supportRoot.appendingPathComponent("cache/papers", isDirectory: true).standardizedFileURL
        ]
        guard managedRoots.contains(where: { root in
            paperDirectory.path == root.path || paperDirectory.path.hasPrefix(root.path + "/")
        }) else {
            return
        }
        try removeDirectoryIfExists(paperDirectory)
    }

    private func discoverRankingVersion() -> String {
        let embedding = localDiscoverPreferences.normalized.embedding
        let model = embedding.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard embedding.enabled, !model.isEmpty else {
            return "local-rank-v3-no-embedding"
        }
        return "local-rank-v3-category-average-\(model)"
    }

    private func applyDiscoverRanking(to feed: ArxivFeedResponse, query: DiscoverQuery) async throws -> ArxivFeedResponse {
        let preferences = localDiscoverPreferences.normalized
        let sourceIDs = query.similaritySourceIDs
        guard preferences.embedding.enabled, !sourceIDs.isEmpty else {
            return applyLocalDiscoverPreferences(to: feed)
        }

        let embeddingSettings = preferences.embedding
        let model = embeddingSettings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = embeddingProviderAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !embeddingSettings.baseURL.isEmpty, !model.isEmpty, !apiKey.isEmpty else {
            errorMessage = "Embedding similarity is enabled, but Base URL, API key, or model is missing."
            return applyLocalDiscoverPreferences(to: feed)
        }

        let categorySources = similarityCategorySources(for: sourceIDs)
        let sourcePapers = uniquePapers(categorySources.flatMap(\.papers))
        guard !categorySources.isEmpty, !sourcePapers.isEmpty else {
            errorMessage = "No library papers matched the selected similarity source."
            return applyLocalDiscoverPreferences(to: feed)
        }

        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }

        arxivCacheProgress = ArxivCacheProgress(
            date: feed.date,
            title: "Embedding ranking",
            detail: "Preparing \(sourcePapers.count) library sources",
            completed: 0,
            total: sourcePapers.count + feed.papers.count
        )

        let client = try OpenAICompatibleEmbeddingClient(settings: embeddingSettings, apiKey: apiKey)
        let interestInputs = try sourcePapers.map { paper in
            DiscoverEmbeddingInput(
                sourceID: "paper:\(paper.id)",
                text: try libraryEmbeddingText(for: paper, repository: repository)
            )
        }
        let sourceVectors = try await cachedEmbeddings(
            inputs: interestInputs,
            model: model,
            client: client,
            progressDate: feed.date,
            progressTitle: "Embedding library sources",
            totalOffset: 0
        )
        let sourceVectorsByID = Dictionary(uniqueKeysWithValues: zip(interestInputs.map(\.sourceID), sourceVectors))
        let interestVectorGroups = categorySources.map { source in
            source.papers.compactMap { paper in
                sourceVectorsByID["paper:\(paper.id)"]
            }
        }
        guard !interestVectorGroups.flatMap({ $0 }).isEmpty else {
            return applyLocalDiscoverPreferences(to: feed)
        }

        let paperInputs = feed.papers.map { paper in
            DiscoverEmbeddingInput(
                sourceID: "arxiv:\(paper.id)",
                text: trimmedEmbeddingText(DiscoverEmbeddingText.arxivPaperText(paper))
            )
        }
        let paperVectors = try await cachedEmbeddings(
            inputs: paperInputs,
            model: model,
            client: client,
            progressDate: feed.date,
            progressTitle: "Embedding arXiv results",
            totalOffset: interestInputs.count
        )

        let vectorsByID = Dictionary(uniqueKeysWithValues: zip(paperInputs.map(\.sourceID), paperVectors))
        let papersWithEmbeddings = feed.papers.map { paper -> ArxivFeedPaper in
            var rankedPaper = paper
            rankedPaper.embedding = vectorsByID["arxiv:\(paper.id)"]
            return rankedPaper
        }
        let rankedPapers = SimilarityRanker.rank(
            papers: papersWithEmbeddings,
            whitelistTags: preferences.whitelistTags,
            blacklistTags: preferences.blacklistTags,
            interestVectorGroups: interestVectorGroups
        )
        arxivCacheProgress = ArxivCacheProgress(
            date: feed.date,
            title: "Embedding ranking ready",
            detail: "\(rankedPapers.filter { $0.similarity != nil }.count)/\(rankedPapers.count) scored",
            completed: rankedPapers.count,
            total: rankedPapers.count
        )
        return ArxivFeedResponse(
            date: feed.date,
            count: rankedPapers.count,
            papers: rankedPapers,
            groups: [
                ArxivFeedGroup(key: "white", count: rankedPapers.filter { $0.filterGroup == "white" }.count),
                ArxivFeedGroup(key: "neutral", count: rankedPapers.filter { $0.filterGroup == "neutral" }.count),
                ArxivFeedGroup(key: "black", count: rankedPapers.filter { $0.filterGroup == "black" }.count)
            ],
            tagOptions: Array(Set(rankedPapers.flatMap(\.tags))).sorted()
        )
    }

    private func cachedEmbeddings(
        inputs: [DiscoverEmbeddingInput],
        model: String,
        client: OpenAICompatibleEmbeddingClient,
        progressDate: String,
        progressTitle: String,
        totalOffset: Int
    ) async throws -> [[Double]] {
        guard !inputs.isEmpty else {
            return []
        }
        var vectorsBySourceID: [String: [Double]] = [:]
        var missing: [DiscoverEmbeddingInput] = []
        for input in inputs {
            if let cached = try localDiscoverCache.loadEmbedding(sourceID: input.sourceID, model: model, text: input.text) {
                vectorsBySourceID[input.sourceID] = cached.vector
            } else {
                missing.append(input)
            }
        }

        arxivCacheProgress = ArxivCacheProgress(
            date: progressDate,
            title: progressTitle,
            detail: "\(inputs.count - missing.count)/\(inputs.count) cached",
            completed: totalOffset + inputs.count - missing.count,
            total: totalOffset + inputs.count
        )

        if !missing.isEmpty {
            let cachedCount = inputs.count - missing.count
            var generatedCount = 0
            for batch in OpenAICompatibleEmbeddingClient.embeddingBatches(missing) {
                let vectors = try await client.embed(texts: batch.map(\.text))
                for (input, vector) in zip(batch, vectors) {
                    let record = DiscoverEmbeddingRecord(
                        sourceID: input.sourceID,
                        model: model,
                        textHash: DiscoverEmbeddingText.hash(input.text),
                        vector: vector,
                        generatedAt: Date()
                    )
                    try localDiscoverCache.saveEmbedding(record)
                    vectorsBySourceID[input.sourceID] = vector
                }
                generatedCount += batch.count
                arxivCacheProgress = ArxivCacheProgress(
                    date: progressDate,
                    title: progressTitle,
                    detail: "\(cachedCount + generatedCount)/\(inputs.count) ready",
                    completed: totalOffset + cachedCount + generatedCount,
                    total: totalOffset + inputs.count
                )
            }
        }

        arxivCacheProgress = ArxivCacheProgress(
            date: progressDate,
            title: progressTitle,
            detail: "\(inputs.count)/\(inputs.count) ready",
            completed: totalOffset + inputs.count,
            total: totalOffset + inputs.count
        )
        return inputs.compactMap { vectorsBySourceID[$0.sourceID] }
    }

    private func effectiveDiscoverSimilaritySourceIDs() -> [String] {
        let selected = normalizedSimilaritySourceIDs(discoverSelectedSimilaritySourceIDs)
        if !selected.isEmpty {
            return selected
        }
        return effectiveDiscoverSimilarityCategoryIDs().map { "category:\($0)" }
    }

    private func effectiveDiscoverSimilarityCategoryIDs() -> [String] {
        let configured = localDiscoverPreferences.normalized.similarityCategoryIDs ?? categories.map(\.id)
        return normalizedIdentifiers(configured).filter { categoryID in
            categories.contains { $0.id == categoryID }
        }
    }

    private func normalizedSimilaritySourceIDs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let normalized = similaritySourceID(from: trimmed)
            guard !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }

    private func similaritySourceID(from value: String) -> String {
        if value.hasPrefix("tag:") || value.hasPrefix("category:") {
            return value
        }
        if let tag = tags.first(where: { $0.id == value || $0.name.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
            return "tag:\(tag.id)"
        }
        if let category = categories.first(where: { $0.id == value || $0.name.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
            return "category:\(category.id)"
        }
        return value
    }

    private func similarityCategorySources(for sourceIDs: [String]) -> [DiscoverSimilarityCategorySource] {
        var seenCategoryIDs: Set<String> = []
        var sources: [DiscoverSimilarityCategorySource] = []
        for sourceID in sourceIDs {
            guard sourceID.hasPrefix("category:") else {
                continue
            }
            let categoryID = String(sourceID.dropFirst("category:".count))
            guard !seenCategoryIDs.contains(categoryID),
                  categories.contains(where: { $0.id == categoryID }) else {
                continue
            }
            let categoryIDs = Set([categoryID]).union(categoryDescendantIDs(of: categoryID))
            let sourcePapers = papers.filter { paper in
                !Set(paperCategoryIDsByID[paper.id, default: []]).isDisjoint(with: categoryIDs)
            }
            if !sourcePapers.isEmpty {
                seenCategoryIDs.insert(categoryID)
                sources.append(DiscoverSimilarityCategorySource(categoryID: categoryID, papers: sourcePapers))
            }
        }
        return sources
    }

    private func uniquePapers(_ values: [Paper]) -> [Paper] {
        var seen: Set<String> = []
        var result: [Paper] = []
        for paper in values where !seen.contains(paper.id) {
            seen.insert(paper.id)
            result.append(paper)
        }
        return result
    }

    private func libraryEmbeddingText(for paper: Paper, repository: PaperRepository) throws -> String {
        let pageText = try repository.fetchPages(paperID: paper.id)
            .prefix(5)
            .map(\.text)
            .joined(separator: "\n")
        let categoryNames = paperCategoryIDsByID[paper.id, default: []].compactMap { categoryID in
            categories.first { $0.id == categoryID }?.name
        }
        let tagNames = paperTagsByID[paper.id, default: []].map(\.name)
        return trimmedEmbeddingText(
            DiscoverEmbeddingText.libraryPaperText(
                title: paper.title,
                authors: paper.authors,
                tags: tagNames,
                categories: categoryNames,
                indexedText: pageText
            )
        )
    }

    private func trimmedEmbeddingText(_ text: String) -> String {
        String(DiscoverEmbeddingText.normalized(text).prefix(12_000))
    }

    private func applyLocalDiscoverPreferences(to feed: ArxivFeedResponse) -> ArxivFeedResponse {
        let preferences = localDiscoverPreferences.normalized
        let rankedPapers = SimilarityRanker.rank(
            papers: feed.papers,
            whitelistTags: preferences.whitelistTags,
            blacklistTags: preferences.blacklistTags,
            interestVectors: []
        )
        return ArxivFeedResponse(
            date: feed.date,
            count: rankedPapers.count,
            papers: rankedPapers,
            groups: [
                ArxivFeedGroup(key: "white", count: rankedPapers.filter { $0.filterGroup == "white" }.count),
                ArxivFeedGroup(key: "neutral", count: rankedPapers.filter { $0.filterGroup == "neutral" }.count),
                ArxivFeedGroup(key: "black", count: rankedPapers.filter { $0.filterGroup == "black" }.count)
            ],
            tagOptions: Array(Set(rankedPapers.flatMap(\.tags))).sorted()
        )
    }

    private func fetchArxivAsset(_ asset: ArxivFeedAsset) async throws -> Data {
        guard let url = URL(string: asset.url), url.scheme != nil else {
            throw LocalArxivClientError.invalidURL(asset.url)
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        var request = URLRequest(url: url)
        request.setValue("PaperCodex/0.1 (+https://arxiv.org)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw LocalArxivClientError.badStatus(http.statusCode, url.absoluteString)
        }
        return data
    }

    private func makeLocalArxivClient(categories overrideCategories: [String]? = nil) -> LocalArxivClient {
        let preferences = localDiscoverPreferences.normalized
        let categories = overrideCategories ?? (preferences.categories.isEmpty ? LocalArxivClient.defaultCategories : preferences.categories)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 60
        return LocalArxivClient(
            configuration: LocalArxivClientConfiguration(categories: categories),
            session: URLSession(configuration: configuration)
        )
    }

    private func runDiscoverCodexEnrichment(
        for paper: ArxivFeedPaper,
        actions: Set<DiscoverProcessAction>,
        existing: DiscoverPaperEnrichment?
    ) async throws -> (enrichment: DiscoverPaperEnrichment, tokenUsage: CodexTokenUsage?) {
        let executable = try CodexCLI.findCodexExecutable(preferWorkspaceImageOutput: false)
        let cli = CodexCLI(executablePath: executable)
        let workspaceURL = supportRoot
            .appendingPathComponent("discover-processing", isDirectory: true)
            .appendingPathComponent("\(makeSlug(from: paper.id))-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let outputURL = workspaceURL.appendingPathComponent("last-message.json")
        let eventLogURL = workspaceURL.appendingPathComponent("events.jsonl")
        let modelOverride = effectiveDiscoverCodexModelOverride()
        let modelIdentity = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "codex" : "codex:\(modelOverride)"
        let prompt = discoverEnrichmentPrompt(for: paper, actions: actions)
        let arguments = cli.startArguments(
            prompt: prompt,
            workspacePath: workspaceURL.path,
            outputLastMessagePath: outputURL.path,
            modelOverride: modelOverride,
            reasoningEffort: codexReasoningEffort
        )
        let runHandle = CodexRunHandle()
        activeDiscoverCodexRunHandles.append(runHandle)
        defer {
            activeDiscoverCodexRunHandles.removeAll { $0 === runHandle }
        }
        let stdout = try await Task.detached(priority: .userInitiated) {
            try cli.runStreaming(
                arguments: arguments,
                eventLogURL: eventLogURL,
                currentDirectoryURL: workspaceURL,
                runHandle: runHandle
            ) { _ in }
        }.value
        let lastMessage = try String(contentsOf: outputURL, encoding: .utf8)
        let tokenUsage = CodexCLI.aggregateTokenUsage(from: stdout)
        let parsed = try DiscoverEnrichmentParser.parse(
            lastMessage,
            arxivID: paper.id,
            modelIdentity: modelIdentity,
            generatedAt: Date()
        )
        return (mergeDiscoverEnrichment(parsed, existing: existing, actions: actions), tokenUsage)
    }

    private func mergeDiscoverEnrichment(
        _ parsed: DiscoverPaperEnrichment,
        existing: DiscoverPaperEnrichment?,
        actions: Set<DiscoverProcessAction>
    ) -> DiscoverPaperEnrichment {
        let currentExisting = existing?.isCurrent == true && existing?.error == nil ? existing : nil
        return DiscoverPaperEnrichment(
            arxivID: parsed.arxivID,
            processorVersion: parsed.processorVersion,
            promptVersion: parsed.promptVersion,
            modelIdentity: parsed.modelIdentity,
            titleZH: actions.contains(.translate) ? parsed.titleZH : currentExisting?.titleZH ?? "",
            summaryZH: actions.contains(.summarize) ? parsed.summaryZH : currentExisting?.summaryZH ?? "",
            contribution: actions.contains(.summarize) ? parsed.contribution : currentExisting?.contribution ?? "",
            tags: actions.contains(.summarize) ? parsed.tags : currentExisting?.tags ?? [],
            links: actions.contains(.summarize) ? parsed.links : currentExisting?.links ?? [:],
            generatedAt: parsed.generatedAt,
            error: nil
        )
    }

    private func discoverEnrichmentPrompt(for paper: ArxivFeedPaper, actions: Set<DiscoverProcessAction>) -> String {
        var schemaLines: [String] = []
        var taskLines: [String] = []
        if actions.contains(.translate) {
            schemaLines.append(#"  "title_zh": "Chinese translation of the title""#)
            taskLines.append("- Translate the title into concise Chinese.")
        }
        if actions.contains(.summarize) {
            schemaLines.append(#"  "summary_zh": "2 concise Chinese sentences summarizing the paper from title and abstract""#)
            schemaLines.append(#"  "contribution": "1 concise Chinese sentence naming the main contribution""#)
            schemaLines.append(#"  "tags": ["3-8 short lowercase tags"]"#)
            schemaLines.append(#"  "links": {"github": "https://...", "project": "https://...", "hugging_face": "https://..."}"#)
            taskLines.append("- Summarize the paper and extract discovery tags plus useful project links.")
        }
        let schema = "{\n\(schemaLines.joined(separator: ",\n"))\n}"
        let tasks = taskLines.joined(separator: "\n")
        return """
        You are helping Paper Codex enrich an arXiv discovery card.
        Return strict JSON only. Do not wrap the JSON in Markdown.

        Required JSON schema:
        \(schema)

        Selected tasks:
        \(tasks)

        Include only the selected schema keys. Use empty strings or omit link keys when no link is present.
        Tags should be useful for paper discovery.

        arXiv ID: \(paper.id)
        Primary category: \(paper.primaryCategory ?? paper.categories.first ?? "unknown")
        Categories: \(paper.categories.joined(separator: ", "))
        Title: \(paper.title.en)
        Authors: \(paper.authors.joined(separator: ", "))
        Abstract: \(paper.abstract.en)
        Comment: \(paper.comment)
        Known links:
        abs: \(paper.links.abs ?? "")
        pdf: \(paper.links.pdf ?? "")
        github: \(paper.links.github ?? "")
        project: \(paper.links.project ?? "")
        hugging_face: \(paper.links.huggingFace ?? "")
        """
    }

    private func makeManualID(prefix: String, name: String) -> String {
        let slug = makeSlug(from: name)
        return "\(prefix)-\(slug.isEmpty ? "item" : slug)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func makeSlug(from text: String) -> String {
        text
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func scanWatchedFolder(_ folder: WatchedFolder) throws {
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        _ = try WatchedFolderScanner(repository: repository, supportRoot: supportRoot)
            .scan(folder: folder)
    }

    private func scanAllWatchedFolders() throws -> [WatchedFolderScanResult] {
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        return try WatchedFolderScanner(repository: repository, supportRoot: supportRoot)
            .scanAllWatchedFolders()
    }

    private func beginCodexRun(sessionID: String, title: String) -> String {
        let runID = UUID().uuidString.lowercased()
        activeCodexRunsBySessionID[sessionID] = ActiveCodexRun(
            id: runID,
            sessionID: sessionID,
            title: title,
            startedAt: Date(),
            events: [
                CodexRunEvent(kind: .status, title: "Preparing", detail: "Preparing paper context and Codex workspace")
            ]
        )
        return runID
    }

    private func appendCodexRunEvent(_ event: CodexRunEvent, runID: String) {
        guard let sessionID = activeCodexRunsBySessionID.first(where: { $0.value.id == runID })?.key else {
            return
        }
        activeCodexRunsBySessionID[sessionID]?.events.append(event)
        if let count = activeCodexRunsBySessionID[sessionID]?.events.count, count > 80 {
            activeCodexRunsBySessionID[sessionID]?.events.removeFirst(count - 80)
        }
    }

    private func finishCodexRun(sessionID: String) {
        activeCodexRunsBySessionID[sessionID] = nil
        activeCodexRunHandlesBySessionID[sessionID] = nil
        cancellingCodexRunSessionIDs.remove(sessionID)
    }

    private func startWatchedFolderAutoScan() {
        watchedFolderAutoScanTask?.cancel()
        watchedFolderAutoScanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else {
                    return
                }
                self?.scanWatchedFoldersIfNeeded()
            }
        }
    }

    private func scanWatchedFoldersIfNeeded() {
        guard !watchedFolders.isEmpty else {
            return
        }
        scanWatchedFolders()
    }

    private func runCodex(
        prompt: String,
        session: PaperSession,
        runID: String,
        prefersWorkspaceImageOutput: Bool
    ) async throws -> (stdout: String, lastMessage: String, threadID: String?, generatedImages: [URL], tokenUsage: CodexTokenUsage?) {
        let executable = try CodexCLI.findCodexExecutable(preferWorkspaceImageOutput: prefersWorkspaceImageOutput)
        let cli = CodexCLI(executablePath: executable)
        appendCodexRunEvent(
            CodexRunEvent(kind: .status, title: "Codex", detail: "Launching \(URL(fileURLWithPath: executable).lastPathComponent)"),
            runID: runID
        )
        let workspaceURL = URL(fileURLWithPath: session.workspacePath, isDirectory: true)
        let imageSnapshot = try GeneratedImageCollector.snapshot(in: workspaceURL)
        let outputURL = URL(fileURLWithPath: session.workspacePath)
            .appendingPathComponent("turns", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString.lowercased())-codex.txt")
        let eventLogURL = outputURL.deletingPathExtension().appendingPathExtension("events.jsonl")
        let reasoningEffort = codexReasoningEffort
        let modelOverride = effectiveModelOverride(prefersWorkspaceImageOutput: prefersWorkspaceImageOutput)
        let arguments: [String]
        if let codexSessionID = session.codexSessionID, !prefersWorkspaceImageOutput {
            arguments = cli.resumeArguments(
                sessionID: codexSessionID,
                prompt: prompt,
                outputLastMessagePath: outputURL.path,
                modelOverride: modelOverride,
                reasoningEffort: reasoningEffort
            )
        } else {
            arguments = cli.startArguments(
                prompt: prompt,
                workspacePath: session.workspacePath,
                outputLastMessagePath: outputURL.path,
                modelOverride: modelOverride,
                reasoningEffort: reasoningEffort
            )
        }

        appendCodexRunEvent(
            CodexRunEvent(
                kind: .status,
                title: "Codex",
                detail: codexRunModeDescription(
                    reasoningEffort: reasoningEffort,
                    modelOverride: modelOverride,
                    prefersWorkspaceImageOutput: prefersWorkspaceImageOutput
                )
            ),
            runID: runID
        )
        let eventSink: @Sendable (CodexRunEvent) -> Void = { [weak self] event in
            Task { @MainActor in
                self?.appendCodexRunEvent(event, runID: runID)
            }
        }
        let runHandle = CodexRunHandle()
        activeCodexRunHandlesBySessionID[session.id] = runHandle
        let stdout = try await Task.detached(priority: .userInitiated) {
            try cli.runStreaming(
                arguments: arguments,
                eventLogURL: eventLogURL,
                currentDirectoryURL: workspaceURL,
                runHandle: runHandle,
                onEvent: eventSink
            )
        }.value
        let lastMessage = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let tokenUsage = CodexCLI.aggregateTokenUsage(from: stdout)
        let generatedImages = try GeneratedImageCollector.newImages(in: workspaceURL, excluding: imageSnapshot)
        if !generatedImages.isEmpty {
            appendCodexRunEvent(
                CodexRunEvent(kind: .answer, title: "Image", detail: "Generated \(generatedImages.count) image\(generatedImages.count == 1 ? "" : "s")"),
                runID: runID
            )
        }
        return (
            stdout: stdout,
            lastMessage: lastMessage,
            threadID: CodexCLI.parseThreadID(from: stdout),
            generatedImages: generatedImages,
            tokenUsage: tokenUsage
        )
    }

    private func effectiveModelOverride(prefersWorkspaceImageOutput: Bool) -> String {
        let trimmed = codexModelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefersWorkspaceImageOutput else {
            return trimmed
        }
        if trimmed.isEmpty || trimmed == "gpt-5.5" {
            return "gpt-5.4-mini"
        }
        return trimmed
    }

    private func effectiveDiscoverCodexModelOverride() -> String {
        let trimmed = discoverCodexModelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return effectiveModelOverride(prefersWorkspaceImageOutput: false)
    }

    private func codexRunModeDescription(
        reasoningEffort: CodexReasoningEffort,
        modelOverride: String,
        prefersWorkspaceImageOutput: Bool
    ) -> String {
        var parts: [String] = []
        if prefersWorkspaceImageOutput {
            parts.append("Image generation enabled")
        }
        let trimmedModel = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            parts.append("Model \(trimmedModel)")
        }
        parts.append(reasoningEffort == .default ? "default thinking" : "\(reasoningEffort.displayName) thinking")
        return parts.joined(separator: " · ")
    }

    private func runCodexTurn(
        content: String,
        session: PaperSession,
        fallbackPaper: Paper,
        repository: PaperRepository
    ) async throws -> PaperSession {
        let runID = beginCodexRun(sessionID: session.id, title: "Codex is working")
        let context = try loadSessionPaperContext(session: session, fallbackPaper: fallbackPaper, repository: repository)
        let selectedAnchors = anchorsReferenced(in: content, context: context)
        appendCodexRunEvent(
            CodexRunEvent(kind: .status, title: "Context", detail: "Loaded \(context.papers.count) paper(s), \(context.spans.count) indexed span(s), \(selectedAnchors.count) selected source anchor(s)"),
            runID: runID
        )
        try workspaceManager.writeWorkspace(
            session: session,
            papers: context.papers,
            pagesByPaperID: context.pagesByPaperID,
            spansByPaperID: context.spansByPaperID,
            anchorsByPaperID: context.anchorsByPaperID
        )
        appendCodexRunEvent(
            CodexRunEvent(kind: .status, title: "Workspace", detail: "Wrote session workspace at \(session.workspacePath)"),
            runID: runID
        )

        let prompt = PromptBuilder().buildPrompt(
            request: PromptRequest(
                userMessage: content,
                workspacePath: session.workspacePath,
                papers: context.papers,
                selectedAnchors: selectedAnchors,
                relevantSpans: [],
                systemPromptTemplate: codexSystemPrompt,
                languageMode: globalLanguageMode
            )
        )
        appendCodexRunEvent(
            CodexRunEvent(kind: .status, title: "Prompt", detail: "Built grounded prompt and started Codex"),
            runID: runID
        )
        let prefersWorkspaceImageOutput = ImageGenerationRequestDetector.isImageRequest(content)
        let codexReply = try await runCodex(
            prompt: prompt,
            session: session,
            runID: runID,
            prefersWorkspaceImageOutput: prefersWorkspaceImageOutput
        )
        var updatedSession = session
        if let threadID = codexReply.threadID, !prefersWorkspaceImageOutput {
            updatedSession.codexSessionID = threadID
        }
        updatedSession.updatedAt = Date()
        try repository.upsertSession(updatedSession)

        let codexMessage = ChatMessage(
            id: UUID().uuidString.lowercased(),
            sessionID: session.id,
            role: .codex,
            content: codexMessageContent(
                lastMessage: codexReply.lastMessage,
                stdout: codexReply.stdout,
                generatedImages: codexReply.generatedImages
            ),
            createdAt: Date()
        )
        try repository.appendMessage(codexMessage)
        if let tokenUsage = codexReply.tokenUsage {
            postNotice(
                kind: .info,
                title: "Chat Tokens",
                message: tokenUsage.compactSummary,
                autoDismissAfter: 8
            )
        }
        return updatedSession
    }

    private func codexMessageContent(lastMessage: String, stdout: String, generatedImages: [URL]) -> String {
        let imageMarkdown = GeneratedImageCollector.markdown(for: generatedImages)
        let trimmedLastMessage = lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLastMessage.isEmpty {
            return imageMarkdown.isEmpty ? stdout : imageMarkdown
        }
        guard !imageMarkdown.isEmpty else {
            return lastMessage
        }
        let missingImageMarkdown = imageMarkdown
            .components(separatedBy: "\n\n")
            .filter { !lastMessage.contains($0) }
            .joined(separator: "\n\n")
        guard !missingImageMarkdown.isEmpty else {
            return lastMessage
        }
        return "\(lastMessage)\n\n\(missingImageMarkdown)"
    }

    private func fallbackPaper(for session: PaperSession, repository: PaperRepository) throws -> Paper {
        if let selectedPaper {
            return selectedPaper
        }
        guard let firstPaperID = session.paperIDs.first,
              let paper = try repository.fetchPapers(ids: [firstPaperID]).first else {
            throw AppModelError.noSelectedPaper
        }
        return paper
    }

    private func appendCodexFailureMessage(_ failure: String, sessionID: String) async {
        guard let repository else {
            errorMessage = failure
            return
        }
        do {
            let message = ChatMessage(
                id: UUID().uuidString.lowercased(),
                sessionID: sessionID,
                role: .codex,
                content: CodexFailureNotice(detail: failure).messageContent,
                createdAt: Date()
            )
            try repository.appendMessage(message)
            if selectedSession?.id == sessionID {
                messages = try repository.fetchMessages(sessionID: sessionID)
            }
        } catch {
            errorMessage = "\(failure)\n\nAlso failed to store error message: \(error)"
        }
    }

    private func appendCodexCancellationMessage(sessionID: String) async {
        guard let repository else {
            return
        }
        do {
            let message = ChatMessage(
                id: UUID().uuidString.lowercased(),
                sessionID: sessionID,
                role: .codex,
                content: "_Codex run stopped by the user._",
                createdAt: Date()
            )
            try repository.appendMessage(message)
            if selectedSession?.id == sessionID {
                messages = try repository.fetchMessages(sessionID: sessionID)
            }
            let sessionTitle = try repository.fetchSession(id: sessionID)?.title ?? "Session"
            postNotice(kind: .info, title: "Codex Stopped", message: sessionTitle)
        } catch {
            errorMessage = "Codex stopped, but the cancellation note could not be saved: \(error)"
        }
    }
}

enum AppModelError: Error, CustomStringConvertible {
    case repositoryUnavailable
    case noSelectedPaper
    case noSelectedSession
    case emptyName
    case sessionPaperMismatch
    case sourceNotFound(String)
    case anchorMatchFailed
    case noRecoverableCodexTurn
    case downloadedFileIsNotPDF(String)
    case arxivMetadataNotFound(String)
    case categoryNotFound(String)
    case invalidCategoryMove
    case keychainFailure(OSStatus)

    var description: String {
        switch self {
        case .repositoryUnavailable:
            "Local repository is not available."
        case .noSelectedPaper:
            "No paper is selected."
        case .noSelectedSession:
            "No Codex session is selected."
        case .emptyName:
            "Name cannot be empty."
        case .sessionPaperMismatch:
            "This chat session belongs to a different paper. Open a session for the current paper before sending."
        case let .sourceNotFound(id):
            "No source was found for citation \(id)."
        case .anchorMatchFailed:
            "The selected PDF text could not be matched to the paper index. Try selecting a slightly larger or smaller passage."
        case .noRecoverableCodexTurn:
            "No failed Codex turn could be retried."
        case let .downloadedFileIsNotPDF(arxivID):
            "Downloaded content for \(arxivID) was not a PDF."
        case let .arxivMetadataNotFound(arxivID):
            "No arXiv metadata was found for \(arxivID)."
        case let .categoryNotFound(categoryID):
            "No folder was found for \(categoryID)."
        case .invalidCategoryMove:
            "A category cannot be moved into itself or one of its subcategories."
        case let .keychainFailure(status):
            "Keychain operation failed with status \(status)."
        }
    }
}
