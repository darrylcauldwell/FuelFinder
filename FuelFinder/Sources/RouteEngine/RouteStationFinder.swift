import Foundation
import CoreData
import CoreLocation
import MapKit

// MARK: - CLLocationCoordinate2D Equatable

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 1e-7 && abs(lhs.longitude - rhs.longitude) < 1e-7
    }
}

// MARK: - StationWithScore

/// A station scored for relevance, combining price and distance.
struct StationWithScore: Identifiable, Sendable, Equatable {
    let id: String
    let stationID: String
    let name: String
    let brand: String
    let coordinate: CLLocationCoordinate2D
    let address: String
    let price: Double
    let fuelType: String
    let distanceKm: Double
    let estimatedDetourMinutes: Double
    let score: Double  // Lower is better
    let isFavourite: Bool

    /// Price tier: 0 = cheapest (green), 1 = mid (amber), 2 = expensive (red).
    var priceTier: Int

    var formattedPrice: String {
        String(format: "£%.2f", price)
    }

    var formattedDistance: String {
        if distanceKm < 0.1 { return "< 100m" }
        if distanceKm < 1.0 { return String(format: "%.0f m", distanceKm * 1000) }
        return String(format: "%.1f km", distanceKm)
    }

    /// Summary for CarPlay: "Shell — £1.48 (1.2 km)"
    var carPlaySummary: String {
        "\(brand) — \(formattedPrice) (\(formattedDistance))"
    }
}

// MARK: - RouteStationFinder

/// Finds and scores nearby fuel stations.
///
/// Thread-safe: creates a new background context per search call.
/// No shared mutable state.
final class RouteStationFinder: Sendable {

    private let coreDataStack: CoreDataStack

    /// Score weights — higher distance weight = prefer closer stations.
    private let distanceWeight: Double = 0.4
    private let averageSpeedKmH: Double = 30.0

    init(coreDataStack: CoreDataStack) {
        self.coreDataStack = coreDataStack
    }

    // MARK: - Public: Nearby Search

    func findNearbyStations(
        coordinate: CLLocationCoordinate2D,
        radiusKm: Double,
        fuelType: String,
        limit: Int = 20
    ) -> [StationWithScore] {
        let center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let boundingBox = expandedBoundingBox(for: [center], marginKm: radiusKm)
        let context = coreDataStack.newBackgroundContext()

        var scored: [StationWithScore] = []
        context.performAndWait {
            let stations = self.fetchStations(in: boundingBox, fuelType: fuelType, limit: limit * 10, context: context)

            for station in stations {
                guard let price = station.price(for: fuelType), price > 0 else { continue }

                let distanceKm = center.distance(from: station.location) / 1000.0
                guard distanceKm <= radiusKm else { continue }

                let detourMinutes = distanceKm / self.averageSpeedKmH * 60

                scored.append(StationWithScore(
                    id: station.id ?? UUID().uuidString,
                    stationID: station.id ?? "",
                    name: station.name ?? "Unknown",
                    brand: station.brand ?? "",
                    coordinate: station.coordinate,
                    address: station.address ?? "",
                    price: price,
                    fuelType: fuelType,
                    distanceKm: distanceKm,
                    estimatedDetourMinutes: detourMinutes,
                    score: 0,
                    isFavourite: station.isFavourite,
                    priceTier: 0
                ))
            }
        }

        guard !scored.isEmpty else { return [] }
        var normalised = normaliseAndScore(scored)
        assignPriceTiers(&normalised)
        normalised.sort { $0.score < $1.score }
        return Array(normalised.prefix(limit))
    }

    // MARK: - Bounding Box

    private struct BoundingBox {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double
    }

