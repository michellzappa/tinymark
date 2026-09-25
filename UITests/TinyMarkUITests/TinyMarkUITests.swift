import Foundation
import XCTest

final class TinyMarkUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchesWithFixtureAndShowsMarkdownMode() {
        let fixturePath = fixturePath(named: "sample.md")
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-ai", "--disable-spotlight", "--disable-file-watchers"]
        app.launchEnvironment["TINY_FIXTURE_PATH"] = fixturePath

        app.launch()

        let probe = app.staticTexts["ui-smoke-status"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        XCTAssertTrue(probe.label.contains("sample.md"))
        XCTAssertTrue(probe.label.contains("mode:markdown"))
    }

    private func fixturePath(named name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
            .path
    }
}
