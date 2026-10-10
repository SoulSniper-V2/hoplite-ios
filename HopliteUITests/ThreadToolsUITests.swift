import XCTest

/// Thread-level tools beyond chat: details (spend limit, checkpoints, workspace recovery,
/// export) and pull request review (review loop, review comments).
final class ThreadToolsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    func testDetailsRestoreCheckpointAndRecoverWorkspace() {
        app.launchArguments = ["-UITestDemo", "YES"]
        app.launch()

        let row = element(containing: "Investigate Sentry")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        app.buttons["Thread actions"].tap()
        app.buttons["Details & checkpoints"].tap()
        XCTAssertTrue(app.staticTexts["Details"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Export transcript"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(element(containing: "The sandbox can't start").waitForExistence(timeout: 5))
        snapshot("20-details")

        app.buttons["Restore snapshot"].tap()
        XCTAssertTrue(element(containing: "Sandbox healthy").waitForExistence(timeout: 6))

        let restore = app.buttons.matching(identifier: "Restore").firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        app.buttons["Restore workspace"].tap()
        XCTAssertTrue(element(containing: "Workspace restored").waitForExistence(timeout: 8), "the thread shows the restore status")
        snapshot("21-restored")
    }

    func testPullRequestReviewLoopAndComments() {
        app.launchArguments = ["-UITestDemo", "YES", "-UITestThread", "thr_billing", "-UITestSheet", "pr"]
        app.launch()

        let loop = app.switches["reviewLoop"]
        XCTAssertTrue(loop.waitForExistence(timeout: 20))
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: loop)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 5), .completed)
        XCTAssertTrue(element(containing: "2 unresolved").waitForExistence(timeout: 8))
        XCTAssertTrue(element(containing: "backfill").exists)
        snapshot("22-review-comments")

        let showResolved = element(containing: "Show 1 resolved")
        for _ in 0..<4 where !showResolved.isHittable { app.swipeUp() }
        showResolved.tap()
        XCTAssertTrue(element(containing: "const tuple").waitForExistence(timeout: 3))
    }

    func testFilterChipsSwitchWithoutCrashing() {
        app.launchArguments = ["-UITestDemo", "YES"]
        app.launch()
        XCTAssertTrue(element(containing: "Add rate limiting").waitForExistence(timeout: 10))
        for chip in ["attention", "active", "ready", "all", "attention", "ready"] {
            app.buttons["filter-\(chip)"].tap()
            sleep(1)
            XCTAssertEqual(app.state, .runningForeground, "app crashed after tapping \(chip)")
        }
        XCTAssertFalse(app.staticTexts["In progress"].exists, "Ready filter hides running threads")
    }
}
