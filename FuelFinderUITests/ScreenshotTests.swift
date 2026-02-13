import XCTest

/// Generates App Store screenshots by navigating through key screens.
///
/// Run across devices with:
/// ```
/// xcodebuild test \
///   -project FuelFinder.xcodeproj \
///   -scheme FuelFinder \
///   -testPlan Screenshots \
///   -destination 'name=Screenshot-iPhone16Pro' \
///   -destination 'name=Screenshot-iPhone16ProMax' \
///   -destination 'name=Screenshot-iPadPro13M5'
/// ```
///
/// Extract screenshots from xcresult using `xcresulttool`.
final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    // MARK: - App Store Screenshots

    func test01_RouteMapScreen() throws {
        // Wait for map to render
        let originField = app.textFields["Origin"]
        XCTAssertTrue(originField.waitForExistence(timeout: 5))
        sleep(2) // Allow map tiles to load

        takeScreenshot(named: "01-RouteMap")
    }

    func test02_RoutePlanning() throws {
        let originField = app.textFields["Origin"]
        XCTAssertTrue(originField.waitForExistence(timeout: 5))
        originField.tap()
        originField.typeText("London")

        let destField = app.textFields["Destination"]
        destField.tap()
        destField.typeText("Birmingham")

        sleep(1) // Allow UI to settle

        takeScreenshot(named: "02-RoutePlanning")
    }

    func test03_RouteWithStations() throws {
        // Plan a route first
        let originField = app.textFields["Origin"]
        XCTAssertTrue(originField.waitForExistence(timeout: 5))
        originField.tap()
        originField.typeText("London")

        let destField = app.textFields["Destination"]
        destField.tap()
        destField.typeText("Birmingham")

        // Tap Plan Route
        let planButton = app.buttons["Plan Route"]
        XCTAssertTrue(planButton.isEnabled)
        planButton.tap()

        // Wait for route calculation
        sleep(5)

        // If Find Fuel button appears, tap it
        let findFuelButton = app.buttons["Find Fuel"]
        if findFuelButton.waitForExistence(timeout: 10) {
            findFuelButton.tap()
            sleep(3) // Wait for station search
        }

        takeScreenshot(named: "03-RouteWithStations")
    }

    func test04_StationList() throws {
        // Plan route and find stations
        let originField = app.textFields["Origin"]
        XCTAssertTrue(originField.waitForExistence(timeout: 5))
        originField.tap()
        originField.typeText("London")

        let destField = app.textFields["Destination"]
        destField.tap()
        destField.typeText("Birmingham")

        app.buttons["Plan Route"].tap()
        sleep(5)

        let findFuelButton = app.buttons["Find Fuel"]
        if findFuelButton.waitForExistence(timeout: 10) {
            findFuelButton.tap()
            sleep(3)
        }

        // Open station list
        let viewListButton = app.buttons["View List"]
        if viewListButton.waitForExistence(timeout: 5) {
            viewListButton.tap()
            sleep(1)
            takeScreenshot(named: "04-StationList")
        }
    }

    func test05_FavouritesScreen() throws {
        app.tabBars.buttons["Favourites"].tap()
        sleep(1)

        takeScreenshot(named: "05-Favourites")
    }

    func test06_SettingsScreen() throws {
        app.tabBars.buttons["Settings"].tap()
        sleep(1)

        takeScreenshot(named: "06-Settings")
    }

    func test07_FuelTypeSettings() throws {
        // Navigate to route settings
        let gearButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'gear' OR label CONTAINS 'Settings'")).element(boundBy: 0)
        if gearButton.waitForExistence(timeout: 3) {
            gearButton.tap()
            sleep(1)
            takeScreenshot(named: "07-FuelSettings")
        }
    }

    // MARK: - Screenshot Helper

    private func takeScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
