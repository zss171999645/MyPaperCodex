import PaperCodexCore
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingSaveToLibrarySheet = false

    var body: some View {
        VStack(spacing: 0) {
            ReaderTabBar {
                isShowingSaveToLibrarySheet = true
            }
                .environmentObject(model)
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

    private var pdfPane: some View {
        ZStack {
            if let paper = model.selectedPaper {
                VStack(spacing: 0) {
                    ReaderPDFToolbar(
                        status: model.pdfDocumentStatus,
                        returnPoint: model.citationReturnPoint,
                        onCommand: { model.sendPDFKitCommand($0) },
                        onReturn: { model.returnFromCitationJump() }
                    )
                    Divider()
                    PDFKitView(
                        filePath: paper.filePath,
                        jumpTarget: model.pdfJumpTarget,
                        readingContextID: model.readerPositionContextID,
                        readingPosition: model.readerPosition,
                        command: model.pdfKitCommand,
                        onSelection: { selection in
                            model.updateSelection(selection)
                        },
                        onReadingPositionChange: { position in
                            model.updateReaderPosition(position)
                        },
                        onDocumentStatusChange: { status in
                            model.updatePDFDocumentStatus(status)
                        }
                    )
                }
            } else {
                ContentUnavailableView("No Paper Selected", systemImage: "doc.text")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ReaderPDFToolbar: View {
    var status: PDFDocumentStatus?
    var returnPoint: CitationReturnPoint?
    var onCommand: (PDFKitCommandKind) -> Void
    var onReturn: () -> Void

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
                    .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 13, weight: .semibold))
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                    Text(tab.title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
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
                    .font(.system(size: 10, weight: .bold))
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
