import PDFKit
import PaperCodexCore
import SwiftUI

fileprivate final class CitationAwarePDFView: PDFView {
    var onMouseDown: ((CitationAwarePDFView, NSEvent) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        if onMouseDown?(self, event) == true {
            return
        }
        super.mouseDown(with: event)
    }
}

struct PDFViewportPosition: Equatable {
    var pageIndex: Int
    var pagePointX: Double
    var pagePointY: Double
    var scaleFactor: Double

    func isMeaningfullyDifferent(from other: PDFViewportPosition?) -> Bool {
        guard let other else {
            return true
        }
        return pageIndex != other.pageIndex
            || abs(pagePointX - other.pagePointX) > 8
            || abs(pagePointY - other.pagePointY) > 8
            || abs(scaleFactor - other.scaleFactor) > 0.01
    }
}

struct PDFKitView: NSViewRepresentable {
    var filePath: String
    var jumpTarget: PDFJumpTarget?
    var readingContextID: String?
    var readingPosition: PaperReaderPosition?
    var command: PDFKitCommand?
    var onSelection: (PDFSelectionInfo?) -> Void
    var onReadingPositionChange: (PDFViewportPosition) -> Void
    var onDocumentStatusChange: (PDFDocumentStatus) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelection: onSelection,
            onReadingPositionChange: onReadingPositionChange,
            onDocumentStatusChange: onDocumentStatusChange
        )
    }

    func makeNSView(context: Context) -> PDFView {
        let view = CitationAwarePDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .textBackgroundColor
        let coordinator = context.coordinator
        view.onMouseDown = { [weak coordinator] pdfView, event in
            coordinator?.handlePDFMouseDown(in: pdfView, event: event) ?? false
        }
        context.coordinator.pdfView = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        loadDocument(in: view)
        context.coordinator.documentDidLoad()
        let readingContextID = readingContextID
        let readingPosition = readingPosition
        DispatchQueue.main.async {
            coordinator.attachScrollObservation(to: view)
            coordinator.applyReadingPosition(readingPosition, contextID: readingContextID)
            coordinator.reportDocumentStatus()
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL?.path != filePath {
            loadDocument(in: nsView)
            context.coordinator.documentDidLoad()
            let coordinator = context.coordinator
            let readingContextID = readingContextID
            DispatchQueue.main.async {
                coordinator.attachScrollObservation(to: nsView)
                coordinator.applyReadingPosition(readingPosition, contextID: readingContextID)
            }
        }
        context.coordinator.onSelection = onSelection
        context.coordinator.onReadingPositionChange = onReadingPositionChange
        context.coordinator.onDocumentStatusChange = onDocumentStatusChange
        context.coordinator.applyReadingPosition(readingPosition, contextID: readingContextID)
        context.coordinator.applyJumpTarget(jumpTarget)
        context.coordinator.applyCommand(command)
    }

    private func loadDocument(in view: PDFView) {
        view.document = PDFDocument(url: URL(fileURLWithPath: filePath))
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var onSelection: (PDFSelectionInfo?) -> Void
        var onReadingPositionChange: (PDFViewportPosition) -> Void
        var onDocumentStatusChange: (PDFDocumentStatus) -> Void
        private var highlightedAnnotations: [(PDFPage, PDFAnnotation)] = []
        private var lastJumpTarget: PDFJumpTarget?
        private var lastAppliedReadingContext: String?
        private var lastAppliedCommand: PDFKitCommand?
        private var lastReportedStatus: PDFDocumentStatus?
        private var lastReportedPosition: PDFViewportPosition?
        private weak var observedClipView: NSClipView?
        private var pendingViewportReport: DispatchWorkItem?
        private var isApplyingReadingPosition = false
        private var referenceResolver = PDFReferenceResolver(pageTexts: [:])
        private var citationPopover: NSPopover?

        init(
            onSelection: @escaping (PDFSelectionInfo?) -> Void,
            onReadingPositionChange: @escaping (PDFViewportPosition) -> Void,
            onDocumentStatusChange: @escaping (PDFDocumentStatus) -> Void
        ) {
            self.onSelection = onSelection
            self.onReadingPositionChange = onReadingPositionChange
            self.onDocumentStatusChange = onDocumentStatusChange
        }

        deinit {
            pendingViewportReport?.cancel()
            NotificationCenter.default.removeObserver(self)
        }

        @MainActor
        func documentDidLoad() {
            lastJumpTarget = nil
            lastAppliedReadingContext = nil
            lastAppliedCommand = nil
            lastReportedStatus = nil
            lastReportedPosition = nil
            referenceResolver = Self.makeReferenceResolver(from: pdfView?.document)
            citationPopover?.close()
            citationPopover = nil
            clearHighlights()
            detachScrollObservation()
        }

        @MainActor
        func attachScrollObservation(to pdfView: PDFView) {
            guard let scrollView = findScrollView(in: pdfView) else {
                return
            }
            let clipView = scrollView.contentView
            guard observedClipView !== clipView else {
                return
            }
            detachScrollObservation()
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(viewportChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }

        @MainActor
        func detachScrollObservation() {
            if let observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedClipView
                )
            }
            observedClipView = nil
        }

        @MainActor
        func applyReadingPosition(_ position: PaperReaderPosition?, contextID: String?) {
            let contextKey = contextID ?? position.map { "\($0.sessionID)|\($0.paperID)" }
            guard let contextKey else {
                lastAppliedReadingContext = nil
                return
            }
            guard let position else {
                return
            }
            guard contextKey != lastAppliedReadingContext else {
                return
            }
            lastAppliedReadingContext = contextKey
            applyViewportPosition(position)
        }

        @MainActor
        func applyCommand(_ command: PDFKitCommand?) {
            guard let command, command != lastAppliedCommand, let pdfView else {
                return
            }
            lastAppliedCommand = command
            switch command.kind {
            case .zoomIn:
                pdfView.autoScales = false
                pdfView.scaleFactor = min(pdfView.scaleFactor * 1.18, pdfView.maxScaleFactor)
            case .zoomOut:
                pdfView.autoScales = false
                pdfView.scaleFactor = max(pdfView.scaleFactor / 1.18, pdfView.minScaleFactor)
            case .fitWidth:
                pdfView.autoScales = true
                pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
            case .fitPage:
                pdfView.autoScales = true
                pdfView.displayMode = .singlePage
                DispatchQueue.main.async {
                    pdfView.displayMode = .singlePageContinuous
                }
            case .previousPage:
                pdfView.goToPreviousPage(nil)
            case .nextPage:
                pdfView.goToNextPage(nil)
            case .restorePosition(let position):
                lastAppliedReadingContext = "\(position.sessionID)|\(position.paperID)"
                applyViewportPosition(position)
                return
            }
            scheduleViewportReport()
            reportDocumentStatus()
        }

        @MainActor
        private func applyViewportPosition(_ position: PaperReaderPosition) {
            guard let pdfView,
                  let document = pdfView.document,
                  document.pageCount > 0 else {
                return
            }
            let pageIndex = min(max(position.pageIndex, 0), document.pageCount - 1)
            guard let page = document.page(at: pageIndex) else {
                return
            }

            isApplyingReadingPosition = true
            if position.scaleFactor.isFinite, position.scaleFactor > 0 {
                pdfView.autoScales = false
                pdfView.scaleFactor = CGFloat(position.scaleFactor)
            }
            let point = NSPoint(x: position.pagePointX, y: position.pagePointY)
            pdfView.go(to: PDFDestination(page: page, at: point))
            DispatchQueue.main.async { [weak self] in
                self?.isApplyingReadingPosition = false
                self?.scheduleViewportReport()
                self?.reportDocumentStatus()
            }
        }

        @MainActor
        func applyJumpTarget(_ target: PDFJumpTarget?) {
            guard target != lastJumpTarget else {
                return
            }
            lastJumpTarget = target
            clearHighlights()

            guard let target,
                  let pdfView,
                  let document = pdfView.document,
                  let page = document.page(at: target.page - 1) else {
                return
            }

            let boxes = target.bboxList.filter { $0.width > 0 && $0.height > 0 }
            for box in boxes {
                let annotation = PDFAnnotation(
                    bounds: CGRect(x: box.x, y: box.y, width: box.width, height: box.height),
                    forType: .highlight,
                    withProperties: nil
                )
                annotation.color = NSColor.systemYellow.withAlphaComponent(0.45)
                page.addAnnotation(annotation)
                highlightedAnnotations.append((page, annotation))
            }

            if boxes.isEmpty {
                pdfView.go(to: page)
            } else {
                centerJumpTarget(on: page, boxes: boxes)
            }
            scheduleViewportReport()
            reportDocumentStatus()
        }

        @MainActor
        private func centerJumpTarget(on page: PDFPage, boxes: [BoundingBox]) {
            guard let targetRect = unionRect(for: boxes), let pdfView else {
                return
            }
            let targetPoint = NSPoint(x: targetRect.midX, y: targetRect.midY)
            pdfView.go(to: PDFDestination(page: page, at: targetPoint))
            centerPDFPagePointInViewport(targetPoint, page: page)
            DispatchQueue.main.async { [weak self] in
                self?.centerPDFPagePointInViewport(targetPoint, page: page)
                self?.scheduleViewportReport()
            }
        }

        private func unionRect(for boxes: [BoundingBox]) -> CGRect? {
            let rects = boxes.map { box in
                CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
            }
            guard let first = rects.first else {
                return nil
            }
            return rects.dropFirst().reduce(first) { partialResult, rect in
                partialResult.union(rect)
            }
        }

        @MainActor
        private func centerPDFPagePointInViewport(_ pagePoint: NSPoint, page: PDFPage) {
            guard let pdfView,
                  let documentView = pdfView.documentView,
                  let scrollView = findScrollView(in: pdfView) else {
                return
            }
            let clipView = scrollView.contentView
            let targetInPDFView = pdfView.convert(pagePoint, from: page)
            let targetInDocumentView = documentView.convert(targetInPDFView, from: pdfView)
            let boundedOrigin = boundedClipOrigin(
                centeredOn: targetInDocumentView,
                clipSize: clipView.bounds.size,
                documentBounds: documentView.bounds
            )
            clipView.scroll(to: boundedOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }

        private func boundedClipOrigin(centeredOn point: NSPoint, clipSize: NSSize, documentBounds: NSRect) -> NSPoint {
            let minX = documentBounds.minX
            let minY = documentBounds.minY
            let maxX = max(minX, documentBounds.maxX - clipSize.width)
            let maxY = max(minY, documentBounds.maxY - clipSize.height)
            return NSPoint(
                x: min(max(point.x - clipSize.width / 2, minX), maxX),
                y: min(max(point.y - clipSize.height / 2, minY), maxY)
            )
        }

        @MainActor
        func clearHighlights() {
            for (page, annotation) in highlightedAnnotations {
                page.removeAnnotation(annotation)
            }
            highlightedAnnotations.removeAll()
        }

        @MainActor
        fileprivate func handlePDFMouseDown(in pdfView: CitationAwarePDFView, event: NSEvent) -> Bool {
            guard event.clickCount == 1,
                  event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else {
                return false
            }
            let viewPoint = pdfView.convert(event.locationInWindow, from: nil)
            guard let page = pdfView.page(for: viewPoint, nearest: false) ?? pdfView.page(for: viewPoint, nearest: true),
                  let document = pdfView.document else {
                closeCitationPopover()
                return false
            }
            let pageNumber = document.index(for: page) + 1
            guard pageNumber > 0 else {
                closeCitationPopover()
                return false
            }
            let pagePoint = pdfView.convert(viewPoint, to: page)
            let clickedLine = page.selectionForLine(at: pagePoint)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !clickedLine.isEmpty else {
                closeCitationPopover()
                return false
            }

            if let entry = referenceResolver.referenceEntry(containingLine: clickedLine, page: pageNumber) {
                showReferenceCard(entry, at: viewPoint, in: pdfView)
                return true
            }
            guard let clickedText = page.selectionForWord(at: pagePoint)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !clickedText.isEmpty else {
                closeCitationPopover()
                return false
            }
            if let preview = referenceResolver.preview(forLine: clickedLine, clickedText: clickedText, page: pageNumber) {
                showCitationPreviewPopover(preview, at: viewPoint, in: pdfView)
                return true
            }
            closeCitationPopover()
            return false
        }

        @MainActor
        private func showCitationPreviewPopover(_ preview: PDFCitationPreview, at point: NSPoint, in pdfView: PDFView) {
            showPopover(
                at: point,
                in: pdfView,
                contentSize: NSSize(width: 380, height: preview.references.isEmpty ? 118 : 220),
                rootView: InTextCitationPreview(preview: preview)
            )
        }

        @MainActor
        private func showReferenceCard(_ entry: PDFReferenceEntry, at point: NSPoint, in pdfView: PDFView) {
            showPopover(
                at: point,
                in: pdfView,
                contentSize: NSSize(width: 420, height: 230),
                rootView: ReferenceEntryCard(entry: entry)
            )
        }

        @MainActor
        private func showPopover<Content: View>(
            at point: NSPoint,
            in pdfView: PDFView,
            contentSize: NSSize,
            rootView: Content
        ) {
            closeCitationPopover()
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = contentSize
            popover.contentViewController = NSHostingController(rootView: rootView)
            let anchor = NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)
            popover.show(relativeTo: anchor, of: pdfView, preferredEdge: .maxX)
            citationPopover = popover
        }

        @MainActor
        private func closeCitationPopover() {
            citationPopover?.close()
            citationPopover = nil
        }

        @MainActor
        @objc func selectionChanged(_ notification: Notification) {
            guard let pdfView,
                  let selection = pdfView.currentSelection,
                  let document = pdfView.document else {
                onSelection(nil)
                return
            }

            guard let capturedSelection = PDFSelectionGeometry.capture(selection: selection, in: document) else {
                onSelection(nil)
                return
            }
            onSelection(PDFSelectionInfo(
                text: capturedSelection.text,
                page: capturedSelection.page,
                bboxList: capturedSelection.bboxList
            ))
        }

        @MainActor
        @objc func pageChanged(_ notification: Notification) {
            scheduleViewportReport()
            reportDocumentStatus()
        }

        @MainActor
        @objc func viewportChanged(_ notification: Notification) {
            scheduleViewportReport()
        }

        @MainActor
        private func scheduleViewportReport() {
            guard !isApplyingReadingPosition else {
                return
            }
            pendingViewportReport?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.reportCurrentViewportPosition()
            }
            pendingViewportReport = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }

        @MainActor
        private func reportCurrentViewportPosition() {
            guard !isApplyingReadingPosition,
                  let position = currentViewportPosition(),
                  position.isMeaningfullyDifferent(from: lastReportedPosition) else {
                return
            }
            lastReportedPosition = position
            onReadingPositionChange(position)
            reportDocumentStatus()
        }

        @MainActor
        func reportDocumentStatus() {
            guard let pdfView,
                  let document = pdfView.document else {
                return
            }
            let pageIndex: Int
            if let page = pdfView.currentPage {
                pageIndex = max(document.index(for: page), 0)
            } else {
                pageIndex = 0
            }
            let status = PDFDocumentStatus(
                pageIndex: pageIndex,
                pageCount: document.pageCount,
                scaleFactor: Double(pdfView.scaleFactor)
            )
            guard status != lastReportedStatus else {
                return
            }
            lastReportedStatus = status
            onDocumentStatusChange(status)
        }

        @MainActor
        private func currentViewportPosition() -> PDFViewportPosition? {
            guard let pdfView,
                  let document = pdfView.document,
                  let page = pdfView.currentPage else {
                return nil
            }
            let pageIndex = document.index(for: page)
            guard pageIndex >= 0, pageIndex < document.pageCount else {
                return nil
            }
            let visibleCenter: NSPoint
            if let documentView = pdfView.documentView {
                let visibleRect = documentView.visibleRect
                let pointInDocumentView = NSPoint(x: visibleRect.midX, y: visibleRect.midY)
                visibleCenter = pdfView.convert(pointInDocumentView, from: documentView)
            } else {
                visibleCenter = NSPoint(x: 0, y: 0)
            }
            let pagePoint = pdfView.convert(visibleCenter, to: page)
            return PDFViewportPosition(
                pageIndex: pageIndex,
                pagePointX: Double(pagePoint.x),
                pagePointY: Double(pagePoint.y),
                scaleFactor: Double(pdfView.scaleFactor)
            )
        }

        @MainActor
        private func findScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            for subview in view.subviews {
                if let scrollView = findScrollView(in: subview) {
                    return scrollView
                }
            }
            return nil
        }

        private static func makeReferenceResolver(from document: PDFDocument?) -> PDFReferenceResolver {
            guard let document else {
                return PDFReferenceResolver(pageTexts: [:])
            }
            var pageTexts: [Int: String] = [:]
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index),
                      let text = page.string,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                pageTexts[index + 1] = text
            }
            return PDFReferenceResolver(pageTexts: pageTexts)
        }
    }
}

private struct InTextCitationPreview: View {
    var preview: PDFCitationPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(Color.accentColor)
                Text(preview.citationText)
                    .font(.headline)
                Spacer()
            }
            if preview.references.isEmpty {
                Text("No matching reference found in the paper's reference list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preview.references.prefix(3)) { reference in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(referenceTitle(reference))
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(2)
                        Text(reference.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    if reference.id != preview.references.prefix(3).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
    }

    private func referenceTitle(_ reference: PDFReferenceEntry) -> String {
        if let marker = reference.marker {
            return "[\(marker)] \(reference.title)"
        }
        return reference.title
    }
}

private struct ReferenceEntryCard: View {
    var entry: PDFReferenceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(entry.marker.map { "Reference \($0)" } ?? "Reference", systemImage: "text.book.closed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(entry.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(3)
            Text(entry.text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(8)
                .textSelection(.enabled)
        }
        .padding(15)
        .frame(width: 420, alignment: .leading)
    }
}
