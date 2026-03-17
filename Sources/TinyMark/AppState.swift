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

    // MARK: - File type detection

    var isSVGFile: Bool {
        selectedFile?.pathExtension.lowercased() == "svg"
    }

    private static let markdownExtensions = Set(["md", "markdown"])

    var isMarkdownFile: Bool {
        guard let ext = selectedFile?.pathExtension.lowercased() else { return false }
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
