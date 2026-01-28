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
