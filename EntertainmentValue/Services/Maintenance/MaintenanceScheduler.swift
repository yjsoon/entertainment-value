import Foundation

/// Serialises automatic maintenance against restore, import, and trash
/// mutations on the shared MainActor model context.
///
/// Two hazards make this necessary:
/// - Every return to the foreground requests maintenance; rapid inactive/active
///   bounces must coalesce into a single run, or two purge passes can interleave
///   across suspension points and touch models the other already deleted.
/// - A Replace-Everything restore suspends mid-mutation (credential I/O) and
///   relies on rollback for atomicity; a purge that saves the context mid-restore
///   would commit a half-restored graph. Maintenance is therefore deferred while
///   the gate is held, and a gated caller first drains any in-flight maintenance.
///
/// Concurrent gated callers queue. A request that arrives while the gate is
/// held is remembered and replayed once after the last waiter drains, so a
/// foreground that lands mid-restore still gets that day's snapshot and purge.
@MainActor
final class MaintenanceScheduler {
    private var isGateHeld = false
    private var maintenanceTask: Task<Void, Never>?
    private var pendingMaintenance: (@MainActor () async -> Void)?
    private var exclusiveWaiters: [CheckedContinuation<Void, Never>] = []

    nonisolated init() {}

    @discardableResult
    func scheduleMaintenance(_ work: @escaping @MainActor () async -> Void) -> Bool {
        guard !isGateHeld else {
            pendingMaintenance = work
            return false
        }
        guard maintenanceTask == nil else { return false }
        maintenanceTask = Task { @MainActor [weak self] in
            await work()
            self?.maintenanceTask = nil
        }
        return true
    }

    func withRestoreGate<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        await acquireExclusiveSlot()
        defer { releaseExclusiveSlot() }
        return try await operation()
    }

    func waitForIdle() async {
        while let task = maintenanceTask {
            await task.value
        }
    }

    private func acquireExclusiveSlot() async {
        while true {
            if isGateHeld {
                await withCheckedContinuation { exclusiveWaiters.append($0) }
                return
            }
            if let task = maintenanceTask {
                await task.value
                continue
            }
            isGateHeld = true
            return
        }
    }

    private func releaseExclusiveSlot() {
        if !exclusiveWaiters.isEmpty {
            exclusiveWaiters.removeFirst().resume()
            return
        }
        isGateHeld = false
        if let pending = pendingMaintenance {
            pendingMaintenance = nil
            scheduleMaintenance(pending)
        }
    }
}
