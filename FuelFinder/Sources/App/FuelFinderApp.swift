import SwiftUI

@main
struct FuelFinderApp: App {

    let coreDataStack = CoreDataStack.shared
    @StateObject private var dataManager: FuelDataManager
    @StateObject private var locationService = LocationService()

    init() {
        let stack = CoreDataStack.shared
        _dataManager = StateObject(wrappedValue: FuelDataManager(coreDataStack: stack))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, coreDataStack.viewContext)
                .environmentObject(dataManager)
                .environmentObject(locationService)
        }
    }
}
