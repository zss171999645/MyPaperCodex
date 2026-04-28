import PaperCodexCore
import SwiftUI

struct SaveToLibrarySheet: View {
    var paperTitle: String
    var detail: String?
    var libraryTags: [PaperTag]
    var suggestedTagNames: [String]
    var onSave: ([String]) -> Void
    var onCancel: () -> Void

    @State private var selectedKeys: Set<String>
    @State private var customTagNames: [String] = []
    @State private var newTagName = ""

    init(
        paperTitle: String,
        detail: String? = nil,
        libraryTags: [PaperTag],
        suggestedTagNames: [String],
        onSave: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.paperTitle = paperTitle
        self.detail = detail
        self.libraryTags = libraryTags
        self.suggestedTagNames = suggestedTagNames
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedKeys = State(initialValue: Set(Self.uniqueNames(suggestedTagNames).map(Self.tagKey)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            selectedTags
            tagPicker
            newTagRow
            Divider()
            actionRow
        }
        .padding(22)
        .frame(width: 520)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Save to Library")
                    .font(.title3.weight(.semibold))
                Text(paperTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedTags: some View {
        let names = selectedTagNames
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(names, id: \.self) { name in
                        Button {
                            selectedKeys.remove(Self.tagKey(name))
                            customTagNames.removeAll { Self.tagKey($0) == Self.tagKey(name) }
                        } label: {
                            HStack(spacing: 5) {
                                Text(name)
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var tagPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                tagSection(title: "Suggested", names: suggestedNames)
                tagSection(title: "Library Tags", names: libraryNames)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 230)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func tagSection(title: String, names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        Button {
                            toggle(name)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isSelected(name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected(name) ? Color.accentColor : Color.secondary)
                                Text(name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSelected(name) ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
    }

    private var newTagRow: some View {
        HStack(spacing: 8) {
            TextField("New tag", text: $newTagName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addNewTag)
            Button {
                addNewTag()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.bordered)
            .disabled(trimmedNewTagName.isEmpty)
            .help("Add Tag")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel", action: onCancel)
            Button {
                onSave(Self.uniqueNames(selectedTagNames + [trimmedNewTagName]))
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var suggestedNames: [String] {
        Self.uniqueNames(suggestedTagNames)
    }

    private var libraryNames: [String] {
        let suggestedKeys = Set(suggestedNames.map(Self.tagKey))
        return Self.uniqueNames(libraryTags.map(\.name))
            .filter { !suggestedKeys.contains(Self.tagKey($0)) }
    }

    private var selectedTagNames: [String] {
        Self.uniqueNames((suggestedNames + libraryNames + customTagNames).filter { selectedKeys.contains(Self.tagKey($0)) })
    }

    private var trimmedNewTagName: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isSelected(_ name: String) -> Bool {
        selectedKeys.contains(Self.tagKey(name))
    }

    private func toggle(_ name: String) {
        let key = Self.tagKey(name)
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
            customTagNames.removeAll { Self.tagKey($0) == key }
        } else {
            selectedKeys.insert(key)
        }
    }

    private func addNewTag() {
        let name = trimmedNewTagName
        guard !name.isEmpty else {
            return
        }
        let key = Self.tagKey(name)
        selectedKeys.insert(key)
        let presentedKeys = Set((suggestedNames + libraryNames + customTagNames).map(Self.tagKey))
        if !presentedKeys.contains(key) {
            customTagNames.append(name)
        }
        newTagName = ""
    }

    private static func uniqueNames(_ names: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = tagKey(trimmed)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    private static func tagKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
