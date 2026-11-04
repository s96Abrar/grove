import AppKit
import SwiftUI

enum PerformanceProfile: String, CaseIterable, Identifiable {
    case auto, highPerformance, efficient
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto (System-Aware)"
        case .highPerformance: return "High Performance"
        case .efficient: return "Efficient"
        }
    }
}

enum PerformanceTier {
    case highPerformance, efficient
}

/// Manual overrides apply immediately. Auto waits for sustained power/thermal
/// triggers and schedules both downgrade and recovery, without periodic idle work.
@MainActor
final class PerformanceProfileManager: ObservableObject {
    static let shared = PerformanceProfileManager()
    @Published var profile: PerformanceProfile {
        didSet { defaults.set(profile.rawValue, forKey: "performanceProfile"); evaluate() }
    }
    @Published private(set) var effectiveTier: PerformanceTier = .highPerformance
    @Published private(set) var activeTriggers: [String] = []
    private let defaults: UserDefaults
    private let now: () -> Date
    private let triggers: () -> [String]
    private var transitionTarget: PerformanceTier?
    private var transitionSince: Date?
    private var evalTask: Task<Void, Never>?
    private(set) var nextEvaluationDate: Date?
    private static let downgradeDwell: TimeInterval = 15
    private static let upgradeDwell: TimeInterval = 10

    // Injection keeps checks independent of the user's preferences and power mode.
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         triggers: (() -> [String])? = nil, observeSystem: Bool = true) {
        self.defaults = defaults
        self.now = now
        self.triggers = triggers ?? {
            var result: [String] = []
            let info = ProcessInfo.processInfo
            if info.isLowPowerModeEnabled { result.append("Low Power Mode enabled") }
            if info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue { result.append("Thermal pressure") }
            return result
        }
        profile = PerformanceProfile(rawValue: defaults.string(forKey: "performanceProfile") ?? "") ?? .auto
        if observeSystem {
            let center = NotificationCenter.default
            let names: [Notification.Name] = [NSApplication.didBecomeActiveNotification,
                NSApplication.didResignActiveNotification, NSNotification.Name.NSProcessInfoPowerStateDidChange,
                ProcessInfo.thermalStateDidChangeNotification]
            for name in names {
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.evaluate() }
                }
            }
        }
        evaluate()
    }

    var animationsEnabled: Bool { effectiveTier == .highPerformance && NSApp?.isActive != false }
    var statusPollInterval: TimeInterval { effectiveTier == .efficient ? 15 : 5 }

    func evaluate() {
        evalTask?.cancel(); evalTask = nil; nextEvaluationDate = nil
        let currentTriggers = triggers()
        if activeTriggers != currentTriggers { activeTriggers = currentTriggers }
        let target: PerformanceTier = profile == .auto
            ? (currentTriggers.isEmpty ? .highPerformance : .efficient)
            : (profile == .efficient ? .efficient : .highPerformance)
        let instant = now()
        if profile != .auto || target == effectiveTier {
            transitionTarget = nil; transitionSince = nil
            if effectiveTier != target { effectiveTier = target }
        } else {
            if transitionTarget != target {
                transitionTarget = target; transitionSince = instant
            }
            let dwell = target == .efficient ? Self.downgradeDwell : Self.upgradeDwell
            let deadline = (transitionSince ?? instant).addingTimeInterval(dwell)
            if instant >= deadline {
                effectiveTier = target
                transitionTarget = nil; transitionSince = nil
            } else {
                nextEvaluationDate = deadline
                evalTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(deadline.timeIntervalSince(instant))) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    self?.evaluate()
                }
            }
        }
        // App activation changes animation eligibility even without a tier flip.
        objectWillChange.send()
    }
}
