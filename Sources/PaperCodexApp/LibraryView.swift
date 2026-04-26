import PaperCodexCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isImporting = false
    @State private var searchText = ""

    private var filteredPapers: [Paper] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return model.papers
        }
        return model.papers.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.authors.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
            paperList
                .frame(minWidth: 680)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                model.importPDF(from: url)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.system(size: 24, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Label("Categories", systemImage: "folder")
                    .font(.headline)
                if model.categories.isEmpty {
                    Text("No categories yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.categories) { category in
                        Text(category.name)
                            .padding(.vertical, 5)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Tags", systemImage: "tag")
                    .font(.headline)
                Text("Tags are added manually from imported papers.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var paperList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Library")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label("Import PDF", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            TextField("Search title or author", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15))

            if filteredPapers.isEmpty {
                ContentUnavailableView(
                    "No Papers",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Import a text-layer PDF to create its local index and start a Codex-backed reading session.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredPapers) { paper in
                            Button {
                                model.openPaper(paper)
                            } label: {
                                PaperRow(paper: paper)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
    }
}

private struct PaperRow: View {
    var paper: Paper

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 22))
                .foregroundStyle(.blue)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(paper.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                Text(paper.filePath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
