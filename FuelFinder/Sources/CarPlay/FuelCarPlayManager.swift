import Foundation
import CarPlay
import MapKit
import CoreLocation
import Combine

/// Bridges app state to CarPlay templates.
/// Manages station data display and keeps templates in sync with FuelDataManager.
@MainActor
final class FuelCarPlayManager: ObservableObject {

    // MARK: - Dependencies

    private let dataManager: FuelDataManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CarPlay State

    private(set) var interfaceController: CPInterfaceController?
    private var nearbyTemplate: CPListTemplate?
    private var rootTabBar: CPTabBarTemplate?

    var fuelType: String = "unleaded"

    init(dataManager: FuelDataManager) {
        self.dataManager = dataManager
    }

    // MARK: - Template Builders

    /// Builds the root CPTabBarTemplate.
    func buildRootTemplate() -> CPTabBarTemplate {
        let nearbyTab = buildNearbyListTemplate()
        let favouritesTab = buildFavouritesListTemplate()
        let tabBar = CPTabBarTemplate(templates: [nearbyTab, favouritesTab])
        self.rootTabBar = tabBar
        return tabBar
    }

    /// "Nearby" tab — CPListTemplate of nearest stations.
    func buildNearbyListTemplate() -> CPListTemplate {
        let items = dataManager.nearbyStations.prefix(12).map { station in
            buildStationListItem(station: station)
        }

        let section = CPListSection(items: items, header: "Nearest Fuel Stations", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Nearby", sections: [section])
        template.tabTitle = "Nearby"
        template.tabImage = UIImage(systemName: "location.fill")
        self.nearbyTemplate = template
        return template
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
        guard let nearbyTemplate else { return }
        let items = dataManager.nearbyStations.prefix(12).map { station in
            buildStationListItem(station: station)
        }
        let section = CPListSection(items: items, header: "Nearest Fuel Stations", sectionIndexTitle: nil)
        nearbyTemplate.updateSections([section])
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
