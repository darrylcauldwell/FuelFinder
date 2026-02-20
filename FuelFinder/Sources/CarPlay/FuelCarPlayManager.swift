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
    private let routeManager: RouteManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CarPlay State

    private(set) var interfaceController: CPInterfaceController?
    private var nearbyPOITemplate: CPPointOfInterestTemplate?
    private var nearbyListTemplate: CPListTemplate?
    private var favouritesListTemplate: CPListTemplate?
    private var settingsListTemplate: CPListTemplate?
    private var rootTabBar: CPTabBarTemplate?

    // User preferences
    private var selectedFuelType: FuelType = .unleaded
    private var sortOrder: StationSortOrder = .price
    private var currentLocation: CLLocationCoordinate2D?

    init(dataManager: FuelDataManager, routeManager: RouteManager) {
        self.dataManager = dataManager
        self.routeManager = routeManager
    }

    // MARK: - Template Builders

    /// Builds the root CPTabBarTemplate with 4 tabs: Nearby (map), List, Favourites, Settings.
    func buildRootTemplate() -> CPTabBarTemplate {
        let nearbyTab = buildNearbyPointsOfInterestTemplate()
        let listTab = buildNearbyListTemplate()
        let favouritesTab = buildFavouritesListTemplate()
        let settingsTab = buildSettingsListTemplate()
        let tabBar = CPTabBarTemplate(templates: [nearbyTab, listTab, favouritesTab, settingsTab])
        self.rootTabBar = tabBar
        return tabBar
    }

    /// "Map" tab — CPPointOfInterestTemplate: map with fuel-station pins.
    func buildNearbyPointsOfInterestTemplate() -> CPPointOfInterestTemplate {
        let pois = makePOIs(from: dataManager.nearbyStations)
        let template = CPPointOfInterestTemplate(
            title: "Map",
            pointsOfInterest: pois,
            selectedIndex: NSNotFound
        )
        template.tabTitle = "Map"
        template.tabImage = UIImage(systemName: "map.fill")
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

    /// "List" tab — CPListTemplate: list of nearby stations with sort control.
    func buildNearbyListTemplate() -> CPListTemplate {
        let sortedStations = sortStations(dataManager.nearbyStations)
        let items = sortedStations.prefix(20).map { buildStationListItem(station: $0) }
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Nearby Stations", sections: [section])
        template.tabTitle = "List"
        template.tabImage = UIImage(systemName: "list.bullet")
        template.emptyViewTitleVariants = ["No Stations"]
        template.emptyViewSubtitleVariants = ["No fuel stations found nearby"]

        // Add sort button
        let sortButton = CPBarButton(title: sortOrder.displayName) { [weak self] _ in
            self?.showSortOrderPicker()
        }
        template.trailingNavigationBarButtons = [sortButton]

        self.nearbyListTemplate = template
        return template
    }

    /// Sorts stations based on current sort order.
    private func sortStations(_ stations: [StationWithScore]) -> [StationWithScore] {
        switch sortOrder {
        case .price:
            return stations.sorted { $0.price < $1.price }
        case .distance:
            return stations.sorted { $0.distanceKm < $1.distanceKm }
        }
    }

    /// "Favourites" tab — shows favourite stations from Core Data.
    func buildFavouritesListTemplate() -> CPListTemplate {
        let favourites = dataManager.nearbyStations.filter { $0.isFavourite }
        let items = favourites.map { buildStationListItem(station: $0) }
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Favourites", sections: items.isEmpty ? [] : [section])
        template.tabTitle = "Favourites"
        template.tabImage = UIImage(systemName: "star.fill")
        template.emptyViewTitleVariants = ["No Favourites"]
        template.emptyViewSubtitleVariants = ["Mark stations as favourite on your iPhone"]
        self.favouritesListTemplate = template
        return template
    }

    /// "Settings" tab — fuel type selection, route planning, and preferences.
    func buildSettingsListTemplate() -> CPListTemplate {
        var items: [CPListItem] = []

        // Route section
        if routeManager.hasActiveRoute {
            let routeItem = CPListItem(
                text: "Active Route",
                detailText: routeManager.routeSummary
            )
            routeItem.handler = { [weak self] _, completion in
                self?.showRouteClearConfirmation()
                completion()
            }
            items.append(routeItem)

            let corridorItem = CPListItem(
                text: "Search Radius",
                detailText: "\(Int(routeManager.corridorRadiusMiles)) mi"
            )
            corridorItem.handler = { [weak self] _, completion in
                self?.showCorridorPicker()
                completion()
            }
            items.append(corridorItem)
        } else {
            let setDestinationItem = CPListItem(
                text: "Set Destination",
                detailText: "Plan a route"
            )
            setDestinationItem.handler = { [weak self] _, completion in
                self?.showDestinationInput()
                completion()
            }
            items.append(setDestinationItem)
        }

        // Fuel type selection item
        let fuelTypeItem = CPListItem(
            text: "Fuel Type",
            detailText: selectedFuelType.displayName
        )
        fuelTypeItem.handler = { [weak self] _, completion in
            self?.showFuelTypePicker()
            completion()
        }
        items.append(fuelTypeItem)

        // Sort order item
        let sortOrderItem = CPListItem(
            text: "Sort Order",
            detailText: sortOrder.displayName
        )
        sortOrderItem.handler = { [weak self] _, completion in
            self?.showSortOrderPicker()
            completion()
        }
        items.append(sortOrderItem)

        // Refresh button item
        let refreshItem = CPListItem(
            text: "Refresh Stations",
            detailText: nil
        )
        refreshItem.handler = { [weak self] _, completion in
            self?.refreshStationsManually()
            completion()
        }
        items.append(refreshItem)

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Settings", sections: [section])
        template.tabTitle = "Settings"
        template.tabImage = UIImage(systemName: "gearshape.fill")
        self.settingsListTemplate = template
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
        // Fetch the Core Data station to get all fuel prices
        var items: [CPInformationItem] = []

        // Add all available fuel prices
        let coreStation = fetchCoreDataStation(id: station.stationID)
        if let coreStation {
            for fuelType in FuelType.allCases {
                if let price = coreStation.price(for: fuelType.rawValue), price > 0 {
                    let priceStr = String(format: "£%.2f", price)
                    let item = CPInformationItem(title: fuelType.displayName, detail: priceStr)
                    items.append(item)
                }
            }
        } else {
            // Fallback to showing just the selected fuel type price
            items.append(CPInformationItem(title: selectedFuelType.displayName, detail: station.formattedPrice))
        }

        // Add brand, distance, address
        items.append(CPInformationItem(title: "Brand", detail: station.brand))
        items.append(CPInformationItem(title: "Distance", detail: station.formattedDistance))
        items.append(CPInformationItem(title: "Address", detail: station.address))

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

    /// Fetches the Core Data Station entity for the given ID to access all fuel prices.
    private func fetchCoreDataStation(id: String) -> Station? {
        let context = dataManager.coreDataStack.viewContext
        let request = Station.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    // MARK: - Refresh All Data

    /// Refreshes all templates with latest nearby stations data.
    func refreshNearbyData() {
        // Refresh map pins
        if let nearbyPOITemplate {
            let pois = makePOIs(from: dataManager.nearbyStations)
            nearbyPOITemplate.setPointsOfInterest(pois, selectedIndex: NSNotFound)
        }

        // Refresh list with current sort order
        if let nearbyListTemplate {
            let sortedStations = sortStations(dataManager.nearbyStations)
            let items = sortedStations.prefix(20).map { buildStationListItem(station: $0) }
            let section = CPListSection(items: items)
            nearbyListTemplate.updateSections([section])
        }

        // Refresh favourites
        if let favouritesListTemplate {
            let favourites = dataManager.nearbyStations.filter { $0.isFavourite }
            let items = favourites.map { buildStationListItem(station: $0) }
            let section = CPListSection(items: items)
            favouritesListTemplate.updateSections(items.isEmpty ? [] : [section])
        }

        // Update settings to reflect current preferences
        updateSettingsTemplate()
    }

    /// Updates settings template to show current fuel type, route status, and sort order.
    private func updateSettingsTemplate() {
        guard let settingsListTemplate else { return }

        var items: [CPListItem] = []

        // Route section
        if routeManager.hasActiveRoute {
            let routeItem = CPListItem(
                text: "Active Route",
                detailText: routeManager.routeSummary
            )
            routeItem.handler = { [weak self] _, completion in
                self?.showRouteClearConfirmation()
                completion()
            }
            items.append(routeItem)

            let corridorItem = CPListItem(
                text: "Search Radius",
                detailText: "\(Int(routeManager.corridorRadiusMiles)) mi"
            )
            corridorItem.handler = { [weak self] _, completion in
                self?.showCorridorPicker()
                completion()
            }
            items.append(corridorItem)
        } else {
            let setDestinationItem = CPListItem(
                text: "Set Destination",
                detailText: "Plan a route"
            )
            setDestinationItem.handler = { [weak self] _, completion in
                self?.showDestinationInput()
                completion()
            }
            items.append(setDestinationItem)
        }

        let fuelTypeItem = CPListItem(
            text: "Fuel Type",
            detailText: selectedFuelType.displayName
        )
        fuelTypeItem.handler = { [weak self] _, completion in
            self?.showFuelTypePicker()
            completion()
        }
        items.append(fuelTypeItem)

        let sortOrderItem = CPListItem(
            text: "Sort Order",
            detailText: sortOrder.displayName
        )
        sortOrderItem.handler = { [weak self] _, completion in
            self?.showSortOrderPicker()
            completion()
        }
        items.append(sortOrderItem)

        let refreshItem = CPListItem(
            text: "Refresh Stations",
            detailText: nil
        )
        refreshItem.handler = { [weak self] _, completion in
            self?.refreshStationsManually()
            completion()
        }
        items.append(refreshItem)

        let section = CPListSection(items: items)
        settingsListTemplate.updateSections([section])
    }

    // MARK: - User Preference Pickers

    /// Shows fuel type picker action sheet.
    private func showFuelTypePicker() {
        let choices = FuelType.allCases.map { fuelType in
            CPListItem(
                text: fuelType.displayName,
                detailText: fuelType == selectedFuelType ? "✓" : nil
            )
        }

        for (index, fuelType) in FuelType.allCases.enumerated() {
            choices[index].handler = { [weak self] _, completion in
                self?.changeFuelType(to: fuelType)
                completion()
            }
        }

        let section = CPListSection(items: choices)
        let template = CPListTemplate(title: "Select Fuel Type", sections: [section])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    /// Shows sort order picker action sheet.
    private func showSortOrderPicker() {
        let choices = StationSortOrder.allCases.map { order in
            CPListItem(
                text: order.displayName,
                detailText: order == sortOrder ? "✓" : nil
            )
        }

        for (index, order) in StationSortOrder.allCases.enumerated() {
            choices[index].handler = { [weak self] _, completion in
                self?.changeSortOrder(to: order)
                completion()
            }
        }

        let section = CPListSection(items: choices)
        let template = CPListTemplate(title: "Sort By", sections: [section])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    /// Changes fuel type and re-queries stations.
    private func changeFuelType(to fuelType: FuelType) {
        guard fuelType != selectedFuelType else {
            interfaceController?.popTemplate(animated: true, completion: nil)
            return
        }

        selectedFuelType = fuelType
        interfaceController?.popTemplate(animated: true, completion: nil)

        // Re-query with new fuel type (route mode or nearby mode)
        Task {
            guard let location = currentLocation else { return }

            if let route = routeManager.activeRoute {
                await dataManager.findStationsAlongRoute(
                    route: route,
                    corridorRadiusMeters: routeManager.corridorRadiusMeters,
                    fuelType: fuelType.rawValue,
                    currentLocation: location
                )
            } else {
                await dataManager.findNearbyStations(
                    coordinate: location,
                    fuelType: fuelType.rawValue
                )
            }
        }
    }

    /// Changes sort order and refreshes list.
    private func changeSortOrder(to order: StationSortOrder) {
        guard order != sortOrder else {
            interfaceController?.popTemplate(animated: true, completion: nil)
            return
        }

        sortOrder = order
        interfaceController?.popTemplate(animated: true, completion: nil)

        // Refresh list with new sort order
        if let nearbyListTemplate {
            let sortedStations = sortStations(dataManager.nearbyStations)
            let items = sortedStations.prefix(20).map { buildStationListItem(station: $0) }
            let section = CPListSection(items: items)
            nearbyListTemplate.updateSections([section])

            // Update sort button label
            let sortButton = CPBarButton(title: sortOrder.displayName) { [weak self] _ in
                self?.showSortOrderPicker()
            }
            nearbyListTemplate.trailingNavigationBarButtons = [sortButton]
        }

        updateSettingsTemplate()
    }

    /// Manual refresh triggered from Settings.
    private func refreshStationsManually() {
        Task {
            guard let location = currentLocation else { return }

            if let route = routeManager.activeRoute {
                await dataManager.findStationsAlongRoute(
                    route: route,
                    corridorRadiusMeters: routeManager.corridorRadiusMeters,
                    fuelType: selectedFuelType.rawValue,
                    currentLocation: location
                )
            } else {
                await dataManager.findNearbyStations(
                    coordinate: location,
                    fuelType: selectedFuelType.rawValue
                )
            }
        }
    }

    /// Updates current location for queries.
    func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        self.currentLocation = coordinate
    }

    // MARK: - Route Management

    /// Shows destination input UI (simple text field in CarPlay).
    private func showDestinationInput() {
        // In CarPlay, we'll show a list of suggested destinations
        // For now, show a simple message directing users to set destination on iPhone
        let infoItem = CPInformationItem(
            title: "Set Destination",
            detail: "Use your iPhone to enter a destination and plan a route. Fuel stations within \(Int(routeManager.corridorRadiusMiles)) miles of your route will be shown."
        )

        let dismissAction = CPTextButton(title: "OK", textStyle: .normal) { [weak self] _ in
            self?.interfaceController?.popTemplate(animated: true, completion: nil)
        }

        let template = CPInformationTemplate(
            title: "Route Planning",
            layout: .leading,
            items: [infoItem],
            actions: [dismissAction]
        )

        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    /// Shows corridor radius picker.
    private func showCorridorPicker() {
        let radiusOptions = [1.0, 2.0, 3.0, 5.0]
        let choices = radiusOptions.map { radius in
            CPListItem(
                text: "\(Int(radius)) mi",
                detailText: radius == routeManager.corridorRadiusMiles ? "✓" : nil
            )
        }

        for (index, radius) in radiusOptions.enumerated() {
            choices[index].handler = { [weak self] _, completion in
                self?.changeCorridorRadius(to: radius)
                completion()
            }
        }

        let section = CPListSection(items: choices)
        let template = CPListTemplate(title: "Search Radius", sections: [section])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    /// Changes corridor radius and refreshes route search.
    private func changeCorridorRadius(to radius: Double) {
        routeManager.corridorRadiusMiles = radius
        interfaceController?.popTemplate(animated: true, completion: nil)

        // Refresh with new radius
        Task {
            guard let location = currentLocation, let route = routeManager.activeRoute else { return }
            await dataManager.findStationsAlongRoute(
                route: route,
                corridorRadiusMeters: routeManager.corridorRadiusMeters,
                fuelType: selectedFuelType.rawValue,
                currentLocation: location
            )
        }

        updateSettingsTemplate()
    }

    /// Shows confirmation dialog to clear active route.
    private func showRouteClearConfirmation() {
        let clearItem = CPListItem(text: "Clear Route", detailText: nil)
        clearItem.handler = { [weak self] _, completion in
            self?.clearRoute()
            completion()
        }

        let cancelItem = CPListItem(text: "Cancel", detailText: nil)
        cancelItem.handler = { [weak self] _, completion in
            self?.interfaceController?.popTemplate(animated: true, completion: nil)
            completion()
        }

        let section = CPListSection(items: [clearItem, cancelItem])
        let template = CPListTemplate(title: "Clear Route?", sections: [section])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    /// Clears route and returns to nearby mode.
    private func clearRoute() {
        routeManager.clearRoute()
        interfaceController?.popTemplate(animated: true, completion: nil)

        // Refresh in nearby mode
        Task {
            if let location = currentLocation {
                await dataManager.findNearbyStations(
                    coordinate: location,
                    fuelType: selectedFuelType.rawValue
                )
            }
        }

        updateSettingsTemplate()
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
            refreshNearbyData()
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
