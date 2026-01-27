import Foundation
import GRDB
import Supabase

/// Manages bidirectional sync between local GRDB database and Supabase backend.
///
/// SyncManager handles:
/// - Push: Local changes → Supabase (using updatedAt > lastPushed)
/// - Pull: Supabase changes → Local (using LWW conflict resolution)
/// - Registration of Syncable types
/// - Timestamp tracking for incremental sync
///
/// ## Usage
/// ```swift
/// let dbPool = try DatabasePool(path: "db.sqlite")
/// let supabase = SupabaseClient(supabaseURL: url, supabaseKey: key)
/// let syncManager = SyncManager(
///     dbWriter: dbPool,
///     supabaseClient: supabase,
///     timestampStorage: UserDefaultsSyncTimestampStorage()
/// )
///
/// // Register types
/// syncManager.register(Todo.self)
///
/// // Set user and enable
/// await syncManager.setUserId(currentUser.id)
/// await syncManager.setSyncingEnabled(true)
///
/// // Trigger sync
/// try await syncManager.sync()
/// ```
public final class SyncManager: @unchecked Sendable {
    // MARK: - Dependencies

    private let dbWriter: any DatabaseWriter
    private let supabaseClient: SupabaseClient
    private let timestampStorage: SyncTimestampStorage

    // MARK: - Configuration

    /// Maximum rows to sync in a single batch
    public let maxRows: Int

    // MARK: - State (protected by lock)

    private let lock = NSLock()
    private var _userId: UUID?
    private var _syncingEnabled: Bool = false

    // MARK: - Registrations

    private var registrations: [String: SyncableRegistration] = [:]

    // MARK: - Initialization

    /// Create a new SyncManager
    /// - Parameters:
    ///   - dbWriter: GRDB DatabaseWriter (DatabasePool or DatabaseQueue)
    ///   - supabaseClient: Configured Supabase client
    ///   - timestampStorage: Storage for sync timestamps
    ///   - maxRows: Maximum rows per sync batch (default: 100)
    public init(
        dbWriter: any DatabaseWriter,
        supabaseClient: SupabaseClient,
        timestampStorage: SyncTimestampStorage,
        maxRows: Int = 100
    ) {
        self.dbWriter = dbWriter
        self.supabaseClient = supabaseClient
        self.timestampStorage = timestampStorage
        self.maxRows = maxRows
    }

    // MARK: - Thread-safe property access

    /// The current user ID for sync operations
    public var userId: UUID? {
        lock.withLock { _userId }
    }

    /// Whether syncing is currently enabled
    public var syncingEnabled: Bool {
        lock.withLock { _syncingEnabled }
    }

    /// Set the current user ID
    public func setUserId(_ userId: UUID?) async {
        lock.withLock { _userId = userId }
    }

    /// Enable or disable syncing
    public func setSyncingEnabled(_ enabled: Bool) async {
        lock.withLock { _syncingEnabled = enabled }
    }

    // MARK: - Registration

    /// Register a Syncable type for synchronization
    /// - Parameter type: The Syncable type to register
    public func register<T: SyncableProtocol>(_ type: T.Type) {
        let registration = SyncableRegistration.create(type)
        lock.withLock {
            registrations[registration.tableName] = registration
        }
    }

    /// Get all registered table names
    public var registeredTables: [String] {
        lock.withLock { Array(registrations.keys) }
    }

    // MARK: - Sync Operations

    /// Perform a full sync cycle (push then pull) for all registered types
    public func sync() async throws {
        guard syncingEnabled else { return }
        guard userId != nil else { return }

        let currentRegistrations = lock.withLock { registrations }

        for (_, registration) in currentRegistrations {
            try await push(registration: registration)
            try await pull(registration: registration)
        }
    }

    /// Push local changes to Supabase for a specific type
    public func push<T: SyncableProtocol>(_ type: T.Type) async throws {
        guard let registration = lock.withLock({ registrations[T.databaseTableName] }) else {
            throw SyncError.typeNotRegistered(T.databaseTableName)
        }
        try await push(registration: registration)
    }

