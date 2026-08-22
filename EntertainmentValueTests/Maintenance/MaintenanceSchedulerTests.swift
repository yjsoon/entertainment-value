import Testing
@testable import EntertainmentValue

@Suite("Maintenance scheduling and restore gating")
@MainActor
struct MaintenanceSchedulerTests {
    @MainActor
    final class OrderRecorder {
        private(set) var events: [String] = []
        func record(_ event: String) { events.append(event) }
    }

    private func ranExclusively(_ events: [String], _ first: String, _ second: String) -> Bool {
        let firstPair = ["\(first)-start", "\(first)-end"]
        let secondPair = ["\(second)-start", "\(second)-end"]
        let stripped = events.filter { $0.hasPrefix(first) || $0.hasPrefix(second) }
        return stripped == firstPair + secondPair || stripped == secondPair + firstPair
    }

    @Test("Rapid foreground bounces coalesce into a single maintenance run")
    func rapidRequestsCoalesce() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        let first = scheduler.scheduleMaintenance {
            await Task.yield()
            recorder.record("run")
        }
        let second = scheduler.scheduleMaintenance { recorder.record("run") }
        await scheduler.waitForIdle()

        #expect(first)
        #expect(!second)
        #expect(recorder.events == ["run"])
    }

    @Test("Maintenance requested during a restore is replayed exactly once after the gate closes")
    func maintenanceReplayedAfterRestore() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        await scheduler.withRestoreGate {
            let accepted = scheduler.scheduleMaintenance { recorder.record("maintenance") }
            let secondAccepted = scheduler.scheduleMaintenance { recorder.record("maintenance") }
            #expect(!accepted)
            #expect(!secondAccepted)
            recorder.record("restore")
        }
        await scheduler.waitForIdle()

        #expect(recorder.events == ["restore", "maintenance"])
    }

    @Test("A restore drains in-flight maintenance before mutating")
    func restoreWaitsForInFlightMaintenance() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        scheduler.scheduleMaintenance {
            recorder.record("maintenance-start")
            await Task.yield()
            recorder.record("maintenance-end")
        }
        await scheduler.withRestoreGate {
            recorder.record("restore")
        }

        #expect(recorder.events == ["maintenance-start", "maintenance-end", "restore"])
    }

    @Test("Overlapping restores keep the gate closed until both complete")
    func overlappingRestoresKeepGateClosed() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        await scheduler.withRestoreGate {
            recorder.record("outer-start")
            await scheduler.withRestoreGate {
                recorder.record("inner")
            }
            // The inner gate has released, but the outer one is still active:
            // a maintenance request must be deferred, not started.
            let accepted = scheduler.scheduleMaintenance { recorder.record("maintenance") }
            #expect(!accepted)
            await Task.yield()
            #expect(!recorder.events.contains("maintenance"))
            recorder.record("outer-end")
        }
        await scheduler.waitForIdle()

        #expect(recorder.events == ["outer-start", "inner", "outer-end", "maintenance"])
    }

    @Test("Concurrent restores replay deferred maintenance only after the last one finishes")
    func concurrentRestoresReplayAfterLastRelease() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        async let first: Void = scheduler.withRestoreGate {
            recorder.record("restore1-start")
            scheduler.scheduleMaintenance { recorder.record("maintenance") }
            for _ in 0 ..< 3 { await Task.yield() }
            recorder.record("restore1-end")
        }
        async let second: Void = scheduler.withRestoreGate {
            recorder.record("restore2-start")
            for _ in 0 ..< 8 { await Task.yield() }
            recorder.record("restore2-end")
        }
        _ = await (first, second)
        await scheduler.waitForIdle()

        let maintenanceRuns = recorder.events.filter { $0 == "maintenance" }
        #expect(maintenanceRuns.count == 1)
        let maintenanceIndex = recorder.events.firstIndex(of: "maintenance")
        let firstEnd = recorder.events.firstIndex(of: "restore1-end")
        let secondEnd = recorder.events.firstIndex(of: "restore2-end")
        #expect(maintenanceIndex != nil && firstEnd != nil && secondEnd != nil)
        if let maintenanceIndex, let firstEnd, let secondEnd {
            #expect(maintenanceIndex > firstEnd)
            #expect(maintenanceIndex > secondEnd)
        }
        #expect(ranExclusively(recorder.events, "restore1", "restore2"))
    }

    @Test("Concurrent gated mutations do not interleave")
    func concurrentGatesAreExclusive() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        async let first: Void = scheduler.withRestoreGate {
            recorder.record("purge-start")
            await Task.yield()
            recorder.record("purge-end")
        }
        async let second: Void = scheduler.withRestoreGate {
            recorder.record("restore-start")
            await Task.yield()
            recorder.record("restore-end")
        }
        _ = await (first, second)

        #expect(ranExclusively(recorder.events, "purge", "restore"))
    }

    @Test("Maintenance runs again once the restore gate is released")
    func maintenanceResumesAfterRestore() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        await scheduler.withRestoreGate { recorder.record("restore") }
        let accepted = scheduler.scheduleMaintenance { recorder.record("maintenance") }
        await scheduler.waitForIdle()

        #expect(accepted)
        #expect(recorder.events == ["restore", "maintenance"])
    }
}
