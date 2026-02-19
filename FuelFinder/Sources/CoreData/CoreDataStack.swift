import Foundation
import CoreData
import CloudKit

/// Persistent CloudKit-backed Core Data stack.
/// Thread-safe singleton — all view context access confined to main actor.
final class CoreDataStack: Sendable {

    static let shared = CoreDataStack()

    /// In-memory store for previews and tests.
    static let preview: CoreDataStack = {
        let stack = CoreDataStack(inMemory: true)
        let ctx = stack.container.viewContext
        for i in 0..<3 {
            let station = Station(context: ctx)
            station.id = "preview\(i)"
            station.name = "Preview Station \(i)"
            station.brand = ["Shell", "BP", "Morrisons"][i]
            station.latitude = 51.5074 + Double(i) * 0.01
            station.longitude = -0.1278 + Double(i) * 0.01
            station.address = "\(i) Preview Road, London"
            station.amenities = "[]"
            station.lastUpdated = Date()
            station.isFavourite = i == 0

            let prices = PriceSet(context: ctx)
            prices.unleaded = 1.42 + Double(i) * 0.03
            prices.diesel = 1.50 + Double(i) * 0.02
            prices.superUnleaded = 1.55 + Double(i) * 0.03
            prices.premiumDiesel = 1.60 + Double(i) * 0.02
            prices.updatedAt = Date()
            prices.station = station
            station.prices = prices
        }
        try? ctx.save()
        return stack
    }()

    let container: NSPersistentCloudKitContainer

    /// Main-thread context — access only from @MainActor.
    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "FuelFinder")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
        } else if let description = container.persistentStoreDescriptions.first {
            // iCloud entitlement not yet provisioned — using local SQLite only.
            // To re-enable CloudKit: add com.apple.developer.icloud-containers to
            // the entitlements file and set cloudKitContainerOptions here.
            description.cloudKitContainerOptions = nil
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { _, error in
            if let error {
                print("[CoreDataStack] Failed to load store: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    /// Creates a new background context for batch imports.
    /// Each caller gets its own context — safe for concurrent use.
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    func save(context: NSManagedObjectContext? = nil) {
        let ctx = context ?? viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            print("[CoreDataStack] Save error: \(error.localizedDescription)")
        }
    }
}
