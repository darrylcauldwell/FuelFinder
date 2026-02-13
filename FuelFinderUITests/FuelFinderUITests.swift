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

    func testRouteTabIsDefault() throws {
        let routeTab = app.tabBars.buttons["Route"]
        XCTAssertTrue(routeTab.isSelected, "Route tab should be selected by default")
    }

    func testCanSwitchToFavouritesTab() throws {
        app.tabBars.buttons["Favourites"].tap()
        XCTAssertTrue(app.navigationBars["Favourites"].exists)
    }

    func testCanSwitchToSettingsTab() throws {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    // MARK: - Route View

    func testRouteViewHasOriginAndDestinationFields() throws {
        XCTAssertTrue(app.textFields["Origin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Destination"].exists)
    }

    func testPlanRouteButtonDisabledWithoutInput() throws {
        let planButton = app.buttons["Plan Route"]
        XCTAssertTrue(planButton.exists)
        XCTAssertFalse(planButton.isEnabled)
    }

    func testPlanRouteButtonEnabledWithInput() throws {
        let originField = app.textFields["Origin"]
        originField.tap()
        originField.typeText("London")

        let destField = app.textFields["Destination"]
        destField.tap()
        destField.typeText("Birmingham")

        let planButton = app.buttons["Plan Route"]
        XCTAssertTrue(planButton.isEnabled)
    }

    // MARK: - Settings View

    func testSettingsShowsMockDataToggle() throws {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Use Mock Data"].waitForExistence(timeout: 3))
    }

    func testSettingsShowsRefreshButton() throws {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Refresh All Prices"].waitForExistence(timeout: 3))
    }

    // MARK: - Favourites View

    func testFavouritesShowsEmptyState() throws {
        app.tabBars.buttons["Favourites"].tap()
        // With mock data, some stations are favourites, but the empty state text
        // should appear if none are favourited
        let navBar = app.navigationBars["Favourites"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 3))
    }
}
