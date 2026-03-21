import Foundation
import SwiftUI
import Markdown
import TinyKit

@Observable
final class AppState: FileState {
    init() {
        super.init(
            bookmarkKey: "lastFolderBookmark",
            defaultExtension: "md",
            supportedExtensions: ["md", "markdown", "svg", "txt", "text"]
        )
    }

    private static let spotlightDomain = "com.tinyapps.tinymark.files"

    override func didOpenFile(_ url: URL) {
        indexFile(url)
    }

    override func didSaveFile(_ url: URL) {
        indexFile(url)
    }

    private func indexFile(_ url: URL) {
        // Extract first heading as display name
        let heading = content.components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("# ") })
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        SpotlightIndexer.index(file: url, content: content, domainID: Self.spotlightDomain, displayName: heading)
    }

    // MARK: - Export HTML

    var exportHTML: String {
        guard let url = Bundle.main.url(forResource: "preview", withExtension: "html"),
              let template = try? String(contentsOf: url, encoding: .utf8) else {
            return ExportManager.wrapHTML(body: renderedHTML, title: selectedFile?.lastPathComponent ?? "document")
        }
        return template
            .replacingOccurrences(of: "<div id=\"content\"></div>",
                                  with: "<div id=\"content\">\(renderedHTML)</div>")
            .replacingOccurrences(of: "background: transparent;",
                                  with: "background: var(--bg);")
    }

    // MARK: - File type detection

    var isSVGFile: Bool {
        selectedFile?.pathExtension.lowercased() == "svg"
    }

    private static let markdownExtensions = Set(["md", "markdown"])

    var isMarkdownFile: Bool {
        guard let ext = selectedFile?.pathExtension.lowercased() else {
            // No file selected — default to markdown (the app's primary format)
            return true
        }
        return Self.markdownExtensions.contains(ext)
    }

    // MARK: - Rendered HTML

    var renderedHTML: String {
        if isSVGFile {
            return "<div style=\"display:flex;justify-content:center;padding:20px\">\(content)</div>"
        }

        guard isMarkdownFile else {
            let escaped = content
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<pre style=\"white-space:pre-wrap;word-wrap:break-word;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;line-height:1.5;\">\(escaped)</pre>"
        }

        let (frontmatter, body) = Self.extractFrontmatter(content)
        let document = Document(parsing: body)
        var html = HTMLFormatter.format(document)

        if let fm = frontmatter {
            html = Self.renderFrontmatterTable(fm) + html
        }

        return html
    }

    // MARK: - Frontmatter

    private static func extractFrontmatter(_ text: String) -> ([(String, String)]?, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return (nil, text) }

        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, text) }

        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }

        guard let end = endIndex, end > 1 else { return (nil, text) }

        var pairs: [(String, String)] = []
        for i in 1..<end {
            let line = lines[i]
            guard let colonRange = line.range(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                pairs.append((key, value))
            }
        }

        let body = lines[(end + 1)...].joined(separator: "\n")
        return (pairs.isEmpty ? nil : pairs, body)
    }

    private static func renderFrontmatterTable(_ pairs: [(String, String)]) -> String {
        var html = "<table class=\"frontmatter\"><tbody>"
        for (key, value) in pairs {
            let escapedKey = key.replacingOccurrences(of: "<", with: "&lt;")
            let escapedValue = value.replacingOccurrences(of: "<", with: "&lt;")
            html += "<tr><td class=\"fm-key\">\(escapedKey)</td><td>\(escapedValue)</td></tr>"
        }
        html += "</tbody></table>"
        return html
    }
}
