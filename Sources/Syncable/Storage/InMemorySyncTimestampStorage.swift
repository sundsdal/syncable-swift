import Foundation

/// In-memory implementation of sync timestamp storage.
///
/// Useful for testing or when persistence isn't needed.
/// Timestamps are lost when the app terminates.
public actor InMemorySyncTimestampStorage: SyncTimestampStorage {
    private var timestamps: [String: Date] = [:]

    public init() {}

    public func getLastSyncTimestamp(for tableName: String) -> Date? {
        timestamps[tableName]
    }

    public func setLastSyncTimestamp(_ timestamp: Date, for tableName: String) {
        timestamps[tableName] = timestamp
    }

    public func clearAll() {
        timestamps.removeAll()
    }
}
