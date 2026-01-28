import Foundation
import GRDB
import Syncable

/// A simple Todo model demonstrating SyncableProtocol conformance.
/// No CodingKeys needed - the library handles camelCase ↔ snake_case conversion.
struct Todo: SyncableProtocol {
    // MARK: - Required Syncable Fields

    var id: UUID
    var userId: UUID?
    var updatedAt: Date
    var deleted: Bool
    var syncedAt: Date?

    // MARK: - Custom Fields

    var title: String
    var isCompleted: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        title: String,
        isCompleted: Bool = false,
        updatedAt: Date = Date(),
        deleted: Bool = false,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.syncedAt = syncedAt
    }

    // MARK: - Table Name

    static var databaseTableName: String { "todos" }

    // MARK: - GRDB Column Mapping (camelCase to match local schema)

    enum Columns: String, ColumnExpression {
        case id
        case userId
        case updatedAt
        case deleted
        case syncedAt
        case title
        case isCompleted
    }
}

// MARK: - Database Schema

extension Todo {
    /// Create the todos table in the database (local GRDB schema)
    /// Column names use camelCase - the library converts to snake_case for Supabase
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            // Syncable required columns (TEXT for UUIDs)
            t.column("id", .text).primaryKey()
            t.column("userId", .text)
            t.column("updatedAt", .datetime).notNull()
            t.column("deleted", .boolean).notNull().defaults(to: false)
            t.column("syncedAt", .datetime)  // Local-only, not in Supabase

            // Custom columns
            t.column("title", .text).notNull()
            t.column("isCompleted", .boolean).notNull().defaults(to: false)
        }
    }
}

// MARK: - Convenience Methods

extension Todo {
    /// Mark this todo as completed and update timestamp
    mutating func complete() {
        isCompleted = true
        updatedAt = Date()
    }

    /// Mark this todo as deleted (soft delete) and update timestamp
    mutating func markDeleted() {
        deleted = true
        updatedAt = Date()
    }
}
