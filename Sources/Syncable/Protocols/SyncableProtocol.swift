import Foundation

/// Protocol that models must conform to for synchronization.
///
/// Any SwiftData model that needs to be synced across devices should conform to this protocol.
/// The protocol ensures models have the necessary fields for conflict resolution and soft deletion.
///
/// ## Clock Skew Warning (V1 Limitation)
/// This library uses Last-Write-Wins (LWW) conflict resolution based on `updatedAt`.
/// Client devices with drifted clocks may cause unexpected conflict outcomes.
/// A device with a clock set 5 minutes ahead will "win" against valid updates from other devices.
/// The server-side `discard_older_updates` trigger protects server state, but cannot fix
/// incorrectly timestamped client updates.
public protocol SyncableProtocol: Identifiable, Codable, Sendable {
    /// Unique identifier for the record
    var id: UUID { get }

    /// The user who owns this record (for row-level security)
    var userId: UUID { get set }

    /// Timestamp of last modification (used for conflict resolution - LWW)
    var updatedAt: Date { get set }

    /// Soft delete flag - records are never hard deleted during sync
    var deleted: Bool { get set }

    /// Marks the record as needing sync (persisted dirty flag for crash resilience)
    /// When true, the record will be included in the next outbound sync.
    var needsSync: Bool { get set }

    /// Number of failed sync attempts (for dead letter queue handling)
    /// After maxRetries, the record is moved to failed state to unblock the queue.
    var syncRetryCount: Int { get set }

    /// The name of the Supabase table for this model
    static var tableName: String { get }

    /// Maximum retry attempts before moving to dead letter queue (default: 3)
    static var maxSyncRetries: Int { get }
}

/// Extension providing default values
public extension SyncableProtocol {
    static var tableName: String {
        String(describing: Self.self).lowercased() + "s"
    }

    static var maxSyncRetries: Int { 3 }
}
