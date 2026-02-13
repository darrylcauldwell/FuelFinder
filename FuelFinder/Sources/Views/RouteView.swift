import SwiftUI
import MapKit
import CoreData

// MARK: - RouteView (iPhone Main Map)

struct RouteView: View {

    @EnvironmentObject private var dataManager: FuelDataManager
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.managedObjectContext) private var viewContext

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationService.defaultUK,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    )
    @State private var route: MKRoute?
    @State private var selectedStation: StationWithScore?
    @State private var showStationSheet = false
    @State private var showSettings = false
    @State private var isSearchingRoute = false
    @State private var routeTask: Task<Void, Never>?

    // Route planning
    @State private var originText = ""
    @State private var destinationText = ""

    // Settings
    @State private var selectedFuelType: FuelType = .unleaded
    @State private var maxDetourKm: Double = 2.0

    var body: some View {
        ZStack {
            mapContent

            VStack(spacing: 0) {
                routePlanningOverlay
                Spacer()
                if dataManager.isDataStale {
                    staleBanner
                }
                if !dataManager.stationsAlongRoute.isEmpty {
                    bottomStatusBar
                }
            }

            if dataManager.isLoading || isSearchingRoute {
                loadingOverlay
            }
        }
        .sheet(isPresented: $showStationSheet) {
            stationListSheet
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .alert("Error", isPresented: .constant(dataManager.lastError != nil)) {
            Button("OK") { dataManager.lastError = nil }
        } message: {
            Text(dataManager.lastError ?? "")
        }
        .onAppear {
            locationService.requestPermission()
        }
        .onDisappear {
            routeTask?.cancel()
        }
    }

    // MARK: - Map

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            // User location
            UserAnnotation()

            // Route polyline
            if let route {
                MapPolyline(route.polyline)
                    .stroke(AppColors.routeLine, lineWidth: 5)
            }

            // Station pins with price badges
            ForEach(dataManager.stationsAlongRoute) { station in
                Annotation(
                    station.formattedPrice,
                    coordinate: station.coordinate
                ) {
                    StationPinView(station: station)
                        .onTapGesture {
                            selectedStation = station
                            showStationSheet = true
                        }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    // MARK: - Route Planning Overlay

    private var routePlanningOverlay: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(AppColors.active)
                    .font(.caption2)
                TextField("Origin", text: $originText)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }

            HStack(spacing: Spacing.sm) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(AppColors.priceExpensive)
                    .font(.caption2)
                TextField("Destination", text: $destinationText)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }

            HStack(spacing: Spacing.md) {
                Button {
                    routeTask = Task { await planRoute() }
                } label: {
                    Label("Plan Route", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(GlassButtonStyle(tint: AppColors.primary))
                .disabled(originText.isEmpty || destinationText.isEmpty)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                        .font(.title3)
                }
                .buttonStyle(GlassButtonStyle(tint: AppColors.secondary))

                Spacer()

                if route != nil {
                    Button {
                        routeTask = Task { await findFuelStops() }
                    } label: {
                        Label("Find Fuel", systemImage: "fuelpump")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(GlassButtonStyle(tint: AppColors.priceCheap))
                }
            }
        }
        .glassCard(material: .regular, cornerRadius: CornerRadius.lg, shadowRadius: 10, padding: Spacing.lg)
        .padding()
    }

    private var staleBanner: some View {
        HStack(spacing: Spacing.sm) {
            AccessibleStatusIndicator(.stale, size: .small)
            Text("Prices may be outdated")
                .font(.caption)
            Spacer()
            Button("Refresh") {
                Task {
                    await dataManager.refreshStations(near: locationService.effectiveLocation)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColors.primary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(AppColors.warning.opacity(Opacity.light))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .padding(.horizontal)
    }

    private var bottomStatusBar: some View {
        HStack {
            let count = dataManager.stationsAlongRoute.count
            Image(systemName: "fuelpump.fill")
                .foregroundStyle(AppColors.primary)
            Text("\(count) station\(count == 1 ? "" : "s") found")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("View List") {
                showStationSheet = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.primary)
        }
        .glassCard(material: .thin, cornerRadius: CornerRadius.md, shadowRadius: 6, padding: Spacing.md)
        .padding(.horizontal)
        .padding(.bottom, Spacing.sm)
    }

    private var loadingOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: Spacing.sm) {
                ProgressView()
                    .tint(AppColors.primary)
                Text("Searching...")
                    .font(.subheadline)
            }
            .glassCard(material: .thin, cornerRadius: CornerRadius.pill, padding: Spacing.md)
            .padding(.bottom, 80)
        }
    }

    // MARK: - Station List Sheet

    private var stationListSheet: some View {
        NavigationStack {
            List {
                ForEach(dataManager.stationsAlongRoute) { station in
                    StationRowView(station: station) {
                        routeTask = Task { await addStopAndReroute(station: station) }
                    }
                }
            }
            .glassList()
            .navigationTitle("Fuel Stops")
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigation()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showStationSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Fuel", selection: $selectedFuelType) {
                        ForEach(FuelType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    GlassSectionHeader("Fuel Type", icon: "fuelpump")
                }

                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(String(format: "%.1f km", maxDetourKm))
                            .font(.headline)
                            .foregroundStyle(AppColors.primary)
                        Slider(value: $maxDetourKm, in: 0.5...10.0, step: 0.5)
                            .tint(AppColors.primary)
                    }
                } header: {
                    GlassSectionHeader("Maximum Detour", icon: "arrow.triangle.branch")
                }

                Section {
                    if let lastRefresh = dataManager.lastRefresh {
                        LabeledContent("Last Updated", value: lastRefresh.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Refresh Prices") {
                        Task {
                            await dataManager.refreshStations(near: locationService.effectiveLocation)
                        }
                    }
                } header: {
                    GlassSectionHeader("Data", icon: "arrow.clockwise")
                }
            }
            .glassList()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigation()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSettings = false }
                }
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func planRoute() async {
        isSearchingRoute = true
        defer { isSearchingRoute = false }

        let request = MKDirections.Request()
        let geocoder = CLGeocoder()

        do {
            let originPlacemarks = try await geocoder.geocodeAddressString(originText)
            guard let originPlacemark = originPlacemarks.first else {
                dataManager.lastError = "Could not find origin location"
                return
            }
            request.source = MKMapItem(placemark: MKPlacemark(placemark: originPlacemark))

            let destPlacemarks = try await geocoder.geocodeAddressString(destinationText)
            guard let destPlacemark = destPlacemarks.first else {
                dataManager.lastError = "Could not find destination"
                return
            }
            request.destination = MKMapItem(placemark: MKPlacemark(placemark: destPlacemark))
        } catch {
            dataManager.lastError = "Geocoding failed: \(error.localizedDescription)"
            return
        }

        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            if let firstRoute = response.routes.first {
                route = firstRoute
                let rect = firstRoute.polyline.boundingMapRect
                cameraPosition = .rect(rect.insetBy(dx: -rect.size.width * 0.1, dy: -rect.size.height * 0.1))
            }
        } catch {
            dataManager.lastError = "Route calculation failed: \(error.localizedDescription)"
        }
    }

    private func findFuelStops() async {
        guard let route else { return }
        await dataManager.findStationsAlongRoute(
            route: route,
            fuelType: selectedFuelType.rawValue,
            maxDetourKm: maxDetourKm
        )
    }

    @MainActor
    private func addStopAndReroute(station: StationWithScore) async {
        showStationSheet = false
        guard let currentRoute = route else { return }

        let pointCount = currentRoute.polyline.pointCount
        guard pointCount > 1 else { return }

        let originCoord = currentRoute.polyline.points()[0].coordinate
        let destCoord = currentRoute.polyline.points()[pointCount - 1].coordinate

        let stationMapItem = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        stationMapItem.name = station.name

        // Leg 1: Origin → Station
        let req1 = MKDirections.Request()
        req1.source = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
        req1.destination = stationMapItem
        req1.transportType = .automobile

        // Leg 2: Station → Destination
        let req2 = MKDirections.Request()
        req2.source = stationMapItem
        req2.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        req2.transportType = .automobile

        do {
            let response1 = try await MKDirections(request: req1).calculate()
            let response2 = try await MKDirections(request: req2).calculate()

            if let route1 = response1.routes.first {
                self.route = route1
                let rect = route1.polyline.boundingMapRect
                    .union(response2.routes.first?.polyline.boundingMapRect ?? route1.polyline.boundingMapRect)
                cameraPosition = .rect(rect.insetBy(dx: -rect.size.width * 0.1, dy: -rect.size.height * 0.1))
            }
        } catch {
            dataManager.lastError = "Re-routing failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Station Pin View (Glass Design)

struct StationPinView: View {
    let station: StationWithScore

    var body: some View {
        VStack(spacing: 2) {
            FuelPriceBadge(station.formattedPrice, tier: station.priceTier, size: .large)

            Image(systemName: "fuelpump.fill")
                .font(.title3)
                .foregroundStyle(AppColors.priceTier(station.priceTier))

            if station.isFavourite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(station.name), \(station.formattedPrice), \(station.formattedDetour)")
    }
}

// MARK: - Station Row View (Glass Design)

struct StationRowView: View {
    let station: StationWithScore
    let onAddStop: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Price tier indicator
            Circle()
                .fill(AppColors.priceTier(station.priceTier))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text(station.name)
                        .font(.headline)
                    if station.isFavourite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                    }
                }

                Text(station.brand)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(station.formattedDetour)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                FuelPriceBadge(station.formattedPrice, tier: station.priceTier, size: .large)

                Button("Add Stop", action: onAddStop)
                    .buttonStyle(GlassButtonStyle(tint: AppColors.primary))
                    .controlSize(.small)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(station.name), \(station.brand), \(station.formattedPrice), \(station.formattedDetour)")
        .accessibilityAction(named: "Add Stop", onAddStop)
    }
}

// MARK: - Preview

#Preview {
    RouteView()
        .environmentObject(FuelDataManager(coreDataStack: .preview))
        .environmentObject(LocationService())
        .environment(\.managedObjectContext, CoreDataStack.preview.viewContext)
}