    private func expandedBoundingBox(for points: [CLLocation], marginKm: Double) -> BoundingBox {
        guard !points.isEmpty else {
            return BoundingBox(minLat: 0, maxLat: 0, minLon: 0, maxLon: 0)
        }

        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for point in points {
            minLat = min(minLat, point.coordinate.latitude)
            maxLat = max(maxLat, point.coordinate.latitude)
            minLon = min(minLon, point.coordinate.longitude)
            maxLon = max(maxLon, point.coordinate.longitude)
        }

        let latMargin = marginKm / 111.0
        let avgLat = (minLat + maxLat) / 2.0
        let lonMargin = marginKm / (111.0 * cos(avgLat * .pi / 180.0))

        return BoundingBox(
            minLat: minLat - latMargin,
            maxLat: maxLat + latMargin,
            minLon: minLon - lonMargin,
            maxLon: maxLon + lonMargin
        )
    }

    // MARK: - Core Data Fetch

    private func fetchStations(in box: BoundingBox, fuelType: String, limit: Int, context: NSManagedObjectContext) -> [Station] {
        let request: NSFetchRequest<Station> = Station.fetchRequest()

        // Combine bounding box with fuel-type price > 0 to filter at the DB level
        let boxPredicate = NSPredicate(
            format: "latitude >= %lf AND latitude <= %lf AND longitude >= %lf AND longitude <= %lf",
            box.minLat, box.maxLat, box.minLon, box.maxLon
        )
        let priceKey: String
        switch fuelType {
        case "unleaded": priceKey = "prices.unleaded"
        case "diesel": priceKey = "prices.diesel"
        case "superUnleaded": priceKey = "prices.superUnleaded"
        case "premiumDiesel": priceKey = "prices.premiumDiesel"
        default: priceKey = "prices.unleaded"
        }
        let pricePredicate = NSPredicate(format: "%K > 0", priceKey)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [boxPredicate, pricePredicate])

        request.fetchBatchSize = 100
        request.fetchLimit = limit
        request.returnsObjectsAsFaults = false
        request.relationshipKeyPathsForPrefetching = ["prices"]

        do {
            return try context.fetch(request)
        } catch {
            print("[RouteStationFinder] Fetch error: \(error)")
            return []
        }
    }

    // MARK: - Scoring

    private func normaliseAndScore(_ stations: [StationWithScore]) -> [StationWithScore] {
        let prices = stations.map(\.price)
        let distances = stations.map(\.distanceKm)

        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 1
        let priceRange = maxPrice - minPrice

        let minDist = distances.min() ?? 0
        let maxDist = distances.max() ?? 1
        let distRange = maxDist - minDist

        return stations.map { station in
            let normPrice = priceRange > 0 ? (station.price - minPrice) / priceRange : 0
            let normDist = distRange > 0 ? (station.distanceKm - minDist) / distRange : 0
            let score = (1.0 - distanceWeight) * normPrice + distanceWeight * normDist

            return StationWithScore(
                id: station.id, stationID: station.stationID,
                name: station.name, brand: station.brand,
                coordinate: station.coordinate, address: station.address,
                price: station.price, fuelType: station.fuelType,
                distanceKm: station.distanceKm,
                estimatedDetourMinutes: station.estimatedDetourMinutes,
                score: score, isFavourite: station.isFavourite,
                priceTier: 0
            )
        }
    }

    /// Assigns price tiers in-place without re-sorting the array.
    /// Sorts indices by price, assigns tiers to thirds, then writes back.
    private func assignPriceTiers(_ stations: inout [StationWithScore]) {
        let count = stations.count
        guard count > 0 else { return }

        // Sort indices by price — avoids copying StationWithScore structs
        let sortedIndices = stations.indices.sorted { stations[$0].price < stations[$1].price }
        let thirdSize = max(1, count / 3)

        for (rank, idx) in sortedIndices.enumerated() {
            if rank < thirdSize {
                stations[idx].priceTier = 0
            } else if rank < thirdSize * 2 {
                stations[idx].priceTier = 1
            } else {
                stations[idx].priceTier = 2
            }
        }
    }
}
