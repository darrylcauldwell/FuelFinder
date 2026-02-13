import Foundation
import CoreLocation
import Combine

/// Wraps CLLocationManager to provide reactive location updates.
/// Publishes the user's current coordinate for map centering and nearby station searches.
@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?

    /// Default coordinate (central London) used before location is available.
    static let defaultUK = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)

    /// Best available coordinate — real location or fallback.
    var effectiveLocation: CLLocationCoordinate2D {
        currentLocation ?? Self.defaultUK
    }

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500 // Update every 500m
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdating()
            case .denied, .restricted:
                self.locationError = "Location access denied. Enable in Settings to find nearby stations."
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.locationError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationError = error.localizedDescription
        }
    }
}
