import Foundation
import CoreData
import CoreLocation
import MapKit

// MARK: - CLLocationCoordinate2D Equatable

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - StationWithScore

/// A station scored for relevance along a route, combining price and detour cost.
struct StationWithScore: Identifiable, Sendable, Equatable {
    let id: String
    let stationID: String
    let name: String
    let brand: String
    let coordinate: CLLocationCoordinate2D
    let address: String
    let price: Double
    let fuelType: String
    let distanceFromRouteKm: Double
    let estimatedDetourMinutes: Double
    let score: Double  // Lower is better
    let isFavourite: Bool

    /// Price tier: 0 = cheapest (green), 1 = mid (amber), 2 = expensive (red).
    var priceTier: Int

    var formattedPrice: String {
        String(format: "£%.2f", price)
    }

    var formattedDetour: String {
        if distanceFromRouteKm < 0.1 {
            return "On route"
        }
        return String(format: "%.1f km (+%d min)", distanceFromRouteKm, Int(estimatedDetourMinutes))
    }

    /// Summary for CarPlay: "Shell — £1.48 (1.2km, +3min)"
    var carPlaySummary: String {
        "\(brand) — \(formattedPrice) (\(formattedDetour))"
    }
}

// MARK: - RouteStationFinder

/// Finds and scores fuel stations along a MapKit route corridor.
///
/// Thread-safe: creates a new background context per search call.
/// No shared mutable state.
final class RouteStationFinder: Sendable {

    private let coreDataStack: CoreDataStack

    /// Score weights — higher detour weight = prefer closer stations.
    private let detourWeight: Double = 0.4
    private let averageDetourSpeedKmH: Double = 30.0
    private let sampleIntervalMetres: Double = 500.0

    init(coreDataStack: CoreDataStack) {
        self.coreDataStack = coreDataStack
    }

    // MARK: - Public: Route Corridor Search

    func findStationsAlongRoute(
        route: MKRoute,
        maxDistanceKm: Double,
        fuelType: String,
        limit: Int = 50
    ) -> [StationWithScore] {
        let polyline = route.polyline
        let samplePoints = samplePolyline(polyline, intervalMetres: sampleIntervalMetres)
        guard !samplePoints.isEmpty else { return [] }

        let boundingBox = expandedBoundingBox(for: samplePoints, marginKm: maxDistanceKm)
        let context = coreDataStack.newBackgroundContext()

        var scored: [StationWithScore] = []
        context.performAndWait {
            let stations = self.fetchStations(in: boundingBox, fuelType: fuelType, limit: limit * 10, context: context)

            for station in stations {
                guard let price = station.price(for: fuelType), price > 0 else { continue }

                let stationLocation = station.location
                let minDistance = self.minimumDistance(from: stationLocation, to: samplePoints, threshold: maxDistanceKm * 1000.0)
                let distanceKm = minDistance / 1000.0
                guard distanceKm <= maxDistanceKm else { continue }

                let detourMinutes = (distanceKm * 2) / self.averageDetourSpeedKmH * 60

                scored.append(StationWithScore(
                    id: station.id ?? UUID().uuidString,
                    stationID: station.id ?? "",
                    name: station.name ?? "Unknown",
                    brand: station.brand ?? "",
                    coordinate: station.coordinate,
                    address: station.address ?? "",
                    price: price,
                    fuelType: fuelType,
                    distanceFromRouteKm: distanceKm,
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

                let detourMinutes = distanceKm / self.averageDetourSpeedKmH * 60

                scored.append(StationWithScore(
                    id: station.id ?? UUID().uuidString,
                    stationID: station.id ?? "",
                    name: station.name ?? "Unknown",
                    brand: station.brand ?? "",
                    coordinate: station.coordinate,
                    address: station.address ?? "",
                    price: price,
                    fuelType: fuelType,
                    distanceFromRouteKm: distanceKm,
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

    // MARK: - Polyline Sampling

    private func samplePolyline(_ polyline: MKPolyline, intervalMetres: Double) -> [CLLocation] {
        let count = polyline.pointCount
        guard count > 1 else { return [] }

        let points = polyline.points()
        var samples: [CLLocation] = []
        var accumulated: Double = 0

        // Reuse previous CLLocation to avoid creating 2 per iteration
        var prevLocation = CLLocation(latitude: points[0].coordinate.latitude, longitude: points[0].coordinate.longitude)
        samples.append(prevLocation)

        for i in 1..<count {
            let curr = CLLocation(latitude: points[i].coordinate.latitude, longitude: points[i].coordinate.longitude)
            accumulated += prevLocation.distance(from: curr)

            if accumulated >= intervalMetres {
                samples.append(curr)
                accumulated = 0
            }
            prevLocation = curr
        }

        // Always include the last point
        if let lastSample = samples.last, lastSample.distance(from: prevLocation) > 10 {
            samples.append(prevLocation)
        }

        return samples
    }

    // MARK: - Distance Calculations

    private func minimumDistance(from location: CLLocation, to samplePoints: [CLLocation], threshold: Double) -> Double {
        var minDist = Double.greatestFiniteMagnitude
        for sample in samplePoints {
            let dist = location.distance(from: sample)
            if dist < minDist {
                minDist = dist
                // Early termination: if already within threshold, no need to check further
                if minDist < 100 { return minDist }
            }
        }
        return minDist
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
        let detours = stations.map(\.distanceFromRouteKm)

        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 1
        let priceRange = maxPrice - minPrice

        let minDetour = detours.min() ?? 0
        let maxDetour = detours.max() ?? 1
        let detourRange = maxDetour - minDetour

        return stations.map { station in
            let normPrice = priceRange > 0 ? (station.price - minPrice) / priceRange : 0
            let normDetour = detourRange > 0 ? (station.distanceFromRouteKm - minDetour) / detourRange : 0
            let score = (1.0 - detourWeight) * normPrice + detourWeight * normDetour

            return StationWithScore(
                id: station.id, stationID: station.stationID,
                name: station.name, brand: station.brand,
                coordinate: station.coordinate, address: station.address,
                price: station.price, fuelType: station.fuelType,
                distanceFromRouteKm: station.distanceFromRouteKm,
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
