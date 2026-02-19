import Foundation
import CarPlay
import MapKit
import CoreLocation
import Combine

/// Bridges app state to CarPlay templates.
/// Manages station data display and keeps templates in sync with FuelDataManager.
@MainActor
final class FuelCarPlayManager: NSObject, ObservableObject {

    // MARK: - Dependencies

    private let dataManager: FuelDataManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CarPlay State

    private(set) var interfaceController: CPInterfaceController?
    private var nearbyPOITemplate: CPPointOfInterestTemplate?
    private var rootTabBar: CPTabBarTemplate?

    var fuelType: String = "unleaded"

    init(dataManager: FuelDataManager) {
        self.dataManager = dataManager
    }

    // MARK: - Template Builders

    /// Builds the root CPTabBarTemplate.
    func buildRootTemplate() -> CPTabBarTemplate {
        let nearbyTab = buildNearbyPointsOfInterestTemplate()
        let favouritesTab = buildFavouritesListTemplate()
        let tabBar = CPTabBarTemplate(templates: [nearbyTab, favouritesTab])
        self.rootTabBar = tabBar
        return tabBar
    }

    /// "Nearby" tab — CPPointOfInterestTemplate: map with fuel-station pins.
    func buildNearbyPointsOfInterestTemplate() -> CPPointOfInterestTemplate {
        let pois = makePOIs(from: dataManager.nearbyStations)
        let template = CPPointOfInterestTemplate(
            title: "Nearby Fuel",
            pointsOfInterest: pois,
            selectedIndex: NSNotFound
        )
        template.tabTitle = "Nearby"
        template.tabImage = UIImage(systemName: "location.fill")
        template.pointOfInterestDelegate = self
        self.nearbyPOITemplate = template
        return template
    }

    /// Converts `StationWithScore` array into `CPPointOfInterest` pins.
    private func makePOIs(from stations: [StationWithScore]) -> [CPPointOfInterest] {
        stations.prefix(12).map { station in
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
            mapItem.name = station.name

            let tierColor: UIColor
            switch station.priceTier {
            case 0: tierColor = .systemGreen
            case 1: tierColor = .systemOrange
            default: tierColor = .systemRed
            }
            let pinImage = UIImage(systemName: "fuelpump.fill")?
                .withTintColor(tierColor, renderingMode: .alwaysOriginal)

            return CPPointOfInterest(
                location: mapItem,
                title: station.name,
                subtitle: station.formattedPrice,
                summary: station.formattedDistance,
                detailTitle: station.name,
                detailSubtitle: "\(station.formattedPrice) · \(station.brand)",
                detailSummary: station.address,
                pinImage: pinImage
            )
        }
    }

    /// "Favourites" tab — placeholder.
    func buildFavouritesListTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Favourites", sections: [])
        template.tabTitle = "Favourites"
        template.tabImage = UIImage(systemName: "star.fill")
        template.emptyViewTitleVariants = ["No Favourites"]
        template.emptyViewSubtitleVariants = ["Mark stations as favourite on your iPhone"]
        return template
    }

    /// Builds a CPListItem for a station.
    private func buildStationListItem(station: StationWithScore) -> CPListItem {
        let item = CPListItem(
            text: "\(station.name) — \(station.formattedPrice)",
            detailText: station.formattedDistance
        )

        // Price tier badge
        let tierImageName: String
        let tierColor: UIColor
        switch station.priceTier {
        case 0:
            tierImageName = "leaf.circle.fill"
            tierColor = .systemGreen
        case 1:
            tierImageName = "circle.fill"
            tierColor = .systemYellow
        default:
            tierImageName = "exclamationmark.circle.fill"
            tierColor = .systemRed
        }
        item.setImage(
            UIImage(systemName: tierImageName)?.withTintColor(tierColor, renderingMode: .alwaysOriginal)
        )

        item.handler = { [weak self] _, completion in
            self?.showStationDetail(station: station)
            completion()
        }

        return item
    }

    // MARK: - Station Detail

    func showStationDetail(station: StationWithScore) {
        let items: [CPInformationItem] = [
            CPInformationItem(title: "Price", detail: station.formattedPrice),
            CPInformationItem(title: "Brand", detail: station.brand),
            CPInformationItem(title: "Distance", detail: station.formattedDistance),
            CPInformationItem(title: "Address", detail: station.address)
        ]

        let navigateAction = CPTextButton(title: "Get Directions", textStyle: .confirm) { [weak self] _ in
            self?.navigateToStation(station: station)
        }

        let template = CPInformationTemplate(
            title: station.name,
            layout: .leading,
            items: items,
            actions: [navigateAction]
        )

        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Refresh Nearby Tab

    func refreshNearbyTab() {
        guard let nearbyPOITemplate else { return }
        let pois = makePOIs(from: dataManager.nearbyStations)
        nearbyPOITemplate.setPointsOfInterest(pois, selectedIndex: NSNotFound)
    }

    // MARK: - Navigation

    func navigateToStation(station: StationWithScore) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        mapItem.name = station.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
        interfaceController?.popToRootTemplate(animated: true, completion: nil)
    }

    // MARK: - Voice Commands

    func handleVoiceCommand(_ command: String) {
        let lowered = command.lowercased()

        if lowered.contains("cheapest") {
            if let cheapest = dataManager.nearbyStations.min(by: { $0.price < $1.price }) {
                showStationDetail(station: cheapest)
            }
        } else if lowered.contains("nearest") || lowered.contains("nearby") {
            refreshNearbyTab()
        } else if let brand = extractBrand(from: lowered) {
            let filtered = dataManager.nearbyStations.filter {
                $0.brand.lowercased().contains(brand)
            }
            if let cheapestOfBrand = filtered.min(by: { $0.price < $1.price }) {
                showStationDetail(station: cheapestOfBrand)
            }
        }
    }

    private func extractBrand(from text: String) -> String? {
        let brands = ["shell", "bp", "esso", "texaco", "morrisons", "tesco", "sainsbury", "asda", "jet"]
        return brands.first { text.contains($0) }
    }

    // MARK: - Interface Controller

    func setInterfaceController(_ controller: CPInterfaceController) {
        self.interfaceController = controller
    }
}

// MARK: - CPPointOfInterestTemplateDelegate

extension FuelCarPlayManager: CPPointOfInterestTemplateDelegate {

    nonisolated func pointOfInterestTemplate(
        _ pointOfInterestTemplate: CPPointOfInterestTemplate,
        didChangeMapRegion region: MKCoordinateRegion
    ) {
        // No action — stations are pre-loaded for the user's location
    }

    nonisolated func pointOfInterestTemplate(
        _ pointOfInterestTemplate: CPPointOfInterestTemplate,
        didSelectPointOfInterest pointOfInterest: CPPointOfInterest
    ) {
        let coord = pointOfInterest.location.placemark.coordinate
        Task { @MainActor [self] in
            if let station = dataManager.nearbyStations.first(where: {
                abs($0.coordinate.latitude - coord.latitude) < 0.0001 &&
                abs($0.coordinate.longitude - coord.longitude) < 0.0001
            }) {
                showStationDetail(station: station)
            }
        }
    }
}
