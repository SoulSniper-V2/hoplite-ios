import XCTest

/// End-to-end flows against the built-in demo workspace, which simulates runs, drafts and
/// approvals with the same event shapes as api.hoplite.sh.
final class HopliteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String]) {
        let theme = ProcessInfo.processInfo.environment["SHOT_APPEARANCE"].map { ["-appearance", $0] } ?? []
        app.launchArguments = arguments + theme
        app.launch()
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

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    func testOnboardingEntersDemo() {
        launch(["-UITestSignedOut", "YES"])
        XCTAssertTrue(app.buttons["Sign in with Hoplite"].waitForExistence(timeout: 5))
        snapshot("01-onboarding")
        app.buttons["Explore the demo workspace"].tap()
        XCTAssertTrue(element(containing: "Add rate limiting to the public API").waitForExistence(timeout: 8))
        snapshot("02-threads")
    }

    func testLiveRunRequestsApprovalAndFinishes() {
        launch(["-UITestDemo", "YES"])
        let row = element(containing: "Add rate limiting to the public API")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let approve = app.buttons["Approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 40), "the simulated run should pause for approval")
        snapshot("03-approval")
        approve.tap()

        XCTAssertTrue(element(containing: "ready for review").waitForExistence(timeout: 30))
        snapshot("04-approved")

        let composer = app.descendants(matching: .any)["composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Add a test for the 429 path")
        app.buttons["Send"].tap()
        XCTAssertTrue(element(containing: "Add a test for the 429 path").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Done. I worked through").waitForExistence(timeout: 40))
        snapshot("05-follow-up")
    }

    func testCreateThreadPreparesWorkspaceAndRuns() {
        launch(["-UITestDemo", "YES"])
        let compose = app.buttons["New thread"]
        XCTAssertTrue(compose.waitForExistence(timeout: 5))
        compose.tap()
        let prompt = app.descendants(matching: .any)["newThreadPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("Add order history to the account page")
        snapshot("06-new-thread")
        app.buttons["Start thread"].tap()
        XCTAssertTrue(element(containing: "Preparing cloud workspace").waitForExistence(timeout: 10))
        snapshot("07-preparing")
        XCTAssertTrue(element(containing: "Done. I worked through").waitForExistence(timeout: 45))
        snapshot("08-new-thread-done")
    }

    func testInboxApprovalAndReview() {
        launch(["-UITestDemo", "YES", "-UITestTab", "inbox"])
        let approve = app.buttons["Approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 8))
        snapshot("09-inbox")
        approve.tap()
        let ready = element(containing: "Fix the flaky checkout test")
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        ready.tap()
        XCTAssertTrue(app.buttons["Changes"].waitForExistence(timeout: 5))
        app.buttons["Changes"].tap()
        XCTAssertTrue(element(containing: "files changed").waitForExistence(timeout: 5))
        snapshot("10-diff")
    }

    func testSlideToMergeReadyPullRequest() {
        launch(["-UITestDemo", "YES", "-UITestThread", "thr_checkout"])
        let review = element(containing: "ready to merge")
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        review.tap()
        let slider = app.descendants(matching: .any).matching(identifier: "slideToConfirm").firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 8))
        snapshot("11-pr")
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(element(containing: "Merged").waitForExistence(timeout: 8))
        snapshot("12-merged")
    }

    func testLiveActivityOnLockScreenAndDynamicIsland() {
        launch(["-UITestDemo", "YES"])
        XCTAssertTrue(element(containing: "Add rate limiting to the public API").waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 5))
        sleep(20)

        XCUIDevice.shared.press(.home)
        sleep(2)
        snapshot("13-home-island")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 1.2)
        sleep(1)
        snapshot("14-island-expanded")
        let islandApprove = springboard.buttons["Approve"].firstMatch
        XCTAssertTrue(islandApprove.waitForExistence(timeout: 5), "the expanded island should offer Approve")
        islandApprove.tap()
        sleep(3)
        app.activate()
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertFalse(element(containing: "github/workflows/ci.yml").waitForExistence(timeout: 4), "approving from the island should resolve it in the app")
        XCUIDevice.shared.press(.home)
        sleep(1)

        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(2)
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(3)
        snapshot("15-lock-screen")
        XCTAssertTrue(springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Hoplite")).firstMatch.waitForExistence(timeout: 5))
    }

    func testCreateWebhookFromWorkspaceAppearsInList() {
        launch(["-UITestDemo", "YES", "-UITestAccount", "YES"])
        let webhooks = app.buttons["Webhooks"]
        XCTAssertTrue(element(containing: "Spend this period").waitForExistence(timeout: 10))
        reveal(webhooks)
        webhooks.tap()
        XCTAssertTrue(element(containing: "ci.acme.dev").waitForExistence(timeout: 5))
        snapshot("20-webhooks")

        app.buttons["New webhook"].tap()
        let url = app.textFields["webhookURL"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("https://deploys.acme.dev/hooks/hoplite")
        snapshot("21-new-webhook")
        app.buttons["Create"].tap()

        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 8), "the signing secret should be revealed once")
        snapshot("22-webhook-secret")
        app.buttons["Done"].tap()
        XCTAssertTrue(element(containing: "deploys.acme.dev").waitForExistence(timeout: 5))
        snapshot("23-webhook-created")
    }

