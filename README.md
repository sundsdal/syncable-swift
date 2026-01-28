# Syncable

[![Swift](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20macOS-lightgrey.svg)]()

Syncable is a library for **offline-first multi-device data synchronization** in Swift apps (iOS/macOS).

It was inspired by the [Dart/Flutter Syncable library](https://github.com/Mr-Pepe/syncable).
The library provides a `SyncManager` class that handles bidirectional data synchronization between a local SQLite database and a Supabase backend.
Conflicts are resolved using **Last-Write-Wins (LWW)** based on the `updatedAt` timestamp.

This implementation uses [GRDB.swift](https://github.com/groue/GRDB.swift) for local storage and [Supabase](https://supabase.com/) for the backend.

## Installation

Add Syncable to your Swift package dependencies:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/sundsdal/syncable-swift.git", from: "1.0.0")
]

// In your target
.target(
    name: "YourApp",
    dependencies: ["Syncable"]
)
```

## Quick Start

For a complete working example, see the [CLI Demo](Sources/SyncableDemo/) which includes:
- A complete `Todo` model ([Todo.swift](Sources/SyncableDemo/Todo.swift))
- Interactive sync operations ([SyncableDemo.swift](Sources/SyncableDemo/SyncableDemo.swift))
- Supabase migration ([migrations/](Sources/SyncableDemo/supabase/migrations/))

Run the demo:
```bash
export SUPABASE_URL=https://your-project.supabase.co
export SUPABASE_KEY=your-anon-key
swift run SyncableDemo
```

## Usage

This guide assumes familiarity with [GRDB](https://github.com/groue/GRDB.swift) and [Supabase](https://supabase.com/).

### 1. Define a Syncable Model

Every model you want to synchronize must conform to `SyncableProtocol`:

```swift
import Foundation
import GRDB
import Syncable

struct Todo: SyncableProtocol {
    // MARK: - Required Syncable Fields
    var id: UUID
    var userId: UUID?
    var updatedAt: Date
    var deleted: Bool
    var syncedAt: Date?  // Local-only: tracks sync state

    // MARK: - Your Custom Fields
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
}
```

**No `CodingKeys` needed!** The library automatically converts between Swift camelCase and PostgreSQL snake_case when syncing with Supabase.

#### Understanding `syncedAt`

The `syncedAt` field is **local-only** (not stored in Supabase) and tracks when each record was last successfully synced. A record is considered "dirty" (needs sync) when:
- `syncedAt` is `nil` (never synced), OR
- `updatedAt > syncedAt` (modified since last sync)

This per-record tracking is crash-resilient: if the app crashes mid-sync, unsynced records remain dirty and will sync on restart.

### 2. Create the Local Database Table

Create the SQLite table using GRDB with **camelCase** column names (matching your Swift properties):

```swift
import GRDB

func createTodosTable(in db: Database) throws {
    try db.create(table: "todos", ifNotExists: true) { t in
        // Required Syncable columns (TEXT for UUIDs)
        t.column("id", .text).primaryKey()
        t.column("userId", .text)
        t.column("updatedAt", .datetime).notNull()
        t.column("deleted", .boolean).notNull().defaults(to: false)
        t.column("syncedAt", .datetime)  // Local-only, NOT in Supabase

        // Your custom columns
        t.column("title", .text).notNull()
        t.column("isCompleted", .boolean).notNull().defaults(to: false)
    }
}
```

The library handles the conversion to snake_case (`user_id`, `updated_at`, etc.) when syncing with Supabase.

### 3. Set Up the Supabase Backend

Run these SQL statements in your Supabase SQL Editor:

#### 3.1 Enable Realtime (run once per project)

```sql
BEGIN;
DROP PUBLICATION IF EXISTS supabase_realtime;
CREATE PUBLICATION supabase_realtime;
COMMIT;
```

#### 3.2 Create the LWW Conflict Resolution Function (run once per project)

```sql
CREATE OR REPLACE FUNCTION discard_older_updates()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.updated_at > NEW.updated_at THEN
        RETURN OLD;  -- Keep the existing (newer) row
    END IF;
    RETURN NEW;  -- Allow the update
END;
$$ LANGUAGE plpgsql;
```

#### 3.3 Create Your Table

Supabase uses PostgreSQL conventions (snake_case). The library automatically converts between your camelCase Swift code and Supabase's snake_case:

```sql
CREATE TABLE todos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,          -- Maps to Swift: userId
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),  -- Maps to Swift: updatedAt
    deleted BOOLEAN NOT NULL DEFAULT false,
    title TEXT NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT false  -- Maps to Swift: isCompleted
);

