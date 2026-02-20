import Foundation
import CoreData
import CoreLocation
import MapKit
import Combine

// MARK: - UK Retailer Feed Response Models

/// Common JSON format used by all UK retailer open data feeds.
struct RetailerFeedResponse: Codable, Sendable {
    let lastUpdated: String?
    let stations: [RetailerStation]

    enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case stations
    }
}

struct RetailerStation: Codable, Sendable {
    let siteId: String
    let brand: String
    let address: String?
    let postcode: String?
    let location: RetailerLocation
    let prices: RetailerPrices

    enum CodingKeys: String, CodingKey {
        case siteId = "site_id"
        case brand, address, postcode, location, prices
    }
}

struct RetailerLocation: Codable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct RetailerPrices: Codable, Sendable {
    let e10: Double?  // Unleaded (E10)
    let e5: Double?   // Super unleaded (E5)
    let b7: Double?   // Diesel (B7)
    let sdv: Double?  // Premium diesel (SDV)

    enum CodingKeys: String, CodingKey {
        case e10 = "E10"
        case e5 = "E5"
        case b7 = "B7"
        case sdv = "SDV"
    }
}

// MARK: - FuelDataManager

@MainActor
final class FuelDataManager: ObservableObject {

    // MARK: Published State

    @Published var nearbyStations: [StationWithScore] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastRefresh: Date?
    @Published var isDataStale = true

    // MARK: UK Retailer Open Data Feed URLs (no auth required)

    private static let retailerFeeds: [(name: String, url: String)] = [
        ("Asda", "https://storelocator.asda.com/fuel_prices_data.json"),
        ("BP", "https://www.bp.com/en_gb/united-kingdom/home/fuelprices/fuel_prices_data.json"),
        ("Esso", "https://fuelprices.esso.co.uk/latestdata.json"),
        ("JET", "https://jetlocal.co.uk/fuel_prices_data.json"),
        ("Morrisons", "https://www.morrisons.com/fuel-prices/fuel.json"),
        ("Moto", "https://moto-way.com/fuel-price/fuel_prices.json"),
        ("Motor Fuel Group", "https://fuel.motorfuelgroup.com/fuel_prices_data.json"),
        ("Rontec", "https://www.rontec-servicestations.co.uk/fuel-prices/data/fuel_prices_data.json"),
        ("Sainsburys", "https://api.sainsburys.co.uk/v1/exports/latest/fuel_prices_data.json"),
        ("SGN", "https://www.sgnretail.uk/files/data/SGN_daily_fuel_prices.json"),
        ("Shell", "https://www.shell.co.uk/fuel-prices-data.json"),
        ("Tesco", "https://www.tesco.com/fuel_prices/fuel_prices_data.json"),
    ]

    // MARK: Dependencies

    let coreDataStack: CoreDataStack
    private let routeFinder: RouteStationFinder
    private let session: URLSession

    // MARK: Refresh Configuration

    /// Refresh interval — 12 hours (data updates twice per day).
    private static let refreshInterval: TimeInterval = 12 * 60 * 60

    /// The app's shared instance — used by CarPlay to avoid a second fetch cycle.
    nonisolated(unsafe) static var shared: FuelDataManager?

