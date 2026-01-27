import Foundation
import GRDB

/// Protocol that models must conform to for synchronization with GRDB and Supabase.
///
/// Any GRDB model that needs to be synced across devices should conform to this protocol.
/// The protocol ensures models have the necessary fields for conflict resolution and soft deletion.
///
/// ## Usage
/// ```swift
/// struct Todo: SyncableProtocol {
///     var id: UUID
///     var userId: UUID?
///     var updatedAt: Date
///     var deleted: Bool
///     var title: String
///
///     // GRDB column mapping
///     enum Columns: String, ColumnExpression {
///         case id, userId, updatedAt, deleted, title
///     }
/// }
/// ```
///
/// ## Clock Skew Warning (V1 Limitation)
/// This library uses Last-Write-Wins (LWW) conflict resolution based on `updatedAt`.
/// Client devices with drifted clocks may cause unexpected conflict outcomes.
/// A device with a clock set 5 minutes ahead will "win" against valid updates from other devices.
/// The server-side `discard_older_updates` trigger protects server state, but cannot fix
/// incorrectly timestamped client updates.
public protocol SyncableProtocol: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    /// Unique identifier for the record
    var id: UUID { get }

    /// The user who owns this record (for row-level security)
    /// Nullable to support anonymous users or shared records
    var userId: UUID? { get set }

    /// Timestamp of last modification (used for conflict resolution - LWW)
    var updatedAt: Date { get set }

    /// Soft delete flag - records are never hard deleted during sync
    var deleted: Bool { get set }

    /// The name of the database table (and Supabase table) for this model
    static var databaseTableName: String { get }
}

/// Extension providing default table name
public extension SyncableProtocol {
    /// Default table name derived from type name (e.g., Todo -> "todos")
    static var databaseTableName: String {
        String(describing: Self.self).lowercased() + "s"
    }
}

/// Column expressions for common Syncable fields
/// Use these when building GRDB queries on Syncable types
public enum SyncableColumns: String, ColumnExpression {
    case id
    case userId
    case updatedAt
    case deleted
}
