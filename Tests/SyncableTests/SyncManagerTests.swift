import Testing
import Foundation
import GRDB
import Supabase
@testable import Syncable

@Suite("SyncManager Tests")
struct SyncManagerTests {

    @Test("SyncManager initializes with correct defaults")
    func initializesCorrectly() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        #expect(manager.maxRows == 100)
        #expect(manager.userId == nil)
        #expect(manager.syncingEnabled == false)
        #expect(manager.registeredTables.isEmpty)
    }

    @Test("SyncManager respects custom maxRows")
    func customMaxRows() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage,
            maxRows: 50
        )

        #expect(manager.maxRows == 50)
    }

    @Test("Register adds type to registeredTables")
    func registerAddsType() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        manager.register(TestItem.self)

        #expect(manager.registeredTables.contains("testitems"))
    }

    @Test("setUserId updates userId")
    func setUserIdWorks() async throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        let userId = UUID()
        await manager.setUserId(userId)

        #expect(manager.userId == userId)
    }

    @Test("setSyncingEnabled updates syncingEnabled")
    func setSyncingEnabledWorks() async throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        #expect(manager.syncingEnabled == false)
        await manager.setSyncingEnabled(true)
        #expect(manager.syncingEnabled == true)
    }

    @Test("clearSyncState resets state")
    func clearSyncStateWorks() async throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        // Set up state
        await manager.setUserId(UUID())
        await manager.setSyncingEnabled(true)
        await storage.setLastSyncTimestamp(Date(), for: "test")

        // Clear state
        await manager.clearSyncState()

        #expect(manager.userId == nil)
        #expect(manager.syncingEnabled == false)
        #expect(await storage.getLastSyncTimestamp(for: "test") == nil)
    }
}

@Suite("SyncError Tests")
struct SyncErrorTests {

    @Test("typeNotRegistered has descriptive message")
    func typeNotRegisteredMessage() {
        let error = SyncError.typeNotRegistered("todos")
        #expect(error.localizedDescription.contains("todos"))
        #expect(error.localizedDescription.contains("not registered"))
    }

    @Test("encodingFailed has descriptive message")
    func encodingFailedMessage() {
        let error = SyncError.encodingFailed("Invalid data")
        #expect(error.localizedDescription.contains("encode"))
        #expect(error.localizedDescription.contains("Invalid data"))
    }

    @Test("decodingFailed has descriptive message")
    func decodingFailedMessage() {
        let error = SyncError.decodingFailed("Missing field")
        #expect(error.localizedDescription.contains("decode"))
        #expect(error.localizedDescription.contains("Missing field"))
    }
}

// MARK: - Test Helpers

/// Standalone backoff helper for testing (can be used in future implementations)
struct ExponentialBackoff {
    var currentDelay: TimeInterval = 1.0
    let maxDelay: TimeInterval

    init(maxDelay: TimeInterval = 60.0) {
        self.maxDelay = maxDelay
    }

    @discardableResult
    mutating func recordFailure() -> TimeInterval {
        let delay = currentDelay
        currentDelay = min(currentDelay * 2, maxDelay)
        return delay
    }

    mutating func recordSuccess() {
        currentDelay = 1.0
    }
}

/// Standalone echo cache helper for testing (can be used in future implementations)
struct EchoPreventionCache {
    private var cache: [UUID: Date] = [:]
    let ttl: TimeInterval

    init(ttl: TimeInterval = 60.0) {
        self.ttl = ttl
    }

    var count: Int { cache.count }

    mutating func markAsSynced(_ id: UUID) {
        cache[id] = Date()
    }

    func wasRecentlySynced(_ id: UUID) -> Bool {
        guard let syncedAt = cache[id] else { return false }
        return Date().timeIntervalSince(syncedAt) < ttl
    }

    mutating func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-ttl)
        cache = cache.filter { $0.value > cutoff }
    }
}

@Suite("Backoff Tests")
struct BackoffTests {

    @Test("Initial backoff is 1 second")
    func initialBackoff() {
        let backoff = ExponentialBackoff()
        #expect(backoff.currentDelay == 1.0)
    }

    @Test("Backoff doubles on failure")
    func backoffDoubles() {
        var backoff = ExponentialBackoff()

        let first = backoff.recordFailure()
        #expect(first == 1.0)
        #expect(backoff.currentDelay == 2.0)

        let second = backoff.recordFailure()
        #expect(second == 2.0)
        #expect(backoff.currentDelay == 4.0)

        let third = backoff.recordFailure()
        #expect(third == 4.0)
        #expect(backoff.currentDelay == 8.0)
    }

    @Test("Backoff caps at maximum")
    func backoffCapsAtMax() {
        var backoff = ExponentialBackoff(maxDelay: 60.0)

        for _ in 0..<10 {
            _ = backoff.recordFailure()
        }

        #expect(backoff.currentDelay == 60.0)

        _ = backoff.recordFailure()
        #expect(backoff.currentDelay == 60.0)
    }

    @Test("Backoff resets on success")
    func backoffResetsOnSuccess() {
        var backoff = ExponentialBackoff()

        _ = backoff.recordFailure()
        _ = backoff.recordFailure()
        _ = backoff.recordFailure()
        #expect(backoff.currentDelay == 8.0)

        backoff.recordSuccess()
        #expect(backoff.currentDelay == 1.0)
    }
}

@Suite("Echo Prevention Cache Tests")
struct EchoCacheTests {

    @Test("Newly added items are marked as synced")
    func itemsMarkedAsSynced() {
        var cache = EchoPreventionCache(ttl: 60.0)
        let id = UUID()

        #expect(!cache.wasRecentlySynced(id))
        cache.markAsSynced(id)
        #expect(cache.wasRecentlySynced(id))
    }

    @Test("Items expire after TTL")
    func itemsExpireAfterTTL() {
        var cache = EchoPreventionCache(ttl: 0.1)
        let id = UUID()

        cache.markAsSynced(id)
        #expect(cache.wasRecentlySynced(id))

        Thread.sleep(forTimeInterval: 0.15)
        #expect(!cache.wasRecentlySynced(id))
    }

    @Test("Purge removes expired items")
    func purgeRemovesExpired() {
        var cache = EchoPreventionCache(ttl: 0.1)
        let id1 = UUID()
        let id2 = UUID()

        cache.markAsSynced(id1)
        Thread.sleep(forTimeInterval: 0.15)
        cache.markAsSynced(id2)

        #expect(cache.count == 2)
        cache.purgeExpired()
        #expect(cache.count == 1)
        #expect(!cache.wasRecentlySynced(id1))
        #expect(cache.wasRecentlySynced(id2))
    }

    @Test("Multiple IDs tracked independently")
    func multipleIdsTracked() {
        var cache = EchoPreventionCache(ttl: 60.0)
        let ids = (0..<5).map { _ in UUID() }

        for id in ids {
            cache.markAsSynced(id)
        }

        #expect(cache.count == 5)
        for id in ids {
            #expect(cache.wasRecentlySynced(id))
        }

        #expect(!cache.wasRecentlySynced(UUID()))
    }
}

// MARK: - Mock Supabase Client

/// Mock Supabase client for testing
struct MockSupabaseClient {
    // We can't easily mock SupabaseClient without the actual dependency,
    // so we create a real one with dummy credentials for initialization tests only
    var client: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "dummy-key-for-testing"
        )
    }
}
