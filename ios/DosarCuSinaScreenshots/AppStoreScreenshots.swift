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
        // The review is up once the invoice's firm shows as read.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Service Exemplu")).firstMatch.waitForExistence(timeout: 60))
        keep(app, "04-capture")
    }

    func test05Trip() throws {
        let app = launch(.trip)
        unlockIfAsked(app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Grecia")).firstMatch.waitForExistence(timeout: 30))
        keep(app, "05-trip")
    }

    func test06Document() throws {
        let app = launch(.document)
        unlockIfAsked(app)
        XCTAssertTrue(app.staticTexts["050000000"].firstMatch.waitForExistence(timeout: 30))
        keep(app, "06-document")
    }

    func test07Search() throws {
        let app = launch(.search)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        field.tap()
        field.typeText("rca")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "RCA")).firstMatch.waitForExistence(timeout: 30))
        // The keyboard goes, so the results show whole.
        app.swipeDown(velocity: .fast)
        keep(app, "07-search")
    }

    // MARK: Helpers

    private enum Scene: String { case binder, upcoming, car, document, capture, trip, search }

    private func launch(_ scene: Scene) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-DosarScreenshots", scene.rawValue,
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

    /// A locked section asks for Face ID: the simulator's enrolled face matches.
    private func unlockIfAsked(_ app: XCUIApplication) {
        let unlock = app.buttons["Deblochează"].firstMatch
        guard unlock.waitForExistence(timeout: 5) else { return }
        unlock.tap()
        answerSystemAlerts()
        notify_post("com.apple.BiometricKit_Sim.pearl.match")
        _ = unlock.waitForNonExistence(timeout: 10)
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        answerSystemAlerts()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name)-\(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
