import AppKit
import PaperCodexCore
import PDFKit

final class PDFThumbnailCache {
    private let root: URL
    private let fileManager: FileManager

    init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    func thumbnails(for paper: Paper, pageLimit: Int = 5) throws -> [URL] {
        let directory = root.appendingPathComponent(paper.id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (1...pageLimit).map { directory.appendingPathComponent(String(format: "p%03d.png", $0)) }
        if existing.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) {
            return existing
        }

        guard let document = PDFDocument(url: URL(fileURLWithPath: paper.filePath)) else {
            return []
        }
        var urls: [URL] = []
        let count = min(pageLimit, document.pageCount)
        for index in 0..<count {
            guard let page = document.page(at: index) else {
                continue
            }
            let image = page.thumbnail(of: CGSize(width: 86, height: 112), for: .cropBox)
            guard let data = image.pngData else {
                continue
            }
            let url = directory.appendingPathComponent(String(format: "p%03d.png", index + 1))
            try data.write(to: url, options: [.atomic])
            urls.append(url)
        }
        return urls
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
