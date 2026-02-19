import SwiftUI
import MapKit

// MARK: - ContentView

struct ContentView: View {

    @EnvironmentObject private var dataManager: FuelDataManager
    @EnvironmentObject private var locationService: LocationService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                NearbyView()
                    .glassNavigation()
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            .tag(0)

            NavigationStack {
                FavouritesView()
                    .glassNavigation()
            }
            .tabItem {
                Label("Favourites", systemImage: "star")
            }
            .tag(1)

            NavigationStack {
                AppSettingsView()
                    .glassNavigation()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
        .tint(AppColors.primary)
        .task {
            await dataManager.refreshStations()
            dataManager.startPeriodicRefresh()
        }
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

