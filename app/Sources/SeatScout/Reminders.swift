import Foundation


struct PlanStep: Codable, Equatable {
    var fromEva: UInt32
    var toEva: UInt32
    var fromName: String
    var toName: String
    var wagon: Int
    var seat: Int?
    var seat2: Int?
    var window: Bool
}

struct CommittedPlan: Codable, Equatable {
    var trainKey: String
    var label: String
    var people: [[PlanStep]]
}

struct Reminder: Equatable, Identifiable {
    var id: String
    var fireDate: Date
    var title: String
    var body: String
}

enum ReminderPlanner {
    static func date(fromLocalMinutes m: Int64, timeZone tz: TimeZone) -> Date {
        let naive = Date(timeIntervalSince1970: Double(m) * 60)
        let first = tz.secondsFromGMT(for: naive)
        let guess = naive.addingTimeInterval(-Double(first))
        let second = tz.secondsFromGMT(for: guess)
        return naive.addingTimeInterval(-Double(second))
    }

    private static func people(_ s: PlanStep) -> String {
        guard let a = s.seat else { return "" }
        let pair = s.seat2.map { "miejsca \(a) + \($0)" } ?? "miejsce \(a)"
        return "wagon \(s.wagon), \(pair)\(s.window ? " (okno)" : "")"
    }

    static func changeLine(from a: PlanStep, to b: PlanStep) -> String {
        switch (a.seat != nil, b.seat != nil) {
        case (true, true): return "przesiądź się → \(people(b))"
        case (true, false): return "wstań – dalej brak wolnych miejsc"
        case (false, true): return "możesz usiąść → \(people(b))"
        case (false, false): return ""
        default: return ""
        }
    }

    private struct ReminderKey: Hashable { var eva: UInt32; var kind: Int }

    static func reminders(plan: CommittedPlan, arr: [UInt32: Int64], dep: [UInt32: Int64],
                          now: Date, timeZone: TimeZone, minLead: TimeInterval = 15) -> [Reminder] {
        var lines: [ReminderKey: [String]] = [:]
        var names: [UInt32: String] = [:]
        var lead: [ReminderKey: Int] = [:]
        let multi = plan.people.count > 1

        for (pi, steps) in plan.people.enumerated() {
            guard let first = steps.first, let last = steps.last else { continue }
            let prefix = multi ? "Osoba \(pi + 1): " : ""
            names[first.fromEva] = first.fromName
            let start = ReminderKey(eva: first.fromEva, kind: 0)
            lines[start, default: []].append(prefix + (first.seat != nil ? "twój fotel: \(people(first))" : "brak wolnych miejsc na początku – stoisz do \(first.toName)"))
            lead[start] = 10

            for i in 0..<(steps.count - 1) {
                let a = steps[i], b = steps[i + 1]
                names[a.toEva] = a.toName
                let line = changeLine(from: a, to: b)
                guard !line.isEmpty else { continue }
                let k = ReminderKey(eva: a.toEva, kind: 1)
                lines[k, default: []].append(prefix + line)
                let walk = (a.seat != nil && b.seat != nil) ? min(abs(a.wagon - b.wagon), 4) : 0
                lead[k] = max(lead[k] ?? 0, 3 + walk)
            }
            names[last.toEva] = last.toName
            let end = ReminderKey(eva: last.toEva, kind: 2)
            lines[end, default: []].append(prefix + "wysiadasz")
            lead[end] = 5
        }

        var out: [Reminder] = []
        for (k, ls) in lines {
            let base: Int64?
            switch k.kind {
            case 0: base = dep[k.eva] ?? arr[k.eva]
            default: base = arr[k.eva] ?? dep[k.eva]
            }
            guard let b = base else { continue }
            let l = lead[k] ?? 3
            let fire = date(fromLocalMinutes: b, timeZone: timeZone).addingTimeInterval(-Double(l) * 60)
            guard fire > now.addingTimeInterval(minLead) else { continue }
            let stop = names[k.eva] ?? "stacja"
            let title: String
            switch k.kind {
            case 0: title = "Za \(l) min odjazd: \(stop)"
            case 1: title = "Za \(l) min \(stop)"
            default: title = "Za \(l) min wysiadasz: \(stop)"
            }
            out.append(Reminder(id: "seat-\(k.kind)-\(k.eva)", fireDate: fire, title: title, body: ls.joined(separator: "\n")))
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }
}

enum ReminderStore {
    static let key = "reminders.plan.v1"

    static func load(_ d: UserDefaults = .standard) -> CommittedPlan? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CommittedPlan.self, from: data)
    }

    static func save(_ plan: CommittedPlan?, _ d: UserDefaults = .standard) {
        guard let plan, let data = try? JSONEncoder().encode(plan) else { d.removeObject(forKey: key); return }
        d.set(data, forKey: key)
    }
}
