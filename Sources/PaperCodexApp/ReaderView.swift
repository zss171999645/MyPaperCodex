import PaperCodexCore
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingSessionPapers = false
    @State private var isShowingSaveToLibrarySheet = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                pdfPane
                    .frame(minWidth: 560)
                ChatView()
                    .frame(minWidth: 330, idealWidth: 420, maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isShowingSaveToLibrarySheet) {
            if let paper = model.selectedPaper {
                SaveToLibrarySheet(
                    paperTitle: paper.title,
                    detail: paper.authors.prefix(4).joined(separator: ", "),
                    libraryTags: model.tags,
                    suggestedTagNames: model.suggestedTagNames(for: paper),
                    onSave: { tagNames in
                        isShowingSaveToLibrarySheet = false
                        model.saveCachedPaperToLibrary(paper, selectedTagNames: tagNames)
                    },
                    onCancel: {
                        isShowingSaveToLibrarySheet = false
                    }
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.goToLibrary()
            } label: {
                Label("Library", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedPaper?.title ?? "Reader")
                    .font(.system(size: 18, weight: .semibold))
                Text(model.selectedPaper?.filePath ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            if let paper = model.selectedPaper, !paper.isSaved {
                Button {
                    isShowingSaveToLibrarySheet = true
                } label: {
                    Label("Save to Library", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                isShowingSessionPapers.toggle()
            } label: {
                Label(sessionPaperCountLabel, systemImage: "rectangle.stack")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isShowingSessionPapers, arrowEdge: .bottom) {
                SessionPapersPopover()
                    .environmentObject(model)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sessionPaperCountLabel: String {
        let count = model.selectedSession?.paperIDs.count ?? 0
        return count == 1 ? "1 Paper" : "\(count) Papers"
    }

    private var pdfPane: some View {
        ZStack {
            if let paper = model.selectedPaper {
                PDFKitView(filePath: paper.filePath, jumpTarget: model.pdfJumpTarget) { selection in
                    model.updateSelection(selection)
                }
            } else {
                ContentUnavailableView("No Paper Selected", systemImage: "doc.text")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct SessionPapersPopover: View {
    @EnvironmentObject private var model: AppModel

    private var sessionPaperIDs: Set<String> {
        Set(model.selectedSession?.paperIDs ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Papers")
                .font(.headline)

            if model.papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text")
                    .frame(width: 320, height: 160)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.papers) { paper in
                            SessionPaperRow(
                                paper: paper,
                                isIncluded: sessionPaperIDs.contains(paper.id),
                                isFocused: model.selectedPaper?.id == paper.id,
                                canRemove: sessionPaperIDs.count > 1
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(width: 360)
                .frame(maxHeight: 360)
            }
        }
        .padding(16)
    }
}

private struct SessionPaperRow: View {
    @EnvironmentObject private var model: AppModel
    var paper: Paper
    var isIncluded: Bool
    var isFocused: Bool
    var canRemove: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(
                get: { isIncluded },
                set: { isOn in
                    model.setPaper(paper, includedInCurrentSession: isOn)
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(isIncluded && !canRemove)

            VStack(alignment: .leading, spacing: 4) {
                Text(paper.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isIncluded {
                Button {
                    model.selectReaderPaper(paper)
                } label: {
                    Image(systemName: isFocused ? "eye.fill" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isFocused ? "Reading" : "Read This Paper")
            }
        }
        .padding(8)
        .background(isFocused ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
