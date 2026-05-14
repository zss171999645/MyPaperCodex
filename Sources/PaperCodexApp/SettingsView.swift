import PaperCodexCore
import SwiftUI

private enum SettingsSectionAnchor: String, CaseIterable, Identifiable {
    case language
    case arxiv
    case ranking
    case enrichment
    case prompt
    case processing
    case embedding
    case quickPrompts
    case storage
    case cache

    var id: String { rawValue }

    var title: String {
        switch self {
        case .language:
            "Language"
        case .arxiv:
            "arXiv Feed"
        case .ranking:
            "Ranking"
        case .enrichment:
            "Enrichment"
        case .prompt:
            "Prompt"
        case .processing:
            "Processing"
        case .embedding:
            "Embedding"
        case .quickPrompts:
            "Quick Prompts"
        case .storage:
            "Storage"
        case .cache:
            "Cache"
        }
    }

    var systemImage: String {
        switch self {
        case .language:
            "globe"
        case .arxiv:
            "network"
        case .ranking:
            "slider.horizontal.3"
        case .enrichment:
            "sparkles"
        case .prompt:
            "text.quote"
        case .processing:
            "cpu"
        case .embedding:
            "point.3.connected.trianglepath.dotted"
        case .quickPrompts:
            "text.bubble"
        case .storage:
            "folder.badge.gearshape"
        case .cache:
            "internaldrive"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftArxivCategories = ""
    @State private var draftWhitelistTags = ""
    @State private var draftBlacklistTags = ""
    @State private var draftSimilarityCategoryIDs: Set<String> = []
    @State private var draftAutoEnrichOnOpen = false
    @State private var draftAutoEnrichOnSave = false
    @State private var draftCodexSystemPrompt = PromptBuilder.defaultSystemPrompt
    @State private var draftDiscoverCodexModel = ""
    @State private var draftDiscoverCodexReasoningEffort: CodexReasoningEffort = .default
    @State private var draftDiscoverCodexConcurrency = 10
    @State private var draftEmbeddingEnabled = false
    @State private var draftEmbeddingBaseURL = ""
    @State private var draftEmbeddingAPIKey = ""
    @State private var draftEmbeddingModel = ""
    @State private var newPromptTitle = ""
    @State private var newPromptContent = ""
    @State private var sectionToScroll: SettingsSectionAnchor?
    @State private var isConfirmingClearCache = false
    @State private var editingPrompt: QuickPrompt?
    @State private var editingPromptTitle = ""
    @State private var editingPromptContent = ""

    private var isArxivFeedDirty: Bool {
        splitDraftList(draftArxivCategories) != model.localDiscoverPreferences.normalized.categories
    }

    private var isRankingDirty: Bool {
        let preferences = model.localDiscoverPreferences.normalized
        return splitDraftList(draftWhitelistTags) != preferences.whitelistTags
            || splitDraftList(draftBlacklistTags) != preferences.blacklistTags
            || draftSimilarityCategoryIDs != Set(model.similarityCategoryIDsForSettings())
    }

    private var isEnrichmentDirty: Bool {
        let enrichment = model.localDiscoverPreferences.normalized.enrichment
        return draftAutoEnrichOnOpen != enrichment.autoEnrichOnOpen
            || draftAutoEnrichOnSave != enrichment.autoEnrichOnSave
    }

    private var isProcessingDirty: Bool {
        draftDiscoverCodexModel.trimmingCharacters(in: .whitespacesAndNewlines) != model.discoverCodexModelOverride
            || draftDiscoverCodexReasoningEffort != model.discoverCodexReasoningEffort
            || draftDiscoverCodexConcurrency != model.discoverCodexConcurrency
    }

    private var isEmbeddingDirty: Bool {
        let embedding = model.localDiscoverPreferences.normalized.embedding
        return draftEmbeddingEnabled != embedding.enabled
            || draftEmbeddingBaseURL.trimmingCharacters(in: .whitespacesAndNewlines) != embedding.baseURL
            || draftEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines) != embedding.model
            || draftEmbeddingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines) != model.embeddingProviderAPIKey
    }

