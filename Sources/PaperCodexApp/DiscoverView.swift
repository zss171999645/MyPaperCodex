import AppKit
import PaperCodexCore
import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var paperPendingSave: ArxivFeedPaper?

    private var papers: [ArxivFeedPaper] {
        var result = model.arxivFeed?.papers ?? []
        if let selectedCategory {
            result = result.filter {
                $0.categories.contains(selectedCategory) || $0.listCategories.contains(selectedCategory)
            }
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

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
            feed
                .frame(minWidth: 760)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard model.arxivFeed == nil, !model.isLoadingArxivFeed else {
                return
            }
            Task {
                await model.refreshArxivDatesAndFeed()
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
                filterButton(title: "All", selected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(categories, id: \.self) { category in
                    filterButton(title: category, selected: selectedCategory == category) {
                        selectedCategory = category
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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(papers) { paper in
                            ArxivPaperCard(
                                paper: paper,
                                imageURL: model.cachedArxivAssetURL(for: paper.assets.small),
                                inLibrary: model.libraryPaper(for: paper) != nil,
                                isBusy: model.isDownloadingArxivPaper(paper),
                                downloadProgress: model.arxivDownloadProgress(for: paper),
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
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(24)
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

    private func filterButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer()
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
    var paper: ArxivFeedPaper
    var imageURL: URL?
    var inLibrary: Bool
    var isBusy: Bool
    var downloadProgress: Double?
    var onSave: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ArxivPreviewImage(url: imageURL)
                    .frame(width: 164, height: 112)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
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
                        if let groupLabel {
                            Text(groupLabel)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(groupColor.opacity(0.12))
                                .foregroundStyle(groupColor)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if let similarity = paper.similarity {
                            Text("\(Int((similarity * 100).rounded()))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Text(paper.displayTitle(language: "zh"))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text(paper.title.en)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(paper.displaySummary(language: "zh"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                FlowTags(tags: Array(paper.tags.prefix(5)))
                Spacer(minLength: 8)
                if isBusy {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: downloadProgress)
                            .frame(width: 120)
                        Text("Downloading")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    onSave()
                } label: {
                    Label(inLibrary ? "Saved" : "Add", systemImage: inLibrary ? "checkmark" : "plus")
                }
                .buttonStyle(.bordered)
                .disabled(inLibrary || isBusy)
                Button {
                    onOpen()
                } label: {
                    Label("Open", systemImage: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 168, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var groupLabel: String? {
        switch paper.filterGroup {
        case "white":
            "Whitelist"
        case "black":
            "Blacklist"
        default:
            nil
        }
    }

    private var groupColor: Color {
        paper.filterGroup == "black" ? .red : .blue
    }
}

private struct ArxivPreviewImage: View {
    var url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
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
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
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
