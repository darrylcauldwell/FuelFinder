import Foundation
import MapKit
import CoreLocation
import Combine

/// Manages route calculation and storage for finding stations along a planned route.
@MainActor
final class RouteManager: ObservableObject {

    // MARK: - Published State

    @Published var activeRoute: MKRoute?
    @Published var destination: MKMapItem?
    @Published var isCalculatingRoute = false
    @Published var routeError: String?

    /// Corridor radius for finding stations (in meters)
    @Published var corridorRadiusMiles: Double = 2.0

    var corridorRadiusMeters: Double {
        corridorRadiusMiles * 1609.34 // miles to meters
    }

    // MARK: - Route Calculation

    /// Calculates route from current location to destination.
    func calculateRoute(from origin: CLLocationCoordinate2D, to destination: MKMapItem) async {
        isCalculatingRoute = true
        routeError = nil

        defer { isCalculatingRoute = false }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()

            guard let route = response.routes.first else {
                routeError = "No route found"
                activeRoute = nil
                return
            }

            activeRoute = route
            self.destination = destination
            routeError = nil

        } catch {
            routeError = error.localizedDescription
            activeRoute = nil
        }
    }

    /// Clears the active route and returns to nearby mode.
    func clearRoute() {
        activeRoute = nil
        destination = nil
        routeError = nil
    }

    /// Returns true if a route is currently active.
    var hasActiveRoute: Bool {
        activeRoute != nil
    }

    /// Formatted route summary for display.
    var routeSummary: String? {
        guard let route = activeRoute else { return nil }
        let distance = Measurement(value: route.distance, unit: UnitLength.meters)
            .converted(to: .miles)
        let time = route.expectedTravelTime / 60 // minutes
        return String(format: "%.1f mi, %.0f min", distance.value, time)
    }

    // MARK: - Station Distance to Route

    /// Calculates minimum distance from a point to the route polyline.
    func distanceToRoute(from coordinate: CLLocationCoordinate2D) -> Double? {
        guard let route = activeRoute else { return nil }

        let point = MKMapPoint(coordinate)
        var minDistance = Double.infinity

        let polyline = route.polyline
        let pointCount = polyline.pointCount
        let points = polyline.points()

        // Check distance to each line segment
        for i in 0..<(pointCount - 1) {
            let p1 = points[i]
            let p2 = points[i + 1]
            let distance = distanceFromPoint(point, toLineSegmentBetween: p1, and: p2)
            minDistance = min(minDistance, distance)
        }

        return minDistance
    }

    /// Calculates perpendicular distance from a point to a line segment.
    private func distanceFromPoint(
        _ point: MKMapPoint,
        toLineSegmentBetween p1: MKMapPoint,
        and p2: MKMapPoint
    ) -> Double {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y

        if dx == 0 && dy == 0 {
            // p1 and p2 are the same point
            return point.distance(to: p1)
        }

        // Calculate projection parameter
        let t = ((point.x - p1.x) * dx + (point.y - p1.y) * dy) / (dx * dx + dy * dy)

        if t < 0 {
            // Beyond p1 end of segment
            return point.distance(to: p1)
        } else if t > 1 {
            // Beyond p2 end of segment
            return point.distance(to: p2)
        } else {
            // Perpendicular point is on segment
            let projection = MKMapPoint(x: p1.x + t * dx, y: p1.y + t * dy)
            return point.distance(to: projection)
        }
    }

    /// Estimates detour time to visit a station and return to route (in minutes).
    func estimatedDetourMinutes(
        to stationCoordinate: CLLocationCoordinate2D,
        from currentLocation: CLLocationCoordinate2D
    ) -> Double? {
        guard let distanceMeters = distanceToRoute(from: stationCoordinate) else {
            return nil
        }

        // Simplified detour calculation:
        // Assume average speed of 30 mph (48 km/h) for detour
        // Detour = distance to route * 2 (there and back) + small buffer for fuel stop
        let detourDistanceMeters = distanceMeters * 2.0
        let averageSpeedMetersPerMinute = 804.67 // 30 mph = 804.67 m/min
        let detourMinutes = detourDistanceMeters / averageSpeedMetersPerMinute

        return detourMinutes + 3.0 // Add 3 minutes for fuel stop
    }
}