    func testCreateAutomationFromAutomationsTab() {
        launch(["-UITestDemo", "YES", "-UITestTab", "automations"])
        XCTAssertTrue(element(containing: "Nightly flaky test sweep").waitForExistence(timeout: 8))
        app.buttons["New automation"].tap()
        let name = app.textFields["automationName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Morning dependency digest")
        let prompt = app.textFields["automationPrompt"].exists ? app.textFields["automationPrompt"] : app.textViews["automationPrompt"]
        prompt.tap()
        prompt.typeText("Summarize outdated dependencies and open a PR for safe upgrades.")
        snapshot("24-new-automation")
        app.buttons["Create"].tap()
        XCTAssertTrue(element(containing: "Morning dependency digest").waitForExistence(timeout: 8))
        snapshot("25-automation-created")
    }

    func testWorkspaceTourCapturesEveryScreen() {
        launch(["-UITestDemo", "YES", "-UITestAccount", "YES"])
        let projects = app.buttons["Projects"]
        XCTAssertTrue(element(containing: "Spend this period").waitForExistence(timeout: 10))
        reveal(projects)
        snapshot("30-account-workspace")
        projects.tap()
        let storefront = element(containing: "storefront")
        XCTAssertTrue(storefront.waitForExistence(timeout: 5))
        snapshot("31-projects")
        storefront.tap()
        XCTAssertTrue(app.buttons["Edit repositories"].waitForExistence(timeout: 5))
        snapshot("32-project-detail")
        app.swipeUp()
        snapshot("33-project-detail-more")
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["projectName"].waitForExistence(timeout: 5))
        snapshot("34-project-edit")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["New project"].tap()
        XCTAssertTrue(app.textFields["projectName"].waitForExistence(timeout: 5))
        snapshot("35-new-project")
        app.buttons["Choose a repository"].tap()
        XCTAssertTrue(element(containing: "billing").waitForExistence(timeout: 5))
        snapshot("36-repo-picker")
        element(containing: "mobile-app").tap()
        XCTAssertTrue(element(containing: "Detected").waitForExistence(timeout: 5))
        sleep(1)
        snapshot("37-new-project-picked")
    }

    func testWorkspaceTourOfAdminLists() {
        for (route, name, marker) in [("env", "40-environment", "storefront"), ("mcp", "41-mcp", "Linear"), ("accounts", "42-accounts", "ci-deploy-bot"), ("about", "43-about", "API healthy")] {
            launch(["-UITestDemo", "YES", "-UITestWorkspace", route])
            XCTAssertTrue(element(containing: marker).waitForExistence(timeout: 10), route)
            sleep(1)
            snapshot(name)
            app.terminate()
        }
    }

    func testWorkspaceTourOfEnvironmentAndMcp() {
        launch(["-UITestDemo", "YES", "-UITestWorkspace", "env"])
        let storefront = element(containing: "storefront")
        XCTAssertTrue(storefront.waitForExistence(timeout: 10))
        storefront.tap()
        XCTAssertTrue(element(containing: "STRIPE_SECRET_KEY").waitForExistence(timeout: 5))
        snapshot("50-env-vars")
        app.buttons["Add variable"].tap()
        XCTAssertTrue(app.textFields["envKey"].waitForExistence(timeout: 5))
        snapshot("51-env-add")
        app.buttons["Cancel"].tap()
        element(containing: "REDIS_URL").tap()
        XCTAssertTrue(app.secureTextFields["envValue"].waitForExistence(timeout: 5))
        snapshot("52-env-replace")
        app.terminate()

        launch(["-UITestDemo", "YES", "-UITestWorkspace", "mcp"])
        let sentry = element(containing: "Sentry")
        XCTAssertTrue(sentry.waitForExistence(timeout: 10))
        sentry.tap()
        XCTAssertTrue(app.textFields["mcpName"].waitForExistence(timeout: 5))
        snapshot("53-mcp-edit")
        app.buttons["Cancel"].tap()
        app.buttons["Add server"].tap()
        XCTAssertTrue(app.textFields["mcpName"].waitForExistence(timeout: 5))
        snapshot("54-mcp-add")
    }

    func testWorkspaceTourOfWebhookAndServiceAccountDetails() {
        launch(["-UITestDemo", "YES", "-UITestWorkspace", "webhooks"])
        let hook = element(containing: "ci.acme.dev")
        XCTAssertTrue(hook.waitForExistence(timeout: 10))
        hook.tap()
        XCTAssertTrue(element(containing: "evt_").waitForExistence(timeout: 5))
        snapshot("60-webhook-detail")
        app.swipeUp()
        snapshot("61-webhook-detail-more")
        app.terminate()

        launch(["-UITestDemo", "YES", "-UITestWorkspace", "accounts"])
        let account = element(containing: "ci-deploy-bot")
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        XCTAssertTrue(element(containing: "cred_deploy").waitForExistence(timeout: 5))
        snapshot("62-account-detail")
        app.swipeUp()
        snapshot("63-account-detail-more")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["New service account"].tap()
        XCTAssertTrue(app.textFields["accountName"].waitForExistence(timeout: 5))
        snapshot("64-account-new")
    }

    func testWorkspaceTourOfAutomations() {
        launch(["-UITestDemo", "YES", "-UITestTab", "automations"])
        let flaky = element(containing: "Nightly flaky test sweep")
        XCTAssertTrue(flaky.waitForExistence(timeout: 8))
        snapshot("70-automations")
        flaky.tap()
        XCTAssertTrue(element(containing: "Last 30 days").waitForExistence(timeout: 5))
        snapshot("71-automation-detail")
        app.buttons["Manage"].tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["automationName"].waitForExistence(timeout: 5))
        snapshot("72-automation-edit")
    }
}
