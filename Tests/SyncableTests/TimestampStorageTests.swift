import Testing
import Foundation
@testable import Syncable

@Suite("InMemorySyncTimestampStorage Tests")
struct InMemoryStorageTests {

    @Test("Initially returns nil for unknown tables")
    func initiallyNil() async {
        let storage = InMemorySyncTimestampStorage()
        let timestamp = await storage.getLastSyncTimestamp(for: "unknown")
        #expect(timestamp == nil)
    }

    @Test("Stores and retrieves timestamps")
    func storeAndRetrieve() async {
        let storage = InMemorySyncTimestampStorage()
        let date = Date()

        await storage.setLastSyncTimestamp(date, for: "users")
        let retrieved = await storage.getLastSyncTimestamp(for: "users")

        #expect(retrieved == date)
    }

    @Test("Stores timestamps per table")
    func perTableStorage() async {
        let storage = InMemorySyncTimestampStorage()
        let date1 = Date()
        let date2 = Date().addingTimeInterval(100)

        await storage.setLastSyncTimestamp(date1, for: "users")
        await storage.setLastSyncTimestamp(date2, for: "posts")

        let users = await storage.getLastSyncTimestamp(for: "users")
        let posts = await storage.getLastSyncTimestamp(for: "posts")

        #expect(users == date1)
        #expect(posts == date2)
    }

    @Test("Clear removes all timestamps")
    func clearAll() async {
        let storage = InMemorySyncTimestampStorage()

        await storage.setLastSyncTimestamp(Date(), for: "users")
        await storage.setLastSyncTimestamp(Date(), for: "posts")
        await storage.clearAll()

        let users = await storage.getLastSyncTimestamp(for: "users")
        let posts = await storage.getLastSyncTimestamp(for: "posts")

        #expect(users == nil)
        #expect(posts == nil)
    }
}

@Suite("UserDefaultsSyncTimestampStorage Tests")
struct UserDefaultsStorageTests {

    func makeStorage() -> (UserDefaultsSyncTimestampStorage, UserDefaults) {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let storage = UserDefaultsSyncTimestampStorage(
            defaults: defaults,
            keyPrefix: "test.sync."
        )
        return (storage, defaults)
    }

    @Test("Initially returns nil for unknown tables")
    func initiallyNil() async {
        let (storage, _) = makeStorage()
        let timestamp = await storage.getLastSyncTimestamp(for: "unknown")
        #expect(timestamp == nil)
    }

    @Test("Stores and retrieves timestamps")
    func storeAndRetrieve() async {
        let (storage, _) = makeStorage()
        let date = Date()

        await storage.setLastSyncTimestamp(date, for: "users")
        let retrieved = await storage.getLastSyncTimestamp(for: "users")

        #expect(retrieved == date)
    }

    @Test("Clear removes only prefixed keys")
    func clearOnlyPrefixed() async {
        let (storage, defaults) = makeStorage()

        // Set a sync timestamp
        await storage.setLastSyncTimestamp(Date(), for: "users")

        // Set an unrelated key
        defaults.set("unrelated", forKey: "other.key")

        await storage.clearAll()

        let users = await storage.getLastSyncTimestamp(for: "users")
        let other = defaults.string(forKey: "other.key")

        #expect(users == nil)
        #expect(other == "unrelated")
    }
}
