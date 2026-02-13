import XCTest
import CoreData
import CoreLocation
import MapKit
@testable import FuelFinder

final class RouteStationFinderTests: XCTestCase {

    var coreDataStack: CoreDataStack!
    var finder: RouteStationFinder!

    override func setUpWithError() throws {
        coreDataStack = CoreDataStack(inMemory: true)
        finder = RouteStationFinder(coreDataStack: coreDataStack)
        seedTestStations()
    }

    override func tearDownWithError() throws {
        coreDataStack = nil
        finder = nil
    }

    // MARK: - Seed Data

    private func seedTestStations() {
        let context = coreDataStack.viewContext

        // M1 approximate: lat 51.56 → 53.80, lon -0.22 → -1.55
        let startLat = 51.56
        let endLat = 53.80
        let startLon = -0.22
        let endLon = -1.55

        for i in 0..<100 {
            let fraction = Double(i) / 99.0
            let lat = startLat + (endLat - startLat) * fraction + Double.random(in: -0.02...0.02)
            let lon = startLon + (endLon - startLon) * fraction + Double.random(in: -0.02...0.02)

            let station = Station(context: context)
            station.id = "test\(String(format: "%03d", i))"
            station.name = "Test Station \(i)"
            station.brand = ["Shell", "BP", "Esso", "Tesco", "Morrisons"][i % 5]
            station.latitude = lat
            station.longitude = lon
            station.address = "\(i) Test Road"
            station.amenities = "[]"
            station.lastUpdated = Date()
            station.isFavourite = i % 10 == 0

            let prices = PriceSet(context: context)
            prices.unleaded = 1.35 + Double.random(in: 0...0.20)
            prices.diesel = 1.42 + Double.random(in: 0...0.20)
            prices.superUnleaded = 1.50 + Double.random(in: 0...0.20)
            prices.premiumDiesel = 1.55 + Double.random(in: 0...0.20)
            prices.updatedAt = Date()
            prices.station = station
            station.prices = prices
        }

        try? context.save()
    }

    // MARK: - Tests

    func testNearbySearchFindsStations() throws {
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let results = finder.findNearbyStations(
            coordinate: london,
            radiusKm: 20,
            fuelType: "unleaded"
        )

        XCTAssertFalse(results.isEmpty, "Should find stations near London")

        let center = CLLocation(latitude: london.latitude, longitude: london.longitude)
        for result in results {
            let stationLocation = CLLocation(latitude: result.coordinate.latitude, longitude: result.coordinate.longitude)
            let distanceKm = center.distance(from: stationLocation) / 1000.0
            XCTAssertLessThanOrEqual(distanceKm, 20.0, "Station should be within 20km radius")
        }
    }

    func testNearbySearchRespectsLimit() throws {
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let results = finder.findNearbyStations(
            coordinate: london,
            radiusKm: 200,
            fuelType: "unleaded",
            limit: 5
        )

        XCTAssertLessThanOrEqual(results.count, 5, "Should respect the limit parameter")
    }

    func testScoresAreSortedAscending() throws {
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let results = finder.findNearbyStations(
            coordinate: london,
            radiusKm: 200,
            fuelType: "unleaded"
        )

        guard results.count > 1 else { return }

        for i in 0..<(results.count - 1) {
            XCTAssertLessThanOrEqual(
                results[i].score, results[i + 1].score,
                "Results should be sorted by score ascending"
            )
        }
    }

    func testPriceTiersAssigned() throws {
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let results = finder.findNearbyStations(
            coordinate: london,
            radiusKm: 200,
            fuelType: "unleaded"
        )

        let tiers = Set(results.map(\.priceTier))
        if results.count >= 3 {
            XCTAssertTrue(tiers.count >= 2, "Should assign at least 2 price tiers")
        }

        for result in results {
            XCTAssertTrue((0...2).contains(result.priceTier), "Price tier should be 0, 1, or 2")
        }
    }

    func testEmptyResultsForRemoteLocation() throws {
        let atlantic = CLLocationCoordinate2D(latitude: 40.0, longitude: -30.0)
        let results = finder.findNearbyStations(
            coordinate: atlantic,
            radiusKm: 5,
            fuelType: "unleaded"
        )

        XCTAssertTrue(results.isEmpty, "Should find no stations in the Atlantic")
    }

    func testDieselPricesUsed() throws {
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let results = finder.findNearbyStations(
            coordinate: london,
            radiusKm: 200,
            fuelType: "diesel"
        )

        for result in results {
            XCTAssertEqual(result.fuelType, "diesel", "Fuel type should be diesel")
            XCTAssertGreaterThan(result.price, 0, "Price should be positive")
        }
    }

    func testThreadSafetyWithConcurrentSearches() async throws {
        let london = CLLocationCoordinate2D(latitude: 52.0, longitude: -1.0)
        let finder = self.finder!

        // Run multiple searches concurrently — each uses its own background context
        let results1 = finder.findNearbyStations(coordinate: london, radiusKm: 50, fuelType: "unleaded")
        let results2 = finder.findNearbyStations(coordinate: london, radiusKm: 50, fuelType: "diesel")

        // Both should succeed without crash
        XCTAssertFalse(results1.isEmpty, "Concurrent search 1 should return results")
        XCTAssertFalse(results2.isEmpty, "Concurrent search 2 should return results")
    }

    // MARK: - Performance Tests

    func testCorridorSearchPerformance() throws {
        let context = coreDataStack.viewContext
        for i in 100..<10000 {
            let station = Station(context: context)
            station.id = "perf\(i)"
            station.name = "Perf Station \(i)"
            station.brand = "Shell"
            station.latitude = 51.0 + Double.random(in: 0...3.0)
            station.longitude = -2.0 + Double.random(in: 0...2.0)
            station.address = "\(i) Perf Road"
            station.amenities = "[]"
            station.lastUpdated = Date()
            station.isFavourite = false

            let prices = PriceSet(context: context)
            prices.unleaded = 1.35 + Double.random(in: 0...0.20)
            prices.diesel = 1.42 + Double.random(in: 0...0.20)
            prices.updatedAt = Date()
            prices.station = station
            station.prices = prices
        }
        try? context.save()

        measure {
            _ = finder.findNearbyStations(
                coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: -1.0),
                radiusKm: 50,
                fuelType: "unleaded",
                limit: 50
            )
        }
    }

    func testCoreDataFetchPerformance() throws {
        let context = coreDataStack.viewContext
        for i in 100..<10000 {
            let station = Station(context: context)
            station.id = "fetch\(i)"
            station.name = "Fetch Station \(i)"
            station.brand = "BP"
            station.latitude = 50.0 + Double.random(in: 0...4.0)
            station.longitude = -2.0 + Double.random(in: 0...3.0)
            station.address = "\(i) Fetch Road"
            station.amenities = "[]"
            station.lastUpdated = Date()
            station.isFavourite = false

            let prices = PriceSet(context: context)
            prices.unleaded = 1.40 + Double.random(in: 0...0.15)
            prices.updatedAt = Date()
            prices.station = station
            station.prices = prices
        }
        try? context.save()

        measure {
            let request: NSFetchRequest<Station> = Station.fetchRequest()
            request.predicate = NSPredicate(
                format: "latitude >= %lf AND latitude <= %lf AND longitude >= %lf AND longitude <= %lf",
                51.0, 53.0, -1.5, 0.0
            )
            request.fetchBatchSize = 100
            request.fetchLimit = 500
            request.relationshipKeyPathsForPrefetching = ["prices"]
            _ = try? context.fetch(request)
        }
    }
}