    private var refreshInFlight = false
    private var nearbySearchInFlight = false
    private var periodicRefreshTask: Task<Void, Never>?

    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
        self.routeFinder = RouteStationFinder(coreDataStack: coreDataStack)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 20 * 1024 * 1024)
        self.session = URLSession(configuration: config)
    }

    /// Start periodic refresh — call once from the app's root view.
    func startPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard !Task.isCancelled else { break }
                await self?.refreshStations()
            }
        }
    }

    func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }

    // MARK: - Public API

    func refreshStations(near coordinate: CLLocationCoordinate2D? = nil, radiusKm: Double = 50) async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            try await fetchAllRetailerFeeds()
            lastRefresh = Date()
            isDataStale = false
        } catch {
            lastError = error.localizedDescription
            print("[FuelDataManager] Refresh error: \(error)")
        }
    }

    func findNearbyStations(
        coordinate: CLLocationCoordinate2D,
        fuelType: String = "unleaded",
        radiusKm: Double = 16,
        limit: Int = 50,
        sortBy: StationSortOrder = .price
    ) async {
        guard !nearbySearchInFlight else { return }
        nearbySearchInFlight = true
        defer { nearbySearchInFlight = false }

        isLoading = true
        defer { isLoading = false }

        await refreshStationsIfNeeded()

        var results = routeFinder.findNearbyStations(
            coordinate: coordinate,
            radiusKm: radiusKm,
            fuelType: fuelType,
            limit: limit
        )

        switch sortBy {
        case .price:
            results.sort { $0.price < $1.price }
        case .distance:
            results.sort { $0.distanceKm < $1.distanceKm }
        }

        nearbyStations = results
    }

    /// Finds stations along a route corridor.
    func findStationsAlongRoute(
        route: MKRoute,
        corridorRadiusMeters: Double = 3000,
        fuelType: String = "unleaded",
        currentLocation: CLLocationCoordinate2D,
        limit: Int = 50,
        sortBy: StationSortOrder = .price
    ) async {
        guard !nearbySearchInFlight else { return }
        nearbySearchInFlight = true
        defer { nearbySearchInFlight = false }

        isLoading = true
        defer { isLoading = false }

        await refreshStationsIfNeeded()

        var results = routeFinder.findStationsAlongRoute(
            route: route,
            corridorRadiusMeters: corridorRadiusMeters,
            fuelType: fuelType,
            currentLocation: currentLocation,
            limit: limit
        )

        switch sortBy {
        case .price:
            results.sort { $0.price < $1.price }
        case .distance:
            // In route mode, sort by detour time instead of distance
            results.sort { $0.estimatedDetourMinutes < $1.estimatedDetourMinutes }
        }

        nearbyStations = results
    }

    /// Checks if cached data is stale and updates the flag.
    func checkStaleness() {
        guard let last = lastRefresh else {
            isDataStale = true
            return
        }
        isDataStale = Date().timeIntervalSince(last) > Self.refreshInterval
    }

    // MARK: - Fetch All Retailer Feeds

    private func fetchAllRetailerFeeds() async throws {
        var allStations: [ImportableStation] = []
        var feedErrors: [String] = []

        // Fetch all feeds concurrently
        await withTaskGroup(of: (String, Result<[RetailerStation], Error>).self) { group in
            for feed in Self.retailerFeeds {
                group.addTask { [session] in
                    do {
                        guard let url = URL(string: feed.url) else {
                            return (feed.name, .failure(FuelFinderError.invalidURL))
                        }
                        let (data, response) = try await session.data(from: url)
                        guard let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode == 200 else {
                            return (feed.name, .failure(FuelFinderError.serverError))
                        }
                        let feedResponse = try JSONDecoder().decode(RetailerFeedResponse.self, from: data)
                        return (feed.name, .success(feedResponse.stations))
                    } catch {
                        return (feed.name, .failure(error))
                    }
                }
            }

            for await (name, result) in group {
                switch result {
                case .success(let stations):
                    print("[FuelDataManager] \(name): \(stations.count) stations")
                    allStations.append(contentsOf: stations.map { ImportableStation(retailer: $0) })
                case .failure(let error):
                    let msg = "\(name): \(error.localizedDescription)"
                    print("[FuelDataManager] Feed error — \(msg)")
                    feedErrors.append(msg)
                }
            }
        }

        if allStations.isEmpty {
            throw FuelFinderError.noDataAvailable(feedErrors)
        }

        print("[FuelDataManager] Total stations fetched: \(allStations.count)")
        try await importStations(allStations)

        if !feedErrors.isEmpty {
            print("[FuelDataManager] \(feedErrors.count) feed(s) failed but data was imported from others")
        }
    }

    // MARK: - Importable Station (normalised from retailer format)

    private struct ImportableStation: Sendable {
        let id: String
        let name: String
        let brand: String
        let latitude: Double
        let longitude: Double
        let address: String
        let amenities: String
        let unleaded: Double    // in pounds (£)
        let superUnleaded: Double
        let diesel: Double
        let premiumDiesel: Double
        let updated: Date

        init(retailer: RetailerStation) {
            self.id = retailer.siteId
            self.brand = retailer.brand
            self.latitude = retailer.location.latitude
            self.longitude = retailer.location.longitude
            self.address = [retailer.address, retailer.postcode]
                .compactMap { $0 }
                .joined(separator: ", ")
            self.name = "\(retailer.brand) \(retailer.postcode ?? retailer.address ?? "")"
            self.amenities = "[]"
            // Convert from pence to pounds
            self.unleaded = (retailer.prices.e10 ?? 0) / 100.0
            self.superUnleaded = (retailer.prices.e5 ?? 0) / 100.0
            self.diesel = (retailer.prices.b7 ?? 0) / 100.0
            self.premiumDiesel = (retailer.prices.sdv ?? 0) / 100.0
            self.updated = Date()
        }
    }

    // MARK: - Core Data Import

    private func importStations(_ stations: [ImportableStation]) async throws {
        let context = coreDataStack.newBackgroundContext()

        try await context.perform {
            // Batch fetch all existing stations in one query
            let ids = stations.map(\.id)
            let fetchRequest: NSFetchRequest<Station> = Station.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)
            fetchRequest.returnsObjectsAsFaults = false
            fetchRequest.relationshipKeyPathsForPrefetching = ["prices"]

            let existingStations = try context.fetch(fetchRequest)
            let existingByID: [String: Station] = existingStations.reduce(into: [:]) { dict, station in
                if let id = station.id { dict[id] = station }
            }

            let now = Date()
            for importable in stations {
                // Skip stations with no valid prices
                guard importable.unleaded > 0 || importable.diesel > 0 else { continue }
                // Skip stations with invalid coordinates
                guard importable.latitude != 0 && importable.longitude != 0 else { continue }

                let station: Station
                if let existing = existingByID[importable.id] {
                    station = existing
                } else {
                    station = Station(context: context)
                    station.id = importable.id
                    station.isFavourite = false
                }

                station.name = importable.name
                station.brand = importable.brand
                station.latitude = importable.latitude
                station.longitude = importable.longitude
                station.address = importable.address
                station.lastUpdated = now
                station.amenities = importable.amenities

                let priceSet: PriceSet
                if let existing = station.prices {
                    priceSet = existing
                } else {
                    priceSet = PriceSet(context: context)
                    priceSet.station = station
                    station.prices = priceSet
                }

                priceSet.unleaded = importable.unleaded
                priceSet.superUnleaded = importable.superUnleaded
                priceSet.diesel = importable.diesel
                priceSet.premiumDiesel = importable.premiumDiesel
                priceSet.updatedAt = importable.updated
            }

            try context.save()
        }
    }

    // MARK: - Helpers

    private func refreshStationsIfNeeded() async {
        if let last = lastRefresh, Date().timeIntervalSince(last) < Self.refreshInterval {
            return
        }
        await refreshStations()
    }
}

// MARK: - Errors

enum FuelFinderError: LocalizedError {
    case invalidURL
    case serverError
    case noDataAvailable([String])
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid fuel data URL"
        case .serverError: return "Fuel price server returned an error"
        case .noDataAvailable(let errors):
            return "Could not fetch fuel prices from any retailer. Errors: \(errors.joined(separator: "; "))"
        case .decodingFailed: return "Failed to decode fuel price response"
        }
    }
}
