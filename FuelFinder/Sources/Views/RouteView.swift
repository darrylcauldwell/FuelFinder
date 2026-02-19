import SwiftUI
import MapKit
import CoreData

// MARK: - NearbyView (iPhone Main Map + Station List)

struct NearbyView: View {

    @EnvironmentObject private var dataManager: FuelDataManager
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.managedObjectContext) private var viewContext

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationService.defaultUK,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )
    @State private var selectedStationDetail: StationWithScore?
    @State private var showStationDetail = false
    @State private var showSettings = false

    // Filters & sorting
    @State private var selectedFuelType: FuelType = .unleaded
    @State private var sortOrder: StationSortOrder = .price
    @State private var maxPricePence: Double = 200

    // Map region tracking for re-query
    @State private var lastQueryCenter: CLLocationCoordinate2D?
    @State private var isInitialLoadComplete = false
    @State private var showErrorAlert = false

    /// Stations filtered by the user's max price setting.
    private var filteredStations: [StationWithScore] {
        let maxPounds = maxPricePence / 100.0
        if maxPricePence >= 200 {
            return dataManager.nearbyStations
        }
        return dataManager.nearbyStations.filter { $0.price <= maxPounds }
    }

    var body: some View {
        ZStack {
            mapContent

            VStack(spacing: 0) {
                topToolbar
                Spacer()
                if dataManager.isDataStale {
                    staleBanner
                }
            }

            if dataManager.isLoading {
                loadingOverlay
            }
        }
        .sheet(isPresented: .constant(true)) {
            stationListPanel
        }
        .sheet(isPresented: $showStationDetail) {
            if let station = selectedStationDetail {
                StationDetailSheet(station: station, viewContext: viewContext)
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { dataManager.lastError = nil }
        } message: {
            Text(dataManager.lastError ?? "")
        }
        .onChange(of: dataManager.lastError) { _, newValue in
            if newValue != nil { showErrorAlert = true }
        }
        .onAppear {
            locationService.requestPermission()
        }
        .task {
            await loadNearbyStations()
        }
        .onChange(of: selectedFuelType) {
            Task { await loadNearbyStations() }
        }
        .onChange(of: sortOrder) {
            Task { await loadNearbyStations() }
        }
        .onChange(of: locationService.currentLocation) { old, newLocation in
            // Re-centre and re-query when real location first arrives (nil → non-nil).
            // Handles the case where .task fires before permission is granted.
            guard old == nil, newLocation != nil else { return }
            isInitialLoadComplete = false
            Task { await loadNearbyStations() }
        }
    }

    // MARK: - Map

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            ForEach(filteredStations) { station in
                Annotation(
                    station.formattedPrice,
                    coordinate: station.coordinate
                ) {
                    StationPinView(station: station)
                        .onTapGesture {
                            selectedStationDetail = station
                            showStationDetail = true
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
        .onMapCameraChange(frequency: .onEnd) { context in
            handleMapRegionChange(context.region)
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: Spacing.sm) {
            Picker("Fuel", selection: $selectedFuelType) {
                ForEach(FuelType.allCases) { type in
                    Text(type.shortName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Picker("Sort", selection: $sortOrder) {
                ForEach(StationSortOrder.allCases) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
            }
            .buttonStyle(GlassButtonStyle(tint: AppColors.secondary))
        }
        .glassCard(material: .thin, cornerRadius: CornerRadius.md, shadowRadius: 6, padding: Spacing.md)
        .padding(.horizontal)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Stale Banner

    private var staleBanner: some View {
        HStack(spacing: Spacing.sm) {
            AccessibleStatusIndicator(.stale, size: .small)
            Text("Prices may be outdated")
                .font(.caption)
            Spacer()
            Button("Refresh") {
                Task {
                    await dataManager.refreshStations()
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

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: Spacing.sm) {
                ProgressView()
                    .tint(AppColors.primary)
                Text("Loading stations...")
                    .font(.subheadline)
            }
            .glassCard(material: .thin, cornerRadius: CornerRadius.pill, padding: Spacing.md)
            .padding(.bottom, 80)
        }
    }

    // MARK: - Station List Panel (Persistent Bottom Sheet)

    private var stationListPanel: some View {
        NavigationStack {
            List {
                if filteredStations.isEmpty && !dataManager.isLoading {
                    ContentUnavailableView(
                        "No Stations Found",
                        systemImage: "fuelpump.slash",
                        description: Text("Try zooming out or changing fuel type.")
                    )
                } else {
                    ForEach(filteredStations) { station in
                        NearbyStationRowView(station: station)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedStationDetail = station
                                showStationDetail = true
                            }
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
            .glassList()
            .navigationTitle("\(filteredStations.count) Stations Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigation()
        }
        .presentationDetents([.fraction(0.3), .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled()
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
                        Text(maxPricePence >= 200 ? "No limit" : String(format: "%.1fp", maxPricePence))
                            .font(.headline)
                            .foregroundStyle(AppColors.primary)
                        Slider(value: $maxPricePence, in: 100...200, step: 1)
                            .tint(AppColors.primary)
                            .accessibilityLabel("Maximum price filter")
                            .accessibilityValue(maxPricePence >= 200 ? "No limit" : String(format: "%.0f pence", maxPricePence))
                        Text("Slide left to hide expensive stations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    GlassSectionHeader("Maximum Price", icon: "sterlingsign.circle")
                }

                Section {
                    if let lastRefresh = dataManager.lastRefresh {
                        LabeledContent("Last Updated", value: lastRefresh.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Refresh Prices") {
                        Task {
                            await dataManager.refreshStations()
                        }
                    }
                } header: {
                    GlassSectionHeader("Data", icon: "arrow.clockwise")
                }
            }
            .glassList()
            .navigationTitle("Filters")
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
    private func loadNearbyStations() async {
        let coord = locationService.effectiveLocation
        lastQueryCenter = coord

        await dataManager.findNearbyStations(
            coordinate: coord,
            fuelType: selectedFuelType.rawValue,
            radiusKm: 16,
            limit: 50,
            sortBy: sortOrder
        )

        if !isInitialLoadComplete {
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ))
            isInitialLoadComplete = true
        }
    }

    private func handleMapRegionChange(_ region: MKCoordinateRegion) {
        let newCenter = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let lastCenter: CLLocation
        if let prev = lastQueryCenter {
            lastCenter = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
        } else {
            lastCenter = CLLocation(latitude: LocationService.defaultUK.latitude, longitude: LocationService.defaultUK.longitude)
        }

        guard newCenter.distance(from: lastCenter) > 2000 else { return }
        lastQueryCenter = region.center

        let radiusKm = max(16, region.span.latitudeDelta * 111.0 / 2.0)

        Task {
            await dataManager.findNearbyStations(
                coordinate: region.center,
                fuelType: selectedFuelType.rawValue,
                radiusKm: radiusKm,
                limit: 50,
                sortBy: sortOrder
            )
        }
    }

    private func openInAppleMaps(station: StationWithScore) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        mapItem.name = station.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
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
        .accessibilityLabel("\(station.name), \(station.formattedPrice), \(station.formattedDistance)")
        .accessibilityHint("Tap to view station details")
    }
}

// MARK: - Nearby Station Row View

struct NearbyStationRowView: View {
    let station: StationWithScore

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(AppColors.priceTier(station.priceTier))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text(station.name)
                        .font(.headline)
                        .lineLimit(1)
                    if station.isFavourite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                    }
                }

                Text(station.brand)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(station.formattedDistance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            FuelPriceBadge(station.formattedPrice, tier: station.priceTier, size: .large)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(station.name), \(station.brand), \(station.formattedPrice), \(station.formattedDistance)")
    }
}

// MARK: - Station Detail Sheet

struct StationDetailSheet: View {
    let station: StationWithScore
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss
    @State private var isFavourite: Bool
    @State private var coreStation: Station?

    init(station: StationWithScore, viewContext: NSManagedObjectContext) {
        self.station = station
        self.viewContext = viewContext
        self._isFavourite = State(initialValue: station.isFavourite)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Header
                    VStack(spacing: Spacing.sm) {
                        Text(station.brand)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(station.name)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(station.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        GlassChip(station.formattedDistance, icon: "location", color: AppColors.primary)
                    }
                    .padding(.top)

                    // Selected fuel price (prominent)
                    FuelPriceBadge(station.formattedPrice, tier: station.priceTier, size: .large)

                    // All fuel prices
                    allPricesGrid

                    // Get Directions button
                    Button {
                        openInAppleMaps()
                    } label: {
                        Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                    .buttonStyle(PrimaryActionButtonStyle(color: AppColors.primary))
                    .padding(.horizontal)

                    // Favourite toggle
                    Button {
                        toggleFavourite()
                    } label: {
                        Label(
                            isFavourite ? "Remove from Favourites" : "Add to Favourites",
                            systemImage: isFavourite ? "star.fill" : "star"
                        )
                    }
                    .buttonStyle(GlassButtonStyle(tint: AppColors.warning))
                    .accessibilityHint(isFavourite ? "Removes this station from your favourites" : "Saves this station to your favourites")
                    .padding(.horizontal)
                }
                .padding(.bottom, Spacing.xl)
            }
            .navigationTitle("Station Details")
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigation()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { coreStation = fetchStation() }
        .presentationDetents([.medium, .large])
    }

    private var allPricesGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: Spacing.md) {
            ForEach(FuelType.allCases) { fuelType in
                let price = coreStation?.price(for: fuelType.rawValue)
                if let price, price > 0 {
                    GlassStatCard(
                        title: fuelType.displayName,
                        value: String(format: "£%.2f", price),
                        icon: "fuelpump",
                        tint: fuelType.color
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private func fetchStation() -> Station? {
        let request: NSFetchRequest<Station> = Station.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", station.stationID)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    private func toggleFavourite() {
        guard let s = coreStation else { return }
        s.isFavourite.toggle()
        isFavourite = s.isFavourite
        try? viewContext.save()
    }

    private func openInAppleMaps() {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        mapItem.name = station.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

// MARK: - Preview

#Preview {
    NearbyView()
        .environmentObject(FuelDataManager(coreDataStack: .preview))
        .environmentObject(LocationService())
        .environment(\.managedObjectContext, CoreDataStack.preview.viewContext)
}
