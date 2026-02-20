import SwiftUI
import MapKit

/// Shows route on map with fuel stations along the corridor.
struct RoutePreviewView: View {

    @ObservedObject var routeManager: RouteManager
    @ObservedObject var dataManager: FuelDataManager

    @State private var selectedStation: StationWithScore?
    @State private var showingStationDetail = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Map with route and stations
            RouteMapView(
                route: routeManager.activeRoute,
                stations: dataManager.nearbyStations,
                selectedStation: $selectedStation
            )
            .ignoresSafeArea()

            // Bottom sheet with route info and corridor radius control
            VStack(spacing: 0) {
                // Handle bar
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)

                // Route summary
                if let route = routeManager.activeRoute {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "map.fill")
                                .foregroundColor(.accentColor)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                if let destination = routeManager.destination {
                                    Text(destination.name ?? "Destination")
                                        .font(.headline)
                                }

                                Text(routeSummary(route))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                routeManager.clearRoute()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.title3)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        // Corridor radius control
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Search Radius")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text("\(Int(routeManager.corridorRadiusMiles)) mi")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.accentColor)
                            }

                            Slider(
                                value: $routeManager.corridorRadiusMiles,
                                in: 1...5,
                                step: 1
                            )
                            .tint(.accentColor)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        // Station count
                        HStack {
                            Image(systemName: "fuelpump.fill")
                                .foregroundColor(.accentColor)

                            Text("\(dataManager.nearbyStations.count) stations found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 12)
            )
        }
        .navigationTitle("Route Preview")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingStationDetail) {
            if let station = selectedStation {
                StationDetailSheet(
                    station: station,
                    viewContext: dataManager.coreDataStack.viewContext
                )
            }
        }
        .onChange(of: selectedStation) { _, newValue in
            if newValue != nil {
                showingStationDetail = true
            }
        }
    }

    private func routeSummary(_ route: MKRoute) -> String {
        let distance = Measurement(value: route.distance, unit: UnitLength.meters)
            .converted(to: .miles)
        let time = route.expectedTravelTime / 60
        return String(format: "%.1f mi • %.0f min", distance.value, time)
    }
}

// MARK: - Route Map View

struct RouteMapView: UIViewRepresentable {

    let route: MKRoute?
    let stations: [StationWithScore]
    @Binding var selectedStation: StationWithScore?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Remove existing overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

        // Add route overlay
        if let route = route {
            mapView.addOverlay(route.polyline)

            // Fit route in view
            let edgePadding = UIEdgeInsets(top: 100, left: 50, bottom: 300, right: 50)
            mapView.setVisibleMapRect(
                route.polyline.boundingMapRect,
                edgePadding: edgePadding,
                animated: true
            )
        }

        // Add station annotations
        let annotations = stations.map { station in
            StationAnnotation(station: station)
        }
        mapView.addAnnotations(annotations)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedStation: $selectedStation)
    }

    class Coordinator: NSObject, MKMapViewDelegate {

        @Binding var selectedStation: StationWithScore?

        init(selectedStation: Binding<StationWithScore?>) {
            _selectedStation = selectedStation
        }

        // Route overlay renderer
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(AppColors.primary)
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // Station annotation view
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let stationAnnotation = annotation as? StationAnnotation else {
                return nil
            }

            let identifier = "StationPin"
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                annotation: annotation,
                reuseIdentifier: identifier
            )

            view.annotation = annotation
            view.canShowCallout = true

            // Color by price tier
            switch stationAnnotation.station.priceTier {
            case 0:
                view.markerTintColor = .systemGreen
            case 1:
                view.markerTintColor = .systemOrange
            default:
                view.markerTintColor = .systemRed
            }

            view.glyphImage = UIImage(systemName: "fuelpump.fill")

            // Add detail button
            let button = UIButton(type: .detailDisclosure)
            view.rightCalloutAccessoryView = button

            return view
        }

        // Handle annotation tap
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let stationAnnotation = view.annotation as? StationAnnotation {
                selectedStation = stationAnnotation.station
            }
        }
    }
}

// MARK: - Station Annotation

final class StationAnnotation: NSObject, MKAnnotation {

    let station: StationWithScore

    var coordinate: CLLocationCoordinate2D {
        station.coordinate
    }

    var title: String? {
        station.name
    }

    var subtitle: String? {
        "\(station.formattedPrice) • \(station.formattedDistance)"
    }

    init(station: StationWithScore) {
        self.station = station
        super.init()
    }
}