    private var codexDefaultModelLabel: String {
        let trimmed = model.codexDefaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Codex default" : "Codex default (\(trimmed))"
    }

    var body: some View {
        SidebarSplitLayout(minContentWidth: 760) {
            sidebar
        } content: {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        header
                        globalLanguageSettings.id(SettingsSectionAnchor.language)
                        arxivFeedSettings.id(SettingsSectionAnchor.arxiv)
                        localRankingSettings.id(SettingsSectionAnchor.ranking)
                        codexEnrichmentSettings.id(SettingsSectionAnchor.enrichment)
                        codexSystemPromptSettings.id(SettingsSectionAnchor.prompt)
                        discoverCodexProcessingSettings.id(SettingsSectionAnchor.processing)
                        embeddingProviderSettings.id(SettingsSectionAnchor.embedding)
                        quickPromptSettings.id(SettingsSectionAnchor.quickPrompts)
                        storageRules.id(SettingsSectionAnchor.storage)
                        cacheControls.id(SettingsSectionAnchor.cache)
                    }
                    .padding(28)
                    .frame(maxWidth: 820, alignment: .leading)
                }
                .onChange(of: sectionToScroll) { _, anchor in
                    guard let anchor else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
            }
            .frame(minWidth: 0)
        }
        .alert("Clear arXiv cache?", isPresented: $isConfirmingClearCache) {
            Button("Clear", role: .destructive) {
                model.clearArxivCaches()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes cached feed JSON, temporary PDFs, and unsaved opened arXiv papers.")
        }
        .sheet(item: $editingPrompt) { prompt in
            quickPromptEditSheet(prompt)
        }
        .onAppear {
            syncLocalDrafts()
            model.refreshCacheStorageSummary()
        }
        .onChange(of: model.localDiscoverPreferences) { _, _ in
            syncLocalDrafts()
        }
        .onChange(of: model.categories) { _, _ in
            syncLocalDrafts()
        }
        .onChange(of: model.codexSystemPrompt) { _, newValue in
            draftCodexSystemPrompt = newValue
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.paperCodexSystem(size: 24, weight: .semibold))

            PrimaryNavigationSection()

            Divider()

            Label("Settings Sections", systemImage: "gearshape")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(SettingsSectionAnchor.allCases) { anchor in
                    navButton(
                        title: anchor.title,
                        systemImage: anchor.systemImage,
                        selected: sectionToScroll == anchor
                    ) {
                        sectionToScroll = anchor
                    }
                    .help("Jump to \(anchor.title)")
                }
            }

            Spacer()
        }
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.paperCodexSystem(size: 30, weight: .semibold))
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
                    Label(isArxivFeedDirty ? "Save Categories" : "Saved", systemImage: isArxivFeedDirty ? "checkmark" : "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isArxivFeedDirty)

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

    private var globalLanguageSettings: some View {
        settingsSection(title: "Language", systemImage: "globe") {
            Picker("App language", selection: Binding(
                get: { model.globalLanguageMode },
                set: { model.setGlobalLanguageMode($0) }
            )) {
                ForEach(PaperCodexLanguageMode.allCases) { mode in
                    Text(mode.title(appLanguage: model.globalLanguageMode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Controls the whole app interface, Discover language, and the default Codex prompt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var localRankingSettings: some View {
        settingsSection(title: "Local Ranking", systemImage: "slider.horizontal.3") {
            TextField("Whitelist tags, comma separated", text: $draftWhitelistTags)
                .textFieldStyle(.roundedBorder)
            TextField("Blacklist tags, comma separated", text: $draftBlacklistTags)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 8) {
                Text("Similarity categories")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.categories) { category in
                            similarityCategoryRow(category)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button {
                    model.setLocalTagFilters(
                        whitelist: splitDraftList(draftWhitelistTags),
                        blacklist: splitDraftList(draftBlacklistTags)
                    )
                    model.setLocalSimilarityCategoryIDs(selectedSimilarityCategoryIDsInOrder)
                } label: {
                    Label(isRankingDirty ? "Save Ranking" : "Saved", systemImage: isRankingDirty ? "line.3.horizontal.decrease.circle" : "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isRankingDirty)

                Spacer()

                Text("\(model.localDiscoverPreferences.whitelistTags.count) white · \(model.localDiscoverPreferences.blacklistTags.count) black · \(draftSimilarityCategoryIDs.count)/\(model.categories.count) cats")
                    .font(.caption)
                    .foregroundStyle(isRankingDirty ? .orange : .secondary)
            }
        }
    }

    private func similarityCategoryRow(_ category: PaperCodexCore.Category) -> some View {
        Button {
            if draftSimilarityCategoryIDs.contains(category.id) {
                draftSimilarityCategoryIDs.remove(category.id)
            } else {
                draftSimilarityCategoryIDs.insert(category.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: draftSimilarityCategoryIDs.contains(category.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(draftSimilarityCategoryIDs.contains(category.id) ? Color.accentColor : Color.secondary)
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(categoryDisplayName(category))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.paperCodexSystem(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(draftSimilarityCategoryIDs.contains(category.id) ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
                Label(isEnrichmentDirty ? "Save Enrichment" : "Saved", systemImage: isEnrichmentDirty ? "checkmark" : "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnrichmentDirty)
        }
    }

    private var discoverCodexProcessingSettings: some View {
        settingsSection(title: "Discover Processing", systemImage: "cpu") {
            Picker("Model", selection: $draftDiscoverCodexModel) {
                Text(codexDefaultModelLabel).tag("")
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

            Picker("Thinking", selection: $draftDiscoverCodexReasoningEffort) {
                ForEach(CodexReasoningEffort.allCases, id: \.self) { effort in
                    Text(effort.displayName).tag(effort)
                }
            }
            .pickerStyle(.menu)

            Stepper(
                "Concurrent Codex processes: \(draftDiscoverCodexConcurrency)",
                value: $draftDiscoverCodexConcurrency,
                in: 1...20
            )

            HStack {
                Button {
                    model.setDiscoverCodexSettings(
                        modelOverride: draftDiscoverCodexModel,
                        concurrency: draftDiscoverCodexConcurrency,
                        reasoningEffort: draftDiscoverCodexReasoningEffort
                    )
                } label: {
                    Label(isProcessingDirty ? "Save Processing" : "Saved", systemImage: isProcessingDirty ? "checkmark" : "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isProcessingDirty)

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

                Text("\(model.discoverCodexConcurrency) workers · Think \(model.discoverCodexReasoningEffort.displayName)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codexSystemPromptSettings: some View {
        settingsSection(title: "Codex System Prompt", systemImage: "text.quote") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Template")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Workspace placeholder: \(PromptBuilder.workspacePathPlaceholder)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $draftCodexSystemPrompt)
                    .font(.paperCodexSystem(size: 13, design: .monospaced))
                    .frame(height: 240)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("System prompt template editor")
                    .accessibilityValue("\(draftCodexSystemPrompt.count) characters")

                HStack {
                    Button {
                        model.setCodexSystemPrompt(draftCodexSystemPrompt)
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save System Prompt")

                    Button {
                        model.resetCodexSystemPrompt()
                        draftCodexSystemPrompt = model.codexSystemPrompt
                    } label: {
                        Label("Default", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Restore Default System Prompt")

                    Spacer()

                    Text(draftCodexSystemPrompt == model.codexSystemPrompt ? "Saved" : "Unsaved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    Label(isEmbeddingDirty ? "Save Embedding" : "Saved", systemImage: isEmbeddingDirty ? "key" : "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isEmbeddingDirty)

                Button {
                    Task {
                        await model.testEmbeddingProvider(
                            baseURL: draftEmbeddingBaseURL,
                            apiKey: draftEmbeddingAPIKey,
                            model: draftEmbeddingModel
                        )
                    }
                } label: {
                    Label(model.isTestingEmbeddingProvider ? "Testing" : "Test", systemImage: "bolt.horizontal.circle")
                }
                .buttonStyle(.bordered)
                .disabled(model.isTestingEmbeddingProvider)

                Spacer()

                Text(model.embeddingProviderTestStatus ?? (model.localDiscoverPreferences.embedding.enabled ? "Enabled" : "Disabled"))
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
                                .font(.paperCodexSystem(size: 13, weight: .semibold))
                            Text(prompt.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            model.moveQuickPrompt(prompt, direction: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .help("Move Up")
                        Button {
                            model.moveQuickPrompt(prompt, direction: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .help("Move Down")
                        Button {
                            editingPromptTitle = prompt.title
                            editingPromptContent = prompt.content
                            editingPrompt = prompt
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit Prompt")
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
                    .font(.paperCodexSystem(size: 13))
                    .frame(minHeight: 78)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("New quick prompt editor")
                    .accessibilityValue("\(newPromptContent.count) characters")
                Button {
                    model.addQuickPrompt(title: newPromptTitle, content: newPromptContent)
                    if model.errorMessage == nil {
                        newPromptTitle = ""
                        newPromptContent = ""
                    }
                } label: {
                    Label("Add Prompt", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(newPromptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newPromptContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Text(LocalizedStringKey(option.title)).tag(option)
                }
            }
            .pickerStyle(.radioGroup)

            pathRow(label: "Library root", value: model.paperLibraryRootPath)
        }
    }

    private var cacheControls: some View {
        settingsSection(title: "Disposable Cache", systemImage: "internaldrive") {
            pathRow(label: "Cache root", value: model.arxivDisposableCachePath)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.cacheStorageSummary.detailText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("arXiv \(CacheStorageSummary.formatBytes(model.cacheStorageSummary.arxivCacheBytes)) · thumbnails \(CacheStorageSummary.formatBytes(model.cacheStorageSummary.thumbnailBytes))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            HStack {
                Button(role: .destructive) {
                    isConfirmingClearCache = true
                } label: {
                    Label("Clear arXiv Cache", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button {
                    model.refreshCacheStorageSummary()
                } label: {
                    Label("Refresh Size", systemImage: "arrow.clockwise")
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
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
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

    private func quickPromptEditSheet(_ prompt: QuickPrompt) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Edit Quick Prompt", systemImage: "pencil")
                .font(.title3.weight(.semibold))
            TextField("Prompt title", text: $editingPromptTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $editingPromptContent)
                .font(.paperCodexSystem(size: 13))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Quick prompt editor")
                .accessibilityValue("\(editingPromptContent.count) characters")
            HStack {
                Spacer()
                Button("Cancel") {
                    editingPrompt = nil
                }
                Button("Save") {
                    model.updateQuickPrompt(prompt, title: editingPromptTitle, content: editingPromptContent)
                    editingPrompt = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(editingPromptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editingPromptContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func pathRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                Text(value)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button {
                    model.revealPath(value)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
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
        draftSimilarityCategoryIDs = Set(model.similarityCategoryIDsForSettings())
        draftAutoEnrichOnOpen = preferences.enrichment.autoEnrichOnOpen
        draftAutoEnrichOnSave = preferences.enrichment.autoEnrichOnSave
        draftCodexSystemPrompt = model.codexSystemPrompt
        draftDiscoverCodexModel = model.discoverCodexModelOverride
        draftDiscoverCodexReasoningEffort = model.discoverCodexReasoningEffort
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

    private var selectedSimilarityCategoryIDsInOrder: [String] {
        model.categories.map(\.id).filter { draftSimilarityCategoryIDs.contains($0) }
    }

    private func categoryDisplayName(_ category: PaperCodexCore.Category) -> String {
        var names = [category.name]
        var visited = Set([category.id])
        var parentID = category.parentID
        while let id = parentID,
              !visited.contains(id),
              let parent = model.categories.first(where: { $0.id == id }) {
            names.append(parent.name)
            visited.insert(parent.id)
            parentID = parent.parentID
        }
        return names.reversed().joined(separator: " / ")
    }
}
