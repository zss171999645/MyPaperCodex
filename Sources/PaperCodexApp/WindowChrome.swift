import AppKit
import SwiftUI

enum PaperCodexWindowChrome {
    static let sidebarTopPadding: CGFloat = 48
    static let sidebarHorizontalPadding: CGFloat = 22
    static let sidebarBottomPadding: CGFloat = 22
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWhenAttached(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWhenAttached(view)
    }

    private func configureWhenAttached(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
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
