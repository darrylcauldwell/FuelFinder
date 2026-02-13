import Foundation
import CoreData
import CoreLocation
import MapKit
import Combine

// MARK: - Fuel Finder API Response Models

struct FuelFinderStationResponse: Codable, Sendable {
    let id: String
    let name: String
    let brand: String?
    let lat: Double
    let lon: Double
    let address: String?
    let amenities: [String]?
    let prices: FuelFinderPrices
    let updated: String
}

struct FuelFinderPrices: Codable, Sendable {
    let unleaded: Double?
    let superUnleaded: Double?
    let diesel: Double?
    let premiumDiesel: Double?

    enum CodingKeys: String, CodingKey {
        case unleaded
        case superUnleaded = "super_unleaded"
        case diesel
        case premiumDiesel = "premium_diesel"
    }
}

struct FuelFinderSearchResponse: Codable, Sendable {
    let stations: [FuelFinderStationResponse]
    let total: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case stations, total
        case updatedAt = "updated_at"
    }
}

struct OAuthTokenResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

// MARK: - FuelDataManager

@MainActor
final class FuelDataManager: ObservableObject {

    // MARK: Published State

    @Published var stationsAlongRoute: [StationWithScore] = []
    @Published var nearbyStations: [StationWithScore] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastRefresh: Date?
    @Published var isDataStale = false

    // MARK: Configuration

    /// Replace with real Fuel Finder API credentials
    private let clientID = "YOUR_FUEL_FINDER_CLIENT_ID"       // Replace with real client ID
    private let clientSecret = "YOUR_FUEL_FINDER_CLIENT_SECRET" // Replace with real client secret
    private let baseURL = "https://fuel-finder.api.gov.uk/v1"  // Replace with real Fuel Finder base URL
    private let tokenURL = "https://fuel-finder.api.gov.uk/v1/auth/token" // Replace with real token endpoint

    // MARK: Dependencies

    let coreDataStack: CoreDataStack
    private let routeFinder: RouteStationFinder
    private let session: URLSession

    // MARK: Token Cache

    private var cachedToken: String?
    private var tokenExpiry: Date?

    // MARK: Request Deduplication

    /// Tracks in-flight refresh regions to prevent duplicate requests.
    private var inFlightRegions: Set<String> = []

