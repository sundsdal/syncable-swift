# Syncable-Swift Technical Design (GRDB Edition)

A Swift-native implementation of [Mr-Pepe/syncable](https://github.com/Mr-Pepe/syncable) for offline-first multi-device data synchronization, built on **GRDB.swift**.

## Overview

Syncable-Swift provides bidirectional synchronization between a local SQLite database (via GRDB) and a Supabase backend. It uses a **last-write-wins (LWW)** conflict resolution strategy based on `updatedAt` timestamps and leverages SQLite's WAL mode for high-performance concurrency.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SyncManager                              │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐    │
│  │  Change      │  │  InQueue     │  │  Sync Loop         │    │
│  │  Observer    │  │  (BE→local)  │  │  (background)      │    │
│  └──────────────┘  └──────────────┘  └────────────────────┘    │
│         ↑                 ↓                    ↕                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Registered Syncables                        │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         ↑                                        ↓
┌─────────────────┐                    ┌─────────────────────────┐
│   GRDB          │                    │   Supabase              │
│   DatabasePool  │                    │   - REST API (upsert)   │
│   (SQLite)      │                    │   - Realtime (Postgres) │
└─────────────────┘                    └─────────────────────────┘
```

## Core Components

### 1. SyncableProtocol

Every model that needs synchronization must conform to `SyncableProtocol`, which combines GRDB's record protocols:

```swift
import GRDB

public protocol SyncableProtocol: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: UUID { get }
    var userId: UUID? { get set }
    var updatedAt: Date { get set }
    var deleted: Bool { get set }
    var syncedAt: Date? { get set }  // Local-only: tracks sync state

    static var databaseTableName: String { get }
}
```

**Required properties:**
- `id`: UUID primary key for strong typing
- `userId`: Owner's user ID (nullable for anonymous/shared records)
- `updatedAt`: UTC timestamp for conflict resolution
- `deleted`: Soft-delete flag (items are never hard-deleted from the sync perspective)

**Example Implementation:**

```swift
struct Todo: SyncableProtocol {
    var id: UUID
    var userId: UUID?
    var updatedAt: Date
    var deleted: Bool
    var syncedAt: Date?  // Local-only
    var title: String
    var isCompleted: Bool

    // CodingKeys for snake_case (PostgreSQL convention)
    enum CodingKeys: String, CodingKey {
        case id, deleted, title
        case userId = "user_id"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
        case isCompleted = "is_completed"
    }

    // Optional: custom table name (default derived from type name)
    // static var databaseTableName: String { "todos" }
}
```

### 2. SyncTimestampStorage Protocol

Interface for persisting sync timestamps across app restarts:

```swift
public protocol SyncTimestampStorage: Sendable {
    func getLastSyncTimestamp(for tableName: String) async -> Date?
    func setLastSyncTimestamp(_ timestamp: Date, for tableName: String) async
    func clearAll() async
}
```

**Implementations:**
- `InMemorySyncTimestampStorage` - For testing
- `UserDefaultsSyncTimestampStorage` - For production use

### 3. SyncableRegistration

Type-erased registration for Syncable types:

```swift
public struct SyncableRegistration: Sendable {
    public let tableName: String
    let decode: @Sendable (Data) throws -> any SyncableProtocol
    let fetchAll: @Sendable (Database, UUID?) throws -> [any SyncableProtocol]
    let fetchDirty: @Sendable (Database, UUID?, Int) throws -> [any SyncableProtocol]
    let markAsSynced: @Sendable ([UUID], Database) throws -> Void
    let upsertIfNewer: @Sendable (any SyncableProtocol, Database) throws -> Void
    let encode: @Sendable (any SyncableProtocol) throws -> Data
    let assignUserIdToOrphans: @Sendable (UUID, Database) throws -> Int

    public static func create<T: SyncableProtocol>(_ type: T.Type) -> SyncableRegistration
}
```

**Key operations:**
- `fetchDirty`: Finds records where `syncedAt IS NULL OR updatedAt > syncedAt`
- `markAsSynced`: Sets `syncedAt = updatedAt` for successfully pushed records
- `upsertIfNewer`: Applies LWW conflict resolution on pull
- `assignUserIdToOrphans`: Claims anonymous records when user signs in

### 4. SyncManager

The central coordinator for sync operations:

```swift
public final class SyncManager: @unchecked Sendable {
    private let dbWriter: any DatabaseWriter
    private let supabaseClient: SupabaseClient
    private let timestampStorage: SyncTimestampStorage
    public let maxRows: Int

    public init(
        dbWriter: any DatabaseWriter,
        supabaseClient: SupabaseClient,
        timestampStorage: SyncTimestampStorage,
        maxRows: Int = 100
    )

    // Registration
    public func register<T: SyncableProtocol>(_ type: T.Type)

    // State management
    public func setUserId(_ userId: UUID?) async
    public func setSyncingEnabled(_ enabled: Bool) async
    public func clearSyncState() async

