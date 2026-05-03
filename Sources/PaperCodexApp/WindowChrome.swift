import AppKit
import SwiftUI

enum PaperCodexWindowChrome {
    static let sidebarTopPadding: CGFloat = 48
    static let sidebarHorizontalPadding: CGFloat = 22
    static let sidebarBottomPadding: CGFloat = 22
    static let titlebarDoubleClickZoomHeight: CGFloat = 54
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWhenAttached(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWhenAttached(view, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.removeTitlebarDoubleClickZoomMonitor()
    }

    private func configureWhenAttached(_ view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            coordinator.installTitlebarDoubleClickZoomMonitor(for: window, windowHeight: window.frame.height)
        }
    }

    final class Coordinator {
        private weak var monitoredWindow: NSWindow?
        private var titlebarDoubleClickMonitor: Any?
        private var monitoredWindowHeight: CGFloat = 0

        deinit {
            removeTitlebarDoubleClickZoomMonitor()
        }

        func installTitlebarDoubleClickZoomMonitor(for window: NSWindow, windowHeight: CGFloat) {
            monitoredWindowHeight = windowHeight
            guard monitoredWindow !== window else {
                return
            }
            removeTitlebarDoubleClickZoomMonitor()
            monitoredWindow = window
            titlebarDoubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self, weak window] event in
                guard let self,
                      let window,
                      event.window === window,
                      event.clickCount == 2,
                      self.isInTitlebarDoubleClickZoomArea(event.locationInWindow) else {
                    return event
                }
                DispatchQueue.main.async { [weak window] in
                    window?.performZoom(nil)
                }
                return nil
            }
        }

        func removeTitlebarDoubleClickZoomMonitor() {
            if let titlebarDoubleClickMonitor {
                NSEvent.removeMonitor(titlebarDoubleClickMonitor)
            }
            titlebarDoubleClickMonitor = nil
            monitoredWindow = nil
        }

        private func isInTitlebarDoubleClickZoomArea(_ location: NSPoint) -> Bool {
            guard monitoredWindowHeight > 0 else {
                return false
            }
            return location.y >= monitoredWindowHeight - PaperCodexWindowChrome.titlebarDoubleClickZoomHeight
        }
    }
}

extension View {
    func paperCodexSidebarChromePadding() -> some View {
        padding(.top, PaperCodexWindowChrome.sidebarTopPadding)
            .padding(.horizontal, PaperCodexWindowChrome.sidebarHorizontalPadding)
            .padding(.bottom, PaperCodexWindowChrome.sidebarBottomPadding)
    }
}
