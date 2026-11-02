import Foundation


struct SavedSeat: Codable, Equatable {
    var wagon: Int
    var number: Int
}

struct Prefs: Codable, Equatable {
    var fromEva: UInt32?
    var toEva: UInt32?
    var date: String?
    var trainNumber: Int64?
    var discountIndex: Int?
    var planPeople: Int?
    var planTogether: Bool?
    var seats: [String: SavedSeat] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fromEva = try c.decodeIfPresent(UInt32.self, forKey: .fromEva)
        toEva = try c.decodeIfPresent(UInt32.self, forKey: .toEva)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        trainNumber = try c.decodeIfPresent(Int64.self, forKey: .trainNumber)
        discountIndex = try c.decodeIfPresent(Int.self, forKey: .discountIndex)
        planPeople = try c.decodeIfPresent(Int.self, forKey: .planPeople)
        planTogether = try c.decodeIfPresent(Bool.self, forKey: .planTogether)
        seats = try c.decodeIfPresent([String: SavedSeat].self, forKey: .seats) ?? [:]
    }

    static func seatKey(trainNumber: Int64, date: String) -> String { "\(trainNumber)-\(date)" }

    private static func formatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static func dayString(_ date: Date, timeZone: TimeZone) -> String { formatter(timeZone).string(from: date) }

    func searchDate(now: Date, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
        guard let s = date, let saved = Self.formatter(timeZone).date(from: s), saved >= today else { return tomorrow }
        return saved
    }

    mutating func prune(now: Date, timeZone: TimeZone, days: Int = 14) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        guard let limit = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now)) else { return }
        let f = Self.formatter(timeZone)
        seats = seats.filter { key, _ in
            guard key.count > 10, let d = f.date(from: String(key.suffix(10))) else { return false }
            return d >= limit
        }
    }
}

enum PrefsStore {
    static let key = "prefs.v1"

    static func load(_ defaults: UserDefaults = .standard) -> Prefs {
        guard let data = defaults.data(forKey: key), let p = try? JSONDecoder().decode(Prefs.self, from: data) else { return Prefs() }
        return p
    }

    static func save(_ prefs: Prefs, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(prefs) { defaults.set(data, forKey: key) }
    }
}
