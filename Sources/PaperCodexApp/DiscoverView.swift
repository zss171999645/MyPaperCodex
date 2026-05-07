import AppKit
import ImageIO
import PaperCodexCore
import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedCategory: String?
    @State private var selectedTag: String?
    @State private var selectedProcessingFilter: DiscoverProcessingFilter = .all
    @State private var selectedLibraryFilter: DiscoverLibraryFilter = .all
    @State private var requiresProjectLink = false
    @State private var selectedSimilarityBucket: DiscoverSimilarityBucket = .all
    @State private var paperPendingSave: ArxivFeedPaper?
    @State private var previewPaper: ArxivFeedPaper?
    @State private var discoverRowHeights: [Int: CGFloat] = [:]
    @State private var isShowingProcessSelection = false
    @State private var isDiscoverScrollTrackingEnabled = false

    private var papers: [ArxivFeedPaper] {
        var result = model.arxivFeed?.papers ?? []
        if let selectedCategory {
            result = result.filter {
                $0.categories.contains(selectedCategory) || $0.listCategories.contains(selectedCategory)
            }
        }
        if let selectedTag {
            result = result.filter { tags(for: $0).contains(selectedTag) }
        }
        switch selectedProcessingFilter {
        case .all:
            break
        case .processed:
            result = result.filter { model.discoverEnrichment(for: $0)?.error == nil && model.discoverEnrichment(for: $0)?.isCurrent == true }
        case .unprocessed:
            result = result.filter { model.discoverEnrichment(for: $0) == nil }
        case .failed:
            result = result.filter { model.discoverEnrichment(for: $0)?.error != nil }
        }
        switch selectedLibraryFilter {
        case .all:
            break
        case .newOnly:
            result = result.filter { model.libraryPaper(for: $0) == nil }
        case .inLibrary:
            result = result.filter { model.libraryPaper(for: $0) != nil }
        }
        if requiresProjectLink {
            result = result.filter { $0.links.github != nil || $0.links.project != nil || $0.links.huggingFace != nil || !(model.discoverEnrichment(for: $0)?.links.isEmpty ?? true) }
        }
        if selectedSimilarityBucket != .all {
            result = result.filter { selectedSimilarityBucket.contains($0.similarity) }
        }
        return result
    }

    private var categories: [String] {
        let all = (model.arxivFeed?.papers ?? []).flatMap { $0.listCategories.isEmpty ? $0.categories : $0.listCategories }
        return Array(Set(all)).sorted()
    }

    private var tags: [String] {
        let counts = tagCounts
        return counts.keys.sorted { left, right in
            let leftCount = counts[left, default: 0]
            let rightCount = counts[right, default: 0]
            if leftCount == rightCount {
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
            return leftCount > rightCount
        }
    }

    private var tagCounts: [String: Int] {
        Dictionary((model.arxivFeed?.papers ?? []).flatMap { tags(for: $0) }.map { ($0, 1) }, uniquingKeysWith: +)
    }

    private var commonCategories: [String] {
        ["cs.CV", "cs.CL", "cs.AI", "cs.LG", "cs.RO", "stat.ML", "cs.HC", "cs.IR", "cs.SE"]
    }

    private func tags(for paper: ArxivFeedPaper) -> [String] {
        let generated = model.discoverEnrichment(for: paper)?.tags ?? []
        let combined = generated + paper.tags + Array(paper.categories.prefix(2))
        var seen: Set<String> = []
        var result: [String] = []
        for tag in combined {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var body: some View {
        mainLayout
            .overlay {
                if let previewPaper {
                    ArxivImagePreviewOverlay(paper: previewPaper) {
                        self.previewPaper = nil
                    }
                    .environmentObject(model)
                }
            }
            .sheet(item: $paperPendingSave) { paper in
                SaveToLibrarySheet(
                    paperTitle: paper.displayTitle(language: model.globalLanguageMode.discoverLanguageCode),
                    detail: paper.authors.prefix(4).joined(separator: ", "),
                    libraryCategories: model.categories,
                    initialCategoryIDs: model.suggestedCategoryIDsForDiscoverSave(),
                    onSave: { selection in
                        paperPendingSave = nil
                        Task {
                            await model.addArxivPaperToLibrary(
                                paper,
                                selectedCategoryIDs: selection.categoryIDs,
                                newCategoryNames: selection.newCategoryNames
                            )
                        }
                    },
                    onCancel: {
                        paperPendingSave = nil
                    }
                )
            }
            .sheet(isPresented: $isShowingProcessSelection) {
                DiscoverProcessActionSheet(
                    paperCount: papers.count,
                    onConfirm: { actions in
                        isShowingProcessSelection = false
                        Task {
                            await model.processCurrentDiscoverResults(papers, actions: Set(actions))
                        }
                    },
                    onCancel: {
                        isShowingProcessSelection = false
                    }
                )
            }
    }

    private var mainLayout: some View {
        SidebarSplitLayout(minContentWidth: 760) {
            sidebar
        } content: {
            feed
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            let expectedDate = "\(model.discoverStartDate)...\(model.discoverEndDate)"
            guard !model.isSearchingDiscover,
                  model.arxivFeed == nil || model.selectedArxivDate != expectedDate else {
                return
            }
            model.startDiscoverSearch()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.paperCodexSystem(size: 24, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                navButton(title: "Library", systemImage: "books.vertical") {
                    model.goToLibrary()
                }
                navButton(title: "Discover", systemImage: "sparkle.magnifyingglass", selected: true) {}
                navButton(title: "Settings", systemImage: "gearshape") {
                    model.showSettings()
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Categories", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.headline)
                        filterButton(title: "All", selected: selectedCategory == nil && selectedTag == nil) {
                            selectedCategory = nil
                            selectedTag = nil
                        }
                        ForEach(categories, id: \.self) { category in
                            filterButton(title: category, selected: selectedCategory == category) {
                                selectedCategory = category
                                selectedTag = nil
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Status", systemImage: "checklist")
                            .font(.headline)
                        ForEach(DiscoverProcessingFilter.allCases) { filter in
                            filterButton(title: filter.title, selected: selectedProcessingFilter == filter) {
                                selectedProcessingFilter = filter
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Library", systemImage: "books.vertical")
                            .font(.headline)
                        ForEach(DiscoverLibraryFilter.allCases) { filter in
                            filterButton(title: filter.title, selected: selectedLibraryFilter == filter) {
                                selectedLibraryFilter = filter
                            }
                        }
                        filterButton(title: "Has Code / Project", selected: requiresProjectLink) {
                            requiresProjectLink.toggle()
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Similarity", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.headline)
                        ForEach(DiscoverSimilarityBucket.allCases) { bucket in
                            filterButton(title: bucket.title, selected: selectedSimilarityBucket == bucket) {
                                selectedSimilarityBucket = bucket
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Tags", systemImage: "tag")
                            .font(.headline)
                        filterButton(
                            title: "All Tags",
                            detail: "\(tagCounts.values.reduce(0, +))",
                            selected: selectedTag == nil
                        ) {
                            selectedTag = nil
                        }
                        ForEach(tags.prefix(18), id: \.self) { tag in
                            filterButton(
                                title: tag,
                                detail: "\(tagCounts[tag, default: 0])",
                                selected: selectedTag == tag
                            ) {
                                selectedTag = tag
                                selectedCategory = nil
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar

            if model.isSearchingDiscover && model.arxivFeed == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let columnCount = gridColumnCount(for: proxy.size.width)
                    let rows = paperRows(papers, columnCount: columnCount)
                    let layoutSignature = rowLayoutSignature(papers: papers, columnCount: columnCount)
                    let imagePreloadURLs = discoverImagePreloadURLs(for: papers)

                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowPapers in
                                    HStack(alignment: .top, spacing: 16) {
                                        ForEach(rowPapers) { paper in
                                            discoverCard(for: paper, rowIndex: rowIndex)
                                                .id(paper.id)
                                        }
                                        ForEach(0..<max(0, columnCount - rowPapers.count), id: \.self) { _ in
                                            Color.clear
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .onPreferenceChange(DiscoverRowHeightPreferenceKey.self) { values in
                                var updated = discoverRowHeights
                                var didChange = false
                                for (rowIndex, height) in values where height > 0 {
                                    let roundedHeight = (height * 2).rounded() / 2
                                    if abs((updated[rowIndex] ?? 0) - roundedHeight) > 0.5 {
                                        updated[rowIndex] = roundedHeight
                                        didChange = true
                                    }
                                }
                                if didChange {
                                    discoverRowHeights = updated
                                }
                            }
                            .onChange(of: layoutSignature) { _, _ in
                                discoverRowHeights = [:]
                            }
                            .onPreferenceChange(DiscoverVisiblePaperPreferenceKey.self) { positions in
                                recordDiscoverVisiblePaper(positions)
                            }
                            .task(id: "\(layoutSignature):\(imagePreloadURLs.count)") {
                                await warmDiscoverLocalImages(imagePreloadURLs)
                            }
                        }
                        .coordinateSpace(name: DiscoverScrollCoordinateSpace.name)
                        .onAppear {
                            restoreDiscoverScrollPosition(scrollProxy)
                        }
                        .onChange(of: layoutSignature) { _, _ in
                            restoreDiscoverScrollPosition(scrollProxy)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func gridColumnCount(for width: CGFloat) -> Int {
        if width >= 1120 {
            return 3
        }
        if width >= 760 {
            return 2
        }
        return 1
    }

    private func paperRows(_ papers: [ArxivFeedPaper], columnCount: Int) -> [[ArxivFeedPaper]] {
        let count = max(columnCount, 1)
        return stride(from: 0, to: papers.count, by: count).map { start in
            Array(papers[start..<min(start + count, papers.count)])
        }
    }

    private func rowLayoutSignature(papers: [ArxivFeedPaper], columnCount: Int) -> String {
        "\(columnCount):\(papers.map(\.id).joined(separator: ","))"
    }

    private func discoverImagePreloadURLs(for papers: [ArxivFeedPaper]) -> [URL] {
        papers.flatMap { paper in
            var urls: [URL] = []
            if let assetURL = model.cachedArxivAssetURL(for: paper.assets.small) {
                urls.append(assetURL)
            }
            urls.append(contentsOf: model.cachedArxivPDFThumbnailURLs(for: paper))
            return urls
        }
    }

    private func discoverCard(for paper: ArxivFeedPaper, rowIndex: Int) -> some View {
        ArxivPaperCard(
            paper: paper,
            enrichment: model.discoverEnrichment(for: paper),
            imageURL: model.cachedArxivAssetURL(for: paper.assets.small),
            thumbnailURLs: model.cachedArxivPDFThumbnailURLs(for: paper),
            inLibrary: model.libraryPaper(for: paper) != nil,
            isBusy: model.isDownloadingArxivPaper(paper),
            downloadProgress: model.arxivDownloadProgress(for: paper),
            interactionState: model.discoverPaperInteractionStateByID[paper.id],
            languageMode: model.globalLanguageMode,
            minimumHeight: discoverRowHeights[rowIndex] ?? 0,
            onPreview: {
                previewPaper = paper
            },
            onSave: {
                paperPendingSave = paper
            },
            onOpen: {
                model.recordDiscoverScrollPosition(paper.id)
                Task {
                    await model.openArxivPaper(paper)
                }
            }
        )
        .background(DiscoverCardHeightReporter(rowIndex: rowIndex))
        .background(DiscoverVisiblePaperReporter(paperID: paper.id))
    }

    private func restoreDiscoverScrollPosition(_ proxy: ScrollViewProxy) {
        isDiscoverScrollTrackingEnabled = false
        guard let paperID = model.discoverScrollPositionPaperID,
              papers.contains(where: { $0.id == paperID }) else {
            isDiscoverScrollTrackingEnabled = true
            return
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(paperID, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                isDiscoverScrollTrackingEnabled = true
            }
        }
    }

    private func recordDiscoverVisiblePaper(_ positions: [String: CGFloat]) {
        guard isDiscoverScrollTrackingEnabled, !positions.isEmpty else {
            return
        }
        let ordered = papers.enumerated().compactMap { index, paper -> (index: Int, paperID: String, minY: CGFloat)? in
            guard let minY = positions[paper.id] else {
                return nil
            }
            return (index, paper.id, minY)
        }
        guard !ordered.isEmpty else {
            return
        }
        let candidate = ordered.min { left, right in
            let leftDistance = abs(left.minY)
            let rightDistance = abs(right.minY)
            if abs(leftDistance - rightDistance) > 0.5 {
                return leftDistance < rightDistance
            }
            return left.index < right.index
        }
        if let candidate {
            model.recordDiscoverScrollPosition(candidate.paperID)
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discover")
                        .font(.paperCodexSystem(size: 28, weight: .semibold))
                    Text("\(papers.count) visible · \(model.arxivFeed?.count ?? 0) found · \(model.selectedArxivDate ?? "\(model.discoverStartDate)...\(model.discoverEndDate)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Keyword, method, author, arXiv ID", text: $model.discoverKeyword)
                    .textFieldStyle(.roundedBorder)
                    .layoutPriority(-1)
                    .onSubmit {
                        model.startDiscoverSearch()
                    }

                FlowLayout(spacing: 8) {
                    DiscoverDateControls(start: $model.discoverStartDate, end: $model.discoverEndDate) { range in
                        model.applyDiscoverQuickRange(range)
                    }

                    DiscoverCategoryMenu(
                        categories: commonCategories,
                        selected: model.discoverSelectedCategories.first ?? "cs.CV"
                    ) { category in
                        model.discoverSelectedCategories = [category]
                    }

                    SimilaritySourceMenu()
                        .environmentObject(model)

                    ToolbarActionButton(
                        title: model.isSearchingDiscover ? "Searching" : "Search",
                        systemImage: "magnifyingglass",
                        tint: .blue,
                        disabled: model.isSearchingDiscover || model.isProcessingDiscoverResults || model.isCachingDiscoverPDFs
                    ) {
                        model.startDiscoverSearch()
                    }

                    if model.isSearchingDiscover || model.isProcessingDiscoverResults || model.isCachingDiscoverPDFs {
                        ToolbarActionButton(title: "Stop", systemImage: "stop.circle", tint: .red) {
                            if model.isSearchingDiscover {
                                model.cancelDiscoverSearch()
                            }
                            if model.isProcessingDiscoverResults {
                                model.cancelDiscoverProcessing()
                            }
                            if model.isCachingDiscoverPDFs {
                                model.cancelDiscoverPDFCache()
                            }
                        }
                    } else {
                        ToolbarActionButton(
                            title: "Process Results",
                            systemImage: "sparkles",
                            tint: .indigo,
                            disabled: papers.isEmpty || model.isSearchingDiscover
                        ) {
                            isShowingProcessSelection = true
                        }
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)

                activeFilterChips

                if (model.isSearchingDiscover || model.isPreloadingArxivAssets),
                   let progress = model.arxivCacheProgress {
                    ArxivCacheProgressStrip(progress: progress)
                }
                if model.isProcessingDiscoverResults,
                   let progress = model.discoverProcessingProgress {
                    ArxivCacheProgressStrip(progress: progress)
                }
                if model.isCachingDiscoverPDFs,
                   let progress = model.discoverPDFCacheProgress {
                    ArxivCacheProgressStrip(progress: progress)
                }
            }
        }
    }

    private func navButton(title: String, systemImage: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        SidebarRowButton(title: title, systemImage: systemImage, selected: selected, action: action)
    }

    private func filterButton(title: String, detail: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        SidebarFilterButton(title: title, detail: detail, selected: selected, action: action)
    }

    private var activeFilterChips: some View {
        FlowLayout(spacing: 8) {
            if let selectedCategory {
                DiscoverFilterChip(title: selectedCategory) {
                    self.selectedCategory = nil
                }
            }
            if let selectedTag {
                DiscoverFilterChip(title: selectedTag) {
                    self.selectedTag = nil
                }
            }
            if selectedProcessingFilter != .all {
                DiscoverFilterChip(title: selectedProcessingFilter.title) {
                    selectedProcessingFilter = .all
                }
            }
            if selectedLibraryFilter != .all {
                DiscoverFilterChip(title: selectedLibraryFilter.title) {
                    selectedLibraryFilter = .all
                }
            }
            if requiresProjectLink {
                DiscoverFilterChip(title: "Has Code / Project") {
                    requiresProjectLink = false
                }
            }
            if selectedSimilarityBucket != .all {
                DiscoverFilterChip(title: selectedSimilarityBucket.title) {
                    selectedSimilarityBucket = .all
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum DiscoverProcessingFilter: String, CaseIterable, Identifiable {
    case all
    case processed
    case unprocessed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .processed:
            "Processed"
        case .unprocessed:
            "Unprocessed"
        case .failed:
            "Failed"
        }
    }
}

private enum DiscoverLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case newOnly
    case inLibrary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All Papers"
        case .newOnly:
            "New Only"
        case .inLibrary:
            "In Library"
        }
    }
}

private enum DiscoverSimilarityBucket: String, CaseIterable, Identifiable {
    case all
    case high
    case medium
    case low
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All Scores"
        case .high:
            "High"
        case .medium:
            "Medium"
        case .low:
            "Low"
        case .none:
            "No Similarity"
        }
    }

    func contains(_ value: Double?) -> Bool {
        switch self {
        case .all:
            true
        case .high:
            (value ?? 0) >= 0.78
        case .medium:
            (value ?? 0) >= 0.62 && (value ?? 0) < 0.78
        case .low:
            value != nil && (value ?? 0) < 0.62
        case .none:
            value == nil
        }
    }
}

private struct SidebarFilterButton: View {
    @State private var isHovering = false

    var title: String
    var detail: String?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(LocalizedStringKey(title))
                    .lineLimit(1)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: isHovering ? Color.black.opacity(0.06) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.12) : (isHovering ? Color(nsColor: .textBackgroundColor) : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor.opacity(0.20) : Color.clear, lineWidth: 1)
            )
    }
}

private struct DiscoverFilterChip: View {
    var title: String
    var onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            Label(title, systemImage: "xmark.circle.fill")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .help("Remove \(title) filter")
    }
}

private struct DiscoverPaperStatusBadge: View {
    var state: DiscoverPaperInteractionState

    var body: some View {
        Label {
            Text(LocalizedStringKey(title))
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.10), in: Capsule())
            .help(title)
    }

    private var title: String {
        switch state {
        case .queued:
            "Queued"
        case .processing:
            "Processing"
        case .processed:
            "Processed"
        case .cached:
            "Cached"
        case .failed:
            "Failed"
        case .cancelled:
            "Stopped"
        case .downloading:
            "Caching PDF"
        case .pdfCached:
            "PDF Cached"
        }
    }

    private var systemImage: String {
        switch state {
        case .queued:
            "clock"
        case .processing:
            "sparkles"
        case .processed:
            "checkmark.circle.fill"
        case .cached:
            "archivebox.fill"
        case .failed:
            "xmark.octagon.fill"
        case .cancelled:
            "stop.circle.fill"
        case .downloading:
            "arrow.down.circle.fill"
        case .pdfCached:
            "doc.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .queued:
            .secondary
        case .processing:
            .indigo
        case .processed, .cached, .pdfCached:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        case .downloading:
            .blue
        }
    }
}

private struct ToolbarActionButton: View {
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var tint: Color
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
                .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(disabled ? Color.secondary.opacity(0.55) : (isHovering ? tint : Color.primary.opacity(0.82)))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(disabled ? Color(nsColor: .controlBackgroundColor).opacity(0.55) : (isHovering ? tint.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(disabled ? Color.black.opacity(0.06) : (isHovering ? tint.opacity(0.45) : Color.black.opacity(0.10)), lineWidth: 1)
                        )
                )
                .shadow(color: isHovering && !disabled ? tint.opacity(0.18) : .clear, radius: 7, y: 3)
                .scaleEffect(isHovering && !disabled ? 1.035 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct DiscoverDateControls: View {
    @Binding var start: String
    @Binding var end: String
    var onQuickRange: (DiscoverQuickRange) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
            CompactDiscoverDatePicker(title: "Start", dateString: $start) { value in
                if DiscoverDateStrings.date(from: value) > DiscoverDateStrings.date(from: end) {
                    end = value
                }
            }
            Text(LocalizedStringKey("to"))
                .font(.caption)
                .foregroundStyle(.secondary)
            CompactDiscoverDatePicker(title: "End", dateString: $end) { value in
                if DiscoverDateStrings.date(from: value) < DiscoverDateStrings.date(from: start) {
                    start = value
                }
            }
            QuickRangeButtons(onSelect: onQuickRange)
        }
        .help("arXiv date range")
    }
}

private struct CompactDiscoverDatePicker: View {
    var title: String
    @Binding var dateString: String
    var onChange: (String) -> Void

    private var dateBinding: Binding<Date> {
        Binding {
            DiscoverDateStrings.date(from: dateString)
        } set: { newDate in
            let value = DiscoverDateStrings.string(from: newDate)
            dateString = value
            onChange(value)
        }
    }

    var body: some View {
        DatePicker(LocalizedStringKey(title), selection: dateBinding, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .font(.paperCodexSystem(size: 12.5, weight: .medium).monospacedDigit())
            .frame(width: 118)
            .help(title)
    }
}

private enum DiscoverDateStrings {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static func date(from value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2],
                hour: 12
              )) else {
            return Date()
        }
        return date
    }

    static func string(from date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}

private struct QuickRangeButtons: View {
    var onSelect: (DiscoverQuickRange) -> Void
    private let ranges: [DiscoverQuickRange] = [DiscoverQuickRange.today, .last7Days, .last30Days]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                quickButtons
            }
            Menu {
                ForEach(ranges) { range in
                    Button(range.title) {
                        onSelect(range)
                    }
                }
            } label: {
                Label("Ranges", systemImage: "calendar.badge.clock")
                    .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var quickButtons: some View {
        ForEach(ranges) { range in
            Button(range.title) {
                onSelect(range)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(range.title)
        }
    }
}

private struct DiscoverProcessActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var paperCount: Int
    var onConfirm: ([DiscoverProcessAction]) -> Void
    var onCancel: () -> Void

    @State private var selectedActions: Set<DiscoverProcessAction>

    init(
        paperCount: Int,
        onConfirm: @escaping ([DiscoverProcessAction]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.paperCount = paperCount
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selectedActions = State(initialValue: Set(DiscoverProcessAction.allCases))
    }

    private var selectedOrderedActions: [DiscoverProcessAction] {
        DiscoverProcessAction.allCases.filter { selectedActions.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Processing Steps")
                    .font(.paperCodexSystem(size: 20, weight: .semibold))
                Text("\(paperCount) visible results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button("Select All") {
                        selectedActions = Set(DiscoverProcessAction.allCases)
                    }
                    Button("Clear") {
                        selectedActions = []
                    }
                    Spacer()
                    Text("\(selectedOrderedActions.count)/\(DiscoverProcessAction.allCases.count) steps")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(DiscoverProcessAction.allCases) { action in
                        DiscoverProcessActionRow(
                            action: action,
                            isSelected: Binding(get: {
                                selectedActions.contains(action)
                            }, set: { selected in
                                if selected {
                                    selectedActions.insert(action)
                                } else {
                                    selectedActions.remove(action)
                                }
                            })
                        )
                    }
                }
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                Button("Process Results") {
                    onConfirm(selectedOrderedActions)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedOrderedActions.isEmpty || paperCount == 0)
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

private struct DiscoverProcessActionRow: View {
    var action: DiscoverProcessAction
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(action.title))
                        .font(.paperCodexSystem(size: 14, weight: .semibold))
                    Text(LocalizedStringKey(action.detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: action.systemImage)
                    .font(.paperCodexSystem(size: 15, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 24)
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DiscoverCategoryMenu: View {
    var categories: [String]
    var selected: String
    var onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(categories, id: \.self) { category in
                Button {
                    onSelect(category)
                } label: {
                    if category == selected {
                        Label(category, systemImage: "checkmark")
                    } else {
                        Text(category)
                    }
                }
            }
        } label: {
            Label(selected, systemImage: "tray.full")
                .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Primary arXiv category")
    }
}

private struct SimilaritySourceMenu: View {
    @EnvironmentObject private var model: AppModel

    private var selectedTitle: String {
        guard let first = model.discoverSelectedSimilaritySourceIDs.first else {
            return "Similarity"
        }
        if let category = model.categories.first(where: { "category:\($0.id)" == first }) {
            return category.name
        }
        return "\(model.discoverSelectedSimilaritySourceIDs.count) sources"
    }

    private func selectSources(_ sourceIDs: [String]) {
        model.discoverSelectedSimilaritySourceIDs = sourceIDs
        Task {
            await model.rerankCurrentDiscoverResults()
        }
    }

    var body: some View {
        Menu {
            Button {
                selectSources([])
            } label: {
                if model.discoverSelectedSimilaritySourceIDs.isEmpty {
                    Label("Settings default", systemImage: "checkmark")
                } else {
                    Text("Settings default")
                }
            }
            if !model.categories.isEmpty {
                Divider()
                Section("Folders") {
                    ForEach(model.categories) { category in
                        Button {
                            selectSources(["category:\(category.id)"])
                        } label: {
                            if model.discoverSelectedSimilaritySourceIDs == ["category:\(category.id)"] {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                }
            }
        } label: {
            Label(selectedTitle, systemImage: "point.3.connected.trianglepath.dotted")
                .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Similarity source")
    }
}

private struct DateMenuButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var isHovering = false

    var body: some View {
        Menu {
            Button {
                Task {
                    await model.refreshArxivDates()
                }
            } label: {
                Label(model.isRefreshingArxivDates ? "Refreshing dates" : "Refresh dates", systemImage: "arrow.clockwise")
            }
            Divider()
            ForEach(Array(model.arxivDates.reversed()), id: \.self) { date in
                Button {
                    Task {
                        await model.loadArxivFeed(date: date)
                    }
                } label: {
                    if date == model.selectedArxivDate {
                        Label(date, systemImage: "checkmark")
                    } else {
                        Text(date)
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: model.isRefreshingArxivDates ? "arrow.clockwise.circle" : "calendar")
                Text(model.selectedArxivDate ?? "Date")
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.paperCodexSystem(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.paperCodexSystem(size: 12.5, weight: .semibold))
            .foregroundStyle(isHovering ? Color.accentColor : Color.primary.opacity(0.84))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.accentColor.opacity(0.11) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isHovering ? Color.accentColor.opacity(0.36) : Color.black.opacity(0.10), lineWidth: 1)
                    )
            )
            .shadow(color: isHovering ? Color.accentColor.opacity(0.14) : .clear, radius: 7, y: 3)
            .scaleEffect(isHovering ? 1.025 : 1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose feed date")
        .simultaneousGesture(TapGesture().onEnded {
            Task {
                await model.refreshArxivDates()
            }
        })
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct ArxivCacheProgressStrip: View {
    var progress: ArxivCacheProgress

    var body: some View {
        HStack(spacing: 10) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .frame(width: 150)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 150)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.title)
                    .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(progress.date)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ArxivPaperCard: View {
    @State private var isHovering = false

    var paper: ArxivFeedPaper
    var enrichment: DiscoverPaperEnrichment?
    var imageURL: URL?
    var thumbnailURLs: [URL]
    var inLibrary: Bool
    var isBusy: Bool
    var downloadProgress: Double?
    var interactionState: DiscoverPaperInteractionState?
    var languageMode: PaperCodexLanguageMode
    var minimumHeight: CGFloat = 0
    var onPreview: () -> Void
    var onSave: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if imageURL != nil || !thumbnailURLs.isEmpty {
                Button {
                    if imageURL != nil {
                        onPreview()
                    } else {
                        onOpen()
                    }
                } label: {
                    if imageURL != nil {
                        ArxivPreviewImage(url: imageURL)
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .clipped()
                    } else {
                        DiscoverPDFThumbnailHero(urls: thumbnailURLs)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .disabled(imageURL == nil && isBusy)
                .help(imageURL == nil ? "Open cached PDF" : "Open image preview")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    metadataRow
                    Spacer()
                    if let interactionState {
                        DiscoverPaperStatusBadge(state: interactionState)
                    }
                }

                Text(primaryTitle)
                    .font(.paperCodexSystem(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !secondaryTitle.isEmpty, secondaryTitle != primaryTitle {
                    Text(secondaryTitle)
                        .font(.paperCodexSystem(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(summaryText)
                    .font(.paperCodexSystem(size: 13.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                if let contribution = enrichment?.contribution,
                   !contribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(contribution)
                        .font(.paperCodexSystem(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = enrichment?.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .lineLimit(3)
                }

                FlowTags(tags: Array(displayTags.prefix(7)))
            }
            .padding(14)
            .padding(.bottom, footerReservedHeight)
            .frame(
                maxWidth: .infinity,
                minHeight: contentMinimumHeight,
                alignment: .topLeading
            )
            .overlay(alignment: .bottomLeading) {
                cardFooter
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.accentColor.opacity(0.36) : Color.black.opacity(0.08), lineWidth: isHovering ? 1.3 : 1)
        )
        .shadow(color: isHovering ? Color.black.opacity(0.15) : Color.black.opacity(0.035), radius: isHovering ? 14 : 2, y: isHovering ? 7 : 1)
        .scaleEffect(isHovering ? 1.008 : 1)
        .offset(y: isHovering ? -1 : 0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }

    private var cardFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 8) {
                ResourceLinkButtons(links: resourceLinks, compact: true)
                Spacer(minLength: 10)
                actionGroup
            }
            VStack(alignment: .leading, spacing: 8) {
                ResourceLinkButtons(links: resourceLinks, compact: true)
                HStack(alignment: .bottom) {
                    Spacer(minLength: 0)
                    actionGroup
                }
            }
        }
    }

    private var actionGroup: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView(value: downloadProgress)
                    .frame(width: 78)
            }
            if inLibrary {
                SavedActionBadge()
            } else {
                SaveActionButton(isBusy: isBusy, action: onSave)
            }
            StableOpenButton(isBusy: isBusy, action: onOpen)
        }
        .fixedSize()
    }

    private var footerReservedHeight: CGFloat {
        38
    }

    private var previewHeight: CGFloat {
        guard imageURL != nil || !thumbnailURLs.isEmpty else {
            return 0
        }
        return imageURL != nil ? 150 : 154
    }

    private var contentMinimumHeight: CGFloat {
        max(0, minimumHeight - previewHeight)
    }

    private var metadataRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                metadataPills
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let similarity = paper.similarity {
                    SimilarityMeter(value: similarity)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                metadataPills
                if let similarity = paper.similarity {
                    SimilarityMeter(value: similarity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataPills: some View {
        HStack(alignment: .center, spacing: 6) {
            MetadataPill(
                title: paper.primaryCategory ?? paper.categories.first ?? "arXiv",
                foreground: .teal,
                background: Color.teal.opacity(0.12)
            )
            ArxivIDPill(id: paper.id)
        }
    }

    private var primaryTitle: String {
        if languageMode.discoverLanguageCode == "zh" {
            if let title = enrichment?.titleZH.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
            return paper.displayTitle(language: "zh")
        }
        return paper.title.en
    }

    private var secondaryTitle: String {
        guard languageMode.discoverLanguageCode == "zh" else {
            return ""
        }
        return paper.title.en
    }

    private var summaryText: String {
        if languageMode.discoverLanguageCode == "zh" {
            if let summary = enrichment?.summaryZH.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                return summary
            }
            if !paper.summary.zh.isEmpty {
                return paper.summary.zh
            }
        }
        if !paper.summary.en.isEmpty {
            return paper.summary.en
        }
        return paper.abstract.en
    }

    private var displayTags: [String] {
        let generated = enrichment?.tags ?? []
        let fallback = paper.tags.isEmpty ? paper.categories : paper.tags
        var seen: Set<String> = []
        var result: [String] = []
        for tag in generated + fallback {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var resourceLinks: [PaperResourceLink] {
        var result = paper.externalLinks
        func append(id: String, title: String, systemImage: String, key: String) {
            guard let value = enrichment?.links[key] else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !result.contains(where: { $0.urlString.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
                return
            }
            result.append(PaperResourceLink(id: id, title: title, systemImage: systemImage, urlString: trimmed))
        }
        append(id: "github-enriched", title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", key: "github")
        append(id: "project-enriched", title: "Project", systemImage: "globe", key: "project")
        append(id: "hf-enriched", title: "HF", systemImage: "shippingbox", key: "hugging_face")
        return result
    }
}

private struct DiscoverCardHeightReporter: View {
    var rowIndex: Int

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DiscoverRowHeightPreferenceKey.self,
                value: [rowIndex: proxy.size.height]
            )
        }
    }
}

private enum DiscoverScrollCoordinateSpace {
    static let name = "discover-scroll"
}

private struct DiscoverVisiblePaperReporter: View {
    var paperID: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DiscoverVisiblePaperPreferenceKey.self,
                value: [paperID: proxy.frame(in: .named(DiscoverScrollCoordinateSpace.name)).minY]
            )
        }
    }
}

private struct DiscoverVisiblePaperPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        for (paperID, minY) in nextValue() {
            value[paperID] = minY
        }
    }
}

private struct DiscoverRowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        for (rowIndex, height) in nextValue() {
            value[rowIndex] = max(value[rowIndex] ?? 0, height)
        }
    }
}

private struct MetadataPill: View {
    var title: String
    var foreground: Color
    var background: Color

    var body: some View {
        Text(title)
            .font(.paperCodexSystem(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 23)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ArxivIDPill: View {
    var id: String

    var body: some View {
        Text(id)
            .font(.paperCodexSystem(size: 12, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 23)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .help("arXiv ID")
    }
}

private struct SavedActionBadge: View {
    var body: some View {
        Label("Saved", systemImage: "checkmark.seal.fill")
            .font(.paperCodexSystem(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(Color(nsColor: .systemGreen))
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .systemGreen).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(nsColor: .systemGreen).opacity(0.34), lineWidth: 1)
                    )
            )
            .help("Already in Library")
            .fixedSize()
            .layoutPriority(1)
    }
}

private struct SaveActionButton: View {
    @State private var isHovering = false

    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add", systemImage: "tray.and.arrow.down")
                .font(.paperCodexSystem(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .foregroundStyle(isBusy ? Color.secondary.opacity(0.6) : (isHovering ? Color(nsColor: .systemGreen) : Color.primary.opacity(0.86)))
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovering && !isBusy ? Color(nsColor: .systemGreen).opacity(0.13) : Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(isHovering && !isBusy ? Color(nsColor: .systemGreen).opacity(0.44) : Color.black.opacity(0.12), lineWidth: 1)
                        )
                )
                .shadow(color: isHovering && !isBusy ? Color(nsColor: .systemGreen).opacity(0.18) : .clear, radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help("Add to Library")
        .fixedSize()
        .layoutPriority(1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct StableOpenButton: View {
    @State private var isHovering = false

    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Open", systemImage: "book")
                .font(.paperCodexSystem(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(isBusy ? Color.gray.opacity(0.55) : (isHovering ? Color(nsColor: .systemBlue).opacity(0.92) : Color(nsColor: .systemBlue)))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .shadow(color: isHovering && !isBusy ? Color(nsColor: .systemBlue).opacity(0.26) : .clear, radius: 8, y: 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.65 : 1)
        .help("Open in reader")
        .fixedSize()
        .layoutPriority(2)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct SimilarityMeter: View {
    var value: Double

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    private var color: Color {
        if clampedValue >= 0.78 {
            return .green
        }
        if clampedValue >= 0.62 {
            return .blue
        }
        return .orange
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.16))
                Capsule()
                    .fill(color)
                    .frame(width: 34 * clampedValue)
            }
            .frame(width: 34, height: 5)
            Text("\(Int((clampedValue * 100).rounded()))%")
                .font(.paperCodexSystem(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Similarity score")
    }
}

@MainActor
private final class DiscoverLocalImageCache {
    static let shared = DiscoverLocalImageCache()

    private let cache = NSCache<NSURL, CachedDiscoverImage>()

    private init() {
        cache.countLimit = 420
        cache.totalCostLimit = 180 * 1024 * 1024
    }

    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)?.image
    }

    func contains(_ url: URL) -> Bool {
        cache.object(forKey: url as NSURL) != nil
    }

    func insert(_ image: CGImage, for url: URL) {
        cache.setObject(
            CachedDiscoverImage(image),
            forKey: url as NSURL,
            cost: image.bytesPerRow * image.height
        )
    }
}

private final class CachedDiscoverImage {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

private struct DecodedDiscoverImage: @unchecked Sendable {
    let image: CGImage
}

private struct LocalCachedImage<Placeholder: View>: View {
    var url: URL
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        if let cached = DiscoverLocalImageCache.shared.image(for: url) {
            image = cached
            return
        }

        let imageURL = url
        guard let decoded = await decodeDiscoverLocalImage(at: imageURL, priority: .userInitiated) else {
            image = nil
            return
        }
        DiscoverLocalImageCache.shared.insert(decoded.image, for: url)
        image = decoded.image
    }
}

private func warmDiscoverLocalImages(_ urls: [URL], limit: Int = 360) async {
    do {
        try await Task.sleep(nanoseconds: 600_000_000)
    } catch {
        return
    }

    var seen: Set<URL> = []
    var warmed = 0

    for url in urls {
        guard !Task.isCancelled, warmed < limit else {
            return
        }
        guard seen.insert(url).inserted else {
            continue
        }
        let isCached = await MainActor.run {
            DiscoverLocalImageCache.shared.contains(url)
        }
        guard !isCached else {
            continue
        }
        guard let decoded = await decodeDiscoverLocalImage(at: url, priority: .utility) else {
            continue
        }
        await MainActor.run {
            DiscoverLocalImageCache.shared.insert(decoded.image, for: url)
        }
        warmed += 1
        do {
            try await Task.sleep(nanoseconds: 8_000_000)
        } catch {
            return
        }
    }
}

private actor DiscoverImageDecodeGate {
    static let shared = DiscoverImageDecodeGate(maxConcurrent: 2)

    private let maxConcurrent: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func wait() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            activeCount = max(0, activeCount - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private func decodeDiscoverLocalImage(at url: URL, priority: TaskPriority) async -> DecodedDiscoverImage? {
    await DiscoverImageDecodeGate.shared.wait()
    if Task.isCancelled {
        await DiscoverImageDecodeGate.shared.signal()
        return nil
    }

    let result = await Task.detached(priority: priority) { () -> DecodedDiscoverImage? in
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 900
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return DecodedDiscoverImage(image: image)
    }.value
    await DiscoverImageDecodeGate.shared.signal()
    return result
}

private struct DiscoverPDFThumbnailHero: View {
    var urls: [URL]

    var body: some View {
        GeometryReader { proxy in
            let visibleURLs = Array(urls.prefix(5))
            let itemCount = max(visibleURLs.count, 1)
            let itemWidth = max(proxy.size.width / CGFloat(itemCount), 1)

            HStack(spacing: 0) {
                ForEach(Array(visibleURLs.enumerated()), id: \.offset) { _, url in
                    LocalCachedImage(url: url, contentMode: .fill) {
                        Color(nsColor: .controlBackgroundColor)
                            .frame(width: itemWidth, height: proxy.size.height)
                    }
                    .frame(width: itemWidth, height: proxy.size.height)
                    .clipped()
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 1)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
        }
        .frame(height: 154)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ArxivPreviewImage: View {
    var url: URL?

    var body: some View {
        Group {
            if let url {
                LocalCachedImage(url: url, contentMode: .fill) {
                    ZStack {
                        Color(nsColor: .separatorColor).opacity(0.22)
                        ProgressView()
                            .controlSize(.small)
                    }
                    .aspectRatio(4.7, contentMode: .fit)
                }
            } else {
                ZStack {
                    Color(nsColor: .separatorColor).opacity(0.22)
                    Image(systemName: "doc.richtext")
                        .font(.paperCodexSystem(size: 24))
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(4.7, contentMode: .fit)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ArxivImagePreviewOverlay: View {
    @EnvironmentObject private var model: AppModel
    var paper: ArxivFeedPaper
    var onDismiss: () -> Void

    private var imageURL: URL? {
        model.cachedArxivAssetURL(for: paper.assets.large) ?? model.cachedArxivAssetURL(for: paper.assets.small)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.56)
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }
            if let imageURL {
                ZoomableImageScrollView(imageURL: imageURL) {
                    onDismiss()
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 24, y: 16)
                .padding(24)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: paper.id) {
            await model.ensureArxivAssetCached(paper.assets.large ?? paper.assets.small)
        }
        .onExitCommand {
            onDismiss()
        }
    }
}

private struct ResourceLinkButtons: View {
    var links: [PaperResourceLink]
    var compact: Bool

    var body: some View {
        if !links.isEmpty {
            HStack(spacing: compact ? 5 : 8) {
                ForEach(links) { link in
                    ResourceLinkButton(link: link, compact: compact)
                }
            }
        }
    }
}

private struct ResourceLinkButton: View {
    @State private var isHovering = false
    var link: PaperResourceLink
    var compact: Bool

    var body: some View {
        Button {
            openExternalURL(link.urlString)
        } label: {
            labelContent
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if compact && isHovering {
                Text(link.title)
                    .font(.paperCodexSystem(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .textBackgroundColor))
                            .shadow(color: Color.black.opacity(0.16), radius: 7, y: 3)
                    )
                    .offset(y: -28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .zIndex(isHovering ? 10 : 0)
        .help("Open \(link.title)")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var labelContent: some View {
        Group {
            if compact {
                Label(link.title, systemImage: link.systemImage)
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            } else {
                Label(link.title, systemImage: link.systemImage)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
        }
        .font(.paperCodexSystem(size: compact ? 11.5 : 13, weight: .semibold))
        .foregroundStyle(isHovering ? Color.accentColor : Color.primary.opacity(0.82))
        .background(buttonBackground)
        .scaleEffect(isHovering ? 1.06 : 1)
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isHovering ? Color.accentColor.opacity(0.13) : Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovering ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct PaperResourceLink: Identifiable {
    var id: String
    var title: String
    var systemImage: String
    var urlString: String
}

private extension ArxivFeedPaper {
    var externalLinks: [PaperResourceLink] {
        var result: [PaperResourceLink] = []
        var seen: Set<String> = []

        func append(id: String, title: String, systemImage: String, urlString: String?) {
            guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let key = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !seen.contains(key) else {
                return
            }
            seen.insert(key)
            result.append(PaperResourceLink(id: id, title: title, systemImage: systemImage, urlString: urlString))
        }

        append(id: "github", title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", urlString: links.github ?? links.code)
        append(id: "project", title: "Project", systemImage: "globe", urlString: links.project)
        append(id: "hf", title: "HF", systemImage: "shippingbox", urlString: links.huggingFace)
        append(id: "arxiv", title: "arXiv", systemImage: "doc.text", urlString: links.abs)
        append(id: "pdf", title: "PDF", systemImage: "doc.richtext", urlString: links.pdf)
        return result
    }
}

private func openExternalURL(_ urlString: String) {
    guard let url = URL(string: urlString) else {
        NSSound.beep()
        return
    }
    if !NSWorkspace.shared.open(url) {
        NSSound.beep()
    }
}

private struct FlowTags: View {
    var tags: [String]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.paperCodexSystem(size: 12))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
