import SwiftUI

@main
struct PaperCodexApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
                .background(WindowChromeConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            PaperCodexCommands(model: model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.route {
            case .library:
                LibraryView()
            case .discover:
                DiscoverView()
            case .settings:
                SettingsView()
            case .reader:
                ReaderView()
            }
        }
        .environment(\.locale, Locale(identifier: model.globalLanguageMode.appLocaleIdentifier))
        .paperCodexTypographyScale()
        .overlay(alignment: .topTrailing) {
            InteractionNoticeStack(notices: model.notices) { noticeID in
                model.dismissNotice(id: noticeID)
            }
        }
        .overlay(alignment: .bottom) {
            if let status = model.globalOperationStatus {
                GlobalOperationStatusView(status: status)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: model.errorMessage) { _, message in
            guard let message else {
                return
            }
            model.postNotice(kind: .error, title: "Paper Codex", message: message, autoDismissAfter: nil)
            model.errorMessage = nil
        }
    }
}

struct PaperCodexCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu("Paper Codex") {
            Button("Library") {
                model.goToLibrary()
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Discover") {
                model.showDiscover()
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Reader") {
                if model.selectedPaper != nil {
                    model.route = .reader
                }
            }
            .keyboardShortcut("3", modifiers: [.command])
            .disabled(model.selectedPaper == nil)

            Divider()

            Button("New Session") {
                model.newSessionButtonTapped()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(model.selectedPaper == nil || model.route != .reader)

            Button("Stop Codex") {
                model.cancelActiveCodexRun()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!model.isSessionSending(model.selectedSession?.id))

            Divider()

            Button("Settings") {
                model.showSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
