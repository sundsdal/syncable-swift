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
/// syncManager.setUserId(currentUser.id)
/// syncManager.setSyncingEnabled(true)
///
/// // Trigger sync
/// try await syncManager.sync()
/// ```
///
/// ## Thread Safety
/// This class is marked `@unchecked Sendable` because thread safety is manually managed via `NSLock`.
/// All mutable state (`_userId`, `_syncingEnabled`, `_syncStatus`, `registrations`) is protected by `lock`.
/// Maintainers must acquire `lock` before reading or writing any of these properties.
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
    private var _syncStatus: SyncStatus = .idle
    private var _lastSyncTime: Date?
    private var _onStatusChange: ((SyncStatus) -> Void)?

    // MARK: - Sync Loop State (protected by lock)

    private var _syncInterval: TimeInterval = 30.0
    private var _backoff = ExponentialBackoff()
    private var syncLoopTask: Task<Void, Never>?
    private var networkMonitor: NetworkMonitor?

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
    public func setUserId(_ userId: UUID?) {
        lock.withLock { _userId = userId }
    }

    /// Enable or disable syncing
    public func setSyncingEnabled(_ enabled: Bool) {
        lock.withLock { _syncingEnabled = enabled }
    }

    /// Current sync status
    public var syncStatus: SyncStatus {
        lock.withLock { _syncStatus }
    }

    /// Last successful sync time
    public var lastSyncTime: Date? {
        lock.withLock { _lastSyncTime }
    }

    /// Register a callback to be notified of sync status changes
    public func onStatusChange(_ callback: @escaping (SyncStatus) -> Void) {
        lock.withLock { _onStatusChange = callback }
    }

    private func updateStatus(_ status: SyncStatus) {
        let callback: ((SyncStatus) -> Void)? = lock.withLock {
            _syncStatus = status
            return _onStatusChange
        }
        callback?(status)
    }

    /// The interval between automatic sync attempts in seconds
    public var syncInterval: TimeInterval {
        get { lock.withLock { _syncInterval } }
        set { lock.withLock { _syncInterval = newValue } }
    }

    // MARK: - Sync Loop

    /// Start the background sync loop with periodic sync attempts.
    ///
    /// The sync loop will:
    /// - Sync immediately on start, then at the specified interval
    /// - Automatically sync when network connectivity is restored
    /// - Apply exponential backoff on failures (1s → 2s → 4s → ... → 60s max)
    ///
    /// - Parameter interval: Time between sync attempts in seconds (default: 30)
    public func startSyncLoop(interval: TimeInterval = 30.0) {
        stopSyncLoop()  // Cancel any existing loop first
        lock.withLock { _syncInterval = interval }

        // Start network monitor
        let monitor = NetworkMonitor()
        monitor.start { [weak self] in
            Task { try? await self?.sync() }
        }
        lock.withLock { networkMonitor = monitor }

        // Start periodic sync task
        syncLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                do {
                    try await self.sync()
                    self.lock.withLock { self._backoff.reset() }
                } catch {
                    // On failure, wait backoff delay then retry (no interval wait)
                    let delay = self.lock.withLock { self._backoff.recordFailure() }
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                guard !Task.isCancelled else { break }

                // On success, wait interval before next sync
                let interval = self.lock.withLock { self._syncInterval }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Stop the background sync loop
    public func stopSyncLoop() {
        syncLoopTask?.cancel()
        syncLoopTask = nil
        lock.withLock {
            networkMonitor?.stop()
            networkMonitor = nil
            _backoff.reset()
        }
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

        updateStatus(.syncing)

        let currentRegistrations = lock.withLock { registrations }

        do {
            for (_, registration) in currentRegistrations {
                try await push(registration: registration)
                try await pull(registration: registration)
            }
            lock.withLock { _lastSyncTime = Date() }
            updateStatus(.idle)
        } catch {
            updateStatus(.failed(error))
            throw error
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

        // Fetch dirty items using per-row tracking (syncedAt is nil OR updatedAt > syncedAt)
        let dirtyItems: [any SyncableProtocol] = try await dbWriter.read { db in
            try registration.fetchDirty(db, currentUserId, maxRows)
        }

        guard !dirtyItems.isEmpty else { return }

        // Encode items as array of AnyJSON for Supabase
        // TODO: Optimize double encoding overhead - currently: Model -> Data -> AnyJSON -> Data
        // Consider having registration return a type-erased Encodable wrapper instead
        var jsonArray: [AnyJSON] = []
        let decoder = JSONDecoder()
        for item in dirtyItems {
            let data = try registration.encode(item)
            let json = try decoder.decode(AnyJSON.self, from: data)
            jsonArray.append(json)
        }

        // Upsert to Supabase
        try await supabaseClient
            .from(tableName)
            .upsert(jsonArray)
            .execute()

        // Mark successfully synced items (per-row tracking prevents data loss)
        let syncedIds = dirtyItems.map(\.id)
        try await dbWriter.write { db in
            try registration.markAsSynced(syncedIds, db)
        }
    }

    private func pull(registration: SyncableRegistration) async throws {
        guard let currentUserId = userId else { return }

        let tableName = registration.tableName
        let lastPullKey = "lastPull_\(tableName)"
        let lastPullIdKey = "lastPullId_\(tableName)"

        // Key-set pagination state
        let lastPulledTime = await timestampStorage.getLastSyncTimestamp(for: lastPullKey)
        let lastPulledIdString = UserDefaults.standard.string(forKey: lastPullIdKey)
        let lastPulledId = lastPulledIdString.flatMap { UUID(uuidString: $0) }

        // Build query with key-set pagination to avoid missing records at timestamp boundaries
        // Filter: (updated_at > lastPulled) OR (updated_at = lastPulled AND id > lastPulledId)
        var query = supabaseClient
            .from(tableName)
            .select()
            .eq("user_id", value: currentUserId.uuidString)

        if let lastPulledTime {
            if let lastPulledId {
                // Key-set pagination: get records after the cursor (time, id)
                query = query.or("updated_at.gt.\(lastPulledTime.iso8601String),and(updated_at.eq.\(lastPulledTime.iso8601String),id.gt.\(lastPulledId.uuidString))")
            } else {
                query = query.gt("updated_at", value: lastPulledTime.iso8601String)
            }
        }

        let response = try await query
            .order("updated_at", ascending: true)
            .order("id", ascending: true)
            .limit(maxRows)
            .execute()

        guard !response.data.isEmpty else { return }

        // Parse the array of items
        guard let jsonArray = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] else {
            throw SyncError.decodingFailed("Failed to parse JSON array from Supabase response")
        }

        // Process items and track cursor for key-set pagination
        var itemsToUpsert: [any SyncableProtocol] = []
        var lastItem: (any SyncableProtocol)?

        for jsonObject in jsonArray {
            let itemData = try JSONSerialization.data(withJSONObject: jsonObject)
            let item = try registration.decode(itemData)
            itemsToUpsert.append(item)
            lastItem = item
        }

        // Upsert all items in a single write transaction
        let items = itemsToUpsert // Capture for closure
        try await dbWriter.write { db in
            for item in items {
                try registration.upsertIfNewer(item, db)
            }
        }

        // Update key-set pagination cursor
        if let lastItem {
            await timestampStorage.setLastSyncTimestamp(lastItem.updatedAt, for: lastPullKey)
            UserDefaults.standard.set(lastItem.id.uuidString, forKey: lastPullIdKey)
        }
    }

    // MARK: - Utilities

    /// Clear all sync timestamps (call when user logs out)
    public func clearSyncState() async {
        stopSyncLoop()
        await timestampStorage.clearAll()

        // Clear key-set pagination cursor IDs from UserDefaults
        let tables = lock.withLock { Array(registrations.keys) }
        for tableName in tables {
            UserDefaults.standard.removeObject(forKey: "lastPullId_\(tableName)")
        }

        lock.withLock {
            _userId = nil
            _syncingEnabled = false
            _syncStatus = .idle
            _lastSyncTime = nil
        }
    }
}

// MARK: - Sync Status

/// Represents the current state of synchronization
public enum SyncStatus: Equatable, Sendable {
    /// No sync operation in progress
    case idle
    /// Sync operation is currently running
    case syncing
    /// Last sync operation failed with an error
    case failed(Error)

    public static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
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

// MARK: - Array Chunking Helper

private extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
