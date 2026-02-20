import SwiftUI
import MapKit
import Combine

/// Main Route tab view - shows destination search or route preview.
struct RouteTabView: View {

    @ObservedObject var routeManager: RouteManager
    @ObservedObject var dataManager: FuelDataManager
    @ObservedObject var locationService: LocationService

    @State private var selectedFuelType: FuelType = .unleaded
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        NavigationStack {
            Group {
                if routeManager.hasActiveRoute {
                    // Show route preview with map
                    RoutePreviewView(
                        routeManager: routeManager,
                        dataManager: dataManager
                    )
                } else {
                    // Show destination search
                    if let location = locationService.currentLocation {
                        DestinationSearchView(
                            routeManager: routeManager,
                            currentLocation: location
                        )
                    } else {
                        // No location yet
                        VStack(spacing: 16) {
                            Spacer()
                            ProgressView()
                            Text("Getting your location...")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if routeManager.hasActiveRoute {
                        // Fuel type picker (when route active)
                        Menu {
                            Picker("Fuel Type", selection: $selectedFuelType) {
                                ForEach(FuelType.allCases) { fuelType in
                                    Text(fuelType.displayName).tag(fuelType)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "fuelpump.fill")
                                Text(selectedFuelType.shortName)
                                    .font(.caption.bold())
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .onAppear {
            setupObservers()
        }
        .onChange(of: selectedFuelType) { _, newValue in
            refreshStations()
        }
        .onChange(of: routeManager.corridorRadiusMiles) { _, _ in
            refreshStations()
        }
        .onChange(of: routeManager.activeRoute) { _, newRoute in
            if newRoute != nil {
                refreshStations()
            }
        }
    }

    private func setupObservers() {
        // Observe route manager errors
        routeManager.$routeError
            .compactMap { $0 }
            .sink { error in
                print("Route error: \(error)")
            }
            .store(in: &cancellables)
    }

    private func refreshStations() {
        guard routeManager.hasActiveRoute,
              let route = routeManager.activeRoute,
              let location = locationService.currentLocation else {
            return
        }

        Task {
            await dataManager.findStationsAlongRoute(
                route: route,
                corridorRadiusMeters: routeManager.corridorRadiusMeters,
                fuelType: selectedFuelType.rawValue,
                currentLocation: location
            )
        }
    }
}