    /// Pull remote changes from Supabase for a specific type
    public func pull<T: SyncableProtocol>(_ type: T.Type) async throws {
        guard let registration = lock.withLock({ registrations[T.databaseTableName] }) else {
            throw SyncError.typeNotRegistered(T.databaseTableName)
        }
        try await pull(registration: registration)
    }

    // MARK: - Private Sync Implementation

    private func push(registration: SyncableRegistration) async throws {
        guard let currentUserId = userId else { return }

        let tableName = registration.tableName
        let lastPushKey = "lastPush_\(tableName)"
        let lastPushed = await timestampStorage.getLastSyncTimestamp(for: lastPushKey)

        // Fetch dirty items (updated since last push)
        let dirtyItems: [any SyncableProtocol] = try await dbWriter.read { db in
            try registration.fetchUpdatedSince(db, lastPushed, currentUserId)
        }

        guard !dirtyItems.isEmpty else { return }

        // Encode items as array of AnyJSON for Supabase
        var jsonArray: [AnyJSON] = []
        for item in dirtyItems {
            let data = try registration.encode(item)
            let json = try JSONDecoder().decode(AnyJSON.self, from: data)
            jsonArray.append(json)
        }

        // Batch upsert to Supabase
        try await supabaseClient
            .from(tableName)
            .upsert(jsonArray)
            .execute()

        // Update last pushed timestamp
        if let maxUpdatedAt = dirtyItems.map(\.updatedAt).max() {
            await timestampStorage.setLastSyncTimestamp(maxUpdatedAt, for: lastPushKey)
        }
    }

    private func pull(registration: SyncableRegistration) async throws {
        guard let currentUserId = userId else { return }

        let tableName = registration.tableName
        let lastPullKey = "lastPull_\(tableName)"
        let lastPulled = await timestampStorage.getLastSyncTimestamp(for: lastPullKey)

        // Fetch from Supabase
        var query = supabaseClient
            .from(tableName)
            .select()
            .eq("user_id", value: currentUserId.uuidString)

        if let lastPulled {
            query = query.gt("updated_at", value: lastPulled.iso8601String)
        }

        let response = try await query
            .order("updated_at", ascending: true)
            .limit(maxRows)
            .execute()

        guard !response.data.isEmpty else { return }

        // Parse the array of items
        guard let jsonArray = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] else {
            return
        }

        // Process items and track max updated date
        var itemsToUpsert: [(any SyncableProtocol, Data)] = []
        var maxUpdatedAt: Date?

        for jsonObject in jsonArray {
            let itemData = try JSONSerialization.data(withJSONObject: jsonObject)
            let item = try registration.decode(itemData)
            itemsToUpsert.append((item, itemData))

            if maxUpdatedAt == nil || item.updatedAt > maxUpdatedAt! {
                maxUpdatedAt = item.updatedAt
            }
        }

        // Upsert all items in a single write transaction
        try await dbWriter.write { db in
            for (item, _) in itemsToUpsert {
                try registration.upsertIfNewer(item, db)
            }
        }

        // Update last pulled timestamp
        if let maxUpdatedAt {
            await timestampStorage.setLastSyncTimestamp(maxUpdatedAt, for: lastPullKey)
        }
    }

    // MARK: - Utilities

    /// Clear all sync timestamps (call when user logs out)
    public func clearSyncState() async {
        await timestampStorage.clearAll()
        lock.withLock {
            _userId = nil
            _syncingEnabled = false
        }
    }
}

// MARK: - Errors

/// Errors that can occur during sync operations
public enum SyncError: Error, LocalizedError {
    case typeNotRegistered(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .typeNotRegistered(let tableName):
            return "Type '\(tableName)' is not registered with SyncManager"
        case .encodingFailed(let message):
            return "Failed to encode for sync: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode from sync: \(message)"
        case .networkError(let error):
            return "Network error during sync: \(error.localizedDescription)"
        }
    }
}
