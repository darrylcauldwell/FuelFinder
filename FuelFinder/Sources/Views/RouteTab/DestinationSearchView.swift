import SwiftUI
import MapKit
import Combine

/// Destination search view with MKLocalSearchCompleter autocomplete.
struct DestinationSearchView: View {

    @ObservedObject var routeManager: RouteManager
    @StateObject private var searchCompleter = DestinationSearchCompleter()

    @State private var searchText = ""
    @State private var isCalculating = false

    let currentLocation: CLLocationCoordinate2D

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search destination...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        searchCompleter.search(query: newValue)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchCompleter.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top)

            // Search results
            if !searchCompleter.results.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchCompleter.results, id: \.self) { result in
                            Button {
                                selectDestination(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                            }
                            .buttonStyle(.plain)

                            Divider()
                        }
                    }
                }
            } else if searchText.isEmpty {
                // Show recent/favorite destinations
                RecentDestinationsView(routeManager: routeManager, currentLocation: currentLocation)
            } else {
                // No results
                VStack {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .foregroundColor(.secondary)
                        .padding(.top)
                    Spacer()
                }
            }
        }
        .navigationTitle("Set Destination")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isCalculating {
                ProgressView("Calculating route...")
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 8)
            }
        }
    }

    private func selectDestination(_ completion: MKLocalSearchCompletion) {
        searchText = ""
        searchCompleter.clearResults()
        isCalculating = true

        Task {
            // Convert completion to MKMapItem
            let searchRequest = MKLocalSearch.Request(completion: completion)
            let search = MKLocalSearch(request: searchRequest)

            do {
                let response = try await search.start()
                if let mapItem = response.mapItems.first {
                    await routeManager.calculateRoute(from: currentLocation, to: mapItem)

                    // Save to recent destinations
                    RecentDestinationsManager.shared.add(mapItem)
                }
            } catch {
                print("Search error: \(error)")
                routeManager.routeError = error.localizedDescription
            }

            isCalculating = false
        }
    }
}

// MARK: - MKLocalSearchCompleter Wrapper

@MainActor
final class DestinationSearchCompleter: NSObject, ObservableObject {

    @Published var results: [MKLocalSearchCompletion] = []

    nonisolated(unsafe) private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // Bias to UK
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 54.0, longitude: -2.5),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
        )
    }

    func search(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }
        completer.queryFragment = query
    }

    func clearResults() {
        results = []
    }
}

extension DestinationSearchCompleter: MKLocalSearchCompleterDelegate {

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // MKLocalSearchCompleter delegate is called on main thread
        // Use self.completer which is marked nonisolated(unsafe)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.results = self.completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            print("Search completer error: \(error)")
            self?.results = []
        }
    }
}

// MARK: - Recent Destinations View

struct RecentDestinationsView: View {

    @ObservedObject var routeManager: RouteManager
    let currentLocation: CLLocationCoordinate2D

    @State private var recentDestinations: [MKMapItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !recentDestinations.isEmpty {
                    Text("Recent")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)

                    ForEach(recentDestinations.indices, id: \.self) { index in
                        let item = recentDestinations[index]
                        Button {
                            selectDestination(item)
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name ?? "Unknown")
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    if let address = formatAddress(item) {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                } else {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Search for a destination")
                            .foregroundColor(.secondary)
                        Text("Recent destinations will appear here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
        .onAppear {
            recentDestinations = RecentDestinationsManager.shared.getRecent()
        }
    }

    private func selectDestination(_ mapItem: MKMapItem) {
        Task {
            await routeManager.calculateRoute(from: currentLocation, to: mapItem)
        }
    }

    private func formatAddress(_ mapItem: MKMapItem) -> String? {
        let placemark = mapItem.placemark
        var components: [String] = []

        if let locality = placemark.locality {
            components.append(locality)
        }
        if let area = placemark.administrativeArea {
            components.append(area)
        }

        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}

// MARK: - Recent Destinations Manager

@MainActor
final class RecentDestinationsManager {

    static let shared = RecentDestinationsManager()

    private let maxRecent = 5
    private let key = "recentDestinations"

    private init() {}

    func add(_ mapItem: MKMapItem) {
        var recent = getRecent()

        // Remove if already exists (to move to front)
        recent.removeAll { existing in
            guard let existingCoord = existing.placemark.location?.coordinate,
                  let newCoord = mapItem.placemark.location?.coordinate else {
                return false
            }
            return abs(existingCoord.latitude - newCoord.latitude) < 0.001 &&
                   abs(existingCoord.longitude - newCoord.longitude) < 0.001
        }

        // Add to front
        recent.insert(mapItem, at: 0)

        // Keep only maxRecent
        if recent.count > maxRecent {
            recent = Array(recent.prefix(maxRecent))
        }

        save(recent)
    }

    func getRecent() -> [MKMapItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(
                ofClass: MKMapItem.self,
                from: data
              ) else {
            return []
        }
        return decoded
    }

    private func save(_ items: [MKMapItem]) {
        if let encoded = try? NSKeyedArchiver.archivedData(
            withRootObject: items,
            requiringSecureCoding: true
        ) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
