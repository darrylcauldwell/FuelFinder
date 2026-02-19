import SwiftUI
import MapKit
import CoreData

// MARK: - NearbyView (iPhone Main Map + Station List)

struct NearbyView: View {

    @EnvironmentObject private var dataManager: FuelDataManager
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.managedObjectContext) private var viewContext

    // Initial span covers the full 16 km search radius (32 km diameter ≈ 0.29°).
    // Matching the viewport to the search radius ensures every station in the list
    // also has a visible pin on the map.
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationService.defaultUK,
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
    )
    @Binding var selectedFuelType: FuelType
    @State private var selectedStationDetail: StationWithScore?
    @State private var showToolbar = true

    // Price filter for map pins (histogram in top toolbar)
    @State private var minPricePence: Double = 0
    @State private var maxPricePence: Double = 999

    // Map region tracking for re-query
    @State private var lastQueryCenter: CLLocationCoordinate2D?
    @State private var isInitialLoadComplete = false
    @State private var showErrorAlert = false

    /// Stations filtered by the user's selected price range.
    private var filteredStations: [StationWithScore] {
        let stations = dataManager.nearbyStations
        let minPounds = minPricePence / 100.0
        let maxPounds = maxPricePence / 100.0
        return stations.filter { $0.price >= minPounds && $0.price <= maxPounds }
    }

    var body: some View {
        ZStack {
            mapContent

            VStack(spacing: 0) {
                if showToolbar {
                    topToolbar
                        .transition(.move(edge: .top).combined(with: .opacity))
                        // Swipe upward on the toolbar to slide it off the top
                        .gesture(
                            DragGesture()
                                .onEnded { value in
                                    if value.translation.height < -30 {
                                        withAnimation(.spring(response: 0.35)) { showToolbar = false }
                                    }
                                }
                        )
                }
                Spacer()
                if dataManager.isDataStale {
                    staleBanner
                }
            }

            // Top drag handle — visible cue that the toolbar can be pulled back down
            if !showToolbar {
                VStack {
                    Capsule()
                        .fill(.secondary.opacity(0.5))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onEnded { value in
                                    if value.translation.height > 30 {
                                        withAnimation(.spring(response: 0.35)) { showToolbar = true }
                                    }
                                }
                        )
                    Spacer()
                }
                .transition(.opacity)
            }

            if dataManager.isLoading {
                loadingOverlay
            }
        }
        .sheet(item: $selectedStationDetail) { station in
            StationDetailSheet(station: station, viewContext: viewContext)
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
        VStack(spacing: Spacing.sm) {
            // Fuel type selector
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
            .frame(maxWidth: .infinity, alignment: .leading)

            // Price range histogram — compact inline filter, no separate sheet needed
            PriceHistogramRangeView(
                stations: dataManager.nearbyStations,
                minPrice: $minPricePence,
                maxPrice: $maxPricePence,
                barHeight: 36
            )
        }
        .padding(Spacing.md)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
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
            sortBy: .price
        )

        if !isInitialLoadComplete {
            let initialRegion = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
            )
            cameraPosition = .region(initialRegion)
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
                sortBy: .price
            )
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

// MARK: - Price Histogram Range View

/// Airbnb-style price distribution histogram with a two-handle range slider.
struct PriceHistogramRangeView: View {

    let stations: [StationWithScore]
    @Binding var minPrice: Double   // pence
    @Binding var maxPrice: Double   // pence
    var barHeight: CGFloat = 72

    private let binCount = 28
    private let thumbSize: CGFloat = 28

    /// Actual min/max from current station data (in pence).
    private var dataBounds: (min: Double, max: Double) {
        guard !stations.isEmpty else { return (120, 180) }
        let prices = stations.map { $0.price * 100 }
        return ((prices.min() ?? 120).rounded(.down),
                (prices.max() ?? 180).rounded(.up))
    }

    private struct Bin {
        let count: Int
        let inRange: Bool
    }

    private var bins: [Bin] {
        let b = dataBounds
        guard b.max > b.min else {
            return Array(repeating: Bin(count: 0, inRange: true), count: binCount)
        }
        let width = (b.max - b.min) / Double(binCount)
        var counts = Array(repeating: 0, count: binCount)
        for station in stations {
            let p = station.price * 100
            let idx = max(0, min(Int((p - b.min) / width), binCount - 1))
            counts[idx] += 1
        }
        return counts.enumerated().map { i, count in
            let binMin = b.min + Double(i) * width
            let binMax = binMin + width
            return Bin(count: count, inRange: binMax >= minPrice && binMin <= maxPrice)
        }
    }

