import PaperCodexCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftBaseURL = ""
    @State private var draftToken = ""
    @State private var draftUsername = ""
    @State private var newPromptTitle = ""
    @State private var newPromptContent = ""
    @State private var draftFilterCategories = ""
    @State private var draftWhitelistTags = ""
    @State private var draftBlacklistTags = ""
    @State private var draftSimilarityFavoriteIDs: Set<Int> = []

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    feedConnection
                    codeArxivPreferences
                    quickPromptSettings
                    storageRules
                    cacheControls
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .frame(minWidth: 720)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            draftBaseURL = model.arxivFeedBaseURL
            draftToken = model.arxivFeedToken
            draftUsername = model.arxivFeedUsername
            syncCodeArxivDrafts()
        }
        .onChange(of: model.codeArxivUserState) { _, _ in
            syncCodeArxivDrafts()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.system(size: 24, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                navButton(title: "Library", systemImage: "books.vertical") {
                    model.goToLibrary()
                }
                navButton(title: "Discover", systemImage: "sparkle.magnifyingglass") {
                    model.showDiscover()
                }
                navButton(title: "Settings", systemImage: "gearshape", selected: true) {}
            }

            Spacer()
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 30, weight: .semibold))
            Text("Feed connection, disposable cache, and saved-paper organization.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var feedConnection: some View {
        settingsSection(title: "CodeArXiv Feed", systemImage: "server.rack") {
            TextField("Base URL", text: $draftBaseURL)
                .textFieldStyle(.roundedBorder)
            TextField("CodeArXiv username", text: $draftUsername)
                .textFieldStyle(.roundedBorder)
            SecureField("API token", text: $draftToken)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    model.setArxivFeedConnection(baseURL: draftBaseURL, token: draftToken, username: draftUsername)
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                } label: {
                    Label("Save & Connect", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                } label: {
                    Label("Refresh Feed", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var codeArxivPreferences: some View {
        settingsSection(title: "CodeArXiv Preferences", systemImage: "slider.horizontal.3") {
            if let state = model.codeArxivUserState {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(state.user.username, systemImage: "person.crop.circle")
                        Spacer()
                        Button {
                            Task {
                                await model.refreshCodeArxivUserState()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    TextField("Categories, comma separated", text: $draftFilterCategories)
                        .textFieldStyle(.roundedBorder)
                    TextField("Whitelist tags, comma separated", text: $draftWhitelistTags)
                        .textFieldStyle(.roundedBorder)
                    TextField("Blacklist tags, comma separated", text: $draftBlacklistTags)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Similarity folders")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(draftSimilarityFavoriteIDs.isEmpty ? "All favorites" : "\(draftSimilarityFavoriteIDs.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if state.favorites.isEmpty {
                            Text("No CodeArXiv favorites yet.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(state.favorites) { favorite in
                                        Toggle(isOn: Binding(
                                            get: { draftSimilarityFavoriteIDs.contains(favorite.id) },
                                            set: { isOn in
                                                if isOn {
                                                    draftSimilarityFavoriteIDs.insert(favorite.id)
                                                } else {
                                                    draftSimilarityFavoriteIDs.remove(favorite.id)
                                                }
                                            }
                                        )) {
                                            Text("\(favorite.name) · \(favorite.paperIDs.count)")
                                                .lineLimit(1)
                                        }
                                        .toggleStyle(.checkbox)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 150, alignment: .top)
                        }
                    }

                    HStack {
                        Button {
                            Task {
                                await model.updateCodeArxivPreferences(
                                    categories: splitDraftList(draftFilterCategories),
                                    whitelistTags: splitDraftList(draftWhitelistTags),
                                    blacklistTags: splitDraftList(draftBlacklistTags),
                                    simFavoriteIDs: draftSimilarityFavoriteIDs.sorted()
                                )
                            }
                        } label: {
                            Label(model.isSavingCodeArxivPreferences ? "Saving Preferences" : "Save Preferences", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isSavingCodeArxivPreferences)

                        Button {
                            Task {
                                await model.syncCodeArxivFavorites()
                            }
                        } label: {
                            Label(model.isSyncingCodeArxivFavorites ? "Syncing Favorites" : "Sync \(state.user.username) Favorites", systemImage: "square.and.arrow.down.on.square")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isSyncingCodeArxivFavorites || state.favorites.isEmpty)
                    }
                }
            } else {
                HStack {
                    Text("No CodeArXiv user state loaded.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            await model.refreshCodeArxivUserState()
                        }
                    } label: {
                        Label("Load", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var quickPromptSettings: some View {
        settingsSection(title: "Quick Prompts", systemImage: "text.bubble") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.quickPrompts) { prompt in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(prompt.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(prompt.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            model.deleteQuickPrompt(prompt)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete Prompt")
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                TextField("Prompt title", text: $newPromptTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $newPromptContent)
                    .font(.system(size: 13))
                    .frame(minHeight: 78)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    model.addQuickPrompt(title: newPromptTitle, content: newPromptContent)
                    newPromptTitle = ""
                    newPromptContent = ""
                } label: {
                    Label("Add Prompt", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var storageRules: some View {
        settingsSection(title: "Saved Paper Organization", systemImage: "folder.badge.gearshape") {
            Picker("Folder rule", selection: Binding(
                get: { model.arxivSaveOrganization },
                set: { model.setArxivSaveOrganization($0) }
            )) {
                ForEach(ArxivSaveOrganization.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.radioGroup)

            pathRow(label: "Library root", value: model.paperLibraryRootPath)
        }
    }

    private var cacheControls: some View {
        settingsSection(title: "Disposable Cache", systemImage: "internaldrive") {
            pathRow(label: "Cache root", value: model.arxivDisposableCachePath)
            HStack {
                Button(role: .destructive) {
                    model.clearArxivCaches()
                } label: {
                    Label("Clear arXiv Cache", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Text("Clears thumbnails, feed JSON, temporary PDFs, and unsaved opened papers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func pathRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func navButton(title: String, systemImage: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func syncCodeArxivDrafts() {
        guard let state = model.codeArxivUserState else {
            draftFilterCategories = ""
            draftWhitelistTags = ""
            draftBlacklistTags = ""
            draftSimilarityFavoriteIDs = []
            return
        }
        draftFilterCategories = state.filters.categories.joined(separator: ", ")
        draftWhitelistTags = state.filters.tags.whitelist.joined(separator: ", ")
        draftBlacklistTags = state.filters.tags.blacklist.joined(separator: ", ")
        draftSimilarityFavoriteIDs = Set(state.filters.simFavorites)
    }

    private func splitDraftList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
