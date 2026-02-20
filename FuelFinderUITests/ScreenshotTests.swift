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

    func test02_ListScreen() throws {
        app.tabBars.buttons["List"].tap()
        let firstStation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'km' OR label CONTAINS 'mi'")).firstMatch
        _ = firstStation.waitForExistence(timeout: 10)
        snapshot("02-List")
    }

    func test03_RouteSearchScreen() throws {
        app.tabBars.buttons["Route"].tap()
        let searchField = app.textFields["Search destination..."]
        _ = searchField.waitForExistence(timeout: 5)
        snapshot("03-RouteSearch")
    }

    func test04_FavouritesScreen() throws {
        app.tabBars.buttons["Favourites"].tap()
        _ = app.navigationBars["Favourites"].waitForExistence(timeout: 5)
        snapshot("04-Favourites")
    }

    func test05_SettingsScreen() throws {
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 5)
        snapshot("05-Settings")
    }
}