    var body: some View {
        let b = dataBounds

        VStack(spacing: Spacing.sm) {
            // Histogram — padded by half-thumb so bars align with the slider track
            let maxCount = CGFloat(bins.map(\.count).max() ?? 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(bins.enumerated()), id: \.offset) { _, bin in
                    let h = maxCount > 0 ? CGFloat(bin.count) / maxCount * barHeight : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(bin.inRange ? AppColors.primary : AppColors.primary.opacity(0.2))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(bin.count > 0 ? 3 : 0, h))
                }
            }
            .frame(height: barHeight)
            .padding(.horizontal, thumbSize / 2)
            .animation(.easeInOut(duration: 0.12), value: minPrice)
            .animation(.easeInOut(duration: 0.12), value: maxPrice)

            // Two-handle range slider
            PriceRangeSliderView(
                lowerValue: $minPrice,
                upperValue: $maxPrice,
                bounds: b.min...b.max,
                thumbSize: thumbSize
            )

            // Min / Max labels
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Min").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "£%.2f", minPrice / 100))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Max").font(.caption).foregroundStyle(.secondary)
                    let atCeiling = maxPrice >= b.max - 0.5
                    Text(atCeiling ? "Any" : String(format: "£%.2f", maxPrice / 100))
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .onAppear {
            // Initialise handles to the full data range so all stations show.
            let b2 = dataBounds
            if minPrice < b2.min || minPrice > b2.max { minPrice = b2.min }
            if maxPrice > b2.max || maxPrice < b2.min { maxPrice = b2.max }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Price Range Slider View

/// A custom two-handle range slider using drag gestures.
struct PriceRangeSliderView: View {

    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    let bounds: ClosedRange<Double>
    let thumbSize: CGFloat

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let span = bounds.upperBound - bounds.lowerBound
            guard span > 0 else { return AnyView(EmptyView()) }

            let lowerX = (lowerValue - bounds.lowerBound) / span * trackWidth
            let upperX = (upperValue - bounds.lowerBound) / span * trackWidth

            return AnyView(
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color(.systemFill))
                        .frame(height: 4)

                    // Active range track
                    Rectangle()
                        .fill(AppColors.primary)
                        .frame(width: max(0, upperX - lowerX), height: 4)
                        .offset(x: lowerX)

                    // Lower thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
                        .offset(x: lowerX - thumbSize / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let frac = max(0, min(value.location.x / trackWidth, 1))
                                    let proposed = bounds.lowerBound + frac * span
                                    lowerValue = min(proposed, upperValue - span * 0.01)
                                }
                        )
                        .accessibilityLabel("Minimum price")
                        .accessibilityValue(String(format: "£%.2f", lowerValue / 100))
                        .accessibilityAdjustableAction { direction in
                            let step = span * 0.02
                            switch direction {
                            case .increment: lowerValue = min(lowerValue + step, upperValue - step)
                            case .decrement: lowerValue = max(lowerValue - step, bounds.lowerBound)
                            @unknown default: break
                            }
                        }

                    // Upper thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
                        .offset(x: upperX - thumbSize / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let frac = max(0, min(value.location.x / trackWidth, 1))
                                    let proposed = bounds.lowerBound + frac * span
                                    upperValue = max(proposed, lowerValue + span * 0.01)
                                }
                        )
                        .accessibilityLabel("Maximum price")
                        .accessibilityValue(String(format: "£%.2f", upperValue / 100))
                        .accessibilityAdjustableAction { direction in
                            let step = span * 0.02
                            switch direction {
                            case .increment: upperValue = min(upperValue + step, bounds.upperBound)
                            case .decrement: upperValue = max(upperValue - step, lowerValue + step)
                            @unknown default: break
                            }
                        }
                }
            )
        }
        .frame(height: thumbSize)
    }
}

// MARK: - Preview

#Preview {
    NearbyView(selectedFuelType: .constant(.unleaded))
        .environmentObject(FuelDataManager(coreDataStack: .preview))
        .environmentObject(LocationService())
        .environment(\.managedObjectContext, CoreDataStack.preview.viewContext)
}
