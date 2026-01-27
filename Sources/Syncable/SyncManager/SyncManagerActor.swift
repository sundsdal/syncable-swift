import Foundation
import SwiftData
import Supabase

/// The sync state observable from the main thread
@Observable
@MainActor
public final class SyncState: Sendable {
    public private(set) var status: SyncStatus = .idle
    public private(set) var lastSyncDate: Date?
    public private(set) var pendingChangesCount: Int = 0
    public private(set) var failedItemsCount: Int = 0

    public init() {}

    nonisolated func update(
        status: SyncStatus? = nil,
        lastSyncDate: Date? = nil,
        pendingChangesCount: Int? = nil,
        failedItemsCount: Int? = nil
    ) {
        Task { @MainActor in
            if let status { self.status = status }
            if let lastSyncDate { self.lastSyncDate = lastSyncDate }
            if let pendingChangesCount { self.pendingChangesCount = pendingChangesCount }
            if let failedItemsCount { self.failedItemsCount = failedItemsCount }
        }
    }
}

/// Synchronization status
public enum SyncStatus: Sendable, Equatable {
    case idle
    case syncing
    case error(String)
    case offline
}

/// The core sync engine running on a background actor.
///
/// Performs all database operations off the main thread, preventing UI blocking
/// during heavy sync operations.
///
/// ## Architecture
/// - Runs on dedicated background executor with private ModelContext
/// - Observes local changes via NSManagedObjectContextDidSave notifications
/// - Uses persistent dirty flags (needsSync) for crash resilience
/// - Implements dead letter queue for poison pill handling
public actor SyncManagerActor: ModelActor {
    /// ModelActor requirements
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer

    /// Observable state for UI binding (MainActor-isolated)
    public nonisolated let state: SyncState

    /// Supabase client for backend operations
    private let supabase: SupabaseClient

    /// Storage for sync timestamps
    private let timestampStorage: SyncTimestampStorage

    /// User ID for RLS filtering
    private let userId: UUID

    /// Registered syncable types
    private var registrations: [String: AnySyncableRegistration] = [:]

    /// Items that have exceeded max retries (dead letter queue)
    private var deadLetterQueue: [SyncQueueItem] = []

    /// Whether sync is currently in progress
    private var isSyncing = false

    /// JSON encoder configured for Supabase
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    /// JSON decoder configured for Supabase
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    public init(
        modelContainer: ModelContainer,
        supabase: SupabaseClient,
        userId: UUID,
        state: SyncState,
        timestampStorage: SyncTimestampStorage = UserDefaultsSyncTimestampStorage()
    ) {
        let modelContext = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.supabase = supabase
        self.userId = userId
        self.timestampStorage = timestampStorage
        self.state = state
    }

    // MARK: - Registration

    /// Register a syncable type for synchronization
    public func register<T: SyncableProtocol>(_ type: T.Type) {
        let decoder = self.decoder
        let registration = SyncableRegistration<T> { data in
            try decoder.decode(T.self, from: data)
        }
        registrations[T.tableName] = AnySyncableRegistration(registration)
    }

    // MARK: - Sync Operations

    /// Perform a full sync cycle: push local changes, then pull remote changes
    public func sync() async throws {
        guard !isSyncing else { return }
        isSyncing = true
        state.update(status: .syncing)

        defer {
            isSyncing = false
            state.update(status: .idle, lastSyncDate: Date())
        }

        do {
            // Push local changes first
            try await pushLocalChanges()

            // Then pull remote changes
            try await pullRemoteChanges()

        } catch {
            state.update(status: .error(error.localizedDescription))
            throw error
        }
    }

    /// Push all records marked with needsSync to the backend
    private func pushLocalChanges() async throws {
        // This would iterate through registered types and find records with needsSync = true
        // Implementation depends on how we query SwiftData models generically
        // For now, this is a placeholder for the push logic
    }

    /// Pull changes from backend since last sync timestamp
    private func pullRemoteChanges() async throws {
        for (tableName, registration) in registrations {
            let lastSync = await timestampStorage.getLastSyncTimestamp(for: tableName)

            // Build query with timestamp filter
            var query = supabase.from(tableName)
                .select()
                .eq("user_id", value: userId.uuidString)

            if let lastSync {
                query = query.gt("updated_at", value: ISO8601DateFormatter().string(from: lastSync))
            }

            let response: [Data] = try await query.execute().value

            // Process each record
            for data in response {
                do {
                    let item = try registration.decodeToAny(data)
                    // Upsert into local database
                    try upsertLocal(item, tableName: tableName)
                } catch {
                    // Log decode errors but continue processing
                    print("Failed to decode record from \(tableName): \(error)")
                }
            }

            // Update sync timestamp
            await timestampStorage.setLastSyncTimestamp(Date(), for: tableName)
        }
    }

    /// Upsert a record into the local SwiftData store
    private func upsertLocal(_ item: AnySyncable, tableName: String) throws {
        // This needs to be implemented based on how we handle generic SwiftData inserts
        // The ModelActor pattern gives us access to modelContext
    }

    // MARK: - Dead Letter Queue

    /// Get items that have failed too many times
    public func getDeadLetterItems() -> [SyncQueueItem] {
        deadLetterQueue
    }

    /// Retry a dead letter item (resets retry count)
    public func retryDeadLetterItem(id: UUID) {
        if let index = deadLetterQueue.firstIndex(where: { $0.id == id }) {
            var item = deadLetterQueue.remove(at: index)
            item.retryCount = 0
            // Re-queue for sync
        }
    }

    /// Permanently discard a dead letter item
    public func discardDeadLetterItem(id: UUID) {
        deadLetterQueue.removeAll { $0.id == id }
        state.update(failedItemsCount: deadLetterQueue.count)
    }
}
