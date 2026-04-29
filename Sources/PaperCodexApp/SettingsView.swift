import PaperCodexCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftArxivCategories = ""
    @State private var draftWhitelistTags = ""
    @State private var draftBlacklistTags = ""
    @State private var draftSimilaritySources = ""
    @State private var draftAutoEnrichOnOpen = false
    @State private var draftAutoEnrichOnSave = false
    @State private var draftDiscoverCodexModel = ""
    @State private var draftDiscoverCodexConcurrency = 10
    @State private var draftEmbeddingEnabled = false
    @State private var draftEmbeddingBaseURL = ""
    @State private var draftEmbeddingAPIKey = ""
    @State private var draftEmbeddingModel = ""
    @State private var newPromptTitle = ""
    @State private var newPromptContent = ""

    var body: some View {
        SidebarSplitLayout(minContentWidth: 720) {
            sidebar
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    arxivFeedSettings
                    localRankingSettings
                    codexEnrichmentSettings
                    discoverCodexProcessingSettings
                    embeddingProviderSettings
                    quickPromptSettings
                    storageRules
                    cacheControls
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .frame(minWidth: 720)
        }
        .onAppear {
            syncLocalDrafts()
            Task {
                await model.refreshAvailableCodexModels()
            }
        }
        .onChange(of: model.localDiscoverPreferences) { _, _ in
            syncLocalDrafts()
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
            Text("Local arXiv, storage, ranking, and Codex preferences.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var arxivFeedSettings: some View {
        settingsSection(title: "arXiv Feed", systemImage: "network") {
            TextField("Categories, comma separated", text: $draftArxivCategories)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    model.setLocalArxivCategories(splitDraftList(draftArxivCategories))
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                } label: {
                    Label("Save Categories", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                } label: {
                    Label(model.isRefreshingArxivDates ? "Refreshing" : "Refresh arXiv", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.isRefreshingArxivDates)

                Spacer()

                Text(model.selectedArxivDate ?? "No cached date")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var localRankingSettings: some View {
        settingsSection(title: "Local Ranking", systemImage: "slider.horizontal.3") {
            TextField("Whitelist tags, comma separated", text: $draftWhitelistTags)
                .textFieldStyle(.roundedBorder)
            TextField("Blacklist tags, comma separated", text: $draftBlacklistTags)
                .textFieldStyle(.roundedBorder)
            TextField("Similarity source tags or folders, comma separated", text: $draftSimilaritySources)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    model.setLocalTagFilters(
                        whitelist: splitDraftList(draftWhitelistTags),
                        blacklist: splitDraftList(draftBlacklistTags)
                    )
                    model.setLocalSimilaritySourceTagIDs(splitDraftList(draftSimilaritySources))
                } label: {
                    Label("Save Ranking", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Text("\(model.localDiscoverPreferences.whitelistTags.count) white · \(model.localDiscoverPreferences.blacklistTags.count) black")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codexEnrichmentSettings: some View {
        settingsSection(title: "Codex Enrichment", systemImage: "sparkles") {
            Toggle("Auto-enrich when opening arXiv papers", isOn: $draftAutoEnrichOnOpen)
                .toggleStyle(.checkbox)
            Toggle("Auto-enrich when saving to Library", isOn: $draftAutoEnrichOnSave)
                .toggleStyle(.checkbox)
            Button {
                model.setLocalEnrichmentPreferences(
                    autoOpen: draftAutoEnrichOnOpen,
                    autoSave: draftAutoEnrichOnSave
                )
            } label: {
                Label("Save Enrichment", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var discoverCodexProcessingSettings: some View {
        settingsSection(title: "Discover Processing", systemImage: "cpu") {
            Picker("Model", selection: $draftDiscoverCodexModel) {
                Text("Codex default").tag("")
                ForEach(model.availableCodexModelIDs, id: \.self) { modelID in
                    Text(modelID).tag(modelID)
                }
                if !draftDiscoverCodexModel.isEmpty,
                   !model.availableCodexModelIDs.contains(draftDiscoverCodexModel) {
                    Text("\(draftDiscoverCodexModel) (custom)").tag(draftDiscoverCodexModel)
                }
            }
            .pickerStyle(.menu)

            TextField("Custom model override", text: $draftDiscoverCodexModel)
                .textFieldStyle(.roundedBorder)

            Stepper(
                "Concurrent Codex processes: \(draftDiscoverCodexConcurrency)",
                value: $draftDiscoverCodexConcurrency,
                in: 1...20
            )

            HStack {
                Button {
                    model.setDiscoverCodexSettings(
                        modelOverride: draftDiscoverCodexModel,
                        concurrency: draftDiscoverCodexConcurrency
                    )
                } label: {
                    Label("Save Processing", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await model.refreshAvailableCodexModels()
                    }
                } label: {
                    Label(model.isRefreshingCodexModels ? "Refreshing" : "Refresh Models", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.isRefreshingCodexModels)

                Spacer()

                Text("\(model.discoverCodexConcurrency) workers")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var embeddingProviderSettings: some View {
        settingsSection(title: "Embedding Provider", systemImage: "point.3.connected.trianglepath.dotted") {
            Toggle("Enable embedding similarity", isOn: $draftEmbeddingEnabled)
                .toggleStyle(.checkbox)
            TextField("Base URL", text: $draftEmbeddingBaseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("API key", text: $draftEmbeddingAPIKey)
                .textFieldStyle(.roundedBorder)
            TextField("Model", text: $draftEmbeddingModel)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    model.setEmbeddingProviderSettings(
                        enabled: draftEmbeddingEnabled,
                        baseURL: draftEmbeddingBaseURL,
                        apiKey: draftEmbeddingAPIKey,
                        model: draftEmbeddingModel
                    )
                } label: {
                    Label("Save Embedding", systemImage: "key")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Text(model.localDiscoverPreferences.embedding.enabled ? "Enabled" : "Disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Clears feed JSON, temporary PDFs, and unsaved opened papers.")
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
        SidebarRowButton(title: title, systemImage: systemImage, selected: selected, action: action)
    }

    private func syncLocalDrafts() {
        let preferences = model.localDiscoverPreferences.normalized
        draftArxivCategories = preferences.categories.joined(separator: ", ")
        draftWhitelistTags = preferences.whitelistTags.joined(separator: ", ")
        draftBlacklistTags = preferences.blacklistTags.joined(separator: ", ")
        draftSimilaritySources = preferences.similaritySourceTagIDs.joined(separator: ", ")
        draftAutoEnrichOnOpen = preferences.enrichment.autoEnrichOnOpen
        draftAutoEnrichOnSave = preferences.enrichment.autoEnrichOnSave
        draftDiscoverCodexModel = model.discoverCodexModelOverride
        draftDiscoverCodexConcurrency = model.discoverCodexConcurrency
        draftEmbeddingEnabled = preferences.embedding.enabled
        draftEmbeddingBaseURL = preferences.embedding.baseURL
        draftEmbeddingModel = preferences.embedding.model
        draftEmbeddingAPIKey = model.embeddingProviderAPIKey
    }

    private func splitDraftList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
