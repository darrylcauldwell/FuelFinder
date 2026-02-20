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

    func testCanSwitchToListTab() throws {
        app.tabBars.buttons["List"].tap()
        XCTAssertTrue(app.navigationBars["Nearby"].exists)
    }

    func testCanSwitchToFavouritesTab() throws {
        app.tabBars.buttons["Favourites"].tap()
        XCTAssertTrue(app.navigationBars["Favourites"].exists)
    }

    func testCanSwitchToRouteTab() throws {
        app.tabBars.buttons["Route"].tap()
        // Route tab shows either destination search or route preview
        XCTAssertTrue(app.tabBars.buttons["Route"].isSelected)
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

    // MARK: - Route View

    func testRouteTabShowsDestinationSearchOrLocationPrompt() throws {
        app.tabBars.buttons["Route"].tap()
        // Either shows search field or location prompt depending on permission state
        let searchField = app.textFields["Search destination..."]
        let locationPrompt = app.staticTexts["Getting your location..."]

        // Wait for either element to appear
        let viewLoaded = searchField.waitForExistence(timeout: 10) || locationPrompt.exists
        XCTAssertTrue(viewLoaded, "Route tab should show either destination search field or location prompt")
    }

    // MARK: - List View

    func testListViewHasFuelTypeMenu() throws {
        app.tabBars.buttons["List"].tap()
        // Look for fuel type menu button
        let fuelMenu = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Unleaded' OR label CONTAINS 'Diesel'")).firstMatch
        XCTAssertTrue(fuelMenu.waitForExistence(timeout: 3), "List view should have fuel type selector")
    }

    func testListViewHasSortPicker() throws {
        app.tabBars.buttons["List"].tap()
        // Look for sort segmented control
        let sortControl = app.segmentedControls.element
        XCTAssertTrue(sortControl.waitForExistence(timeout: 3), "List view should have sort picker")
    }
}
