#!/usr/bin/env swift

import AppKit
import Foundation
import PDFKit

let defaultVaultRoot = "/Users/horizon/Documents/Obsidian-Main/世界模型"
let arguments = CommandLine.arguments.dropFirst()
let vaultRoot = URL(fileURLWithPath: arguments.first ?? defaultVaultRoot, isDirectory: true).standardizedFileURL
let papersRoot = vaultRoot
    .appendingPathComponent("03-literature", isDirectory: true)
    .appendingPathComponent("papers", isDirectory: true)
let thumbnailsRoot = vaultRoot
    .appendingPathComponent("03-literature", isDirectory: true)
    .appendingPathComponent("assets", isDirectory: true)
    .appendingPathComponent("paper-thumbnails", isDirectory: true)
let supportRoot = URL(fileURLWithPath: "/Users/horizon/Documents/PaperCodex/.papercodex-obsidian", isDirectory: true)

struct PaperNote {
    var url: URL
    var frontmatter: [String]
    var body: ArraySlice<String>
    var properties: [String: String]
}

enum ThumbnailSource: String {
    case pdfFirstPage = "pdf_first_page"
    case generatedTitleCard = "generated_title_card"
}

func loadPaperNotes() throws -> [PaperNote] {
    guard let enumerator = FileManager.default.enumerator(
        at: papersRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var notes: [PaperNote] = []
    for case let url as URL in enumerator where url.pathExtension == "md" {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            continue
        }
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else {
            continue
        }
        let frontmatter = Array(lines[1..<closingIndex])
        let properties = scalarProperties(frontmatter)
        guard properties["type"] == "literature-note" else {
            continue
        }
        notes.append(PaperNote(url: url, frontmatter: frontmatter, body: lines[closingIndex...], properties: properties))
    }
    return notes.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
}

func scalarProperties(_ lines: [String]) -> [String: String] {
    var properties: [String: String] = [:]
    for line in lines {
        guard !line.hasPrefix(" "), let separator = line.firstIndex(of: ":") else {
            continue
        }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = cleanScalar(String(line[line.index(after: separator)...]))
        if !key.isEmpty, !value.isEmpty {
            properties[key] = value
        }
    }
    return properties
}

func cleanScalar(_ value: String) -> String {
    var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"")) || (cleaned.hasPrefix("'") && cleaned.hasSuffix("'")) {
        cleaned = String(cleaned.dropFirst().dropLast())
    }
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}

func slug(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
        .map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        .reduce(into: "") { result, character in
            if character == "-", result.last == "-" {
                return
            }
            result.append(character)
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func thumbnailFilename(for note: PaperNote) -> String {
    let id = note.properties["arxiv"].map { "arxiv-\($0)" }
        ?? note.url.deletingPathExtension().lastPathComponent
    let title = note.properties["short_title"]
        ?? note.properties["paper_title"]
        ?? note.url.deletingPathExtension().lastPathComponent
    let suffix = slug(title)
    return "\(slug(id))\(suffix.isEmpty ? "" : "-\(suffix)").png"
}

func cachedPDFURL(arxiv: String?) -> URL? {
    guard let arxiv else {
        return nil
    }
    let cacheID = "obsidian-arxiv-\(slug(arxiv))"
    let url = supportRoot
        .appendingPathComponent("obsidian-pdf-cache", isDirectory: true)
        .appendingPathComponent(cacheID, isDirectory: true)
        .appendingPathComponent("original.pdf")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

func downloadPDF(from urlString: String, noteID: String) throws -> URL {
    guard let url = URL(string: urlString) else {
        throw NSError(domain: "PaperThumbnail", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid pdf_url: \(urlString)"])
    }
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-thumbnail-\(noteID)-\(UUID().uuidString).pdf")
    if downloadPDFWithCurl(from: url.absoluteString, to: destination) {
        return destination
    }

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<URL, Error>!
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 60
    let session = URLSession(configuration: configuration)
    session.downloadTask(with: url) { temporaryURL, _, error in
        defer { session.invalidateAndCancel() }
        if let error {
            result = .failure(error)
        } else if let temporaryURL {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                result = .success(destination)
            } catch {
                result = .failure(error)
            }
        } else {
            result = .failure(NSError(domain: "PaperThumbnail", code: 2, userInfo: [NSLocalizedDescriptionKey: "No temporary PDF URL"]))
        }
        semaphore.signal()
    }.resume()
    semaphore.wait()
    return try result.get()
}

func downloadPDFWithCurl(from urlString: String, to destination: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = [
        "-fsSL",
        "--max-time", "120",
        "--retry", "2",
        "--retry-delay", "1",
        "-A", "PaperCodex thumbnail generator",
        "-o", destination.path,
        urlString
    ]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0,
           (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 {
            return true
        }
    } catch {
        return false
    }
    try? FileManager.default.removeItem(at: destination)
    return false
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PaperThumbnail", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try pngData.write(to: url, options: .atomic)
}

func renderPDFThumbnail(pdfURL: URL, outputURL: URL) throws {
    guard let document = PDFDocument(url: pdfURL),
          let page = document.page(at: 0) else {
        throw NSError(domain: "PaperThumbnail", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not open PDF first page"])
    }
    let image = page.thumbnail(of: CGSize(width: 900, height: 1180), for: .cropBox)
    try writePNG(image, to: outputURL)
}

func renderTitleCard(note: PaperNote, outputURL: URL) throws {
    let size = NSSize(width: 900, height: 1180)
    let title = note.properties["paper_title"] ?? note.properties["short_title"] ?? note.url.deletingPathExtension().lastPathComponent
    let arxiv = note.properties["arxiv"] ?? "no pdf_url"
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.20, alpha: 1).setStroke()
    NSBezierPath(rect: NSRect(x: 42, y: 42, width: size.width - 84, height: size.height - 84)).stroke()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.10, alpha: 1),
        .paragraphStyle: paragraph
    ]
    let metaAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 28, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.36, alpha: 1)
    ]
    title.draw(in: NSRect(x: 88, y: 500, width: size.width - 176, height: 430), withAttributes: titleAttributes)
    arxiv.draw(in: NSRect(x: 88, y: 230, width: size.width - 176, height: 50), withAttributes: metaAttributes)
    "Paper thumbnail placeholder".draw(in: NSRect(x: 88, y: 178, width: size.width - 176, height: 44), withAttributes: metaAttributes)
    image.unlockFocus()
    try writePNG(image, to: outputURL)
}

