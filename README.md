# Fuel Finder

UK fuel price finder for iPhone and CarPlay. Plan a route and discover the cheapest fuel stations along your journey.

## Architecture

```
FuelFinder/
├── Sources/
│   ├── App/                  # App entry point, ContentView, tabs
│   ├── CoreData/             # NSPersistentCloudKitContainer stack
│   ├── Networking/           # FuelDataManager — OAuth2 + API + Core Data import
│   ├── RouteEngine/          # RouteStationFinder — corridor search algorithm
│   ├── Views/                # RouteView — SwiftUI + MapKit iPhone UI
│   ├── CarPlay/              # CarPlaySceneDelegate + FuelCarPlayManager
│   └── Extensions/           # Station+Convenience, FuelType enum
├── Resources/
│   ├── MockData.json         # 10 test stations (London / M1 corridor)
│   ├── Info.plist            # CarPlay scene config, location permissions
│   └── FuelFinder.entitlements
├── FuelFinder.xcdatamodeld   # Core Data model (Station, PriceSet, UserSettings)
└── Assets.xcassets
```

## Core Components

| File | Purpose |
|---|---|
| `CoreDataStack.swift` | `NSPersistentCloudKitContainer` with iCloud sync for favourites/settings |
| `FuelDataManager.swift` | OAuth2 token management, Fuel Finder API calls, Core Data batch import |
| `RouteStationFinder.swift` | Corridor search: samples polyline, bounding-box query, price+detour scoring |
| `RouteView.swift` | SwiftUI Map with route polyline, coloured station pins, Add Stop re-routing |
| `CarPlaySceneDelegate.swift` | `CPTemplateApplicationSceneDelegate` — CarPlay lifecycle |
| `FuelCarPlayManager.swift` | Bridges app state → `CPTabBarTemplate`, `CPMapTemplate`, `CPInformationTemplate` |
| `Station+Convenience.swift` | Core Data extensions, `StationAnnotation`, `FuelType` enum |

## Quick Start

1. Open `FuelFinder.xcodeproj` in Xcode 16+
2. The app uses **mock data** by default — no API keys needed
3. Build and run on iPhone simulator (iOS 18.0+)
4. Enter origin/destination → "Plan Route" → "Find Fuel" → tap a station → "Add Stop"

### CarPlay Testing

1. In Xcode, go to **Window → Devices and Simulators**
2. Select an iPhone simulator with CarPlay support
3. In the Simulator menu: **I/O → External Displays → CarPlay**
4. The CarPlay scene will connect automatically

## Fuel Finder API Integration

The app is built to work with the UK Government Fuel Finder API. To connect to the real API:

1. Register at the Fuel Finder developer portal (GOV.UK)
2. Obtain OAuth2 client credentials
3. In `FuelDataManager.swift`, update:
   ```swift
   private let clientID = "YOUR_REAL_CLIENT_ID"
   private let clientSecret = "YOUR_REAL_CLIENT_SECRET"
   ```
4. Set `useMockData = false`

## Scoring Algorithm

Stations are scored by combining normalised price and detour distance:

```
score = (1 - detourWeight) × normalised(price) + detourWeight × normalised(detour)
```

- `detourWeight = 0.4` (adjustable)
- Lower score = better recommendation
- Price tiers: cheapest third (green), middle (amber), expensive (red)

## Testing

Run tests via Xcode or command line:

```bash
xcodebuild test -scheme FuelFinder -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Test coverage:
- `RouteStationFinderTests`: corridor search, nearby search, scoring, price tiers, performance
- `FuelDataManagerTests`: mock data import, upsert deduplication, convenience extensions
- `FuelFinderUITests`: tab navigation, route planning, settings
- `ScreenshotTests`: App Store screenshot generation

## Privacy

See [PRIVACY.md](PRIVACY.md) for the full privacy policy.

## Requirements

- Xcode 16.0+
- iOS 18.0+
- Swift 6.0
- CarPlay Fueling entitlement (for CarPlay features)
