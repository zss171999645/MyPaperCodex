import AppKit
import PaperCodexCore
import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var selectedTag: String?
    @State private var paperPendingSave: ArxivFeedPaper?
    @State private var previewPaper: ArxivFeedPaper?

    private var papers: [ArxivFeedPaper] {
        var result = model.arxivFeed?.papers ?? []
        if let selectedCategory {
            result = result.filter {
                $0.categories.contains(selectedCategory) || $0.listCategories.contains(selectedCategory)
            }
        }
        if let selectedTag {
            result = result.filter { $0.tags.contains(selectedTag) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { paper in
                paper.displayTitle(language: "zh").localizedCaseInsensitiveContains(query)
                    || paper.displayTitle(language: "en").localizedCaseInsensitiveContains(query)
                    || paper.authors.joined(separator: " ").localizedCaseInsensitiveContains(query)
                    || paper.tags.joined(separator: " ").localizedCaseInsensitiveContains(query)
                    || paper.id.localizedCaseInsensitiveContains(query)
            }
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
        Dictionary((model.arxivFeed?.papers ?? []).flatMap(\.tags).map { ($0, 1) }, uniquingKeysWith: +)
    }

    var body: some View {
        ZStack {
            SidebarSplitLayout(minContentWidth: 760) {
                sidebar
            } content: {
                feed
                    .frame(minWidth: 760)
            }
            .onAppear {
                guard model.arxivFeed == nil, !model.isLoadingArxivFeed else {
                    return
                }
                Task {
                    await model.refreshArxivDatesAndFeed()
                }
            }

            if let previewPaper {
                ArxivImagePreviewOverlay(paper: previewPaper) {
                    self.previewPaper = nil
                }
                .environmentObject(model)
                .zIndex(1)
            }
        }
        .sheet(item: $paperPendingSave) { paper in
            SaveToLibrarySheet(
                paperTitle: paper.displayTitle(language: "zh"),
                detail: paper.authors.prefix(4).joined(separator: ", "),
                libraryTags: model.tags,
                suggestedTagNames: model.suggestedTagNames(for: paper),
                onSave: { tagNames in
                    paperPendingSave = nil
                    Task {
                        await model.addArxivPaperToLibrary(paper, selectedTagNames: tagNames)
                    }
                },
                onCancel: {
                    paperPendingSave = nil
                }
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.system(size: 24, weight: .semibold))

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

            Spacer()
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar

            if model.isLoadingArxivFeed {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let gridInset: CGFloat = 12
                    let gridWidth = max(0, proxy.size.width - gridInset * 2)

                    ScrollView {
                        LazyVGrid(
                            columns: gridColumns(for: gridWidth),
                            alignment: .leading,
                            spacing: 14
                        ) {
                            ForEach(papers) { paper in
                                ArxivPaperCard(
                                    paper: paper,
                                    imageURL: model.cachedArxivAssetURL(for: paper.assets.small),
                                    inLibrary: model.libraryPaper(for: paper) != nil,
                                    isBusy: model.isDownloadingArxivPaper(paper),
                                    downloadProgress: model.arxivDownloadProgress(for: paper),
                                    onPreview: {
                                        previewPaper = paper
                                    },
                                    onSave: {
                                        paperPendingSave = paper
                                    },
                                    onOpen: {
                                        Task {
                                            await model.openArxivPaper(paper)
                                        }
                                    }
                                )
                            }
                        }
                        .frame(width: gridWidth, alignment: .leading)
                        .padding(.horizontal, gridInset)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(24)
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let spacing: CGFloat = 14
        let minCardWidth: CGFloat = 420
        let columnCount = max(1, min(3, Int((width + spacing) / (minCardWidth + spacing))))
        let cardWidth = floor((width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
        return Array(
            repeating: GridItem(.fixed(cardWidth), spacing: spacing, alignment: .top),
            count: columnCount
        )
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily arXiv")
                        .font(.system(size: 28, weight: .semibold))
                    Text("\(model.arxivFeed?.count ?? 0) papers · \(model.selectedArxivDate ?? "No date")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Date", selection: Binding(
                    get: { model.selectedArxivDate ?? "" },
                    set: { date in
                        guard !date.isEmpty else {
                            return
                        }
                        Task {
                            await model.loadArxivFeed(date: date)
                        }
                    }
                )) {
                    ForEach(model.arxivDates, id: \.self) { date in
                        Text(date).tag(date)
                    }
                }
                .frame(width: 170)
                Button {
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh")
                Button {
                    model.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .help("Settings")
            }

            HStack(spacing: 10) {
                TextField("Search title, author, tag, arXiv ID", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task {
                        await model.preloadArxivAssets(includeLarge: false)
                    }
                } label: {
                    Label(model.isPreloadingArxivAssets ? "Preloading" : "Preload thumbs", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(model.arxivFeed == nil || model.isPreloadingArxivAssets)
                Button {
                    Task {
                        await model.preloadArxivAssets(includeLarge: true)
                    }
                } label: {
                    Label("Full images", systemImage: "photo.stack")
                }
                .buttonStyle(.bordered)
                .disabled(model.arxivFeed == nil || model.isPreloadingArxivAssets)
            }
        }
    }

    private func navButton(title: String, systemImage: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func filterButton(title: String, detail: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .frame(width: 18)
                Text(title)
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
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct ArxivPaperCard: View {
    private let previewHeight: CGFloat = 180

    var paper: ArxivFeedPaper
    var imageURL: URL?
    var inLibrary: Bool
    var isBusy: Bool
    var downloadProgress: Double?
    var onPreview: () -> Void
    var onSave: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onPreview()
            } label: {
                ArxivPreviewImage(url: imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
            }
            .buttonStyle(.plain)
            .disabled(paper.assets.large == nil && paper.assets.small == nil)
            .help("Open image preview")

            VStack(alignment: .leading, spacing: 10) {
                metadataRow

                Text(paper.displayTitle(language: "zh"))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(paper.title.en)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(paper.displaySummary(language: "zh"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                FlowTags(tags: Array(paper.tags.prefix(5)))

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    ResourceLinkButtons(links: paper.externalLinks, compact: true)
                    if isBusy {
                        ProgressView(value: downloadProgress)
                            .frame(width: 78)
                    }
                    if !inLibrary {
                        SaveActionButton(isBusy: isBusy, action: onSave)
                    }
                    StableOpenButton(isBusy: isBusy, action: onOpen)
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 408, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var metadataRow: some View {
        FlowLayout(spacing: 6) {
            Text(paper.primaryCategory ?? paper.categories.first ?? "arXiv")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.teal.opacity(0.12))
                .foregroundStyle(.teal)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(paper.id)
                .font(.caption)
                .foregroundStyle(.secondary)
            if inLibrary {
                Label("Saved", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let similarity = paper.similarity {
                SimilarityMeter(value: similarity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SaveActionButton: View {
    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 46, height: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isBusy)
        .help("Add to Library")
        .layoutPriority(1)
    }
}

private struct StableOpenButton: View {
    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Open")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 24)
                .background(isBusy ? Color.gray.opacity(0.55) : Color(nsColor: .systemBlue))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.65 : 1)
        .help("Open in reader")
        .fixedSize()
        .layoutPriority(2)
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Similarity score")
    }
}

private struct ArxivPreviewImage: View {
    var url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(nsColor: .separatorColor).opacity(0.22)
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipped()
        .background(Color(nsColor: .windowBackgroundColor))
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
        .font(.system(size: compact ? 11.5 : 13, weight: .semibold))
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
        return
    }
    NSWorkspace.shared.open(url)
}

private struct FlowTags: View {
    var tags: [String]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
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
