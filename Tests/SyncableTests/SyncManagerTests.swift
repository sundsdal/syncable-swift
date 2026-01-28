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
    func setUserIdWorks() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        let userId = UUID()
        manager.setUserId(userId)

        #expect(manager.userId == userId)
    }

    @Test("setSyncingEnabled updates syncingEnabled")
    func setSyncingEnabledWorks() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        #expect(manager.syncingEnabled == false)
        manager.setSyncingEnabled(true)
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
        manager.setUserId(UUID())
        manager.setSyncingEnabled(true)
        await storage.setLastSyncTimestamp(Date(), for: "test")

        // Clear state
        await manager.clearSyncState()

        #expect(manager.userId == nil)
        #expect(manager.syncingEnabled == false)
        #expect(await storage.getLastSyncTimestamp(for: "test") == nil)
    }

    @Test("syncStatus starts as idle")
    func syncStatusStartsIdle() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        #expect(manager.syncStatus == .idle)
        #expect(manager.lastSyncTime == nil)
    }

    @Test("Statistics start at zero")
    func statisticsStartAtZero() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        #expect(manager.nSyncedToBackend == 0)
        #expect(manager.nSyncedFromBackend == 0)
    }

    @Test("resetStatistics clears counters")
    func resetStatisticsWorks() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        // We can't easily simulate actual sync without mocking Supabase,
        // but we can verify resetStatistics works
        manager.resetStatistics()

        #expect(manager.nSyncedToBackend == 0)
        #expect(manager.nSyncedFromBackend == 0)
    }

    @Test("clearSyncState resets statistics")
    func clearSyncStateResetsStatistics() async throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        // Clear state should reset statistics
        await manager.clearSyncState()

        #expect(manager.nSyncedToBackend == 0)
        #expect(manager.nSyncedFromBackend == 0)
    }

    @Test("fillMissingUserIdForLocalTables assigns userId to orphaned records")
    func fillMissingUserIdAssignsOrphans() async throws {
        let dbQueue = try makeTestDatabase()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )
        manager.register(TestItem.self)

        // Create orphaned items (userId = nil, simulating anonymous user)
        let orphan1 = TestItem(userId: nil, title: "Orphan 1")
        let orphan2 = TestItem(userId: nil, title: "Orphan 2")
        let existingUserId = UUID()
        let owned = TestItem(userId: existingUserId, title: "Already Owned")

        try await dbQueue.write { db in
            try orphan1.insert(db)
            try orphan2.insert(db)
            try owned.insert(db)
        }

        // Set user and claim orphans
        let newUserId = UUID()
        manager.setUserId(newUserId)
        let count = try await manager.fillMissingUserIdForLocalTables()

        #expect(count == 2)

        // Verify orphans now have the new userId
        let items = try await dbQueue.read { db in
            try TestItem.fetchAll(db)
        }

        let claimedOrphan1 = items.first { $0.id == orphan1.id }
        let claimedOrphan2 = items.first { $0.id == orphan2.id }
        let unchanged = items.first { $0.id == owned.id }

        #expect(claimedOrphan1?.userId == newUserId)
        #expect(claimedOrphan2?.userId == newUserId)
        #expect(unchanged?.userId == existingUserId) // Should not be changed
    }

    @Test("fillMissingUserIdForLocalTables marks orphans as dirty")
    func fillMissingUserIdMarksDirty() async throws {
        let dbQueue = try makeTestDatabase()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )
        manager.register(TestItem.self)

        // Create orphaned item that was previously synced
        let syncTime = Date().addingTimeInterval(-100)
        let orphan = TestItem(userId: nil, updatedAt: syncTime, syncedAt: syncTime, title: "Orphan")

        try await dbQueue.write { db in
            try orphan.insert(db)
        }

        // Claim orphan
        let userId = UUID()
        manager.setUserId(userId)
        _ = try await manager.fillMissingUserIdForLocalTables()

        // Verify orphan is now dirty (syncedAt = nil, updatedAt updated)
        let claimed = try await dbQueue.read { db in
            try TestItem.fetchOne(db, key: orphan.id)
        }

        #expect(claimed?.syncedAt == nil)
        #expect(claimed?.updatedAt ?? Date.distantPast > syncTime)
    }

    @Test("fillMissingUserIdForLocalTables returns 0 when no userId set")
    func fillMissingUserIdNoUserIdReturnsZero() async throws {
        let dbQueue = try makeTestDatabase()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )
        manager.register(TestItem.self)

        // Create orphaned item
        let orphan = TestItem(userId: nil, title: "Orphan")
        try await dbQueue.write { db in
            try orphan.insert(db)
        }

        // Don't set userId - should return 0
        let count = try await manager.fillMissingUserIdForLocalTables()
        #expect(count == 0)

        // Orphan should still be null
        let item = try await dbQueue.read { db in
            try TestItem.fetchOne(db, key: orphan.id)
        }
        #expect(item?.userId == nil)
    }

    @Test("fillMissingUserIdForLocalTables returns 0 when no orphans")
    func fillMissingUserIdNoOrphansReturnsZero() async throws {
        let dbQueue = try makeTestDatabase()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )
        manager.register(TestItem.self)

        // Create item with userId (not an orphan)
        let owned = TestItem(userId: UUID(), title: "Owned")
        try await dbQueue.write { db in
            try owned.insert(db)
        }

        // Set userId and try to claim
        manager.setUserId(UUID())
        let count = try await manager.fillMissingUserIdForLocalTables()
        #expect(count == 0)
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
