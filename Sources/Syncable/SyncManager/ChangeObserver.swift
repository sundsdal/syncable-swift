import Foundation
import SwiftData
import Combine
import CoreData

/// Observes SwiftData changes using Core Data's notification system.
///
/// SwiftData is backed by Core Data, so we use NSManagedObjectContextDidSave
/// notifications to detect changes. This is more reliable than trying to
/// observe SwiftData directly, which lacks a granular change stream API.
public final class ChangeObserver: @unchecked Sendable {
    private let onChanges: @Sendable () -> Void
    private let lock = NSLock()
    private var _subscription: AnyCancellable?

    public init(
        modelContainer: ModelContainer,
        onChanges: @escaping @Sendable () -> Void
    ) {
        self.onChanges = onChanges

        // Subscribe to Core Data's save notifications
        // SwiftData uses Core Data under the hood
        _subscription = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] notification in
                self?.handleContextDidSave(notification)
            }
    }

    deinit {
        _subscription?.cancel()
    }

    private func handleContextDidSave(_ notification: Notification) {
        // Check if there are actual changes
        guard let userInfo = notification.userInfo else { return }

        let hasInserts = (userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>)?.isEmpty == false
        let hasUpdates = (userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>)?.isEmpty == false
        let hasDeletes = (userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>)?.isEmpty == false

        if hasInserts || hasUpdates || hasDeletes {
            onChanges()
        }
    }
}

/// Alternative observer using Persistent History Tracking for more robust change detection.
///
/// This approach is more reliable for detecting changes made by other contexts/actors,
/// but requires enabling persistent history tracking on the model container.
public actor PersistentHistoryObserver {
    private let modelContainer: ModelContainer
    private var lastToken: NSPersistentHistoryToken?
    private let onChanges: @Sendable ([HistoryChange]) -> Void

    public init(
        modelContainer: ModelContainer,
        onChanges: @escaping @Sendable ([HistoryChange]) -> Void
    ) {
        self.modelContainer = modelContainer
        self.onChanges = onChanges
    }

    /// Fetch and process history since last check
    public func processNewHistory() async throws {
        // This would use NSPersistentHistoryChangeRequest to fetch changes
        // since lastToken, process them, and update the token
        // Implementation depends on the Core Data stack configuration
    }
}

/// Represents a change detected from persistent history
public struct HistoryChange: Sendable {
    public enum ChangeType: Sendable {
        case insert
        case update
        case delete
    }

    public let entityName: String
    public let objectID: String
    public let changeType: ChangeType
    public let changedProperties: Set<String>
}
