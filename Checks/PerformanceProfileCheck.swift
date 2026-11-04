import Foundation

@main struct PerformanceProfileCheck {
    @MainActor static func main() async throws {
        let suite = "grove-profile-check-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var time = Date(timeIntervalSince1970: 100)
        var triggers: [String] = []
        let model = PerformanceProfileManager(defaults: defaults, now: { time }, triggers: { triggers }, observeSystem: false)
        precondition(model.profile == .auto && model.effectiveTier == .highPerformance && model.nextEvaluationDate == nil)
        triggers = ["Low Power Mode enabled"]; model.evaluate()
        precondition(model.nextEvaluationDate == time.addingTimeInterval(15))
        time += 14; model.evaluate()
        precondition(model.effectiveTier == .highPerformance && model.nextEvaluationDate == Date(timeIntervalSince1970: 115))
        time += 1; model.evaluate()
        precondition(model.effectiveTier == .efficient && model.nextEvaluationDate == nil)
        triggers = []; model.evaluate()
        precondition(model.effectiveTier == .efficient && model.nextEvaluationDate == time.addingTimeInterval(10))
        time += 9; model.evaluate()
        precondition(model.effectiveTier == .efficient)
        time += 1; model.evaluate()
        precondition(model.effectiveTier == .highPerformance && model.nextEvaluationDate == nil)
        // A trigger which returns before recovery restarts the stable interval.
        model.profile = .efficient; model.profile = .auto
        precondition(model.nextEvaluationDate == time.addingTimeInterval(10))
        time += 5; triggers = ["Thermal pressure"]; model.evaluate()
        precondition(model.effectiveTier == .efficient && model.nextEvaluationDate == nil)
        triggers = []; model.evaluate()
        precondition(model.nextEvaluationDate == time.addingTimeInterval(10))
        // Manual overrides cancel pending transitions immediately.
        model.profile = .highPerformance
        precondition(model.effectiveTier == .highPerformance && model.nextEvaluationDate == nil)
        triggers = ["Thermal pressure"]; model.profile = .auto
        precondition(model.nextEvaluationDate == time.addingTimeInterval(15))
        model.profile = .efficient
        precondition(model.effectiveTier == .efficient && model.nextEvaluationDate == nil)
        precondition(defaults.string(forKey: "performanceProfile") == "efficient")
        let restored = PerformanceProfileManager(defaults: defaults, now: { time }, triggers: { [] }, observeSystem: false)
        precondition(restored.profile == .efficient && restored.effectiveTier == .efficient)
        // Exercise the real scheduled callbacks, without a 25-second test or
        // changing this Mac's power settings. Move the injected clock close to
        // each deadline, schedule it, then advance the clock before it fires.
        defaults.set("auto", forKey: "performanceProfile")
        var scheduledTime = Date(timeIntervalSince1970: 0)
        var scheduledTriggers: [String] = []
        let scheduled = PerformanceProfileManager(defaults: defaults, now: { scheduledTime }, triggers: { scheduledTriggers }, observeSystem: false)
        scheduledTriggers = ["Thermal pressure"]; scheduled.evaluate()
        scheduledTime += 14.99; scheduled.evaluate(); scheduledTime += 0.01
        try await wait(for: .efficient, in: scheduled)
        scheduledTriggers = []; scheduled.evaluate()
        scheduledTime += 9.99; scheduled.evaluate(); scheduledTime += 0.01
        try await wait(for: .highPerformance, in: scheduled)
        precondition(scheduled.nextEvaluationDate == nil)
        // Delivery must use the SDK notification name, without changing the
        // host's thermal state or the user's Grove preferences.
        var notificationTriggers: [String] = []
        let notified = PerformanceProfileManager(defaults: defaults, now: { time }, triggers: { notificationTriggers }, observeSystem: true)
        notificationTriggers = ["SDK thermal notification"]
        NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: ProcessInfo.processInfo)
        for _ in 0..<200 {
            if notified.activeTriggers == notificationTriggers { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(notified.activeTriggers == notificationTriggers, "SDK thermal notification was not delivered")
        precondition(notified.nextEvaluationDate == time.addingTimeInterval(15))
        notified.profile = .highPerformance // Cancel the fixture's pending timer.
        print("PASS: Auto downgrade/recovery deadlines and timer delivery, interrupted dwell, manual cancellation, isolated preference persistence, SDK thermal notification delivery")
    }
    @MainActor static func wait(for tier: PerformanceTier, in model: PerformanceProfileManager) async throws {
        for _ in 0..<500 {
            if model.effectiveTier == tier { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Scheduled profile transition did not fire")
    }
}
