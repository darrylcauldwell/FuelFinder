import SwiftUI
import MapKit

// MARK: - ContentView

struct ContentView: View {

    @EnvironmentObject private var dataManager: FuelDataManager
    @EnvironmentObject private var locationService: LocationService
    @State private var selectedTab = 0
    @State private var selectedFuelType: FuelType = .unleaded

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                NearbyView(selectedFuelType: $selectedFuelType)
                    .glassNavigation()
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            .tag(0)

            NavigationStack {
                NearbyListView(selectedFuelType: $selectedFuelType)
                    .glassNavigation()
            }
            .tabItem {
                Label("List", systemImage: "list.bullet")
            }
            .tag(1)

            NavigationStack {
                FavouritesView()
                    .glassNavigation()
            }
            .tabItem {
                Label("Favourites", systemImage: "star")
            }
            .tag(2)

            NavigationStack {
                AppSettingsView()
                    .glassNavigation()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(3)
        }
        .tint(AppColors.primary)
        .task {
            await dataManager.refreshStations()
            dataManager.startPeriodicRefresh()
        }
    }
}

// MARK: - Nearby List View

struct NearbyListView: View {
    @EnvironmentObject private var dataManager: FuelDataManager
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.managedObjectContext) private var viewContext

    @Binding var selectedFuelType: FuelType
    @State private var sortOrder: StationSortOrder = .price
    @State private var maxDistanceMiles: Double = 10
    @State private var selectedStation: StationWithScore?

    private var distanceLabel: String {
        let miles = Int(maxDistanceMiles)
        return "\(miles) \(miles == 1 ? "mile" : "miles")"
    }

    private var sortedStations: [StationWithScore] {
        let maxKm = maxDistanceMiles * 1.60934
        let filtered = dataManager.nearbyStations.filter { $0.distanceKm <= maxKm }
        switch sortOrder {
        case .price:    return filtered.sorted { $0.price < $1.price }
        case .distance: return filtered.sorted { $0.distanceKm < $1.distanceKm }
        }
    }

    var body: some View {
        List {
            if sortedStations.isEmpty && !dataManager.isLoading {
                ContentUnavailableView(
                    "No Stations",
                    systemImage: "fuelpump.slash",
                    description: Text("Try increasing the distance or switching fuel type.")
                )
            } else {
                ForEach(sortedStations) { station in
                    NearbyStationRowView(station: station)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedStation = station }
                        .swipeActions(edge: .trailing) {
                            Button {
                                openInAppleMaps(station: station)
                            } label: {
                                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                            }
                            .tint(AppColors.primary)
                        }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                // Fuel type + sort row
                HStack(spacing: Spacing.md) {
                    Menu {
                        ForEach(FuelType.allCases) { type in
                            Button {
                                selectedFuelType = type
                            } label: {
                                if type == selectedFuelType {
                                    Label(type.displayName, systemImage: "checkmark")
                                } else {
                                    Text(type.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "fuelpump.fill")
                            Text(selectedFuelType.displayName)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(selectedFuelType.color)
                        .fixedSize()
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Picker("Sort", selection: $sortOrder) {
                        ForEach(StationSortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

                // Distance slider row
                VStack(spacing: 2) {
                    HStack {
                        Text("Within")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(distanceLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                            .monospacedDigit()
                    }
                    Slider(value: $maxDistanceMiles, in: 1...20, step: 1) { editing in
                        if !editing {
                            Task { await loadListStations() }
                        }
                    }
                    .tint(AppColors.primary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)

                Divider()
            }
            .background(.bar)
        }
        .refreshable {
            await loadListStations()
        }
        .glassList()
        .navigationTitle("Nearby")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedStation) { station in
            StationDetailSheet(station: station, viewContext: viewContext)
        }
        .task { await loadListStations() }
        .onChange(of: selectedFuelType) { Task { await loadListStations() } }
        .onChange(of: sortOrder) { Task { await loadListStations() } }
    }

    @MainActor
    private func loadListStations() async {
        let radiusKm = maxDistanceMiles * 1.60934
        await dataManager.findNearbyStations(
            coordinate: locationService.effectiveLocation,
            fuelType: selectedFuelType.rawValue,
            radiusKm: radiusKm,
            limit: 100,
            sortBy: sortOrder
        )
    }

    private func openInAppleMaps(station: StationWithScore) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        mapItem.name = station.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

// MARK: - Favourites View

struct FavouritesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var dataManager: FuelDataManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Station.name, ascending: true)],
        predicate: NSPredicate(format: "isFavourite == YES"),
        animation: .default
    )
    private var favourites: FetchedResults<Station>

    var body: some View {
        List {
            if favourites.isEmpty {
                ContentUnavailableView(
                    "No Favourites",
                    systemImage: "star.slash",
                    description: Text("Tap the star on any station to add it here.")
                )
            } else {
                ForEach(favourites, id: \.objectID) { station in
                    HStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(station.name ?? "Unknown")
                                .font(.headline)
                            Text(station.brand ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: Spacing.sm) {
                                GlassChip(
                                    station.formattedPrice(for: "unleaded"),
                                    icon: "fuelpump",
                                    color: AppColors.priceCheap
                                )
                            }
                        }

                        Spacer()

                        Button {
                            station.isFavourite.toggle()
                            try? viewContext.save()
                        } label: {
                            Image(systemName: station.isFavourite ? "star.fill" : "star")
                                .foregroundStyle(AppColors.warning)
                                .font(.title3)
                        }
                        .minimumTapTarget()
                    }
                    .padding(.vertical, Spacing.xs)
                    .swipeActions(edge: .trailing) {
                        Button {
                            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
                            mapItem.name = station.name ?? "Station"
                            mapItem.openInMaps(launchOptions: [
                                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                            ])
                        } label: {
                            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                        }
                        .tint(AppColors.primary)
                    }
                }
            }
        }
        .glassList()
        .navigationTitle("Favourites")
    }
}

// MARK: - App Settings View

struct AppSettingsView: View {
    @EnvironmentObject private var dataManager: FuelDataManager
    @EnvironmentObject private var locationService: LocationService

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Data Source", value: "UK Retailer Open Data")
            } header: {
                GlassSectionHeader("About", icon: "info.circle")
            }

            Section {
                if let lastRefresh = dataManager.lastRefresh {
                    HStack {
                        LabeledContent("Last Refresh", value: lastRefresh.formatted(date: .abbreviated, time: .shortened))
                        if dataManager.isDataStale {
                            AccessibleStatusIndicator(.stale, size: .small)
                        }
                    }
                } else {
                    LabeledContent("Last Refresh", value: "Never")
                }

                Button {
                    Task {
                        await dataManager.refreshStations()
                    }
                } label: {
                    Label("Refresh All Prices", systemImage: "arrow.clockwise")
                        .foregroundStyle(AppColors.primary)
                }

            } header: {
                GlassSectionHeader("Data Management", icon: "externaldrive")
            }

            Section {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: locationService.currentLocation != nil ? "location.fill" : "location.slash")
                        .foregroundStyle(locationService.currentLocation != nil ? AppColors.active : AppColors.inactive)
                    Text(locationService.currentLocation != nil ? "Location active" : "Location unavailable")
                        .font(.subheadline)
                }

                if let error = locationService.locationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AppColors.error)
                }
            } header: {
                GlassSectionHeader("Location", icon: "location")
            }

            Section {
                Text("Connect your iPhone to a CarPlay-enabled vehicle to use fuel finding on your car's display.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                GlassSectionHeader("CarPlay", icon: "car")
            }

            Section {
                Text("Fuel price data sourced from UK retailer open data feeds published under the CMA fuel price transparency scheme. Prices are updated regularly but may not reflect real-time pricing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                GlassSectionHeader("Legal", icon: "doc.text")
            }
        }
        .glassList()
        .navigationTitle("Settings")
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(FuelDataManager(coreDataStack: .preview))
        .environmentObject(LocationService())
        .environment(\.managedObjectContext, CoreDataStack.preview.viewContext)
}

