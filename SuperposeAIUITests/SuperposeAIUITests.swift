import XCTest

final class SuperposeAIUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingScreenAppears() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingResetOnboarding"]
        app.launch()

        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMainTabBarNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingSkipOnboarding"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let libraryTab = tabBar.buttons["Kütüphane"]
        XCTAssertTrue(libraryTab.exists)
        libraryTab.tap()
        XCTAssertTrue(app.navigationBars["Kütüphane"].waitForExistence(timeout: 3))

        let settingsTab = tabBar.buttons["Ayarlar"]
        XCTAssertTrue(settingsTab.exists)
        settingsTab.tap()

        let cameraTab = tabBar.buttons["Kamera"]
        XCTAssertTrue(cameraTab.exists)
        cameraTab.tap()
    }
}
