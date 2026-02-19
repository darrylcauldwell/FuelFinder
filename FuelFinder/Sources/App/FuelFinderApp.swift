import SwiftUI

@main
struct FuelFinderApp: App {

    @StateObject private var dataManager: FuelDataManager
    @StateObject private var locationService = LocationService()

    init() {
        let dm = FuelDataManager(coreDataStack: .shared)
        _dataManager = StateObject(wrappedValue: dm)
        FuelDataManager.shared = dm
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
                .environmentObject(dataManager)
                .environmentObject(locationService)
        }
    }
}
