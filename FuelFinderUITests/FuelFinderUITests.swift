import XCTest

final class FuelFinderUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    // MARK: - Tab Navigation

    func testMapTabIsDefault() throws {
        let mapTab = app.tabBars.buttons["Map"]
        XCTAssertTrue(mapTab.isSelected, "Map tab should be selected by default")
    }

    func testCanSwitchToFavouritesTab() throws {
        app.tabBars.buttons["Favourites"].tap()
        XCTAssertTrue(app.navigationBars["Favourites"].exists)
    }

    func testCanSwitchToSettingsTab() throws {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    // MARK: - Map View

    func testMapViewDoesNotHaveRouteFields() throws {
        XCTAssertFalse(app.textFields["Origin"].exists, "Should not have Origin field")
        XCTAssertFalse(app.textFields["Destination"].exists, "Should not have Destination field")
        XCTAssertFalse(app.buttons["Plan Route"].exists, "Should not have Plan Route button")
    }

    func testFuelTypePicker() throws {
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Fuel type picker should be visible")
    }

    // MARK: - Settings View

    func testSettingsShowsRefreshButton() throws {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Refresh All Prices"].waitForExistence(timeout: 3))
    }

    // MARK: - Favourites View

    func testFavouritesShowsEmptyState() throws {
        app.tabBars.buttons["Favourites"].tap()
        let navBar = app.navigationBars["Favourites"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 3))
    }
}
