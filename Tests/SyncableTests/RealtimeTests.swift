import Testing
import Foundation
import GRDB
import Supabase
@testable import Syncable

// MARK: - EchoPreventionCache Tests

@Suite("EchoPreventionCache Tests")
struct EchoPreventionCacheTests {

    @Test("Marks IDs as recently pushed")
    func marksIdsAsPushed() {
        var cache = EchoPreventionCache(ttl: 60.0)
        let id = UUID()

        #expect(!cache.wasRecentlyPushed(id))
        cache.markAsPushed(id)
        #expect(cache.wasRecentlyPushed(id))
    }

    @Test("wasRecentlyPushed returns false for unknown IDs")
    func unknownIdReturnsFalse() {
        let cache = EchoPreventionCache(ttl: 60.0)
        let id = UUID()

        #expect(!cache.wasRecentlyPushed(id))
    }

    @Test("IDs expire after TTL")
    func idsExpireAfterTTL() {
        var cache = EchoPreventionCache(ttl: 0.1)
        let id = UUID()

        cache.markAsPushed(id)
        #expect(cache.wasRecentlyPushed(id))

        Thread.sleep(forTimeInterval: 0.15)
        #expect(!cache.wasRecentlyPushed(id))
    }

    @Test("purgeExpired removes old entries")
    func purgeRemovesExpired() {
        var cache = EchoPreventionCache(ttl: 0.1)
        let id1 = UUID()
        let id2 = UUID()

        cache.markAsPushed(id1)
        Thread.sleep(forTimeInterval: 0.15)
        cache.markAsPushed(id2)

        #expect(cache.count == 2)
        cache.purgeExpired()
        #expect(cache.count == 1)
        #expect(!cache.wasRecentlyPushed(id1))
        #expect(cache.wasRecentlyPushed(id2))
    }

    @Test("Multiple IDs tracked independently")
    func multipleIdsTracked() {
        var cache = EchoPreventionCache(ttl: 60.0)
        let ids = (0..<5).map { _ in UUID() }

        for id in ids {
            cache.markAsPushed(id)
        }

        #expect(cache.count == 5)
        for id in ids {
            #expect(cache.wasRecentlyPushed(id))
        }

        #expect(!cache.wasRecentlyPushed(UUID()))
    }

    @Test("clear removes all entries")
    func clearRemovesAll() {
        var cache = EchoPreventionCache(ttl: 60.0)
        let ids = (0..<5).map { _ in UUID() }

        for id in ids {
            cache.markAsPushed(id)
        }

        #expect(cache.count == 5)
        cache.clear()
        #expect(cache.count == 0)
    }

    @Test("Default TTL is 60 seconds")
    func defaultTTL() {
        let cache = EchoPreventionCache()
        #expect(cache.ttl == 60.0)
    }
}

// MARK: - RealtimeSubscriptionManager Tests

@Suite("RealtimeSubscriptionManager Tests")
struct RealtimeSubscriptionManagerTests {

    @Test("Initializes with correct properties")
    func initializesCorrectly() async {
        let supabase = SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "dummy-key"
        )
        let userId = UUID()

        let manager = RealtimeSubscriptionManager(
            supabase: supabase,
            userId: userId,
            onRemoteChange: { _, _ in }
        )

        let subscribedTables = await manager.subscribedTables
        #expect(subscribedTables.isEmpty)
    }

    @Test("unsubscribeAll cleans up when no subscriptions")
    func unsubscribeAllEmptyIsNoOp() async {
        let supabase = SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "dummy-key"
        )

        let manager = RealtimeSubscriptionManager(
            supabase: supabase,
            userId: UUID(),
            onRemoteChange: { _, _ in }
        )

        // Should not crash
        await manager.unsubscribeAll()

        let subscribedTables = await manager.subscribedTables
        #expect(subscribedTables.isEmpty)
    }

    @Test("unsubscribe from non-existent table is no-op")
    func unsubscribeNonExistent() async {
        let supabase = SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "dummy-key"
        )

        let manager = RealtimeSubscriptionManager(
            supabase: supabase,
            userId: UUID(),
            onRemoteChange: { _, _ in }
        )

        // Should not crash
        await manager.unsubscribe(from: "nonexistent_table")

        let subscribedTables = await manager.subscribedTables
        #expect(subscribedTables.isEmpty)
    }
}

// MARK: - SyncManager Realtime Integration Tests

@Suite("SyncManager Realtime Integration Tests")
struct SyncManagerRealtimeTests {

    @Test("stopRealtime when not started is no-op")
    func stopRealtimeWhenNotStarted() async throws {
        let dbQueue = try DatabaseQueue()
        let supabase = SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "dummy-key"
        )
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase,
            timestampStorage: storage
        )

        // Should not crash
        await manager.stopRealtime()
    }

    @Test("startRealtime without userId does nothing")
    func startRealtimeWithoutUserId() async throws {
        let dbQueue = try DatabaseQueue()
        let supabase = SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "dummy-key"
        )
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase,
            timestampStorage: storage
        )

        manager.register(TestItem.self)

        // Should not crash, just return early
        try await manager.startRealtime()

        // Stop should also be safe
        await manager.stopRealtime()
    }

    @Test("clearSyncState stops realtime and resets echo cache")
    func clearSyncStateStopsRealtime() async throws {
        let dbQueue = try DatabaseQueue()
        let supabase = SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "dummy-key"
        )
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase,
            timestampStorage: storage
        )

        // Set up state
        manager.setUserId(UUID())
        manager.setSyncingEnabled(true)
        await storage.setLastSyncTimestamp(Date(), for: "test")

        // Clear state - should stop realtime internally
        await manager.clearSyncState()

        #expect(manager.userId == nil)
        #expect(manager.syncingEnabled == false)
        #expect(await storage.getLastSyncTimestamp(for: "test") == nil)
    }
}
