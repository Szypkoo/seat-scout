import Foundation


struct WatchSeat: Codable, Hashable {
    var wagon: Int
    var number: Int
    var window: Bool
    var x: Int?
    var y: Int?
}

struct WatchTarget: Codable, Equatable {
    var trainNumber: Int64
    var category: String
    var name: String
    var connectionId: Int64
    var departure: String
    var arrival: String
    var fromKod: UInt32, toKod: UInt32
    var fromEva: UInt32, fromEpa: UInt32, fromName: String
    var toEva: UInt32, toEpa: UInt32, toName: String

    var label: String { "\(category) \(trainNumber) \(name.capitalized)" }
    var route: String { "\(fromName) → \(toName)" }
    var day: String { String(departure.prefix(10)) }
    var key: String { "\(category)\(trainNumber)-\(day)-\(fromEva)-\(toEva)" }
}

struct AlertSettings: Codable, Equatable {
    var enabled = false
    var windowOnly = false
    var pairs = false
    var target: WatchTarget?
    var lastCheck: Date?
    var lastFreeCount: Int?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        windowOnly = try c.decodeIfPresent(Bool.self, forKey: .windowOnly) ?? false
        pairs = try c.decodeIfPresent(Bool.self, forKey: .pairs) ?? false
        target = try c.decodeIfPresent(WatchTarget.self, forKey: .target)
        lastCheck = try c.decodeIfPresent(Date.self, forKey: .lastCheck)
        lastFreeCount = try c.decodeIfPresent(Int.self, forKey: .lastFreeCount)
    }
}

struct AlertEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case info, notified, error }
    var id = UUID()
    var date: Date
    var kind: Kind
    var text: String
}

enum AlertEngine {
    static let adjacent = 45

    static func areAdjacent(_ a: WatchSeat, _ b: WatchSeat) -> Bool {
        guard a.wagon == b.wagon, let ax = a.x, let ay = a.y, let bx = b.x, let by = b.y else { return false }
        return (ax - bx) * (ax - bx) + (ay - by) * (ay - by) <= adjacent * adjacent
    }

    static func newlyFree(previous: [WatchSeat]?, current: [WatchSeat], windowOnly: Bool, pairs: Bool) -> [WatchSeat] {
        guard let previous else { return [] }
        let old = Set(previous.map { SeatID(wagon: $0.wagon, number: $0.number) })
        let fresh = current.filter { !old.contains(SeatID(wagon: $0.wagon, number: $0.number)) }
        guard !fresh.isEmpty else { return [] }

        if pairs {
            var out: [WatchSeat] = []
            var seen = Set<SeatID>()
            for f in fresh {
                for other in current where other != f && areAdjacent(f, other) {
                    if windowOnly && !(f.window || other.window) { continue }
                    for s in [f, other] where seen.insert(SeatID(wagon: s.wagon, number: s.number)).inserted { out.append(s) }
                }
            }
            return out
        }
        return windowOnly ? fresh.filter(\.window) : fresh
    }

    private struct SeatID: Hashable {
        let wagon: Int
        let number: Int
    }

    static func describe(_ s: WatchSeat) -> String {
        "wagon \(s.wagon), miejsce \(s.number)\(s.window ? " (okno)" : "")"
    }

    static func notification(newSeats: [WatchSeat], totalFree: Int, target: WatchTarget, pairs: Bool) -> (title: String, body: String) {
        let sorted = newSeats.sorted { ($0.wagon, $0.number) < ($1.wagon, $1.number) }
        let shown = sorted.prefix(3).map(describe).joined(separator: "; ")
        let more = sorted.count > 3 ? " i \(sorted.count - 3) więcej" : ""
        let title = pairs ? "Wolne miejsca obok siebie · \(target.label)" : "Zwolniło się miejsce · \(target.label)"
        let body = "\(target.route), \(target.day): \(shown)\(more). Wolnych na całej trasie: \(totalFree)."
        return (title, body)
    }

    static func isExpired(_ target: WatchTarget, now: Date, timeZone: TimeZone) -> Bool {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let arr = f.date(from: target.arrival) ?? f.date(from: target.departure) else { return false }
        return now > arr.addingTimeInterval(30 * 60)
    }
}

enum AlertStore {
    static let settingsKey = "alerts.settings.v1"
    static let historyKey = "alerts.history.v1"
    static let snapshotPrefix = "alerts.snapshot."
    static let maxHistory = 40

    static func loadSettings(_ d: UserDefaults = .standard) -> AlertSettings {
        guard let data = d.data(forKey: settingsKey), let s = try? JSONDecoder().decode(AlertSettings.self, from: data) else { return AlertSettings() }
        return s
    }

    static func saveSettings(_ s: AlertSettings, _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(s) { d.set(data, forKey: settingsKey) }
    }

    static func loadHistory(_ d: UserDefaults = .standard) -> [AlertEvent] {
        guard let data = d.data(forKey: historyKey), let h = try? JSONDecoder().decode([AlertEvent].self, from: data) else { return [] }
        return h
    }

    static func append(_ event: AlertEvent, to history: [AlertEvent], _ d: UserDefaults = .standard) -> [AlertEvent] {
        let out = Array(([event] + history).prefix(maxHistory))
        if let data = try? JSONEncoder().encode(out) { d.set(data, forKey: historyKey) }
        return out
    }

    static func loadSnapshot(_ key: String, _ d: UserDefaults = .standard) -> [WatchSeat]? {
        guard let data = d.data(forKey: snapshotPrefix + key) else { return nil }
        return try? JSONDecoder().decode([WatchSeat].self, from: data)
    }

    static func saveSnapshot(_ seats: [WatchSeat], key: String, _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(seats) { d.set(data, forKey: snapshotPrefix + key) }
    }

    static func clearSnapshot(_ key: String, _ d: UserDefaults = .standard) {
        d.removeObject(forKey: snapshotPrefix + key)
    }
}
