import ActivityKit
import SeatScoutShared
import SwiftUI

@MainActor
final class LiveActivityService: ObservableObject {
    static let shared = LiveActivityService()

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    private var activity: Activity<TrainActivityAttributes>?
    private var lastState: TrainActivityAttributes.ContentState?

    private init() {
        activity = Activity<TrainActivityAttributes>.activities.first
        isRunning = activity != nil
    }

    static var extensionPresent: Bool {
        guard let url = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return items.contains { $0.hasSuffix(".appex") }
    }

    var isAvailable: Bool { Self.extensionPresent && ActivityAuthorizationInfo().areActivitiesEnabled }

    var unavailableReason: String? {
        if !Self.extensionPresent { return "Ta wersja aplikacji jest zbudowana bez widżetu (SeatScout)." }
        if !ActivityAuthorizationInfo().areActivitiesEnabled { return "Włącz „Aktywności na żywo” w Ustawieniach iOS dla tej aplikacji." }
        return nil
    }

    func start(label: String, route: String, state: TrainActivityAttributes.ContentState) {
        guard isAvailable else {
            lastError = unavailableReason
            log(.warn, "island", "niedostępne: \(unavailableReason ?? "?")")
            return
        }
        Task { await endAll() }
        do {
            let content = ActivityContent(state: state, staleDate: state.nextDate?.addingTimeInterval(15 * 60))
            activity = try Activity.request(attributes: TrainActivityAttributes(trainLabel: label, route: route),
                                            content: content, pushType: nil)
            lastState = state
            isRunning = true
            lastError = nil
            log(.info, "island", "uruchomiono Live Activity: \(label)")
        } catch {
            lastError = error.localizedDescription
            log(.error, "island", "nie udało się uruchomić: \(error.localizedDescription)")
        }
    }

    func update(_ state: TrainActivityAttributes.ContentState) {
        guard activity != nil, state != lastState else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: state.nextDate?.addingTimeInterval(15 * 60))
        Task.detached {
            for a in Activity<TrainActivityAttributes>.activities { await a.update(content) }
        }
        if state.phase == "finished" {
            Task {
                try? await Task.sleep(for: .seconds(20 * 60))
                await self.end()
            }
        }
    }

    func end() async {
        await endAll()
        activity = nil
        lastState = nil
        isRunning = false
        log(.info, "island", "zakończono Live Activity")
    }

    private func endAll() async {
        for a in Activity<TrainActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }
}
