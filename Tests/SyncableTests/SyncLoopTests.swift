import Testing
import Foundation
import GRDB
import Supabase
@testable import Syncable

@Suite("ExponentialBackoff Tests")
struct ExponentialBackoffTests {

    @Test("Initial backoff equals initialDelay")
    func initialBackoffEqualsInitialDelay() {
        let backoff = ExponentialBackoff(initialDelay: 2.0)
        #expect(backoff.currentDelay == 2.0)
    }

    @Test("Backoff doubles on failure")
    func backoffDoublesOnFailure() {
        var backoff = ExponentialBackoff(initialDelay: 1.0)

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

    @Test("Backoff caps at maxDelay")
    func backoffCapsAtMaxDelay() {
        var backoff = ExponentialBackoff(initialDelay: 1.0, maxDelay: 10.0)

        // 1 -> 2 -> 4 -> 8 -> 10 (capped)
        _ = backoff.recordFailure() // 1 -> 2
        _ = backoff.recordFailure() // 2 -> 4
        _ = backoff.recordFailure() // 4 -> 8
        _ = backoff.recordFailure() // 8 -> 10 (capped)

        #expect(backoff.currentDelay == 10.0)

        // Should stay at max
        _ = backoff.recordFailure()
        #expect(backoff.currentDelay == 10.0)
    }

    @Test("Reset returns to initialDelay")
    func resetReturnsToInitialDelay() {
        var backoff = ExponentialBackoff(initialDelay: 1.0)

        _ = backoff.recordFailure()
        _ = backoff.recordFailure()
        _ = backoff.recordFailure()
        #expect(backoff.currentDelay == 8.0)

        backoff.reset()
        #expect(backoff.currentDelay == 1.0)
    }

    @Test("Custom initialDelay is preserved after reset")
    func customInitialDelayPreservedAfterReset() {
        var backoff = ExponentialBackoff(initialDelay: 5.0, maxDelay: 60.0)

        _ = backoff.recordFailure()
        #expect(backoff.currentDelay == 10.0)

        backoff.reset()
        #expect(backoff.currentDelay == 5.0)
    }
}

@Suite("NetworkMonitor Tests")
struct NetworkMonitorTests {

    @Test("Initial state is connected")
    func initialStateIsConnected() {
        let monitor = NetworkMonitor()
        #expect(monitor.isConnected == true)
    }

    @Test("Monitor can be started and stopped without crash")
    func canStartAndStop() {
        let monitor = NetworkMonitor()
        var callbackFired = false

        monitor.start {
            callbackFired = true
        }

        // Give monitor time to initialize
        Thread.sleep(forTimeInterval: 0.1)

        monitor.stop()

        // We can't easily test the callback firing without actually changing network state,
        // but we can verify the monitor doesn't crash on start/stop
        #expect(callbackFired == false) // Callback should not fire if network didn't change
    }
}

@Suite("Sync Loop Tests")
struct SyncLoopTests {

    @Test("syncInterval default is 30 seconds")
    func syncIntervalDefault() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        #expect(manager.syncInterval == 30.0)
    }

    @Test("syncInterval can be set")
    func syncIntervalCanBeSet() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        manager.syncInterval = 60.0
        #expect(manager.syncInterval == 60.0)
    }

    @Test("startSyncLoop sets interval")
    func startSyncLoopSetsInterval() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        manager.startSyncLoop(interval: 15.0)
        #expect(manager.syncInterval == 15.0)

        // Clean up
        manager.stopSyncLoop()
    }

    @Test("stopSyncLoop can be called multiple times safely")
    func stopSyncLoopIdempotent() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        manager.startSyncLoop(interval: 5.0)

        // Multiple stops should not crash
        manager.stopSyncLoop()
        manager.stopSyncLoop()
        manager.stopSyncLoop()
    }

    @Test("clearSyncState stops sync loop")
    func clearSyncStateStopsSyncLoop() async throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        manager.setUserId(UUID())
        manager.setSyncingEnabled(true)
        manager.startSyncLoop(interval: 5.0)

        await manager.clearSyncState()

        // After clearSyncState, all state should be reset
        #expect(manager.userId == nil)
        #expect(manager.syncingEnabled == false)
        #expect(manager.syncStatus == .idle)
    }

    @Test("Sync loop can start and stop cleanly")
    func syncLoopStartStopCleanly() throws {
        let dbQueue = try DatabaseQueue()
        let supabase = MockSupabaseClient()
        let storage = InMemorySyncTimestampStorage()

        let manager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase.client,
            timestampStorage: storage
        )

        // Start loop
        manager.startSyncLoop(interval: 0.1)

        // Wait a bit
        Thread.sleep(forTimeInterval: 0.05)

        // Stop loop
        manager.stopSyncLoop()

        // Should complete without issues
    }
}

// MARK: - Test Helpers

// MockSupabaseClient is defined in SyncManagerTests.swift
