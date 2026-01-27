import Foundation

/// Protocol for storing sync timestamps per table.
///
/// Implementations persist the last successful sync time for each table,
/// allowing incremental syncs that only fetch records updated since the last sync.
public protocol SyncTimestampStorage: Sendable {
    /// Get the last sync timestamp for a table
    /// - Parameter tableName: The name of the table
    /// - Returns: The last sync timestamp, or nil if never synced
    func getLastSyncTimestamp(for tableName: String) async -> Date?

    /// Set the last sync timestamp for a table
    /// - Parameters:
    ///   - timestamp: The timestamp to store
    ///   - tableName: The name of the table
    func setLastSyncTimestamp(_ timestamp: Date, for tableName: String) async

    /// Clear all stored timestamps (used when user logs out)
    func clearAll() async
}
