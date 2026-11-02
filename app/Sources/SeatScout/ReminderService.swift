import SwiftUI
import UserNotifications

@MainActor
final class ReminderService: ObservableObject {
    static let shared = ReminderService()
    private static let warsaw = TimeZone(identifier: "Europe/Warsaw") ?? .current
    private static let idPrefix = "seat-"

    @Published private(set) var plan: CommittedPlan?
    @Published private(set) var scheduled: [Reminder] = []
    private var signature = ""

    private init() {
        plan = ReminderStore.load()
    }

    func commit(_ plan: CommittedPlan, arr: [UInt32: Int64], dep: [UInt32: Int64]) async -> Bool {
        guard await AlertService.shared.requestPermission() else {
            log(.error, "remind", "brak zgody na powiadomienia – przypomnienia wyłączone")
            return false
        }
        self.plan = plan
        ReminderStore.save(plan)
        signature = ""
        await reschedule(arr: arr, dep: dep)
        return true
    }

    func clear() async {
        plan = nil
        scheduled = []
        signature = ""
        ReminderStore.save(nil)
        await removePending()
        log(.info, "remind", "przypomnienia wyłączone")
    }

    private func removePending() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func reschedule(arr: [UInt32: Int64], dep: [UInt32: Int64]) async {
        guard let plan else { return }
        let now = Date()
        if let last = plan.people.compactMap({ $0.last?.toEva }).first, let end = arr[last],
           ReminderPlanner.date(fromLocalMinutes: end, timeZone: Self.warsaw).addingTimeInterval(30 * 60) < now {
            await clear()
            return
        }
        let list = ReminderPlanner.reminders(plan: plan, arr: arr, dep: dep, now: now, timeZone: Self.warsaw)
        let sig = list.map { "\($0.id)@\(Int($0.fireDate.timeIntervalSince1970 / 20))|\($0.body)" }.joined(separator: ";")
        scheduled = list
        guard sig != signature else { return }
        signature = sig

        await removePending()
        let center = UNUserNotificationCenter.current()
        for r in list {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, r.fireDate.timeIntervalSince(now)), repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
            } catch {
                log(.error, "remind", "nie udało się zaplanować \(r.id): \(error.localizedDescription)")
            }
        }
        log(.info, "remind", "zaplanowano \(list.count): " + list.map { "\($0.fireDate.formatted(date: .omitted, time: .shortened)) \($0.title)" }.joined(separator: " | "))
    }
}