func upsertFrontmatter(note: PaperNote, thumbnailWikiLink: String) throws {
    var lines = note.frontmatter
    upsertScalar(key: "paper_thumbnail", value: "\"\(thumbnailWikiLink)\"", lines: &lines)
    let output = (["---"] + lines + Array(note.body)).joined(separator: "\n")
    try output.write(to: note.url, atomically: true, encoding: .utf8)
}

func upsertScalar(key: String, value: String, lines: inout [String]) {
    if let index = lines.firstIndex(where: { line in
        guard !line.hasPrefix(" "), let separator = line.firstIndex(of: ":") else {
            return false
        }
        return String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines) == key
    }) {
        lines[index] = "\(key): \(value)"
    } else {
        lines.append("\(key): \(value)")
    }
}

try FileManager.default.createDirectory(at: thumbnailsRoot, withIntermediateDirectories: true)
let notes = try loadPaperNotes()
var rendered = 0
var placeholders = 0
var skipped = 0
let counterLock = NSLock()

func writeLine(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

func increment(_ counter: inout Int) {
    counterLock.lock()
    counter += 1
    counterLock.unlock()
}

func process(_ note: PaperNote) {
    autoreleasepool {
        do {
            let filename = thumbnailFilename(for: note)
            let outputURL = thumbnailsRoot.appendingPathComponent(filename)
            let wikiLink = "[[世界模型/03-literature/assets/paper-thumbnails/\(filename)]]"
            if FileManager.default.fileExists(atPath: outputURL.path),
               note.properties["paper_thumbnail"] == wikiLink {
                increment(&skipped)
                return
            }

            let source: ThumbnailSource
            if let cached = cachedPDFURL(arxiv: note.properties["arxiv"]) {
                try renderPDFThumbnail(pdfURL: cached, outputURL: outputURL)
                source = .pdfFirstPage
            } else if let pdfURL = note.properties["pdf_url"] {
                let temporaryPDF = try downloadPDF(from: pdfURL, noteID: slug(note.url.deletingPathExtension().lastPathComponent))
                defer { try? FileManager.default.removeItem(at: temporaryPDF) }
                try renderPDFThumbnail(pdfURL: temporaryPDF, outputURL: outputURL)
                source = .pdfFirstPage
            } else {
                try renderTitleCard(note: note, outputURL: outputURL)
                source = .generatedTitleCard
            }
            try upsertFrontmatter(note: note, thumbnailWikiLink: wikiLink)
            switch source {
            case .pdfFirstPage:
                increment(&rendered)
            case .generatedTitleCard:
                increment(&placeholders)
            }
            writeLine("\(source.rawValue): \(note.url.lastPathComponent)")
        } catch {
            do {
                let filename = thumbnailFilename(for: note)
                let outputURL = thumbnailsRoot.appendingPathComponent(filename)
                let wikiLink = "[[世界模型/03-literature/assets/paper-thumbnails/\(filename)]]"
                try renderTitleCard(note: note, outputURL: outputURL)
                try upsertFrontmatter(note: note, thumbnailWikiLink: wikiLink)
                increment(&placeholders)
                writeLine("generated_title_card_after_error: \(note.url.lastPathComponent) :: \(error)")
            } catch {
                fputs("failed: \(note.url.path) :: \(error)\n", stderr)
            }
        }
    }
}

let group = DispatchGroup()
let concurrency = DispatchSemaphore(value: 6)
for note in notes {
    concurrency.wait()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        process(note)
        concurrency.signal()
        group.leave()
    }
}
group.wait()

print("summary: notes=\(notes.count) rendered=\(rendered) placeholders=\(placeholders) skipped=\(skipped)")
