import CryptoKit
import Foundation

public struct PaperImportResult: Equatable, Sendable {
    public var paper: Paper
    public var didImport: Bool

    public init(paper: Paper, didImport: Bool) {
        self.paper = paper
        self.didImport = didImport
    }
}

public final class PaperLibraryImporter {
    private let repository: PaperRepository
    private let supportRoot: URL
    private let fileManager: FileManager

    public init(repository: PaperRepository, supportRoot: URL, fileManager: FileManager = .default) {
        self.repository = repository
        self.supportRoot = supportRoot
        self.fileManager = fileManager
    }

    public func importPDF(
        from sourceURL: URL,
        metadata: PaperImportMetadata? = nil,
        now: Date = Date()
    ) throws -> PaperImportResult {
        let standardizedSource = sourceURL.standardizedFileURL
        let data = try Data(contentsOf: standardizedSource)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let existing = try repository.fetchPaper(fileHash: hash) {
            return PaperImportResult(paper: existing, didImport: false)
        }

        let fallbackTitle = standardizedSource.deletingPathExtension().lastPathComponent
        let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackTitle
        let paperID = makePaperID(title: title, hash: hash)
        let paperDir = supportRoot.appendingPathComponent("papers/\(paperID)", isDirectory: true)
        try fileManager.createDirectory(at: paperDir, withIntermediateDirectories: true)
        let destination = paperDir.appendingPathComponent("original.pdf")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try data.write(to: destination, options: [.atomic])

        let index = try PDFIndexExtractor().extract(paperID: paperID, pdfURL: destination)
        let paper = Paper(
            id: paperID,
            filePath: destination.path,
            fileHash: hash,
            title: title,
            authors: metadata?.authors ?? [],
            year: metadata?.year,
            sourceURL: metadata?.sourceURL,
            importedAt: now,
            updatedAt: now
        )
        try repository.upsertPaper(paper)
        for page in index.pages {
            try repository.upsertPage(page)
        }
        for span in index.spans {
            try repository.upsertSpan(span)
        }

        return PaperImportResult(paper: paper, didImport: true)
    }

    private func makePaperID(title: String, hash: String) -> String {
        let slug = makeSlug(from: title)
        return "\(slug.isEmpty ? "paper" : slug)-\(hash.prefix(10))"
    }

    private func makeSlug(from text: String) -> String {
        text
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
