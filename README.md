# Fuel Finder

UK fuel price browser for iPhone and CarPlay. See the cheapest petrol and diesel stations near you or along your route, compare prices, and hand off navigation to Apple Maps — all without a backend or API keys.

## Architecture

```
FuelFinder/
├── Sources/
│   ├── App/                  # App entry point (@main), ContentView, 5-tab bar
│   ├── CoreData/             # NSPersistentCloudKitContainer stack
│   ├── Networking/           # FuelDataManager — retailer feed fetching + Core Data import
│   ├── RouteEngine/          # RouteStationFinder + RouteManager — nearby/route search + scoring
│   ├── Views/
│   │   ├── NearbyView/       # Map view with station pins + persistent bottom sheet
│   │   ├── RouteTab/         # Route planning: destination search, route preview
│   │   └── Components/       # StationDetailSheet, filters, glass design components
│   ├── CarPlay/              # CarPlaySceneDelegate + FuelCarPlayManager (4 tabs)
│   ├── Services/             # LocationService — CLLocationManager wrapper
│   ├── Utilities/            # DesignTokens, GlassDesignSystem, AppColors
│   └── Extensions/           # Station+Convenience, FuelType enum
├── Resources/
│   ├── MockData.json         # Test stations for unit tests
│   ├── Info.plist            # CarPlay scene config, location permissions
│   └── FuelFinder.entitlements
├── FuelFinder.xcdatamodeld   # Core Data model (Station, PriceSet)
└── Assets.xcassets
```

## Core Components

| File | Purpose |
|---|---|
| `CoreDataStack.swift` | `NSPersistentCloudKitContainer` with local SQLite store; CloudKit sync for favourites when entitlement is provisioned |
| `FuelDataManager.swift` | Fetches 12 UK retailer open data feeds concurrently, batch-imports to Core Data, 12-hour periodic refresh; supports nearby and route-based queries |
| `RouteStationFinder.swift` | Bounding-box Core Data query, haversine distance filter, route corridor search, price + distance normalised scoring |
| `RouteManager.swift` | Route calculation via MKDirections, corridor filtering, detour time estimation |
| `NearbyView.swift` | SwiftUI Map with station pins, persistent bottom sheet list, filter sheet, station detail sheet |
| `RouteTabView.swift` | Route planning tab coordinator — switches between destination search and route preview |
| `DestinationSearchView.swift` | MKLocalSearchCompleter autocomplete for destination input with recent destinations |
| `RoutePreviewView.swift` | Route map view with corridor radius controls and stations along route |
| `CarPlaySceneDelegate.swift` | `CPTemplateApplicationSceneDelegate` — CarPlay lifecycle |
| `FuelCarPlayManager.swift` | Bridges app state → `CPTabBarTemplate` with 4 tabs: Map, List, Favourites, Settings |
| `LocationService.swift` | `CLLocationManager` wrapper; publishes `currentLocation` and `authorizationStatus` |
| `Station+Convenience.swift` | Core Data extensions: `coordinate`, `location`, `price(for:)`, `amenitiesList` |

## How It Works

There is no backend and no API key required. The app calls UK retailer open data feeds directly — a requirement of the [CMA fuel price transparency scheme](https://www.gov.uk/guidance/access-fuel-price-data):

| Retailer | Feed |
|---|---|
| Asda | storelocator.asda.com |
| BP | bp.com |
| Esso | fuelprices.esso.co.uk |
| JET | jetlocal.co.uk |
| Morrisons | morrisons.com |
| Moto | moto-way.com |
| Motor Fuel Group | fuel.motorfuelgroup.com |
| Rontec | rontec-servicestations.co.uk |
| Sainsbury's | api.sainsburys.co.uk |
| SGN | sgnretail.uk |
| Shell | shell.co.uk |
| Tesco | tesco.com |

Prices are refreshed every 12 hours. All 12 feeds are fetched concurrently using Swift structured concurrency.

## Quick Start

1. Open `FuelFinder.xcodeproj` in Xcode 16+
2. Build and run on iPhone simulator (iOS 18.0+)
3. Grant location permission when prompted — the map centres on your location
4. Tap any station pin or row to see full price details
5. Tap **Get Directions** to hand off to Apple Maps

### iPhone App Features

**Map Tab:**
- Interactive map with fuel station pins
- Persistent bottom sheet with station list
- Tap any station to view detailed prices
- Pull sheet up to medium/large detent for full list

**List Tab:**
- Sortable list of nearby stations
- Distance slider (1-20 miles)
- Fuel type selector menu
- Sort by price (Cheapest) or distance (Nearest)
- Swipe for directions

**Route Tab:**
- Search for destinations with autocomplete
- Route preview on map
- Stations along route corridor
- Adjustable corridor radius (1-5 miles)
- Recent destinations

**Favourites Tab:**
- Starred stations synced via iCloud
- Quick access to preferred locations

**Settings Tab:**
- Manual data refresh
- Location status
- App version and data source info

### Filtering & Sorting

- Use the **fuel type** menu to switch between Unleaded, Diesel, Super Unleaded, and Premium Diesel
- Use the **sort** picker to switch between Cheapest and Nearest
- Adjust **distance slider** to set maximum search radius
- In Route tab, adjust **corridor radius** to see more or fewer stations along your route

### CarPlay Testing

1. In Xcode, go to **Window → Devices and Simulators**
2. Select an iPhone simulator with CarPlay support
3. In the Simulator menu: **I/O → External Displays → CarPlay**
4. The CarPlay scene connects automatically, showing 4 tabs: Map, List, Favourites, Settings
5. Settings tab shows fuel type selector, sort order, and route controls

## Scoring Algorithm

### Nearby Mode

Stations are scored by combining normalised price and distance:

```
score = 0.6 × normalised(price) + 0.4 × normalised(distance)
```

### Route Mode

When a route is active, scoring uses detour time instead of straight-line distance:

```
score = 0.6 × normalised(price) + 0.4 × normalised(detour_time)
detour_time = (2 × distance_to_route / 30mph) + 3min_fuel_stop
```

### Common

- Lower score = better recommendation
- Price tiers assigned by thirds: cheapest (green), middle (amber), expensive (red)
- Map re-queries when the centre moves more than 2 km from the last query point
- Route corridor search filters stations within 1-5 miles of route polyline

## Testing

Run tests via Xcode or command line:

```bash
xcodebuild test -scheme FuelFinder -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Test coverage:
- `RouteStationFinderTests`: nearby search, route corridor search, scoring, price tiers, bounding-box, performance
- `FuelDataManagerTests`: feed import, upsert deduplication, convenience extensions
- `FuelFinderUITests`: tab navigation (Map, List, Favourites, Route, Settings), fuel picker, destination search
- `ScreenshotTests`: App Store screenshot generation for all tabs (run via `fastlane screenshots`)

## App Store Screenshots

Screenshots are generated with Fastlane Snapshot:

```bash
fastlane screenshots
```

Requires custom simulators named `Screenshot-iPhone16Pro`, `Screenshot-iPhone16ProMax`, and `Screenshot-iPadPro13M5` to be created in Xcode first.

## Privacy

See [PRIVACY.md](PRIVACY.md) for the full privacy policy.

## Requirements

- Xcode 16.0+
- iOS 18.0+
- Swift 6.0
- CarPlay Fueling entitlement (Apple approval required for CarPlay features)
