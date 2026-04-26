import Foundation

public struct WatchedFolderScanResult: Equatable, Sendable {
    public var folder: WatchedFolder
    public var importedPapers: [Paper]
    public var existingPapers: [Paper]

    public init(folder: WatchedFolder, importedPapers: [Paper], existingPapers: [Paper]) {
        self.folder = folder
        self.importedPapers = importedPapers
        self.existingPapers = existingPapers
    }
}

public final class WatchedFolderScanner {
    private let repository: PaperRepository
    private let importer: PaperLibraryImporter
    private let fileManager: FileManager

    public init(repository: PaperRepository, supportRoot: URL, fileManager: FileManager = .default) {
        self.repository = repository
        self.importer = PaperLibraryImporter(repository: repository, supportRoot: supportRoot, fileManager: fileManager)
        self.fileManager = fileManager
    }

    public func scan(folder: WatchedFolder, now: Date = Date()) throws -> WatchedFolderScanResult {
        let pdfURLs = try pdfFiles(in: URL(fileURLWithPath: folder.path, isDirectory: true))
        var imported: [Paper] = []
        var existing: [Paper] = []
        for pdfURL in pdfURLs {
            let result = try importer.importPDF(from: pdfURL, now: now)
            if result.didImport {
                imported.append(result.paper)
            } else {
                existing.append(result.paper)
            }
        }

        var updatedFolder = folder
        updatedFolder.lastScannedAt = now
        try repository.upsertWatchedFolder(updatedFolder)
        return WatchedFolderScanResult(folder: updatedFolder, importedPapers: imported, existingPapers: existing)
    }

    public func scanAllWatchedFolders(now: Date = Date()) throws -> [WatchedFolderScanResult] {
        let folders = try repository.fetchWatchedFolders()
        var results: [WatchedFolderScanResult] = []
        for folder in folders {
            results.append(try scan(folder: folder, now: now))
        }
        return results
    }

    private func pdfFiles(in folderURL: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: folderURL.standardizedFileURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.compare("pdf", options: [.caseInsensitive]) == .orderedSame else {
                continue
            }
            let values = try url.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                urls.append(url.standardizedFileURL)
            }
        }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
