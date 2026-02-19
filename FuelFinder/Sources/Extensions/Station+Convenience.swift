import Foundation
import CoreData
import CoreLocation
import MapKit
import SwiftUI
import ObjectiveC

// MARK: - Station Convenience

/// Associated object key for cached amenities decode.
nonisolated(unsafe) private var amenitiesCacheKey: UInt8 = 0

extension Station {

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Returns price for the given fuel type key, or nil if unavailable.
    func price(for fuelType: String) -> Double? {
        guard let prices else { return nil }
        switch fuelType {
        case "unleaded":
            let v = prices.unleaded
            return v > 0 ? v : nil
        case "superUnleaded":
            let v = prices.superUnleaded
            return v > 0 ? v : nil
        case "diesel":
            let v = prices.diesel
            return v > 0 ? v : nil
        case "premiumDiesel":
            let v = prices.premiumDiesel
            return v > 0 ? v : nil
        default:
            return nil
        }
    }

    /// Formatted price string e.g. "£1.45"
    func formattedPrice(for fuelType: String) -> String {
        guard let p = price(for: fuelType) else { return "N/A" }
        return String(format: "£%.2f", p)
    }

    /// Decoded amenities array from JSON string.
    /// Cached via associated object to avoid re-decoding on every access.
    var amenitiesList: [String] {
        if let cached = objc_getAssociatedObject(self, &amenitiesCacheKey) as? [String] {
            return cached
        }
        guard let data = amenities?.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        objc_setAssociatedObject(self, &amenitiesCacheKey, arr, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return arr
    }

    /// True if price data is older than the given interval (default 24h).
    func isStale(after interval: TimeInterval = 86400) -> Bool {
        guard let updated = prices?.updatedAt else { return true }
        return Date().timeIntervalSince(updated) > interval
    }
}

// MARK: - Station Sort Order

enum StationSortOrder: String, CaseIterable, Identifiable, Sendable {
    case price, distance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .price: return "Cheapest"
        case .distance: return "Nearest"
        }
    }
}

// MARK: - Fuel Type Enum

enum FuelType: String, CaseIterable, Identifiable, Sendable {
    case unleaded
    case superUnleaded
    case diesel
    case premiumDiesel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unleaded: return "Unleaded"
        case .superUnleaded: return "Super Unleaded"
        case .diesel: return "Diesel"
        case .premiumDiesel: return "Premium Diesel"
        }
    }

    var shortName: String {
        switch self {
        case .unleaded: return "UNL"
        case .superUnleaded: return "SUP"
        case .diesel: return "DSL"
        case .premiumDiesel: return "P.DSL"
        }
    }

    var color: Color {
        AppColors.fuelType(rawValue)
    }
}
