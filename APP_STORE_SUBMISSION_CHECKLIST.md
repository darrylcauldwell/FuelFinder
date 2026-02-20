# App Store Submission Checklist

## ✅ COMPLETED - Ready for Submission

### 1. Documentation Updates ✅
- [x] **README.md** - Updated with route planning features, 5-tab structure, CarPlay 4-tab structure
- [x] **App Store Description (en-GB)** - Removed non-existent features, added route planning, corrected data source
- [x] **App Store Description (en-US)** - Added route planning, map & list views, updated privacy statement
- [x] **Review Notes** - Comprehensive CarPlay fueling entitlement justification with framework details
- [x] **MEMORY.md** - Updated architecture, testing, and project overview sections

### 2. Code & Configuration ✅
- [x] **Info.plist** - Removed incorrect fuel-finder.api.gov.uk reference
- [x] **Build Status** - BUILD SUCCEEDED (verified)
- [x] **CarPlay Entitlement** - Enabled and documented
- [x] **Route Planning** - Fully implemented (RouteManager, DestinationSearchView, RoutePreviewView, RouteTabView)

### 3. Testing ✅
- [x] **Unit Tests** - 15 tests covering RouteStationFinder (nearby + route) and FuelDataManager
- [x] **UI Tests** - Updated with 11 tests including Route tab navigation and destination search
- [x] **Screenshot Tests** - Updated for 5-screen flow: NearbyMap → List → RouteSearch → Favourites → Settings

### 4. Accessibility ✅
- [x] **Accessibility Labels** - Present in RouteView.swift and DesignTokens.swift
- [x] **VoiceOver Support** - Station rows, buttons, and controls properly labeled
- [x] **Dynamic Type** - Using system fonts throughout

---

## 📋 PRE-SUBMISSION CHECKLIST

Before uploading to App Store Connect, verify:

### Build Configuration
- [ ] Version number incremented in Info.plist (`CFBundleShortVersionString`)
- [ ] Build number incremented in Info.plist (`CFBundleVersion`) - currently at `7`
- [ ] Release configuration selected (not Debug)
- [ ] Generic iOS Device selected (not Simulator)

### Code Signing
- [ ] Correct provisioning profile selected
- [ ] Distribution certificate valid
- [ ] All entitlements match App Store Connect configuration

