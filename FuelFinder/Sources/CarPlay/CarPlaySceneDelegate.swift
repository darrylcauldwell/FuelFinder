import UIKit
import CarPlay
import MapKit
import Combine

/// CarPlay scene delegate — entry point for CarPlay Fueling experience.
///
/// Requires `com.apple.developer.carplay-fueling` entitlement.
/// Configure in Info.plist: CPTemplateApplicationSceneSessionRoleApplication.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private var carPlayWindow: CPWindow?
    private var carPlayManager: FuelCarPlayManager?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?

    // MARK: - Shared State

    /// Uses the shared FuelDataManager from the app.
    /// In a production app this would be injected via a shared container.
    private func makeSharedDataManager() -> FuelDataManager {
        FuelDataManager(coreDataStack: .shared)
    }

    // MARK: - Scene Lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        self.carPlayWindow = window

        let dataManager = makeSharedDataManager()
        let manager = FuelCarPlayManager(dataManager: dataManager)
        manager.setInterfaceController(interfaceController)
        self.carPlayManager = manager

        // Set root template
        let rootTemplate = manager.buildRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)

        // Set map template delegate
        if let mapTemplate = manager.mapTemplate {
            mapTemplate.mapDelegate = self
        }

        // Start fetching nearby data
        refreshTask = Task { @MainActor in
            // Default to London; in production use CLLocationManager
            let location = LocationService.defaultUK
            await dataManager.refreshStations(near: location)
            await dataManager.findNearbyStations(coordinate: location)
        }

        // Observe data changes to update templates
        dataManager.$nearbyStations
            .receive(on: DispatchQueue.main)
            .sink { [weak manager] stations in
                guard let manager else { return }
                manager.refreshNearbyTab()
            }
            .store(in: &cancellables)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        refreshTask?.cancel()
        refreshTask = nil
        cancellables.removeAll()
        self.interfaceController = nil
        self.carPlayWindow = nil
        self.carPlayManager = nil
    }
}

// MARK: - CPMapTemplateDelegate

extension CarPlaySceneDelegate: CPMapTemplateDelegate {

    func mapTemplate(_ mapTemplate: CPMapTemplate, panBeganWith direction: CPMapTemplate.PanDirection) {
        // Handle map panning — update visible region
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, panEndedWith direction: CPMapTemplate.PanDirection) {
        // Refresh nearby stations based on new visible region
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, selectedPreviewFor trip: CPTrip, using routeChoice: CPRouteChoice) {
        mapTemplate.showRouteChoicesPreview(for: trip, textConfiguration: nil)
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        // Begin navigation session
        let session = mapTemplate.startNavigationSession(for: trip)
        session.pauseTrip(for: .loading, description: "Starting navigation...")
    }

    func mapTemplateDidCancelNavigation(_ mapTemplate: CPMapTemplate) {
        mapTemplate.dismissNavigationAlert(animated: true) { _ in }
    }
}
