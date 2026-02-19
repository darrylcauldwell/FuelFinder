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
        FuelDataManager.shared ?? FuelDataManager(coreDataStack: .shared)
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

        // Start fetching nearby data
        refreshTask = Task { @MainActor in
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