### Testing
- [ ] Run all unit tests: `xcodebuild test -scheme FuelFinder -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- [ ] Manual test on physical device
- [ ] Test CarPlay on physical device (or note in review that simulator testing was used)
- [ ] Test all 5 iPhone tabs
- [ ] Test route planning flow (search → select → view corridor)
- [ ] Test favourites sync via iCloud

### Screenshots
- [ ] Generate new screenshots: `fastlane screenshots`
- [ ] Verify 5 screenshots generated: NearbyMap, List, RouteSearch, Favourites, Settings
- [ ] Upload to App Store Connect for iPhone 17 Pro and iPhone 17 Pro Max

### Metadata
- [ ] App name: "Fuel Finder"
- [ ] Subtitle: "UK Petrol & Diesel Prices"
- [ ] Keywords: Include "fuel", "petrol", "diesel", "prices", "UK", "CarPlay", "route", "stations"
- [ ] Privacy policy URL set
- [ ] Support URL set

### Review Information
- [ ] Review notes uploaded (with CarPlay justification)
- [ ] Demo account provided (if needed - NOT required for this app)
- [ ] Contact information current

---

## 🚗 CARPLAY ENTITLEMENT JUSTIFICATION

**This justification is already included in the review notes. Highlight these points if contacted by App Review:**

### Why CarPlay Fueling Entitlement is Required

1. **Framework Integration**: Uses CPTemplateApplicationSceneDelegate, CPTabBarTemplate, CPListTemplate, and CPPointOfInterestTemplate from the CarPlay Fueling framework

2. **Safety**: Allows drivers to find fuel stations without touching their phone while driving

3. **Functionality**:
   - Browse nearby fuel stations on car display
   - Compare live prices from 12 UK retailers
   - View favourites synced via iCloud
   - Adjust fuel type and sort order
   - Configure route search radius
   - Hand off to Apple Maps for navigation

4. **Navigation Compliance**: Does NOT replace Apple Maps. All turn-by-turn navigation is handed off to Maps

5. **Data Source**: Uses official UK retailer open data feeds (CMA fuel price transparency scheme), not government API

---

## 📸 SCREENSHOT DESCRIPTIONS

When uploading screenshots, use these descriptions:

1. **NearbyMap** - "Find nearby fuel stations on an interactive map with live prices"
2. **List** - "Browse and sort stations by price or distance with adjustable search radius"
3. **RouteSearch** - "Plan your route and find fuel stations along the way"
4. **Favourites** - "Save your preferred stations and sync across devices with iCloud"
5. **Settings** - "Refresh data and check location status"

---

## 🔍 COMMON APP REVIEW QUESTIONS

**Q: Why do you need the CarPlay Fueling entitlement?**
A: See review notes - uses CPTemplateApplicationSceneDelegate framework, enhances driver safety by allowing fuel station search without phone interaction, hands off navigation to Apple Maps.

**Q: How do you get fuel price data?**
A: Direct from 12 UK retailer open data feeds published under the CMA fuel price transparency scheme. No API authentication required. Retailers: Asda, BP, Esso, JET, Morrisons, Moto, Motor Fuel Group, Rontec, Sainsbury's, SGN, Shell, Tesco.

**Q: Does this replace Apple Maps navigation?**
A: No. The app only shows fuel stations and prices. All turn-by-turn navigation is handed off to Apple Maps via MKMapItem.openInMaps().

**Q: What location data is collected?**
A: Location is used only to find nearby stations and calculate routes via Apple's MapKit framework. No location data is sent to third-party servers or stored remotely.

**Q: What is the route planning feature?**
A: Users enter a destination, MKDirections calculates the route, app shows fuel stations within 1-5 miles of the route corridor. Helps drivers plan fuel stops on long journeys.

---

## 🎯 SUBMISSION STEPS

1. **Archive the App**
   ```bash
   xcodebuild archive -project FuelFinder.xcodeproj \
     -scheme FuelFinder \
     -archivePath ./build/FuelFinder.xcarchive
   ```

2. **Export for App Store**
   ```bash
   xcodebuild -exportArchive \
     -archivePath ./build/FuelFinder.xcarchive \
     -exportPath ./build \
     -exportOptionsPlist exportOptions.plist
   ```

3. **Upload to App Store Connect**
   ```bash
   xcrun altool --upload-app \
     --type ios \
     --file ./build/FuelFinder.ipa \
     --apiKey [YOUR_API_KEY] \
     --apiIssuer [YOUR_ISSUER_ID]
   ```

   OR use Fastlane:
   ```bash
   fastlane upload_to_app_store
   ```

4. **Submit for Review**
   - Go to App Store Connect
   - Select FuelFinder app
   - Add build to version
   - Fill in "What's New" section
   - Submit for review

---

## 📝 SUGGESTED "WHAT'S NEW" TEXT

```
NEW IN VERSION 1.0

• Route Planning: Search for a destination and see fuel stations along your route
• List View: Browse nearby stations in a sortable list with adjustable distance
• CarPlay Integration: Full 4-tab CarPlay support with fuel type selection and route controls
• Improved Sorting: Sort by price (cheapest) or distance (nearest)
• Live Price Data: Prices from 12 UK retailers updated every 12 hours
• iCloud Sync: Favourite stations sync automatically across your devices
• Enhanced UI: Modern glass design with accessibility improvements

We'd love to hear your feedback! Rate the app and let us know how we can improve.
```

---

## ⚠️ IMPORTANT NOTES

1. **CarPlay entitlement MUST remain enabled** in FuelFinder.entitlements (`<true/>`)
2. **Bundle version** must be incremented for each submission (currently at 7)
3. **No mock data** in production builds - all data is live from retailer feeds
4. **Location permission** is required - app prompts on first launch
5. **CloudKit entitlement** optional for iCloud sync but recommended for favourites

---

## 🚀 POST-SUBMISSION

After approval:
- [ ] Monitor reviews and ratings
- [ ] Respond to user feedback
- [ ] Track crash reports via Xcode Organizer
- [ ] Plan next version features based on feedback

---

**Status**: ✅ READY FOR APP STORE SUBMISSION

Last Updated: 2026-02-20
Bundle Version: 1.0.0 (7)
