import XCTest

/// Generates App Store screenshots using Fastlane Snapshot.
///
/// Run with: `fastlane screenshots`
@MainActor
final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
    }

    // MARK: - App Store Screenshots

    func test01_NearbyMapScreen() throws {
        // Wait for at least one station row to appear in the bottom sheet
        let firstStation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'km'")).firstMatch
        _ = firstStation.waitForExistence(timeout: 10)
        snapshot("01-NearbyMap")
    }

    func test02_StationList() throws {
        // Pull the persistent bottom sheet to medium detent and wait for rows
        let sheet = app.otherElements["Station list"]
        if sheet.waitForExistence(timeout: 5) {
            sheet.swipeUp()
        }
        let firstStation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'km'")).firstMatch
        _ = firstStation.waitForExistence(timeout: 10)
        snapshot("02-StationList")
    }

    func test03_FavouritesScreen() throws {
        app.tabBars.buttons["Favourites"].tap()
        _ = app.navigationBars["Favourites"].waitForExistence(timeout: 5)
        snapshot("03-Favourites")
    }

    func test04_SettingsScreen() throws {
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 5)
        snapshot("04-Settings")
    }

    func test05_FiltersScreen() throws {
        let filterButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'slider' OR label CONTAINS 'Filters'")).element(boundBy: 0)
        if filterButton.waitForExistence(timeout: 5) {
            filterButton.tap()
            _ = app.navigationBars["Filters"].waitForExistence(timeout: 3)
            snapshot("05-Filters")
        }
    }
}
