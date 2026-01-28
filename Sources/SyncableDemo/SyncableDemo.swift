import Foundation
import GRDB
import Supabase
import Syncable

/// Syncable Demo - Interactive CLI for testing offline-first sync
///
/// Required environment variables:
///   SUPABASE_URL - Your Supabase project URL
///   SUPABASE_KEY - Your Supabase anon/public key
///
/// Optional:
///   USER_ID - UUID to use as user ID (generates one if not set)
///
/// Usage:
///   swift run SyncableDemo
@main
struct SyncableDemo {
    static func main() async throws {
        print("🔄 Syncable Demo - Offline-First Sync with GRDB + Supabase\n")

        // Load configuration from environment
        guard let supabaseURL = ProcessInfo.processInfo.environment["SUPABASE_URL"],
              let supabaseKey = ProcessInfo.processInfo.environment["SUPABASE_KEY"] else {
            print("❌ Missing required environment variables!")
            print("")
            print("Please set:")
            print("  export SUPABASE_URL=https://your-project.supabase.co")
            print("  export SUPABASE_KEY=your-anon-key")
            print("")
            print("Then run: swift run SyncableDemo")
            return
        }

        let userId: UUID
        if let userIdString = ProcessInfo.processInfo.environment["USER_ID"],
           let parsedId = UUID(uuidString: userIdString) {
            userId = parsedId
        } else {
            userId = UUID()
            print("ℹ️  Generated user ID: \(userId)")
            print("   Set USER_ID env var to use a specific user\n")
        }

        // Initialize GRDB database
        let dbPath = FileManager.default.temporaryDirectory.appendingPathComponent("syncable-demo.sqlite").path
        let dbExists = FileManager.default.fileExists(atPath: dbPath)
        let dbQueue = try DatabaseQueue(path: dbPath)

        if dbExists {
            print("📁 Database: \(dbPath) (existing)")
        } else {
            print("📁 Database: \(dbPath) (created new)")
        }

        // Create the todos table (if not exists)
        try await dbQueue.write { db in
            try Todo.createTable(in: db)
        }
        print("")

        // Initialize Supabase client
        let supabase = SupabaseClient(
            supabaseURL: URL(string: supabaseURL)!,
            supabaseKey: supabaseKey
        )

        // Initialize SyncManager
        let syncManager = SyncManager(
            dbWriter: dbQueue,
            supabaseClient: supabase,
            timestampStorage: InMemorySyncTimestampStorage()
        )

        // Register Todo type and configure
        syncManager.register(Todo.self)
        syncManager.setUserId(userId)
        syncManager.setSyncingEnabled(true)

        // Set up status change callback
        syncManager.onStatusChange { status in
            switch status {
            case .idle:
                print("   ✓ Sync complete")
            case .syncing:
                print("   ⟳ Syncing...")
            case .failed(let error):
                print("   ✗ Sync failed: \(error.localizedDescription)")
            }
        }

        print("=" .padding(toLength: 50, withPad: "=", startingAt: 0))
        print("Interactive Commands:")
        print("  add <title>  - Add a new todo")
        print("  list         - List all todos")
        print("  complete <n> - Mark todo #n as completed")
        print("  delete <n>   - Soft-delete todo #n")
        print("  sync         - Trigger manual sync")
        print("  realtime     - Start realtime subscriptions")
        print("  stop         - Stop realtime subscriptions")
        print("  status       - Show sync status")
        print("  quit         - Exit the demo")
        print("=" .padding(toLength: 50, withPad: "=", startingAt: 0))
        print("")

        // Initial sync
        print("🔄 Performing initial sync...")
        do {
            try await syncManager.sync()
        } catch {
            print("   ⚠️  Initial sync failed: \(error.localizedDescription)")
            print("   Continuing in offline mode...\n")
        }

        // Show current todos
        await listTodos(db: dbQueue, userId: userId)

        // Interactive command loop
        while true {
            print("\n> ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces),
                  !input.isEmpty else {
                continue
            }

            let parts = input.split(separator: " ", maxSplits: 1)
            let command = String(parts[0]).lowercased()
            let argument = parts.count > 1 ? String(parts[1]) : nil

            switch command {
            case "add":
                guard let title = argument, !title.isEmpty else {
                    print("Usage: add <title>")
                    continue
                }
                try await addTodo(db: dbQueue, userId: userId, title: title)
                try await syncManager.sync()

            case "list":
                await listTodos(db: dbQueue, userId: userId)

            case "complete":
                guard let arg = argument, let index = Int(arg) else {
                    print("Usage: complete <number>")
                    continue
                }
                try await completeTodo(db: dbQueue, userId: userId, index: index)
                try await syncManager.sync()

            case "delete":
                guard let arg = argument, let index = Int(arg) else {
                    print("Usage: delete <number>")
                    continue
                }
                try await deleteTodo(db: dbQueue, userId: userId, index: index)
                try await syncManager.sync()

            case "sync":
                print("🔄 Syncing...")
                try await syncManager.sync()

            case "realtime":
                print("📡 Starting realtime subscriptions...")
                try await syncManager.startRealtime()
                print("   Listening for remote changes...")

            case "stop":
                print("📡 Stopping realtime subscriptions...")
                await syncManager.stopRealtime()

            case "status":
                print("📊 Status:")
                print("   Sync enabled: \(syncManager.syncingEnabled)")
                print("   User ID: \(syncManager.userId?.uuidString ?? "none")")
                print("   Last sync: \(syncManager.lastSyncTime?.description ?? "never")")
                print("   Status: \(syncManager.syncStatus)")

            case "quit", "exit", "q":
                print("👋 Goodbye!")
                await syncManager.clearSyncState()
                return

            default:
                print("Unknown command: \(command)")
            }
        }
    }

    // MARK: - Todo Operations

    static func addTodo(db: DatabaseQueue, userId: UUID, title: String) async throws {
        let todo = Todo(userId: userId, title: title)
        try await db.write { db in
            try todo.insert(db)
        }
        print("   ✓ Added: \(title)")
    }

    static func listTodos(db: DatabaseQueue, userId: UUID) async {
        do {
            let todos = try await db.read { db in
                try Todo
                    .filter(Todo.Columns.userId == userId.uuidString)
                    .filter(Todo.Columns.deleted == false)
                    .order(Todo.Columns.updatedAt.desc)
                    .fetchAll(db)
            }

            if todos.isEmpty {
                print("📋 No todos yet. Use 'add <title>' to create one.")
            } else {
                print("📋 Todos:")
                for (index, todo) in todos.enumerated() {
                    let status = todo.isCompleted ? "✓" : "○"
                    let syncStatus = todo.syncedAt != nil ? "☁️" : "💾"
                    print("   \(index + 1). [\(status)] \(todo.title) \(syncStatus)")
                }
            }
        } catch {
            print("   ✗ Error listing todos: \(error.localizedDescription)")
        }
    }

    static func completeTodo(db: DatabaseQueue, userId: UUID, index: Int) async throws {
        let todos = try await db.read { db in
            try Todo
                .filter(Todo.Columns.userId == userId.uuidString)
                .filter(Todo.Columns.deleted == false)
                .order(Todo.Columns.updatedAt.desc)
                .fetchAll(db)
        }

        guard index > 0, index <= todos.count else {
            print("   ✗ Invalid todo number")
            return
        }

        var todo = todos[index - 1]
        todo.complete()
        let updatedTodo = todo

        try await db.write { db in
            try updatedTodo.update(db)
        }
        print("   ✓ Completed: \(updatedTodo.title)")
    }

    static func deleteTodo(db: DatabaseQueue, userId: UUID, index: Int) async throws {
        let todos = try await db.read { db in
            try Todo
                .filter(Todo.Columns.userId == userId.uuidString)
                .filter(Todo.Columns.deleted == false)
                .order(Todo.Columns.updatedAt.desc)
                .fetchAll(db)
        }

        guard index > 0, index <= todos.count else {
            print("   ✗ Invalid todo number")
            return
        }

        var todo = todos[index - 1]
        todo.markDeleted()
        let updatedTodo = todo

        try await db.write { db in
            try updatedTodo.update(db)
        }
        print("   ✓ Deleted: \(updatedTodo.title)")
    }
}
