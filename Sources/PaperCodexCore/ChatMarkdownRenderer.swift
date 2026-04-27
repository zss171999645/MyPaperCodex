import Foundation

public enum ChatMarkdownRenderer {
    public static func renderDocument(markdown: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
          color-scheme: light dark;
          font: -apple-system-body;
        }
        body {
          margin: 0;
          background: transparent;
          color: CanvasText;
          overflow-wrap: anywhere;
        }
        .message {
          font-size: 14px;
          line-height: 1.48;
        }
        p, ul, ol, blockquote, pre, table {
          margin: 0 0 0.72em;
        }
        h1, h2, h3 {
          margin: 0.25em 0 0.45em;
          line-height: 1.2;
        }
        h1 { font-size: 1.35em; }
        h2 { font-size: 1.18em; }
        h3 { font-size: 1.05em; }
        a {
          color: LinkText;
        }
        a.citation {
          display: inline-flex;
          align-items: center;
          min-width: 1.6em;
          height: 1.45em;
          padding: 0 0.35em;
          border-radius: 0.72em;
          background: color-mix(in srgb, LinkText 16%, transparent);
          color: LinkText;
          font-size: 0.86em;
          font-weight: 650;
          text-decoration: none;
          vertical-align: 0.08em;
        }
        code {
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: 0.92em;
          background: color-mix(in srgb, CanvasText 8%, transparent);
          border-radius: 4px;
          padding: 0.08em 0.28em;
        }
        pre {
          overflow-x: auto;
          padding: 0.7em;
          border-radius: 6px;
          background: color-mix(in srgb, CanvasText 8%, transparent);
        }
        pre code {
          background: transparent;
          padding: 0;
        }
        blockquote {
          padding-left: 0.8em;
          border-left: 3px solid color-mix(in srgb, CanvasText 24%, transparent);
          color: color-mix(in srgb, CanvasText 78%, transparent);
        }
        table {
          border-collapse: collapse;
          width: 100%;
        }
        th, td {
          border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
          padding: 0.35em 0.5em;
          text-align: left;
        }
        img {
          max-width: 100%;
          height: auto;
          border-radius: 6px;
        }
        </style>
        <script>
        window.MathJax = {
          tex: {
            inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
            displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']]
          },
          options: {
            skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code']
          }
        };
        </script>
        <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>
        </head>
        <body>
        <div class="message">
        \(renderFragment(markdown: markdown))
        </div>
        <script>
        function reportHeight() {
          const height = Math.ceil(document.documentElement.scrollHeight);
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.height) {
            window.webkit.messageHandlers.height.postMessage(height);
          }
        }
        window.addEventListener('load', reportHeight);
        window.addEventListener('resize', reportHeight);
        setTimeout(reportHeight, 50);
        setTimeout(reportHeight, 250);
        setTimeout(reportHeight, 1000);
        </script>
        </body>
        </html>
        """
    }

    public static func renderFragment(markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var html: [String] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var orderedListItems: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else {
                return
            }
            html.append("<p>\(renderInline(paragraph.joined(separator: "\n")))</p>")
            paragraph.removeAll()
        }

        func flushLists() {
            if !listItems.isEmpty {
                html.append("<ul>\(listItems.map { "<li>\($0)</li>" }.joined())</ul>")
                listItems.removeAll()
            }
            if !orderedListItems.isEmpty {
                html.append("<ol>\(orderedListItems.map { "<li>\($0)</li>" }.joined())</ol>")
                orderedListItems.removeAll()
            }
        }

        func flushCode() {
            guard !codeLines.isEmpty else {
                return
            }
            html.append("<pre><code>\(escapeText(codeLines.joined(separator: "\n")))</code></pre>")
            codeLines.removeAll()
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushLists()
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    inCode = true
                }
                index += 1
                continue
            }

            if inCode {
                codeLines.append(line)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushLists()
                index += 1
                continue
            }

            if isTableStart(lines: lines, index: index) {
                flushParagraph()
                flushLists()
                let rendered = renderTable(lines: lines, start: index)
                html.append(rendered.html)
                index = rendered.nextIndex
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                flushLists()
                html.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                flushLists()
                html.append("<blockquote>\(renderInline(String(trimmed.dropFirst(2))))</blockquote>")
                index += 1
                continue
            }

            if let unordered = parseUnorderedListItem(trimmed) {
                flushParagraph()
                orderedListItems.removeAll()
                listItems.append(renderInline(unordered))
                index += 1
                continue
            }

            if let ordered = parseOrderedListItem(trimmed) {
                flushParagraph()
                listItems.removeAll()
                orderedListItems.append(renderInline(ordered))
                index += 1
                continue
            }

            paragraph.append(line)
            index += 1
        }

        if inCode {
            flushCode()
        }
        flushParagraph()
        flushLists()
        return html.joined(separator: "\n")
    }

    private static func renderInline(_ text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix("!["),
               let close = text[index...].range(of: "]("),
               let end = text[close.upperBound...].firstIndex(of: ")") {
                let altStart = text.index(index, offsetBy: 2)
                let alt = String(text[altStart..<close.lowerBound])
                let source = String(text[close.upperBound..<end])
                output.append(#"<img alt="\#(escapeAttribute(alt))" src="\#(escapeAttribute(normalizeImageSource(source)))">"#)
                index = text.index(after: end)
                continue
            }

            if text[index] == "[",
               let close = text[index...].range(of: "]("),
               let end = text[close.upperBound...].firstIndex(of: ")") {
                let labelStart = text.index(after: index)
                let label = String(text[labelStart..<close.lowerBound])
                let href = String(text[close.upperBound..<end])
                let className = href.hasPrefix("papercodex-cite://") ? #" class="citation""# : ""
                output.append(#"<a\#(className) href="\#(escapeAttribute(href))">\#(renderInline(label))</a>"#)
                index = text.index(after: end)
                continue
            }

            if text[index] == "`",
               let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let code = String(text[text.index(after: index)..<end])
                output.append("<code>\(escapeText(code))</code>")
                index = text.index(after: end)
                continue
            }

            if text[index...].hasPrefix("**"),
               let end = text[text.index(index, offsetBy: 2)...].range(of: "**")?.lowerBound {
                let content = String(text[text.index(index, offsetBy: 2)..<end])
                output.append("<strong>\(renderInline(content))</strong>")
                index = text.index(end, offsetBy: 2)
                continue
            }

            if text[index] == "*",
               let end = text[text.index(after: index)...].firstIndex(of: "*") {
                let content = String(text[text.index(after: index)..<end])
                output.append("<em>\(renderInline(content))</em>")
                index = text.index(after: end)
                continue
            }

            output.append(escapeText(String(text[index])))
            index = text.index(after: index)
        }

        return output.replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard markerCount > 0, markerCount <= 3 else {
            return nil
        }
        let textStart = line.index(line.startIndex, offsetBy: markerCount)
        guard textStart < line.endIndex, line[textStart] == " " else {
            return nil
        }
        return (markerCount, String(line[line.index(after: textStart)...]))
    }

    private static func parseUnorderedListItem(_ line: String) -> String? {
        for marker in ["- ", "* "] {
            if line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count))
            }
        }
        return nil
    }

    private static func parseOrderedListItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else {
            return nil
        }
        let prefix = line[..<dot]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else {
            return nil
        }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else {
            return nil
        }
        return String(line[line.index(after: afterDot)...])
    }

    private static func isTableStart(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else {
            return false
        }
        return lines[index].contains("|") && isTableSeparator(lines[index + 1])
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return false
        }
        let stripped = trimmed.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty
    }

    private static func renderTable(lines: [String], start: Int) -> (html: String, nextIndex: Int) {
        let headers = splitTableRow(lines[start])
        var index = start + 2
        var rows: [[String]] = []
        while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            rows.append(splitTableRow(lines[index]))
            index += 1
        }
        let headerHTML = headers.map { "<th>\(renderInline($0))</th>" }.joined()
        let bodyHTML = rows.map { row in
            "<tr>\(row.map { "<td>\(renderInline($0))</td>" }.joined())</tr>"
        }.joined()
        return ("<table><thead><tr>\(headerHTML)</tr></thead><tbody>\(bodyHTML)</tbody></table>", index)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func normalizeImageSource(_ source: String) -> String {
        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source).absoluteString
        }
        return source
    }

    private static func escapeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeText(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
