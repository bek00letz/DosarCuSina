import notify
import XCTest

/// The App Store's screenshots: each test launches the app at one screen of its made-up
/// household (`ScreenshotStage`, development builds only), waits until the screen is there and
/// keeps a picture of it, named "<order>-<scene>-<appearance>". Run by
/// `scripts/app-store-screenshots.sh`, which sets the device, the appearance and a clean status
/// bar, and takes the pictures out of the result bundle. Never part of the app's test run.
@MainActor
final class AppStoreScreenshots: XCTestCase {
    /// What the script says the simulator is set to ("light" or "dark"), for the pictures' names.
    private var appearance: String { ProcessInfo.processInfo.environment["SCREENSHOT_APPEARANCE"] ?? "light" }
    /// The run all of these launches share, so they share one household (one per run).
    private var run: String { ProcessInfo.processInfo.environment["SCREENSHOT_RUN"] ?? "" }

    func test01Binder() throws {
        let app = launch(.binder)
        XCTAssertTrue(app.navigationBars["Dosar"].waitForExistence(timeout: 30))
        keep(app, "01-binder")
    }

    func test02Upcoming() throws {
        let app = launch(.upcoming)
        XCTAssertTrue(app.navigationBars["Urmează"].waitForExistence(timeout: 30))
        keep(app, "02-upcoming")
    }

    func test03Car() throws {
        let app = launch(.car)
        XCTAssertTrue(app.staticTexts["B-123-ABC"].firstMatch.waitForExistence(timeout: 30))
        keep(app, "03-car")
    }

    func test04Capture() throws {
        let app = launch(.capture)
        // Once the invoice is read: the review, or the visit it belongs to when it names the car.
        let read = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["Verifică documentul", "Am fost la service"])).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 90))
        keep(app, "04-capture")
    }

    func test05Trip() throws {
        let app = launch(.trip)
        unlockIfAsked(app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Grecia")).firstMatch.waitForExistence(timeout: 30))
        keep(app, "05-trip")
    }

    func test06Search() throws {
        let app = launch(.search)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        field.tap()
        // Searching ends with the keyboard's search key, so the results show whole.
        field.typeText("golf\n")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Golf")).firstMatch.waitForExistence(timeout: 30))
        keep(app, "06-search")
    }

    func test07Document() throws {
        let app = launch(.document)
        unlockIfAsked(app)
        XCTAssertTrue(app.staticTexts["050000000"].firstMatch.waitForExistence(timeout: 30))
        keep(app, "07-document")
    }

    // MARK: Helpers

    private enum Scene: String { case binder, upcoming, car, document, capture, trip, search }

    private func launch(_ scene: Scene) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-DosarScreenshots", scene.rawValue,
            "-DosarScreenshotsRun", run,
            // Onboarding was seen: the screenshots show a binder in use.
            "-preferences.hasCompletedOnboarding", "YES",
            "-AppleLanguages", "(ro)",
            "-AppleLocale", "ro_RO",
        ]
        app.launch()
        answerSystemAlerts()
        return app
    }

    /// A system question that may come up on a fresh simulator (notifications, Face ID), answered
    /// with its second button, the one that allows.
    private func answerSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
        let buttons = alert.buttons
        if buttons.count > 1 { buttons.element(boundBy: 1).tap() } else { buttons.firstMatch.tap() }
    }

    /// A locked section asks for Face ID: the simulator's enrolled face matches. The first time,
    /// iOS asks whether the app may use Face ID, and the face can come before the prompt does,
    /// so it tries again.
    private func unlockIfAsked(_ app: XCUIApplication) {
        let unlock = app.buttons["Deblochează"].firstMatch
        guard unlock.waitForExistence(timeout: 5) else { return }
        for _ in 0..<3 where unlock.exists {
            unlock.tap()
            answerSystemAlerts()
            notify_post("com.apple.BiometricKit_Sim.pearl.match")
            _ = unlock.waitForNonExistence(timeout: 8)
        }
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        answerSystemAlerts()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name)-\(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