    // Sync operations
    public func sync() async throws
    public func push<T: SyncableProtocol>(_ type: T.Type) async throws
    public func pull<T: SyncableProtocol>(_ type: T.Type) async throws
}
```

## Synchronization Algorithm

### Outgoing Sync (Local → Backend)

The push operation uses per-record `syncedAt` tracking to find dirty records:

```swift
private func push(registration: SyncableRegistration) async throws {
    // Fetch dirty items: syncedAt IS NULL OR updatedAt > syncedAt
    let dirtyItems = try await dbWriter.read { db in
        try registration.fetchDirty(db, currentUserId, maxRows)
    }

    guard !dirtyItems.isEmpty else { return }

    // Batch upsert to Supabase
    try await supabaseClient
        .from(tableName)
        .upsert(jsonArray)
        .execute()

    // Mark successfully pushed items as synced (sets syncedAt = updatedAt)
    let syncedIds = dirtyItems.map(\.id)
    try await dbWriter.write { db in
        try registration.markAsSynced(syncedIds, db)
    }
}
```

**Crash Resilience:** Per-record tracking means if the app crashes mid-sync, only successfully pushed records are marked as synced. Unpushed records remain dirty and will sync on restart.

### Incoming Sync (Backend → Local)

The pull operation fetches remote changes and applies LWW conflict resolution:

```swift
private func pull(registration: SyncableRegistration) async throws {
    let lastPulled = await timestampStorage.getLastSyncTimestamp(for: "lastPull_\(tableName)")

    // Fetch from Supabase (filtered by user_id and updated_at > lastPulled)
    let response = try await supabaseClient
        .from(tableName)
        .select()
        .eq("user_id", value: currentUserId.uuidString)
        .gt("updated_at", value: lastPulled.iso8601String)
        .order("updated_at", ascending: true)
        .limit(maxRows)
        .execute()

    // Upsert with LWW in a single transaction
    try await dbWriter.write { db in
        for item in incomingItems {
            try registration.upsertIfNewer(item, db)
        }
    }

    // Update last pulled timestamp
    await timestampStorage.setLastSyncTimestamp(maxUpdatedAt, for: "lastPull_\(tableName)")
}
```

### LWW Conflict Resolution

The `upsertIfNewer` function implements Last-Write-Wins:

```swift
// Inside SyncableRegistration.create()
upsertIfNewer: { record, db in
    if let existing = try T.fetchOne(db, key: record.id) {
        if record.updatedAt > existing.updatedAt {
            try record.update(db)
        }
        // else: existing is newer, ignore incoming
    } else {
        try record.insert(db)
    }
}
```

## Optimizations

### 1. WAL Mode (Write-Ahead Logging)

GRDB's `DatabasePool` enables WAL mode, providing:
- **Concurrent Reads:** UI can read while SyncManager writes
- **Non-blocking Writes:** Background sync doesn't block main thread

### 2. Batch Processing

Both push and pull operations work in batches (`maxRows` configuration) to prevent memory issues and network timeouts.

### 3. Timestamp-based Dirty Detection

Using `updatedAt > lastPushed` eliminates the need for a separate queue table:
- No queue maintenance overhead
- Naturally crash-resilient
- Simple to reason about

## Concurrency Model

```
┌─────────────────────┐       ┌──────────────────────┐
│  Main Thread (UI)   │       │  Background Task     │
│                     │       │  (SyncManager)       │
│  [Read-Only]        │       │  [Read/Write]        │
│  ValueObservation   │◄─────►│  Sync Loop           │
│  Querying           │  WAL  │  Network Req         │
└──────────┬──────────┘       └──────────┬───────────┘
           │                             │
           ▼                             ▼
    ┌───────────────────────────────────────┐
    │           SQLite Database             │
    └───────────────────────────────────────┘
```

## Backend Requirements

Supabase tables should have:
- `id` (UUID, primary key)
- `user_id` (UUID, for RLS)
- `updated_at` (timestamp with time zone)
- `deleted` (boolean, default false)

**Note:** The `synced_at` field is local-only and should NOT be in the Supabase table.

Example Postgres table:

```sql
-- LWW conflict resolution function (create once per project)
CREATE OR REPLACE FUNCTION discard_older_updates()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.updated_at > NEW.updated_at THEN
        RETURN OLD;  -- Keep the existing (newer) row
    END IF;
    RETURN NEW;  -- Allow the update
END;
$$ LANGUAGE plpgsql;

-- Create table
CREATE TABLE todos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted BOOLEAN NOT NULL DEFAULT FALSE,
    title TEXT NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE
);

-- Indexes
CREATE INDEX todos_user_id_idx ON todos(user_id);
CREATE INDEX todos_updated_at_idx ON todos(updated_at);

-- LWW trigger
CREATE TRIGGER todos_lww_conflict_resolution
BEFORE UPDATE ON todos
FOR EACH ROW EXECUTE FUNCTION discard_older_updates();

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE todos;

-- Enable RLS
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;

-- RLS policy
CREATE POLICY "Users can manage their own todos" ON todos
    FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
```

## Dependencies

- `GRDB.swift` ^7.0.0 (SQLite wrapper)
- `supabase-swift` ^2.0.0 (Supabase client)
- Foundation
