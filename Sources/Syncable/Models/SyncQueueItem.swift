import Foundation

/// Represents an item in the sync queue with retry tracking.
///
/// Used internally to track sync attempts and handle poison pills.
public struct SyncQueueItem: Sendable, Identifiable {
    public let id: UUID
    public let tableName: String
    public let data: Data
    public var retryCount: Int
    public var lastError: String?
    public let createdAt: Date

    public init(
        id: UUID,
        tableName: String,
        data: Data,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.tableName = tableName
        self.data = data
        self.retryCount = retryCount
        self.lastError = lastError
        self.createdAt = Date()
    }

    /// Returns a new item with incremented retry count
    public func incrementingRetry(error: String) -> SyncQueueItem {
        var copy = self
        copy.retryCount += 1
        copy.lastError = error
        return copy
    }
}

/// Status of a sync queue item
public enum SyncItemStatus: Sendable {
    case pending
    case inProgress
    case completed
    case failed(reason: String)
}
