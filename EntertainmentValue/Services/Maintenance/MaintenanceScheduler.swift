import Foundation

private enum RestoreGateTLS {
    @TaskLocal static var nestDepth = 0
}

@MainActor
final class MaintenanceScheduler {
    private var activeRestoreCount = 0
    private var maintenanceTask: Task<Void, Never>?
    private var pendingMaintenance: (@MainActor () async -> Void)?
    private var exclusiveWaiters: [CheckedContinuation<Void, Never>] = []

    nonisolated init() {}

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
