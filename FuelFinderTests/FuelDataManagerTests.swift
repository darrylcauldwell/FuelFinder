import XCTest
import CoreData
@testable import FuelFinder

@MainActor
final class FuelDataManagerTests: XCTestCase {

    var coreDataStack: CoreDataStack!
    var dataManager: FuelDataManager!

    override func setUpWithError() throws {
        coreDataStack = CoreDataStack(inMemory: true)
        dataManager = FuelDataManager(coreDataStack: coreDataStack)
    }

    override func tearDownWithError() throws {
        coreDataStack = nil
        dataManager = nil
    }

    // MARK: - Core Data Tests

    func testFreshManagerHasNoStations() throws {
        let request: NSFetchRequest<Station> = Station.fetchRequest()
        let count = try coreDataStack.viewContext.count(for: request)
        XCTAssertEqual(count, 0, "Fresh manager should have no stations")
    }

    func testStalenessBeforeRefresh() {
        dataManager.checkStaleness()
        XCTAssertTrue(dataManager.isDataStale, "Should be stale before any refresh")
    }

    func testStationManualInsertAndPrices() throws {
        let context = coreDataStack.viewContext
        let station = Station(context: context)
        station.id = "test001"
        station.name = "Test Station"
        station.brand = "TestBrand"
        station.latitude = 52.0
        station.longitude = -1.0
        station.address = "Test Road, TE1 1ST"
        station.isFavourite = false

        let prices = PriceSet(context: context)
        prices.unleaded = 1.42
        prices.superUnleaded = 1.55
        prices.diesel = 1.49
        prices.premiumDiesel = 1.59
        prices.updatedAt = Date()
        prices.station = station
        station.prices = prices

        try context.save()

        XCTAssertEqual(station.price(for: "unleaded"), 1.42)
        XCTAssertEqual(station.price(for: "diesel"), 1.49)
        XCTAssertEqual(station.formattedPrice(for: "unleaded"), "£1.42")
        XCTAssertEqual(station.coordinate.latitude, 52.0, accuracy: 0.001)
        XCTAssertFalse(station.isStale(), "Freshly created station should not be stale")
    }

    func testFavouriteToggle() throws {
        let context = coreDataStack.viewContext
        let station = Station(context: context)
        station.id = "test002"
        station.name = "Fav Station"
        station.brand = "FavBrand"
        station.latitude = 51.5
        station.longitude = -0.1
        station.isFavourite = false
        try context.save()

        XCTAssertFalse(station.isFavourite)

        station.isFavourite = true
        try context.save()

        let request: NSFetchRequest<Station> = Station.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", "test002")
        let refetched = try XCTUnwrap(try context.fetch(request).first)
        XCTAssertTrue(refetched.isFavourite)
    }

    func testInvalidFuelTypeReturnsNil() throws {
        let context = coreDataStack.viewContext
        let station = Station(context: context)
        station.id = "test003"
        station.name = "Nil Station"
        station.brand = "NilBrand"
        station.latitude = 51.0
        station.longitude = -1.0

        let prices = PriceSet(context: context)
        prices.unleaded = 1.42
        prices.diesel = 1.49
        prices.updatedAt = Date()
        prices.station = station
        station.prices = prices

        try context.save()

        XCTAssertNil(station.price(for: "hydrogen"), "Invalid fuel type should return nil")
        XCTAssertEqual(station.formattedPrice(for: "hydrogen"), "N/A")
    }

    func testUpsertDoesNotDuplicate() throws {
        let context = coreDataStack.viewContext

        let station1 = Station(context: context)
        station1.id = "test004"
        station1.name = "First"
        station1.brand = "Brand"
        station1.latitude = 51.0
        station1.longitude = -1.0
        try context.save()

        let request: NSFetchRequest<Station> = Station.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", "test004")
        let count1 = try context.count(for: request)
        XCTAssertEqual(count1, 1)

        // Simulate upsert — fetch existing, update instead of creating new
        let existing = try XCTUnwrap(try context.fetch(request).first)
        existing.name = "Updated"
        try context.save()

        let count2 = try context.count(for: request)
        XCTAssertEqual(count2, 1, "Upsert should not create duplicates")
        XCTAssertEqual(existing.name, "Updated")
    }
}
