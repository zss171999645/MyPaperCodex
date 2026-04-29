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
                SplitterHandle()
                    .frame(width: handleWidth)
                    .frame(maxHeight: .infinity)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if dragStartWidth == nil {
                                    dragStartWidth = sidebarWidth
                                }
                                liveSidebarWidth = clampedSidebarWidth(
                                    (dragStartWidth ?? sidebarWidth) + value.translation.width,
                                    totalWidth: proxy.size.width,
                                    handleWidth: handleWidth
                                )
                            }
                            .onEnded { _ in
                                if let liveSidebarWidth {
                                    model.setLibrarySidebarWidth(liveSidebarWidth)
                                }
                                dragStartWidth = nil
                                liveSidebarWidth = nil
                            }
                    )
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

struct SplitterHandle: View {
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(isHovering ? 0.80 : 0.55))
                .frame(width: 5)
            Capsule()
                .fill(isHovering ? Color.accentColor.opacity(0.72) : Color.clear)
                .frame(width: 3, height: 52)
                .shadow(color: isHovering ? Color.accentColor.opacity(0.32) : .clear, radius: 6)
        }
        .overlay(
            Rectangle()
                .fill(Color.clear)
                .frame(width: 22)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.arrow.set()
            }
        }
        .help("Resize sidebar")
    }
}
