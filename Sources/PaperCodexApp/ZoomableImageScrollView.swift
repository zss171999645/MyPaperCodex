import AppKit
import SwiftUI

struct ZoomableImageScrollView: NSViewRepresentable {
    var imageURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WheelZoomScrollView {
        let scrollView = WheelZoomScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.08
        scrollView.maxMagnification = 6
        scrollView.magnification = 1

        scrollView.documentView = CenteredImageDocumentView()
        return scrollView
    }

    func updateNSView(_ scrollView: WheelZoomScrollView, context: Context) {
        guard context.coordinator.imageURL != imageURL else {
            return
        }
        context.coordinator.imageURL = imageURL
        guard let image = NSImage(contentsOf: imageURL),
              let documentView = scrollView.documentView as? CenteredImageDocumentView else {
            return
        }

        documentView.setImage(image)
        scrollView.layoutSubtreeIfNeeded()

        DispatchQueue.main.async {
            scrollView.fitDocumentToViewport()
        }
    }

    final class Coordinator {
        var imageURL: URL?
    }
}

final class WheelZoomScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        guard let centeredDocumentView = documentView as? CenteredImageDocumentView else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else {
            super.scrollWheel(with: event)
            return
        }

        let nextMagnification = min(
            max(magnification * pow(1.0018, delta), minMagnification),
            maxMagnification
        )
        let focusPoint = contentView.convert(event.locationInWindow, from: nil)
        let documentFocusPoint = centeredDocumentView.convert(focusPoint, from: contentView)
        centeredDocumentView.layoutImage(viewportSize: contentView.bounds.size, magnification: nextMagnification)
        setMagnification(nextMagnification, centeredAt: documentFocusPoint)
    }

    func fitDocumentToViewport() {
        guard let centeredDocumentView = documentView as? CenteredImageDocumentView,
              centeredDocumentView.imageSize.width > 0,
              centeredDocumentView.imageSize.height > 0,
              contentView.bounds.width > 0,
              contentView.bounds.height > 0 else {
            return
        }
        let fitScale = min(
            contentView.bounds.width / centeredDocumentView.imageSize.width,
            contentView.bounds.height / centeredDocumentView.imageSize.height
        )
        let initialScale = min(max(fitScale, minMagnification), 1)
        centeredDocumentView.layoutImage(viewportSize: contentView.bounds.size, magnification: initialScale)
        setMagnification(
            initialScale,
            centeredAt: NSPoint(x: centeredDocumentView.bounds.midX, y: centeredDocumentView.bounds.midY)
        )
    }
}

final class CenteredImageDocumentView: NSView {
    private let imageView = NSImageView()

    var imageSize: NSSize {
        imageView.image?.size ?? .zero
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: NSImage) {
        imageView.image = image
        frame = NSRect(origin: .zero, size: image.size)
        imageView.frame = NSRect(origin: .zero, size: image.size)
    }

    func layoutImage(viewportSize: NSSize, magnification: CGFloat) {
        let scale = max(magnification, 0.0001)
        let documentSize = NSSize(
            width: max(imageSize.width, viewportSize.width / scale),
            height: max(imageSize.height, viewportSize.height / scale)
        )
        frame = NSRect(origin: .zero, size: documentSize)
        imageView.frame = NSRect(
            x: max((documentSize.width - imageSize.width) / 2, 0),
            y: max((documentSize.height - imageSize.height) / 2, 0),
            width: imageSize.width,
            height: imageSize.height
        )
    }
}