-- Indexes for efficient queries
CREATE INDEX todos_user_id_idx ON todos(user_id);
CREATE INDEX todos_updated_at_idx ON todos(updated_at);

-- LWW conflict resolution trigger
CREATE TRIGGER todos_lww_conflict_resolution
BEFORE UPDATE ON todos
FOR EACH ROW EXECUTE FUNCTION discard_older_updates();

-- Enable Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE todos;
```

#### 3.4 Enable Row-Level Security (Recommended)

```sql
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own todos"
ON todos FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());
```

### 4. Initialize and Start Syncing

```swift
import GRDB
import Supabase
import Syncable

// 1. Create the GRDB database
let dbPath = // your database path
let dbQueue = try DatabaseQueue(path: dbPath)

// Create tables
try dbQueue.write { db in
    try createTodosTable(in: db)
}

// 2. Create the Supabase client
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://your-project.supabase.co")!,
    supabaseKey: "your-anon-key"
)

// 3. Create and configure SyncManager
let syncManager = SyncManager(
    dbWriter: dbQueue,
    supabaseClient: supabase,
    timestampStorage: UserDefaultsSyncTimestampStorage()  // Persists sync state
)

// 4. Register your syncable types
syncManager.register(Todo.self)

// 5. Set the user ID (required for sync)
syncManager.setUserId(currentUser.id)

// 6. Enable syncing
syncManager.setSyncingEnabled(true)

// 7. Start the background sync loop
syncManager.startSyncLoop(interval: 30)  // Syncs every 30 seconds

// 8. (Optional) Enable realtime for instant updates
try await syncManager.startRealtime()
```

### 5. Working with Synced Data

#### Creating Records

```swift
let todo = Todo(userId: currentUser.id, title: "Buy groceries")
try dbQueue.write { db in
    try todo.insert(db)
}
// The sync loop will automatically push this to Supabase
```

#### Updating Records

Always update `updatedAt` when modifying a record:

```swift
var todo = // fetch existing todo
todo.title = "Buy organic groceries"
todo.updatedAt = Date()  // IMPORTANT: Update the timestamp!
try dbQueue.write { db in
    try todo.update(db)
}
```

Or create helper methods:

```swift
extension Todo {
    mutating func complete() {
        isCompleted = true
        updatedAt = Date()
    }
}
```

#### Deleting Records (Soft Delete)

Records must be soft-deleted to propagate deletions across devices:

```swift
var todo = // fetch existing todo
todo.deleted = true
todo.updatedAt = Date()  // IMPORTANT: Update the timestamp!
try dbQueue.write { db in
    try todo.update(db)
}
```

#### Querying Records

Filter out deleted records in your UI queries:

```swift
let activeTodos = try dbQueue.read { db in
    try Todo
        .filter(SyncableColumns.deleted == false)
        .filter(SyncableColumns.userId == currentUser.id)
        .order(SyncableColumns.updatedAt.desc)
        .fetchAll(db)
}
```

### 6. Handle Anonymous to Authenticated Flow

If users can create data before signing in:

```swift
// User creates items while logged out (userId is nil)
let todo = Todo(userId: nil, title: "Remember to sign up")
try dbQueue.write { db in try todo.insert(db) }

// Later, when user signs in...
syncManager.setUserId(authenticatedUser.id)

// Claim orphaned records (assigns userId and marks dirty)
let claimedCount = try await syncManager.fillMissingUserIdForLocalTables()
print("Claimed \(claimedCount) records")

