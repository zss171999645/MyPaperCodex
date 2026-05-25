import PaperCodexCore
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingSaveToLibrarySheet = false
    @State private var isShowingAddPaperToSessionSheet = false
    @State private var isPDFSplitVisible = false
    @State private var pdfSplitTarget: PDFInternalLinkTarget?

    var body: some View {
        VStack(spacing: 0) {
            ReaderTabBar {
                isShowingSaveToLibrarySheet = true
            }
                .environmentObject(model)
            Divider()
            HSplitView {
                pdfPane
                    .frame(minWidth: ReaderPDFLayout.minimumPaneWidth, maxWidth: .infinity)
                ChatView()
                    .frame(minWidth: 330, idealWidth: 420, maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.selectedPaper?.id) { _, _ in
            isPDFSplitVisible = false
            pdfSplitTarget = nil
        }
        .sheet(isPresented: $isShowingSaveToLibrarySheet) {
            if let paper = model.selectedPaper {
                SaveToLibrarySheet(
                    paperTitle: paper.title,
                    detail: paper.authors.prefix(4).joined(separator: ", "),
                    libraryCategories: model.categories,
                    initialCategoryIDs: model.paperCategoryIDsByID[paper.id, default: []],
                    onSave: { selection in
                        isShowingSaveToLibrarySheet = false
                        model.saveCachedPaperToLibrary(
                            paper,
                            selectedCategoryIDs: selection.categoryIDs,
                            newCategoryNames: selection.newCategoryNames,
                            newCategories: selection.newCategories
                        )
                    },
                    onCancel: {
                        isShowingSaveToLibrarySheet = false
                    }
                )
            }
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
                        returnPoint: model.citationReturnPoint,
                        isSplitVisible: isPDFSplitVisible,
                        onCommand: { model.sendPDFKitCommand($0) },
                        onReturn: { model.returnFromCitationJump() },
                        onToggleSplit: { togglePDFSplit() }
                    )
                    ReaderPaperTabStrip(
                        papers: model.currentSessionPapers,
                        activePaperID: model.selectedPaper?.id,
                        onSelect: { paper in
                            model.selectReaderPaper(paper)
                        },
                        onAdd: {
                            isShowingAddPaperToSessionSheet = true
                        },
                        onRemove: { paperID in
                            model.removePaperFromCurrentSession(paperID)
                        }
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
            command: model.pdfKitCommand,
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

private struct ReaderPaperTabStrip: View {
    var papers: [Paper]
    var activePaperID: String?
    var onSelect: (Paper) -> Void
    var onAdd: () -> Void
    var onRemove: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label("\(papers.count)", systemImage: papers.count > 1 ? "square.stack.3d.up.fill" : "doc.text")
                .labelStyle(.iconOnly)
                .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 30)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .help("\(papers.count) papers in this reading set")

            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(papers) { paper in
                        ReaderPaperTabChip(
                            paper: paper,
                            isActive: paper.id == activePaperID,
                            canRemove: papers.count > 1,
                            onSelect: {
                                onSelect(paper)
                            },
                            onRemove: {
                                onRemove(paper.id)
                            }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.paperCodexSystem(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .help("Add Paper")
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 0)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ReaderPaperTabChip: View {
    @State private var isHovering = false

    var paper: Paper
    var isActive: Bool
    var canRemove: Bool
    var onSelect: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Image(systemName: isActive ? "doc.text.fill" : "doc.text")
                        .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    Text(paper.title)
                        .font(.paperCodexSystem(size: 12.5, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, 10)
                .padding(.trailing, canRemove ? 5 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(paper.title)

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.paperCodexSystem(size: 9.5, weight: .bold))
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.secondary : Color.secondary.opacity(0.62))
                .opacity(isActive || isHovering ? 1 : 0.42)
                .padding(.trailing, 6)
                .help("Close Paper Tab")
            }
        }
        .frame(width: isActive ? 238 : 188, height: 34)
        .background(paperTabBackground)
        .overlay(alignment: .top) {
            paperTabAccent
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(paperTabBorder, lineWidth: isActive ? 1.1 : 0.8)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8
            )
        )
        .shadow(
            color: isActive ? Color.black.opacity(0.09) : Color.clear,
            radius: 4,
            x: 0,
            y: 1
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var paperTabAccent: some View {
        Capsule()
            .fill(isActive ? Color.accentColor : Color.clear)
            .frame(height: 3)
            .padding(.horizontal, 10)
            .padding(.top, 2)
    }

    private var paperTabBackground: Color {
        if isActive {
            return Color(nsColor: .textBackgroundColor)
        }
        return isHovering ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor)
    }

    private var paperTabBorder: Color {
        if isActive {
            return Color.accentColor.opacity(0.36)
        }
        return isHovering ? Color.primary.opacity(0.14) : Color.primary.opacity(0.07)
    }
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
    var returnPoint: CitationReturnPoint?
    var isSplitVisible: Bool
    var onCommand: (PDFKitCommandKind) -> Void
    var onReturn: () -> Void
    var onToggleSplit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onCommand(.previousPage)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Previous Page")
            .accessibilityLabel("Previous Page")

            Button {
                onCommand(.nextPage)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Next Page")
            .accessibilityLabel("Next Page")

            Text(pageText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 86, alignment: .leading)

            Divider()
                .frame(height: 18)

            Button {
                onCommand(.zoomOut)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Zoom Out")
            .accessibilityLabel("Zoom Out")

            Button {
                onCommand(.zoomIn)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Zoom In")
            .accessibilityLabel("Zoom In")

            Button {
                onCommand(.fitWidth)
            } label: {
                Image(systemName: "arrow.left.and.right")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Fit Width")
            .accessibilityLabel("Fit Width")

            Text(zoomText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, alignment: .leading)

            Button(action: onToggleSplit) {
                Image(systemName: isSplitVisible ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .frame(width: 28, height: 24)
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

private struct ReaderTabBar: View {
    @EnvironmentObject private var model: AppModel
    var onShowSaveToLibrary: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.returnFromReader()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.paperCodexSystem(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .help("Back")

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.readerTabState.tabs) { tab in
                        ReaderTabItem(
                            tab: tab,
                            isActive: model.selectedPaper?.id == tab.paperID
                                || model.readerTabState.activePaperID == tab.paperID
                        )
                    }
                }
                .padding(.vertical, 7)
            }
            .scrollIndicators(.hidden)

            if let paper = model.selectedPaper, !paper.isSaved {
                Button {
                    onShowSaveToLibrary()
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.paperCodexSystem(size: 13, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help("Save to Library")
            }
        }
        .padding(.horizontal, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ReaderTabItem: View {
    @EnvironmentObject private var model: AppModel
    var tab: ReaderPaperTab
    var isActive: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.selectReaderTab(tab)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isActive ? "doc.text.fill" : "doc.text")
                        .font(.paperCodexSystem(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                    Text(tab.title)
                        .font(.paperCodexSystem(size: 13, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !tab.isSaved {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .help("Cached paper")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tab.detail.isEmpty ? tab.title : "\(tab.title)\n\(tab.detail)")

            Button {
                model.closeReaderTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.paperCodexSystem(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? Color.secondary : Color.secondary.opacity(0.58))
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: isActive ? 268 : 224, height: 34)
        .background(tabBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tabBorder, lineWidth: isActive ? 1.1 : 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(
            color: isHovering ? Color.black.opacity(0.12) : Color.black.opacity(0.04),
            radius: isHovering ? 6 : 2,
            x: 0,
            y: isHovering ? 2 : 1
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var tabBackground: Color {
        if isActive {
            return Color(nsColor: .textBackgroundColor)
        }
        return isHovering ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor)
    }

    private var tabBorder: Color {
        if isActive {
            return Color.accentColor.opacity(0.38)
        }
        return isHovering ? Color.primary.opacity(0.16) : Color.primary.opacity(0.08)
    }
}
