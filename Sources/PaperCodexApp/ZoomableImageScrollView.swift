import AppKit
import SwiftUI

struct ZoomableImageScrollView: NSViewRepresentable {
    var imageURL: URL
    var onBackdropClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBackdropClick: onBackdropClick)
    }

    func makeNSView(context: Context) -> ZoomableImageCanvasView {
        let view = ZoomableImageCanvasView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: ZoomableImageCanvasView, context: Context) {
        context.coordinator.onBackdropClick = onBackdropClick
        view.onBackdropClick = {
            context.coordinator.onBackdropClick()
        }
        guard context.coordinator.imageURL != imageURL else {
            return
        }
        context.coordinator.imageURL = imageURL
        guard let image = NSImage(contentsOf: imageURL) else {
            return
        }
        view.setImage(image)
    }

    final class Coordinator {
        var imageURL: URL?
        var onBackdropClick: () -> Void

        init(onBackdropClick: @escaping () -> Void) {
            self.onBackdropClick = onBackdropClick
        }
    }
}

final class ZoomableImageCanvasView: NSView {
    var onBackdropClick: (() -> Void)?

    private var image: NSImage?
    private var scale: CGFloat = 1
    private var offset: CGPoint = .zero
    private var lastDragPoint: CGPoint?
    private var needsInitialFit = false

    private let minScale: CGFloat = 0.05
    private let maxScale: CGFloat = 8

    override var acceptsFirstResponder: Bool {
        true
    }

    func setImage(_ image: NSImage) {
        self.image = image
        scale = 1
        offset = .zero
        needsInitialFit = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if needsInitialFit {
            fitImageToView()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.035, alpha: 1).setFill()
        dirtyRect.fill()

        guard let image else {
            return
        }
        if needsInitialFit {
            fitImageToView()
        }
        image.draw(in: imageRect(for: image), from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if isBackdropEdge(point) {
            onBackdropClick?()
            return
        }
        if let image, !imageRect(for: image).contains(point) {
            onBackdropClick?()
            return
        }
        lastDragPoint = point
        if event.clickCount == 2 {
            fitImageToView()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let lastDragPoint else {
            self.lastDragPoint = point
            return
        }
        offset.x += point.x - lastDragPoint.x
        offset.y += point.y - lastDragPoint.y
        self.lastDragPoint = point
        clampOffset()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard let image else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else {
            super.scrollWheel(with: event)
            return
        }

        let nextMagnification = min(
            max(scale * pow(1.0018, delta), minScale),
            maxScale
        )
        guard nextMagnification != scale else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let rect = imageRect(for: image)
        let imagePoint = CGPoint(
            x: (point.x - rect.minX) / scale,
            y: (point.y - rect.minY) / scale
        )
        scale = nextMagnification
        let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        offset = CGPoint(
            x: point.x - bounds.midX + scaledSize.width / 2 - imagePoint.x * scale,
            y: point.y - bounds.midY + scaledSize.height / 2 - imagePoint.y * scale
        )
        clampOffset()
        needsDisplay = true
    }

    private func fitImageToView() {
        guard let image,
              image.size.width > 0,
              image.size.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }
        let fitWidth = bounds.width / image.size.width
        let fitHeight = bounds.height / image.size.height
        let isWideStrip = image.size.width / image.size.height > bounds.width / bounds.height * 1.25
        scale = min(max(isWideStrip ? fitHeight : min(fitWidth, fitHeight), minScale), 1.25)
        offset = .zero
        needsInitialFit = false
        clampOffset()
        needsDisplay = true
    }

    private func imageRect(for image: NSImage) -> CGRect {
        let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: bounds.midX - scaledSize.width / 2 + offset.x,
            y: bounds.midY - scaledSize.height / 2 + offset.y,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    private func isBackdropEdge(_ point: CGPoint) -> Bool {
        let closeInset: CGFloat = 34
        return point.x < closeInset
            || point.x > bounds.width - closeInset
            || point.y < closeInset
            || point.y > bounds.height - closeInset
    }

    private func clampOffset() {
        guard let image else {
            return
        }
        let scaledWidth = image.size.width * scale
        let scaledHeight = image.size.height * scale

        if scaledWidth <= bounds.width {
            offset.x = 0
        } else {
            let maxX = (scaledWidth - bounds.width) / 2
            offset.x = min(max(offset.x, -maxX), maxX)
        }

        if scaledHeight <= bounds.height {
            offset.y = 0
        } else {
            let maxY = (scaledHeight - bounds.height) / 2
            offset.y = min(max(offset.y, -maxY), maxY)
        }
    }
}
