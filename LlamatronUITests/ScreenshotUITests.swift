import XCTest

/// Drives the app in a simulator to capture landscape iPad screenshots via fastlane
/// `snapshot`. Launches with `--uitest-seed` so the app shows canned, anonymized content
/// (see `ScreenshotSeed`), plus UserDefaults launch-argument overrides so no real server
/// URL or first-run sheet appears.
final class ScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testScreenshots() {
        let app = XCUIApplication(bundleIdentifier: "com.llamatron.Llamatron")
        setupSnapshot(app)
        app.launchArguments += [
            "--uitest-seed",
            "-didCompleteFirstRun", "YES",
            "-defaultBackend", "llamaServer",
            "-llamaServerURL", "http://localhost:8080",
        ]
        app.launch()

        XCUIDevice.shared.orientation = .landscapeLeft

        // Wait for the seeded hero conversation to render (its title in the sidebar).
        let heroTitle = app.staticTexts["Swift concurrency"]
        XCTAssertTrue(heroTitle.waitForExistence(timeout: 20),
                      "Seeded screenshot content did not appear")

        // Let Markdown + syntax highlighting settle before capturing.
        sleep(2)
        snapshot("01-Chat")

        // Web-research view: select the session with the attached Wikipedia source, so
        // the shot shows the source chip and a transcript reflecting the researched topic.
        app.staticTexts["Bioluminescence"].tap()
        _ = app.staticTexts["Bioluminescence (Wikipedia)"].waitForExistence(timeout: 10)
        sleep(1)
        snapshot("02-WebResearch")
    }
}
