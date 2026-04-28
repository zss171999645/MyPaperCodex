import AppKit
import PaperCodexCore
import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var draftBaseURL = ""
    @State private var draftToken = ""

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
            HSplitView {
                feedList
                    .frame(minWidth: 520)
                detailPane
                    .frame(minWidth: 340, idealWidth: 400, maxWidth: 480)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            draftBaseURL = model.arxivFeedBaseURL
            draftToken = model.arxivFeedToken
            guard model.arxivFeed == nil, !model.isLoadingArxivFeed else {
                return
            }
            Task {
                await model.refreshArxivDatesAndFeed()
            }
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
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("Server", systemImage: "server.rack")
                    .font(.headline)
                TextField("Base URL", text: $draftBaseURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API token", text: $draftToken)
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.setArxivFeedConnection(baseURL: draftBaseURL, token: draftToken)
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                } label: {
                    Label("Connect", systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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

    private var feedList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily arXiv")
                        .font(.system(size: 28, weight: .semibold))
                    Text(model.selectedArxivDate ?? "No date selected")
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
            }

            HStack(spacing: 10) {
                TextField("Search title, author, tag", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task {
                        await model.preloadArxivAssets(includeLarge: false)
                    }
                } label: {
                    Label(model.isPreloadingArxivAssets ? "Preloading" : "Preload", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(model.arxivFeed == nil || model.isPreloadingArxivAssets)
                Button {
                    Task {
                        await model.preloadArxivAssets(includeLarge: true)
                    }
                } label: {
                    Label("Full", systemImage: "photo.stack")
                }
                .buttonStyle(.bordered)
                .disabled(model.arxivFeed == nil || model.isPreloadingArxivAssets)
            }

            if model.isLoadingArxivFeed {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(papers) { paper in
                            ArxivPaperCard(
                                paper: paper,
                                imageURL: model.cachedArxivAssetURL(for: paper.assets.small),
                                selected: model.selectedArxivPaper?.id == paper.id,
                                inLibrary: model.libraryPaper(for: paper) != nil
                            ) {
                                model.selectedArxivPaper = paper
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview")
                .font(.system(size: 20, weight: .semibold))

            if let paper = model.selectedArxivPaper {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ArxivPreviewImage(url: model.cachedArxivAssetURL(for: paper.assets.large) ?? model.cachedArxivAssetURL(for: paper.assets.small))
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)

                        VStack(alignment: .leading, spacing: 7) {
                            Text(paper.displayTitle(language: "zh"))
                                .font(.headline)
                            if paper.title.en != paper.title.zh {
                                Text(paper.title.en)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(paper.authors.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            if let existing = model.libraryPaper(for: paper) {
                                Button {
                                    model.openPaper(existing)
                                } label: {
                                    Label("Read in Library", systemImage: "book")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button {
                                    Task {
                                        await model.addArxivPaperToLibrary(paper)
                                    }
                                } label: {
                                    Label(model.isAddingArxivPaper ? "Adding" : "Add to Library", systemImage: "plus.square.on.square")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isAddingArxivPaper)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Summary")
                                .font(.subheadline.weight(.semibold))
                            Text(paper.displaySummary(language: "zh"))
                                .font(.body)
                            if !paper.summary.en.isEmpty, paper.summary.en != paper.summary.zh {
                                Text(paper.summary.en)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        metadataGrid(for: paper)
                    }
                    .padding(.trailing, 4)
                }
            } else {
                ContentUnavailableView("Select Paper", systemImage: "sidebar.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func metadataGrid(for paper: ArxivFeedPaper) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            metadataRow("arXiv", paper.id)
            metadataRow("Published", paper.published ?? "Unknown")
            metadataRow("Primary", paper.primaryCategory ?? "Unknown")
            if !paper.tags.isEmpty {
                FlowTags(tags: paper.tags)
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
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
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct ArxivPaperCard: View {
    var paper: ArxivFeedPaper
    var imageURL: URL?
    var selected: Bool
    var inLibrary: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                ArxivPreviewImage(url: imageURL)
                    .frame(width: 132, height: 82)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(paper.primaryCategory ?? paper.categories.first ?? "arXiv")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.teal.opacity(0.12))
                            .foregroundStyle(.teal)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        if inLibrary {
                            Label("Library", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                    }
                    Text(paper.displayTitle(language: "zh"))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text(paper.displaySummary(language: "zh"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    FlowTags(tags: Array(paper.tags.prefix(6)))
                }
            }
            .padding(10)
            .background(selected ? Color.accentColor.opacity(0.11) : Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
