import Foundation

/// Protocol for storing sync state per table.
///
/// Implementations persist the last successful sync time and cursor ID for each table,
/// allowing incremental syncs that only fetch records updated since the last sync.
///
/// The cursor ID is used for key-set pagination to avoid missing records at timestamp
/// boundaries when multiple records share the same `updatedAt` value.
public protocol SyncTimestampStorage: Sendable {
    /// Get the last sync timestamp for a table
    /// - Parameter key: The storage key (e.g., "lastPull_tablename")
    /// - Returns: The last sync timestamp, or nil if never synced
    func getLastSyncTimestamp(for key: String) async -> Date?

    /// Set the last sync timestamp for a table
    /// - Parameters:
    ///   - timestamp: The timestamp to store
    ///   - key: The storage key (e.g., "lastPull_tablename")
    func setLastSyncTimestamp(_ timestamp: Date, for key: String) async

    /// Get the last cursor ID for key-set pagination
    /// - Parameter key: The storage key (e.g., "lastPullId_tablename")
    /// - Returns: The last cursor ID string, or nil if not set
    func getCursorId(for key: String) async -> String?

    /// Set the cursor ID for key-set pagination
    /// - Parameters:
    ///   - cursorId: The cursor ID to store (typically a UUID string)
    ///   - key: The storage key (e.g., "lastPullId_tablename")
    func setCursorId(_ cursorId: String?, for key: String) async

    /// Clear all stored sync state (used when user logs out)
    func clearAll() async
}
