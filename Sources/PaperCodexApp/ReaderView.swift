import PaperCodexCore
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingAddPaperToSessionSheet = false
    @State private var isPDFSplitVisible = false
    @State private var pdfSplitTarget: PDFInternalLinkTarget?
    @State private var pdfKitCommand: PDFKitCommand?

    var body: some View {
        HSplitView {
            pdfPane
                .frame(minWidth: ReaderPDFLayout.minimumPaneWidth, maxWidth: .infinity)
            ChatView()
                .frame(minWidth: 330, idealWidth: 420, maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.selectedPaper?.id) { _, _ in
            isPDFSplitVisible = false
            pdfSplitTarget = nil
            pdfKitCommand = nil
        }
        .onChange(of: model.pdfKitCommand) { _, command in
            guard command != pdfKitCommand else {
                return
            }
            pdfKitCommand = command
        }
        .sheet(isPresented: $isShowingAddPaperToSessionSheet) {
            AddPaperToSessionSheet(
                papers: model.papers.filter { paper in
                    !paper.isArxivImportPlaceholder && !model.currentSessionPapers.contains(where: { $0.id == paper.id })
                },
                onAdd: { paper in
                    model.addPaperToCurrentSession(paper)
                    isShowingAddPaperToSessionSheet = false
                },
                onCancel: {
                    isShowingAddPaperToSessionSheet = false
                }
            )
        }
    }

    private var pdfPane: some View {
        ZStack {
            if let paper = model.selectedPaper {
                VStack(spacing: 0) {
                    ReaderPDFToolbar(
                        status: model.pdfDocumentStatus,
                        papers: model.currentSessionPapers,
                        activePaperID: model.selectedPaper?.id,
                        returnPoint: model.citationReturnPoint,
                        isSplitVisible: isPDFSplitVisible,
                        onSelectPaper: { paper in
                            model.selectReaderPaper(paper)
                        },
                        onAddPaper: {
                            isShowingAddPaperToSessionSheet = true
                        },
                        onRemoveActivePaper: {
                            if let paperID = model.selectedPaper?.id {
                                model.removePaperFromCurrentSession(paperID)
                            }
                        },
                        onCommand: { issuePDFKitCommand($0) },
                        onReturn: { model.returnFromCitationJump() },
                        onToggleSplit: { togglePDFSplit() }
                    )
                    Divider()
                    pdfContent(for: paper)
                }
            } else {
                ContentUnavailableView("No Paper Selected", systemImage: "doc.text")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func pdfContent(for paper: Paper) -> some View {
        if isPDFSplitVisible {
            VSplitView {
                primaryPDFView(for: paper)
                    .frame(minHeight: ReaderPDFLayout.minimumSplitPaneHeight, maxHeight: .infinity)
                secondaryPDFView(for: paper)
                    .frame(minHeight: ReaderPDFLayout.minimumSplitPaneHeight, maxHeight: .infinity)
            }
        } else {
            primaryPDFView(for: paper)
        }
    }

    private func primaryPDFView(for paper: Paper) -> some View {
        PDFKitView(
            filePath: paper.filePath,
            jumpTarget: model.pdfJumpTarget,
            readingContextID: model.readerPositionContextID,
            readingPosition: model.readerPosition,
            command: pdfKitCommand,
            internalLinkTarget: nil,
            onSelection: { selection in
                model.updateSelection(selection)
            },
            onReadingPositionChange: { position in
                model.updateReaderPosition(position)
            },
            onDocumentStatusChange: { status in
                model.updatePDFDocumentStatus(status)
            },
            onInternalLinkSplit: { target in
                openPDFSplit(target)
            }
        )
    }

    private func secondaryPDFView(for paper: Paper) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Link Preview", systemImage: "rectangle.split.2x1")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isPDFSplitVisible = false
                    pdfSplitTarget = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Close Split")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            PDFKitView(
                filePath: paper.filePath,
                jumpTarget: nil,
                readingContextID: "split-\(paper.id)",
                readingPosition: nil,
                command: nil,
                internalLinkTarget: pdfSplitTarget,
                onSelection: { selection in
                    model.updateSelection(selection)
                },
                onReadingPositionChange: { _ in },
                onDocumentStatusChange: { _ in },
                onInternalLinkSplit: { target in
                    openPDFSplit(target)
                }
            )
        }
    }

    private func openPDFSplit(_ target: PDFInternalLinkTarget) {
        pdfSplitTarget = target
        isPDFSplitVisible = true
    }

    private func issuePDFKitCommand(_ kind: PDFKitCommandKind) {
        let command = PDFKitCommand(kind: kind)
        pdfKitCommand = command
        model.pdfKitCommand = command
    }

    private func togglePDFSplit() {
        isPDFSplitVisible.toggle()
        if !isPDFSplitVisible {
            pdfSplitTarget = nil
        }
    }
}

