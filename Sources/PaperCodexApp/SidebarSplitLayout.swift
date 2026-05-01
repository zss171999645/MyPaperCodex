import AppKit
import SwiftUI

struct SidebarSplitLayout<Sidebar: View, Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @State private var dragStartWidth: CGFloat?
    @State private var liveSidebarWidth: CGFloat?

    var minContentWidth: CGFloat
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content

    init(
        minContentWidth: CGFloat = 720,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minContentWidth = minContentWidth
        self.sidebar = sidebar
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let handleWidth: CGFloat = 10
            let sidebarWidth = clampedSidebarWidth(
                liveSidebarWidth ?? model.librarySidebarWidth,
                totalWidth: proxy.size.width,
                handleWidth: handleWidth
            )
            let contentMinWidth = max(0, min(minContentWidth, proxy.size.width - sidebarWidth - handleWidth))

            HStack(alignment: .top, spacing: 0) {
                sidebar()
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                WindowSafeSplitterHandle(
                    onDragChanged: { translationX in
                        if dragStartWidth == nil {
                            dragStartWidth = sidebarWidth
                        }
                        liveSidebarWidth = clampedSidebarWidth(
                            (dragStartWidth ?? sidebarWidth) + translationX,
                            totalWidth: proxy.size.width,
                            handleWidth: handleWidth
                        )
                    },
                    onDragEnded: {
                        if let liveSidebarWidth {
                            model.setLibrarySidebarWidth(liveSidebarWidth)
                        }
                        dragStartWidth = nil
                        liveSidebarWidth = nil
                    }
                )
                    .frame(width: handleWidth)
                    .frame(maxHeight: .infinity)
                content()
                    .frame(minWidth: contentMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func clampedSidebarWidth(_ width: CGFloat, totalWidth: CGFloat, handleWidth: CGFloat) -> CGFloat {
        let maxWidth = max(220, min(420, totalWidth - minContentWidth - handleWidth))
        return min(max(width, 220), maxWidth)
    }
}

struct WindowSafeSplitterHandle: NSViewRepresentable {
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: () -> Void

    func makeNSView(context: Context) -> SplitterHandleView {
        let view = SplitterHandleView()
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: SplitterHandleView, context: Context) {
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
    }

    final class SplitterHandleView: NSView {
        var onDragChanged: (CGFloat) -> Void = { _ in }
        var onDragEnded: () -> Void = {}
        private var dragStartWindowX: CGFloat?
        private var isHovering = false
        private var trackingArea: NSTrackingArea?

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseEntered(with event: NSEvent) {
            isHovering = true
            needsDisplay = true
            NSCursor.resizeLeftRight.set()
        }

        override func mouseExited(with event: NSEvent) {
            isHovering = false
            needsDisplay = true
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {
            dragStartWindowX = event.locationInWindow.x
            window?.makeFirstResponder(self)
            NSCursor.resizeLeftRight.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStartWindowX else {
                return
            }
            onDragChanged(event.locationInWindow.x - dragStartWindowX)
        }

        override func mouseUp(with event: NSEvent) {
            dragStartWindowX = nil
            onDragEnded()
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            NSColor.separatorColor.withAlphaComponent(isHovering ? 0.80 : 0.55).setFill()
            let separator = NSRect(x: bounds.midX - 2.5, y: bounds.minY, width: 5, height: bounds.height)
            separator.fill()

            guard isHovering else {
                return
            }
            NSColor.controlAccentColor.withAlphaComponent(0.72).setFill()
            let accent = NSRect(x: bounds.midX - 1.5, y: bounds.midY - 26, width: 3, height: 52)
            NSBezierPath(roundedRect: accent, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
