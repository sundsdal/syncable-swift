import Foundation
import Supabase
import Realtime

/// Manages Supabase Realtime subscriptions for live sync.
///
/// Subscribes to Postgres changes and triggers sync when remote changes occur.
public actor RealtimeSubscriptionManager {
    private let supabase: SupabaseClient
    private let userId: UUID
    private var channels: [String: RealtimeChannelV2] = [:]
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
        // Create channel for this table
        let channel = supabase.realtimeV2.channel("sync:\(tableName)")

        // Subscribe to postgres changes filtered by user_id
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: tableName,
            filter: "user_id=eq.\(userId.uuidString)"
        )

        // Also subscribe to updates and deletes
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: tableName,
            filter: "user_id=eq.\(userId.uuidString)"
        )

        let deletes = channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: tableName,
            filter: "user_id=eq.\(userId.uuidString)"
        )

        // Start listening
        await channel.subscribe()

        // Store channel reference
        channels[tableName] = channel

        // Handle incoming changes
        Task {
            for await insert in changes {
                if let id = extractId(from: insert) {
                    await onRemoteChange(tableName, id)
                }
            }
        }

        Task {
            for await update in updates {
                if let id = extractId(from: update) {
                    await onRemoteChange(tableName, id)
                }
            }
        }

        Task {
            for await delete in deletes {
                if let id = extractId(from: delete) {
                    await onRemoteChange(tableName, id)
                }
            }
        }
    }

    /// Unsubscribe from a specific table
    public func unsubscribe(from tableName: String) async {
        if let channel = channels.removeValue(forKey: tableName) {
            await channel.unsubscribe()
        }
    }

    /// Unsubscribe from all tables
    public func unsubscribeAll() async {
        for (_, channel) in channels {
            await channel.unsubscribe()
        }
        channels.removeAll()
    }

    private func extractId(from action: any PostgresAction) -> UUID? {
        // Extract the 'id' field from the record
        // Implementation depends on the action type and record structure
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
