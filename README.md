# Syncable-Swift

Offline-first multi-device data synchronization for SwiftData + Supabase.

Inspired by [Mr-Pepe/syncable](https://github.com/Mr-Pepe/syncable) (Dart/Flutter).

## Features

- **Offline-first**: Changes are persisted locally and synced when online
- **Crash resilient**: Uses persistent dirty flags, not in-memory queues
- **Multi-device**: Real-time sync via Supabase Realtime
- **Conflict resolution**: Last-Write-Wins based on `updatedAt` timestamps
- **Dead letter queue**: Failed items don't block the sync queue
- **Background processing**: Uses `ModelActor` to keep UI responsive

## Requirements

- iOS 17+ / macOS 14+
- Swift 5.10+
- Supabase project

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/your-org/syncable-swift.git", from: "1.0.0")
]
```

## Quick Start

### 1. Define Your Model

```swift
import SwiftData
import Syncable

@Model
final class Todo: SyncableProtocol {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var updatedAt: Date
    var deleted: Bool
    var needsSync: Bool
    var syncRetryCount: Int

    // Your fields
    var title: String
    var completed: Bool

    init(title: String, userId: UUID) {
        self.id = UUID()
        self.userId = userId
        self.updatedAt = Date()
        self.deleted = false
        self.needsSync = true  // Mark for sync on creation
        self.syncRetryCount = 0
        self.title = title
        self.completed = false
    }
}
```

### 2. Initialize SyncManager

```swift
import Syncable
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://xxx.supabase.co")!,
    supabaseKey: "your-anon-key"
)

let syncManager = SyncManagerActor(
    modelContainer: modelContainer,
    supabase: supabase,
    userId: currentUserId
)

// Register your models
await syncManager.register(Todo.self)
```

### 3. Trigger Sync

```swift
// Manual sync
try await syncManager.sync()

// Observe state in SwiftUI
@State private var syncState = syncManager.state

var body: some View {
    VStack {
        if syncState.status == .syncing {
            ProgressView()
        }
        Text("Last sync: \(syncState.lastSyncDate ?? Date(), style: .relative)")
    }
}
```

## Supabase Setup

### Create Table

```sql
CREATE TABLE todos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted BOOLEAN NOT NULL DEFAULT false,
    title TEXT NOT NULL,
    completed BOOLEAN NOT NULL DEFAULT false
);

-- Enable RLS
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;

-- RLS Policy: users can only access their own data
CREATE POLICY "Users can manage their own todos"
    ON todos
    FOR ALL
    USING (auth.uid() = user_id);
```

### Conflict Resolution Trigger

```sql
-- Prevent older updates from overwriting newer data
CREATE OR REPLACE FUNCTION discard_older_updates()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.updated_at > NEW.updated_at THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_older_updates
    BEFORE UPDATE ON todos
    FOR EACH ROW
    EXECUTE FUNCTION discard_older_updates();
```

### Enable Realtime

```sql
-- Enable realtime for the table
ALTER PUBLICATION supabase_realtime ADD TABLE todos;
```

## Known Limitations (V1)

### Clock Skew

This library uses Last-Write-Wins (LWW) conflict resolution based on client `updatedAt` timestamps. Devices with drifted clocks may cause unexpected results:

- A device with a clock 5 minutes ahead will "win" against valid updates
- The server trigger protects server state but can't fix bad client timestamps
- Consider server-side timestamp assignment for critical applications

### Soft Deletes Only

Records are never hard-deleted during sync. The `deleted` flag is set to `true` instead. Implement periodic cleanup separately if needed.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    SyncManagerActor                     │
│                  (Background ModelActor)                │
├─────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐ │
│  │ ChangeObserver│  │ RealtimeSub   │  │ SyncState   │ │
│  │ (NSNotification)│ │ (Supabase)    │  │ (MainActor) │ │
│  └───────────────┘  └───────────────┘  └─────────────┘ │
├─────────────────────────────────────────────────────────┤
│                  Local SwiftData Store                  │
│           (needsSync flag = persistent queue)           │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                  Supabase Backend                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │  REST API   │  │  Realtime   │  │  RLS Policies   │ │
│  └─────────────┘  └─────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Credits

This library is a Swift implementation inspired by [Mr-Pepe/syncable](https://github.com/Mr-Pepe/syncable), a Dart/Flutter library for offline-first synchronization.

## License

MIT