    /// When true, uses bundled MockData.json instead of network calls.
    var useMockData = true

    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
        self.routeFinder = RouteStationFinder(coreDataStack: coreDataStack)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 20 * 1024 * 1024)
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func refreshStations(near coordinate: CLLocationCoordinate2D, radiusKm: Double = 50) async {
        // Deduplicate: quantise to ~1km grid to prevent overlapping requests
        let regionKey = "\(Int(coordinate.latitude * 100))_\(Int(coordinate.longitude * 100))_\(Int(radiusKm))"
        guard !inFlightRegions.contains(regionKey) else { return }
        inFlightRegions.insert(regionKey)
        defer { inFlightRegions.remove(regionKey) }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            if useMockData {
                try await loadMockData()
            } else {
                try await fetchStationsFromAPI(near: coordinate, radiusKm: radiusKm)
            }
            lastRefresh = Date()
            isDataStale = false
        } catch {
            lastError = error.localizedDescription
            print("[FuelDataManager] Refresh error: \(error)")
        }
    }

    func findStationsAlongRoute(route: MKRoute, fuelType: String = "unleaded", maxDetourKm: Double = 2.0) async {
        isLoading = true
        defer { isLoading = false }

        // Refresh data near route midpoint if stale
        let pointCount = route.polyline.pointCount
        guard pointCount > 0 else { return }
        let midIndex = pointCount / 2
        let points = route.polyline.points()
        let midCoord = points[midIndex].coordinate
        await refreshStationsIfNeeded(near: midCoord)

        // RouteStationFinder uses performAndWait on a background context internally
        stationsAlongRoute = routeFinder.findStationsAlongRoute(
            route: route,
            maxDistanceKm: maxDetourKm,
            fuelType: fuelType
        )
    }

    func findNearbyStations(coordinate: CLLocationCoordinate2D, fuelType: String = "unleaded", limit: Int = 20) async {
        isLoading = true
        defer { isLoading = false }

        await refreshStationsIfNeeded(near: coordinate)

        nearbyStations = routeFinder.findNearbyStations(
            coordinate: coordinate,
            radiusKm: 10,
            fuelType: fuelType,
            limit: limit
        )
    }

    /// Checks if cached data is stale and updates the flag.
    func checkStaleness() {
        guard let last = lastRefresh else {
            isDataStale = true
            return
        }
        isDataStale = Date().timeIntervalSince(last) > 86400 // 24 hours
    }

    // MARK: - OAuth2 Token

    private func getAccessToken() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }

        guard let url = URL(string: tokenURL) else {
            throw FuelFinderError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=client_credentials&client_id=\(clientID)&client_secret=\(clientSecret)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            cachedToken = nil
            tokenExpiry = nil
            throw FuelFinderError.authenticationFailed
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        cachedToken = tokenResponse.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        return tokenResponse.accessToken
    }

    // MARK: - API Fetch

    private func fetchStationsFromAPI(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async throws {
        let token = try await getAccessToken()

        guard var components = URLComponents(string: "\(baseURL)/stations") else {
            throw FuelFinderError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude)),
            URLQueryItem(name: "radius", value: "\(Int(radiusKm))km")
        ]

        guard let url = components.url else {
            throw FuelFinderError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw FuelFinderError.serverError
        }

        let apiResponse = try JSONDecoder().decode(FuelFinderSearchResponse.self, from: data)
        try await importStations(apiResponse.stations)
    }

    // MARK: - Mock Data

    private func loadMockData() async throws {
        guard let url = Bundle.main.url(forResource: "MockData", withExtension: "json") else {
            throw FuelFinderError.mockDataNotFound
        }

        let data = try Data(contentsOf: url)
        let stations = try JSONDecoder().decode([FuelFinderStationResponse].self, from: data)
        try await importStations(stations)
    }

    // MARK: - Core Data Import

    private func importStations(_ apiStations: [FuelFinderStationResponse]) async throws {
        let context = coreDataStack.newBackgroundContext()
        // Pre-encode amenities once on calling thread for each station that has them
        let amenitiesCache: [String: String] = apiStations.reduce(into: [:]) { dict, s in
            if let amenities = s.amenities {
                dict[s.id] = (try? JSONEncoder().encode(amenities))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            }
        }

        try await context.perform {
            let isoFormatter = ISO8601DateFormatter()
            // Batch fetch all existing stations in one query instead of N individual fetches
            let ids = apiStations.map(\.id)
            let fetchRequest: NSFetchRequest<Station> = Station.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)
            fetchRequest.returnsObjectsAsFaults = false
            fetchRequest.relationshipKeyPathsForPrefetching = ["prices"]

            let existingStations = try context.fetch(fetchRequest)
            let existingByID: [String: Station] = existingStations.reduce(into: [:]) { dict, station in
                if let id = station.id { dict[id] = station }
            }

            let now = Date()
            for apiStation in apiStations {
                let station: Station
                if let existing = existingByID[apiStation.id] {
                    station = existing
                } else {
                    station = Station(context: context)
                    station.id = apiStation.id
                    station.isFavourite = false
                }

                station.name = apiStation.name
                station.brand = apiStation.brand ?? ""
                station.latitude = apiStation.lat
                station.longitude = apiStation.lon
                station.address = apiStation.address ?? ""
                station.lastUpdated = now

                if let encoded = amenitiesCache[apiStation.id] {
                    station.amenities = encoded
                }

                let priceSet: PriceSet
                if let existing = station.prices {
                    priceSet = existing
                } else {
                    priceSet = PriceSet(context: context)
                    priceSet.station = station
                    station.prices = priceSet
                }

                priceSet.unleaded = apiStation.prices.unleaded ?? 0
                priceSet.superUnleaded = apiStation.prices.superUnleaded ?? 0
                priceSet.diesel = apiStation.prices.diesel ?? 0
                priceSet.premiumDiesel = apiStation.prices.premiumDiesel ?? 0
                priceSet.updatedAt = isoFormatter.date(from: apiStation.updated) ?? now
            }

            try context.save()
        }
    }

    // MARK: - Helpers

    private func refreshStationsIfNeeded(near coordinate: CLLocationCoordinate2D) async {
        if let last = lastRefresh, Date().timeIntervalSince(last) < 3600 {
            return
        }
        await refreshStations(near: coordinate)
    }
}

// MARK: - Errors

enum FuelFinderError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case serverError
    case mockDataNotFound
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Fuel Finder API URL"
        case .authenticationFailed: return "Fuel Finder authentication failed — check API credentials"
        case .serverError: return "Fuel Finder server returned an error"
        case .mockDataNotFound: return "MockData.json not found in bundle"
        case .decodingFailed: return "Failed to decode Fuel Finder response"
        }
    }
}