private enum ReaderPDFLayout {
    static let minimumPaneWidth: CGFloat = 360
    static let minimumSplitPaneHeight: CGFloat = 220
}

private struct AddPaperToSessionSheet: View {
    var papers: [Paper]
    var onAdd: (Paper) -> Void
    var onCancel: () -> Void

    @State private var query = ""

    private var filteredPapers: [Paper] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return papers
        }
        return papers.filter { paper in
            paper.title.localizedCaseInsensitiveContains(trimmed)
                || paper.authors.joined(separator: " ").localizedCaseInsensitiveContains(trimmed)
                || (paper.year.map(String.init) ?? "").contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add Paper", systemImage: "plus")
                .font(.title3.weight(.semibold))
            TextField("Search library", text: $query)
                .textFieldStyle(.roundedBorder)
            if filteredPapers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(width: 520, height: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredPapers) { paper in
                            Button {
                                onAdd(paper)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(paper.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 520, height: 280)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

private struct ReaderPDFToolbar: View {
    var status: PDFDocumentStatus?
    var papers: [Paper]
    var activePaperID: String?
    var returnPoint: CitationReturnPoint?
    var isSplitVisible: Bool
    var onSelectPaper: (Paper) -> Void
    var onAddPaper: () -> Void
    var onRemoveActivePaper: () -> Void
    var onCommand: (PDFKitCommandKind) -> Void
    var onReturn: () -> Void
    var onToggleSplit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onCommand(.previousPage)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Previous Page")
            .accessibilityLabel("Previous Page")

            Button {
                onCommand(.nextPage)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Next Page")
            .accessibilityLabel("Next Page")

            Text(pageText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            Divider()
                .frame(height: 18)

            Button {
                onCommand(.zoomOut)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Zoom Out")
            .accessibilityLabel("Zoom Out")

            Button {
                onCommand(.zoomIn)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Zoom In")
            .accessibilityLabel("Zoom In")

            Button {
                onCommand(.fitWidth)
            } label: {
                Image(systemName: "arrow.left.and.right")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Fit Width")
            .accessibilityLabel("Fit Width")

            Text(zoomText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

            Divider()
                .frame(height: 18)

            paperSelector

            Button(action: onToggleSplit) {
                Image(systemName: isSplitVisible ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isSplitVisible ? Color.accentColor : Color.primary)
            .help(isSplitVisible ? "Close PDF Split" : "Open PDF Split")
            .accessibilityLabel(isSplitVisible ? "Close PDF Split" : "Open PDF Split")

            Spacer()

            if let returnPoint {
                Button(action: onReturn) {
                    Label("Back to source", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(returnPoint.paperTitle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var paperSelector: some View {
        HStack(spacing: 5) {
            Image(systemName: papers.count > 1 ? "square.stack.3d.up.fill" : "doc.text")
                .font(.paperCodexSystem(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(papers.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .leading)

            Picker("Paper", selection: selectedPaperBinding) {
                ForEach(papers) { paper in
                    Text(paper.title)
                        .tag(paper.id)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(minWidth: 130, idealWidth: 220, maxWidth: 260)
            .help(activePaperTitle)

            Button(action: onAddPaper) {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Add Paper")
            .accessibilityLabel("Add Paper")

            Button(action: onRemoveActivePaper) {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(papers.count <= 1)
            .opacity(papers.count > 1 ? 1 : 0.35)
            .help("Remove Current Paper")
            .accessibilityLabel("Remove Current Paper")
        }
        .layoutPriority(1)
    }

    private var selectedPaperBinding: Binding<String> {
        Binding(
            get: {
                activePaperID ?? ""
            },
            set: { paperID in
                guard let paper = papers.first(where: { $0.id == paperID }) else {
                    return
                }
                onSelectPaper(paper)
            }
        )
    }

    private var activePaperTitle: String {
        guard let activePaperID,
              let paper = papers.first(where: { $0.id == activePaperID }) else {
            return "Select Paper"
        }
        return paper.title
    }

    private var pageText: String {
        guard let status, status.pageCount > 0 else {
            return "Page --"
        }
        return "Page \(status.pageIndex + 1)/\(status.pageCount)"
    }

    private var zoomText: String {
        guard let status else {
            return "--%"
        }
        return "\(Int((status.scaleFactor * 100).rounded()))%"
    }
}
