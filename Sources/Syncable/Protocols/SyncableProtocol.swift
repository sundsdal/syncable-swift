import Foundation
import GRDB

/// Protocol that models must conform to for synchronization with GRDB and Supabase.
///
/// Any GRDB model that needs to be synced across devices should conform to this protocol.
/// The protocol ensures models have the necessary fields for conflict resolution and soft deletion.
///
/// ## Usage
/// Just define your model with standard Swift camelCase properties - no CodingKeys needed:
/// ```swift
/// struct Todo: SyncableProtocol {
///     var id: UUID
///     var userId: UUID?
///     var updatedAt: Date
///     var deleted: Bool
///     var syncedAt: Date?  // Local-only, tracks last successful sync
///     var title: String
/// }
/// ```
///
/// ## Automatic snake_case Conversion
/// The library automatically converts between Swift camelCase and PostgreSQL snake_case
/// when syncing with Supabase. You don't need to think about it:
/// - Your Swift code uses `userId`, `updatedAt`
/// - Your local SQLite uses `userId`, `updatedAt` (camelCase)
/// - Supabase uses `user_id`, `updated_at` (snake_case) - handled by the library
///
/// ## Local SQLite Schema (camelCase)
/// Use standard Swift naming in your local database:
/// ```swift
/// try db.create(table: "todos") { t in
///     t.column("id", .text).primaryKey()
///     t.column("userId", .text)
///     t.column("updatedAt", .datetime).notNull()
///     t.column("deleted", .boolean).notNull()
///     t.column("syncedAt", .datetime)  // Local-only
///     t.column("title", .text).notNull()
/// }
/// ```
///
/// ## Supabase Schema (snake_case)
/// Your Supabase table uses standard PostgreSQL conventions:
/// ```sql
/// CREATE TABLE todos (
///     id UUID PRIMARY KEY,
///     user_id UUID NOT NULL,
///     updated_at TIMESTAMPTZ NOT NULL,
///     deleted BOOLEAN NOT NULL DEFAULT false,
///     title TEXT NOT NULL
///     -- Note: no synced_at column - it's local-only
/// );
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

    /// Timestamp when this record was last successfully synced to backend (local-only field)
    /// A record is "dirty" if syncedAt is nil OR updatedAt > syncedAt
    /// This field should NOT be included in Supabase table schema - it's client-side only
    var syncedAt: Date? { get set }

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

/// Column expressions for common Syncable fields.
/// Use these when building GRDB queries on Syncable types.
/// These match Swift property names - use camelCase in your SQLite schema.
public enum SyncableColumns: String, ColumnExpression {
    case id
    case userId
    case updatedAt
    case deleted
    case syncedAt
}
