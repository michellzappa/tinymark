import XCTest
@testable import TinyMark

final class AppStateTests: XCTestCase {
    func testRenderedHTMLIncludesFrontmatterTableAndMarkdownBody() {
        let state = AppState()
        state.selectedFile = URL(fileURLWithPath: "/tmp/sample.md")
        state.content = """
        ---
        title: TinyMark
        author: mz
        ---

        # Heading
        """

        let html = state.renderedHTML

        XCTAssertTrue(html.contains("frontmatter"))
        XCTAssertTrue(html.contains("TinyMark"))
        XCTAssertTrue(html.contains("<h1>Heading</h1>"))
    }

    func testRenderedHTMLSupportsPlainTextAndSVGModes() {
        let state = AppState()

        state.selectedFile = URL(fileURLWithPath: "/tmp/note.txt")
        state.content = "<tag>"
        XCTAssertTrue(state.renderedHTML.contains("&lt;tag&gt;"))

        state.selectedFile = URL(fileURLWithPath: "/tmp/graphic.svg")
        state.content = "<svg viewBox=\"0 0 10 10\"></svg>"
        XCTAssertTrue(state.renderedHTML.contains("<svg viewBox=\"0 0 10 10\"></svg>"))
    }
}
