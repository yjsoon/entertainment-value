import Foundation

private enum RestoreGateTLS {
    @TaskLocal static var nestDepth = 0
}

/// Serialises automatic maintenance against restore operations on the shared
/// MainActor model context.
///
/// Two hazards make this necessary:
/// - Every return to the foreground requests maintenance; rapid inactive/active
///   bounces must coalesce into a single run, or two purge passes can interleave
///   across suspension points and touch models the other already deleted.
/// - A Replace-Everything restore suspends mid-mutation (credential I/O) and
///   relies on rollback for atomicity; a purge that saves the context mid-restore
///   would commit a half-restored graph. Maintenance is therefore deferred while
///   any restore holds the gate, and a restore first drains any in-flight
///   maintenance.
///
/// Concurrent `withRestoreGate` callers queue. Nested calls on the same task
/// re-enter so import can wrap apply. A request that arrives while the gate is
/// held is remembered and replayed once after the last restore releases it, so
/// a foreground that lands mid-restore still gets that day's snapshot and purge.
@MainActor
final class MaintenanceScheduler {
    private var activeRestoreCount = 0
    private var maintenanceTask: Task<Void, Never>?
    private var pendingMaintenance: (@MainActor () async -> Void)?
    private var exclusiveWaiters: [CheckedContinuation<Void, Never>] = []

    nonisolated init() {}

    /// Starts maintenance unless a run is already in flight or a restore holds
    /// the gate. Returns whether the work started immediately. A request gated
    /// by a restore is stored and replayed once the gate releases; one that
    /// coalesces into an in-flight run is simply dropped, because that run is
    /// already doing today's work.
    @discardableResult
    func scheduleMaintenance(_ work: @escaping @MainActor () async -> Void) -> Bool {
        guard activeRestoreCount == 0 else {
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

    /// Runs a restore, import, or trash mutation exclusively of maintenance and
    /// of other concurrent gated callers. Nested calls on the same task re-enter.
    func withRestoreGate<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        if RestoreGateTLS.nestDepth == 0 {
            await waitForExclusiveSlot()
        }
        return try await RestoreGateTLS.$nestDepth.withValue(RestoreGateTLS.nestDepth + 1) {
            activeRestoreCount += 1
            defer { releaseRestoreGate() }
            return try await operation()
        }
    }

    /// Resumes once no maintenance is in flight.
    func waitForIdle() async {
        while let task = maintenanceTask {
            await task.value
        }
    }

    private func waitForExclusiveSlot() async {
        while true {
            if activeRestoreCount > 0 {
                await withCheckedContinuation { exclusiveWaiters.append($0) }
                continue
            }
            if let task = maintenanceTask {
                await task.value
                continue
            }
            return
        }
    }

    private func releaseRestoreGate() {
        activeRestoreCount -= 1
        guard activeRestoreCount == 0 else { return }
        if !exclusiveWaiters.isEmpty {
            exclusiveWaiters.removeFirst().resume()
            return
        }
        if let pending = pendingMaintenance {
            pendingMaintenance = nil
            scheduleMaintenance(pending)
        }
    }
}
