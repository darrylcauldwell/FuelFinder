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
        dataManager.useMockData = true
    }

    override func tearDownWithError() throws {
        coreDataStack = nil
        dataManager = nil
    }

    // MARK: - Mock Data Tests

    func testLoadMockDataImportsStations() async throws {
        await dataManager.refreshStations(
            near: .init(latitude: 51.5074, longitude: -0.1278)
        )

        XCTAssertNil(dataManager.lastError, "Should not produce an error")
        XCTAssertNotNil(dataManager.lastRefresh, "Should set lastRefresh")

        let request: NSFetchRequest<Station> = Station.fetchRequest()
        let count = try coreDataStack.viewContext.count(for: request)
        XCTAssertEqual(count, 10, "Should import all 10 mock stations")
    }

    func testStationsHavePrices() async throws {
        await dataManager.refreshStations(
            near: .init(latitude: 51.5074, longitude: -0.1278)
        )

        let request: NSFetchRequest<Station> = Station.fetchRequest()
        let stations = try coreDataStack.viewContext.fetch(request)

        for station in stations {
            XCTAssertNotNil(station.prices, "Each station should have a PriceSet")
            XCTAssertGreaterThan(station.prices?.unleaded ?? 0, 0, "Unleaded price should be positive")
            XCTAssertGreaterThan(station.prices?.diesel ?? 0, 0, "Diesel price should be positive")
        }
    }

    func testUpsertDoesNotDuplicate() async throws {
        await dataManager.refreshStations(
            near: .init(latitude: 51.5074, longitude: -0.1278)
        )
        dataManager.lastRefresh = nil
        await dataManager.refreshStations(
            near: .init(latitude: 51.5074, longitude: -0.1278)
        )

        let request: NSFetchRequest<Station> = Station.fetchRequest()
        let count = try coreDataStack.viewContext.count(for: request)
        XCTAssertEqual(count, 10, "Upsert should not create duplicates")
    }

    func testStationConvenienceExtensions() async throws {
        await dataManager.refreshStations(
            near: .init(latitude: 51.5074, longitude: -0.1278)
        )

        let request: NSFetchRequest<Station> = Station.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", "station001")
        let stations = try coreDataStack.viewContext.fetch(request)
        let station = try XCTUnwrap(stations.first)

        XCTAssertEqual(station.price(for: "unleaded"), 1.42)
        XCTAssertEqual(station.price(for: "diesel"), 1.49)
        XCTAssertEqual(station.formattedPrice(for: "unleaded"), "£1.42")
        XCTAssertEqual(station.coordinate.latitude, 51.5954, accuracy: 0.001)
        XCTAssertEqual(station.coordinate.longitude, -0.2491, accuracy: 0.001)
        XCTAssertFalse(station.isStale(), "Freshly imported station should not be stale")
    }

    func testFavouriteToggle() async throws {
        await dataManager.refreshStations(
            near: .init(latitude: 51.5074, longitude: -0.1278)
        )

        let request: NSFetchRequest<Station> = Station.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", "station001")
        let station = try XCTUnwrap(try coreDataStack.viewContext.fetch(request).first)

        XCTAssertFalse(station.isFavourite)

        station.isFavourite = true
        try coreDataStack.viewContext.save()

        let refetched = try XCTUnwrap(try coreDataStack.viewContext.fetch(request).first)
        XCTAssertTrue(refetched.isFavourite)
    }

    func testStaleDataFlag() async throws {
        dataManager.checkStaleness()
        XCTAssertTrue(dataManager.isDataStale, "Should be stale before any refresh")

        await dataManager.refreshStations(
            near: .init(latitude: 51.5074, longitude: -0.1278)
        )

        dataManager.checkStaleness()
        XCTAssertFalse(dataManager.isDataStale, "Should not be stale after refresh")
    }

    func testInvalidFuelTypeReturnsNil() async throws {
        await dataManager.refreshStations(
            near: .init(latitude: 51.5074, longitude: -0.1278)
        )

        let request: NSFetchRequest<Station> = Station.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", "station001")
        let station = try XCTUnwrap(try coreDataStack.viewContext.fetch(request).first)

        XCTAssertNil(station.price(for: "hydrogen"), "Invalid fuel type should return nil")
        XCTAssertEqual(station.formattedPrice(for: "hydrogen"), "N/A")
    }
}
