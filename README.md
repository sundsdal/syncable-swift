# Syncable

[![Swift](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20macOS-lightgrey.svg)]()

Syncable is a library for offline-first multi-device data synchronization in Swift apps (iOS/macOS).

It was inspired by the [Dart/Flutter Syncable library](https://github.com/Mr-Pepe/syncable).
The library provides a `SyncManager` class that handles data synchronization across devices.
Conflicts are resolved based on the last time an item was updated.
This means that if one item is modified offline on multiple devices, the version with
the newer timestamp overwrites the other one when the devices go online.

This implementation uses **GRDB** (SQLite) for local storage and **Supabase** for the backend.

## Usage 📖

This section assumes that you already know how to work with [GRDB](https://github.com/groue/GRDB.swift) and [Supabase](https://supabase.com/).

Setting up syncing requires some work, but we will go through it step by step.

### Set up the local database 🗄️

1. **Define a syncable:**
   Every item you want to synchronize must:

   - Conform to the `SyncableProtocol`.
   - Be a GRDB `FetchableRecord` and `PersistableRecord`.
   - Be `Codable` for serialization to the backend.

   ```swift
   import GRDB
   import Syncable

   struct Item: SyncableProtocol {
       // SyncableProtocol requirements
       var id: UUID
       var userId: UUID?
       var updatedAt: Date
       var deleted: Bool
       var syncedAt: Date? // Local-only, tracks sync state

       // Your fields
       var name: String

       // GRDB Table definition
       static var databaseTableName: String { "items" }
   }
   ```

2. **Define a syncable table:**
   Create the table in your GRDB database. You must include the columns required by `SyncableProtocol`.

   ```swift
   try db.create(table: "items") { t in
       t.column("id", .text).primaryKey()
       t.column("userId", .text) // Nullable for offline creation
       t.column("updatedAt", .datetime).notNull()
       t.column("deleted", .boolean).notNull().defaults(to: false)
       t.column("syncedAt", .datetime) // Local-only column

       t.column("name", .text).notNull()
   }
   ```

### Set up the backend 🛠️

1. **Enable real-time:**
   The `SyncManager` must be able to establish a real-time connection to the backend to listen for changes.

   ```sql
   begin;
   drop publication if exists supabase_realtime;
   create publication supabase_realtime;
   commit;
   ```

2. **Create a function to reject old items:**
   The backend must resolve conflicts by rejecting items that have an older
   `updatedAt` timestamp than what is already in the backend database.

   ```sql
   create or replace function discard_older_updates()
   returns trigger as $$
   BEGIN
       IF NEW.updated_at <= OLD.updated_at THEN
           RETURN NULL; -- Discard the incoming row
       END IF;
       RETURN NEW; -- Allow the update to proceed
   END;
   $$ language plpgsql;
   ```

3. **Create a table to sync to:**
   Make sure to enable real-time and the conflict resolution function for your table.

   ```sql
   create table
   items (
       id uuid not null,
       user_id uuid not null references auth.users (id) on delete cascade,
       updated_at timestamptz not null,
       deleted boolean not null,
       name text not null,
       primary key (id, user_id)
   );

   create trigger handle_conflicts
   before update on items
   for each row
   execute function discard_older_updates();

   alter publication supabase_realtime add table items;
   ```

4. **(Optional) Enable Row-level security (RLS):**
   Allow users to only create, read, update, and delete their own items.

   ```sql
   alter table items enable row level security;

   create policy "Users can work with own data"
   on public.items
   for all
   using (
       (auth.uid() = user_id)
   );
   ```

### Start synchronization 🔄

1.  **Create a sync manager:**

    ```swift
    let syncManager = SyncManager(
        dbWriter: dbQueue, // Your GRDB DatabaseWriter
        supabaseClient: supabaseClient,
        timestampStorage: UserDefaultsSyncTimestampStorage()
    )
    ```

2.  **Register syncables:**

    ```swift
    syncManager.register(Item.self)
    ```

3.  **Set a user ID:**

    ```swift
    syncManager.setUserId(supabaseClient.auth.currentUser?.id)
    ```

    Syncing will only work if a user ID is set.

4.  **Enable syncing:**

    ```swift
    syncManager.setSyncingEnabled(true)
    ```

    Use `setSyncingEnabled(false)` if you only want to enable syncing under
    certain conditions, e.g., if a Wi-Fi network is available.

The sync manager now does a couple of things in the background:

- It tracks changes to the local database. "Dirty" items (where `syncedAt` is nil or older than `updatedAt`) are picked up by the sync loop.
- It listens to changes to the backend database via Realtime (if enabled).
- A loop running in the background checks for dirty items and writes them to the backend. It also periodically pulls changes from the backend.
- Use `syncManager.startSyncLoop()` to start this background process.

> ⚠️ Don't forget to update the `updatedAt` timestamp whenever you change an item.
> Use UTC timestamps to make sure that synchronization works when users change time zones.

### Delete items 🗑️

Items should be soft-deleted to correctly propagate deletions across devices.
When deleting an item, set its `deleted` field to `true` and don't forget to
update its `updatedAt` field.

> ⚠️ Soft-deletion means that your client-side code needs to filter out deleted items in your UI queries.

### Fill user ID after registration/sign-in 👤

If a user creates items while not logged in, set the `userId` field to `nil`.
Once the user signs in, you should update your local records with the new user ID.

```swift
try dbQueue.write { db in
    try Item
        .filter(Column("userId") == nil)
        .updateAll(db, Column("userId").set(to: newUserId))
}
```

If syncing is enabled, those items will then get synced to the backend automatically.

### Optimizations ⚡

There are a few mechanisms that can drastically reduce the ongoing data
usage for synchronization.

#### Persistently store synchronization timestamps

By default, the `SyncManager` needs to know the last time it synced to fetch only incremental changes.

To only sync incremental changes, provide a `SyncTimestampStorage` implementation to the sync manager.
The library provides `UserDefaultsSyncTimestampStorage` which persists these timestamps in `UserDefaults` across app restarts.

```swift
let timestampStorage = UserDefaultsSyncTimestampStorage()
let syncManager = SyncManager(..., timestampStorage: timestampStorage)
```

#### Realtime Subscriptions

You can enable Realtime subscriptions to instantly receive updates from other devices.

```swift
try await syncManager.startRealtime()
```

To prevent "echoes" (receiving your own changes back), the `SyncManager` implements an echo prevention mechanism.
However, maintaining many realtime connections can be expensive. Consider enabling this only when the app is active.

## License

MIT
