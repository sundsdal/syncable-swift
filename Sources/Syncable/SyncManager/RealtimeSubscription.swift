import Foundation
import Supabase
import Realtime

/// Manages Supabase Realtime subscriptions for live sync.
///
/// Subscribes to Postgres changes and triggers sync when remote changes occur.
/// Tasks are properly tracked and cancelled on unsubscribe to prevent resource leaks.
public actor RealtimeSubscriptionManager {
    private let supabase: SupabaseClient
    private let userId: UUID
    private var channels: [String: RealtimeChannelV2] = [:]
    private var listenerTasks: [String: [Task<Void, Never>]] = [:]
    private let onRemoteChange: @Sendable (String, UUID) async -> Void

    public init(
        supabase: SupabaseClient,
        userId: UUID,
        onRemoteChange: @escaping @Sendable (String, UUID) async -> Void
    ) {
        self.supabase = supabase
        self.userId = userId
        self.onRemoteChange = onRemoteChange
    }

    /// Subscribe to changes for a specific table
    public func subscribe(to tableName: String) async throws {
        // Cancel any existing subscription for this table first
        await unsubscribe(from: tableName)

        // Create channel for this table
        let channel = supabase.realtimeV2.channel("sync:\(tableName)")

        // Subscribe to postgres changes filtered by user_id
        let userIdFilter = RealtimePostgresFilter.eq("user_id", value: userId.uuidString)

        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: tableName,
            filter: userIdFilter
        )

        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: tableName,
            filter: userIdFilter
        )

        let deletes = channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: tableName,
            filter: userIdFilter
        )

        // Start listening
        try await channel.subscribeWithError()

        // Store channel reference
        channels[tableName] = channel

        // Track tasks for proper cleanup
        var tasks: [Task<Void, Never>] = []

        tasks.append(Task { [onRemoteChange] in
            for await insert in inserts {
                guard !Task.isCancelled else { break }
                if let id = extractId(from: insert) {
                    await onRemoteChange(tableName, id)
                }
            }
        })

        tasks.append(Task { [onRemoteChange] in
            for await update in updates {
                guard !Task.isCancelled else { break }
                if let id = extractId(from: update) {
                    await onRemoteChange(tableName, id)
                }
            }
        })

        tasks.append(Task { [onRemoteChange] in
            for await delete in deletes {
                guard !Task.isCancelled else { break }
                if let id = extractId(from: delete) {
                    await onRemoteChange(tableName, id)
                }
            }
        })

        listenerTasks[tableName] = tasks
    }

    /// Unsubscribe from a specific table
    public func unsubscribe(from tableName: String) async {
        // Cancel listener tasks first
        if let tasks = listenerTasks.removeValue(forKey: tableName) {
            for task in tasks {
                task.cancel()
            }
        }

        // Then unsubscribe from the channel
        if let channel = channels.removeValue(forKey: tableName) {
            await channel.unsubscribe()
        }
    }

    /// Unsubscribe from all tables
    public func unsubscribeAll() async {
        // Cancel all listener tasks
        for (_, tasks) in listenerTasks {
            for task in tasks {
                task.cancel()
            }
        }
        listenerTasks.removeAll()

        // Unsubscribe from all channels
        for (_, channel) in channels {
            await channel.unsubscribe()
        }
        channels.removeAll()
    }

    /// Get the list of currently subscribed table names
    public var subscribedTables: [String] {
        Array(channels.keys)
    }

    private func extractId(from action: any PostgresAction) -> UUID? {
        // Extract the 'id' field from the record
        guard let record = action.actionRecord,
              let idString = record["id"]?.stringValue,
              let id = UUID(uuidString: idString) else {
            return nil
        }
        return id
    }
}

/// Extension to extract string value from AnyJSON
extension AnyJSON {
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        default: return nil
        }
    }
}

/// Protocol for postgres actions to unify handling
protocol PostgresAction {
    var actionRecord: [String: AnyJSON]? { get }
}

extension InsertAction: PostgresAction {
    var actionRecord: [String: AnyJSON]? { record }
}

extension UpdateAction: PostgresAction {
    var actionRecord: [String: AnyJSON]? { record }
}

extension DeleteAction: PostgresAction {
    var actionRecord: [String: AnyJSON]? { oldRecord }
}
