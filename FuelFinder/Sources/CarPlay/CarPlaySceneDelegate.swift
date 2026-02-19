import UIKit
import CarPlay
import MapKit
import Combine

/// CarPlay scene delegate — entry point for CarPlay Fueling experience.
///
/// Requires `com.apple.developer.carplay-fueling` entitlement.
/// Configure in Info.plist: CPTemplateApplicationSceneSessionRoleApplication.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private var carPlayManager: FuelCarPlayManager?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?

    // MARK: - Shared State

    private var sharedDataManager: FuelDataManager {
        FuelDataManager.shared ?? FuelDataManager(coreDataStack: .shared)
    }

    // MARK: - Scene Lifecycle

    nonisolated func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
            self.connect(interfaceController: interfaceController)
        }
    }

    private func connect(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        let dataManager = sharedDataManager
        let manager = FuelCarPlayManager(dataManager: dataManager)
        manager.setInterfaceController(interfaceController)
        self.carPlayManager = manager

        // Set root template — use animated: false on initial connect
        let rootTemplate = manager.buildRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: false, completion: nil)

        // Fetch nearby stations for CarPlay
        refreshTask = Task {
            await dataManager.findNearbyStations(coordinate: LocationService.defaultUK)
        }

        // Observe data changes to refresh the Nearby tab
        dataManager.$nearbyStations
            .receive(on: DispatchQueue.main)
            .sink { [weak manager] _ in
                manager?.refreshNearbyTab()
            }
            .store(in: &cancellables)
    }

    nonisolated func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
            self.disconnect()
        }
    }

    private func disconnect() {
        refreshTask?.cancel()
        refreshTask = nil
        cancellables.removeAll()
        interfaceController = nil
        carPlayManager = nil
    }
}