// Enable sync to push claimed records
syncManager.setSyncingEnabled(true)
try await syncManager.sync()
```

### 7. Monitor Sync Status

```swift
// Status change callback
syncManager.onStatusChange { status in
    switch status {
    case .idle:
        print("Sync complete")
    case .syncing:
        print("Syncing...")
    case .failed(let error):
        print("Sync failed: \(error.localizedDescription)")
    }
}

// Realtime change callback
syncManager.onRealtimeChange { tableName in
    print("Remote changes received for \(tableName)")
    // Refresh your UI
}

// Check properties
print("Syncing enabled: \(syncManager.syncingEnabled)")
print("Last sync: \(syncManager.lastSyncTime?.description ?? "never")")
print("Records pushed: \(syncManager.nSyncedToBackend)")
print("Records pulled: \(syncManager.nSyncedFromBackend)")
```

### 8. Handle Offline/Online Transitions

```swift
// Go offline (stop syncing but keep local changes)
syncManager.stopSyncLoop()
await syncManager.stopRealtime()
// Local changes are preserved and will sync when back online

// Go online
syncManager.startSyncLoop(interval: 30)
try await syncManager.startRealtime()
try await syncManager.sync()  // Immediate sync
```

### 9. Clean Up on Logout

```swift
await syncManager.clearSyncState()  // Clears timestamps, stops loops, resets state
```

## Error Handling

Sync operations can fail due to network issues or conflicts. The `SyncManager` handles this gracefully:

- **Automatic retry**: The sync loop uses exponential backoff (1s → 2s → 4s → ... → 60s max)
- **Network monitoring**: Automatically syncs when connectivity is restored
- **Per-record tracking**: If sync fails mid-batch, unsynced records remain dirty
- **Status callbacks**: Monitor failures via `onStatusChange`

```swift
do {
    try await syncManager.sync()
} catch {
    // Handle sync error
    print("Sync failed: \(error)")
    // The sync loop will retry automatically
}
```

## Optimizations

### Persistent Timestamp Storage

Use `UserDefaultsSyncTimestampStorage` to persist sync timestamps across app restarts. This enables incremental sync (only changed records) instead of full sync on every launch:

```swift
let syncManager = SyncManager(
    dbWriter: dbQueue,
    supabaseClient: supabase,
    timestampStorage: UserDefaultsSyncTimestampStorage()  // Recommended
)
```

### Realtime Subscriptions

Enable realtime for instant updates when other devices make changes:

```swift
try await syncManager.startRealtime()
```

The library includes **echo prevention** to avoid re-syncing your own changes that come back via realtime.

Note: Supabase limits concurrent realtime connections. Consider only enabling realtime when the app is active or when multiple devices are detected.

## Clock Skew Warning

This library uses Last-Write-Wins (LWW) based on client-side `updatedAt` timestamps. If a device's clock is significantly wrong (e.g., 5 minutes ahead), its changes will incorrectly "win" against valid updates from other devices.

The server-side `discard_older_updates` trigger protects server state, but cannot fix incorrectly timestamped client updates. This is a known V1 limitation.

For most use cases where device clocks are reasonably synchronized (via NTP), this works well.

## API Reference

### SyncableProtocol

Required fields for syncable models:

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Primary key |
| `userId` | `UUID?` | Owner (nullable for anonymous) |
| `updatedAt` | `Date` | LWW conflict resolution timestamp |
| `deleted` | `Bool` | Soft-delete flag |
| `syncedAt` | `Date?` | Local-only: last sync time |

### SyncManager Methods

| Method | Description |
|--------|-------------|
| `register(_:)` | Register a syncable type |
| `setUserId(_:)` | Set the current user |
| `setSyncingEnabled(_:)` | Enable/disable sync |
| `sync()` | Trigger immediate sync |
| `push(_:)` / `pull(_:)` | Sync specific type |
| `startSyncLoop(interval:)` | Start background sync |
| `stopSyncLoop()` | Stop background sync |
| `startRealtime()` | Enable realtime subscriptions |
| `stopRealtime()` | Disable realtime |
| `fillMissingUserIdForLocalTables()` | Claim orphaned records |
| `clearSyncState()` | Reset on logout |

## License

MIT
