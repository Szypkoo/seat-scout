import Foundation


struct CachedStop: Codable {
    var name: String
    var eva: UInt32
    var arrival: String
    var departure: String
    var canBoard: Bool
    var canAlight: Bool

    init(_ s: CoreStop) {
        name = s.name; eva = s.eva; arrival = s.arrival; departure = s.departure
        canBoard = s.canBoard; canAlight = s.canAlight
    }

    var core: CoreStop {
        CoreStop(name: name, eva: eva, arrival: arrival, departure: departure, canBoard: canBoard, canAlight: canAlight)
    }
}

struct CachedDecor: Codable {
    var x: Int, y: Int, w: Int, h: Int
    var sign: Bool
    var code: String
    var title: String
}

struct CachedWagon: Codable {
    var wagon: Int
    var cls: Int
    var seats: [[Int]]
    var width: Int?
    var height: Int?
    var decor: [CachedDecor]?
    var direction: Int?
    var compartments: Int?

    init(_ w: CoreWagon, withLayout: Bool = false) {
        wagon = w.wagon
        cls = w.travelClass
        direction = w.direction
        compartments = w.compartments
        if withLayout {
            width = w.width
            height = w.height
            decor = w.decor.map { CachedDecor(x: $0.x, y: $0.y, w: $0.w, h: $0.h, sign: $0.isSign, code: $0.code, title: $0.title) }
        }
        seats = w.seats.map { s in
            var f = 0
            if s.isFree { f |= 1 }
            if s.isSpecial { f |= 2 }
            if s.position == .window { f |= 4 }
            if s.position == .aisle { f |= 8 }
            if s.xy != nil { f |= 16 }
            return [s.number, f, s.xy?.x ?? 0, s.xy?.y ?? 0]
        }
    }

    var core: CoreWagon {
        let list = seats.compactMap { a -> CoreSeat? in
            guard a.count == 4 else { return nil }
            let f = a[1]
            return CoreSeat(number: a[0], isFree: f & 1 != 0,
                            position: f & 4 != 0 ? .window : (f & 8 != 0 ? .aisle : .unknown),
                            isSpecial: f & 2 != 0, xy: f & 16 != 0 ? (a[2], a[3]) : nil)
        }
        return CoreWagon(wagon: wagon, travelClass: cls, freeCount: list.filter { $0.isFree }.count,
                         occupiedCount: list.filter { !$0.isFree }.count, seats: list,
                         width: width ?? 0, height: height ?? 0,
                         decor: (decor ?? []).map { CoreDecor(x: $0.x, y: $0.y, w: $0.w, h: $0.h, isSign: $0.sign, code: $0.code, title: $0.title) }, direction: direction ?? 0, compartments: compartments ?? -1)
    }
}

struct PlanSnapshot: Codable {
    var key: String
    var savedAt: Date
    var stops: [CachedStop]
    var legs: [String: [CachedWagon]]
}

struct DetailsSnapshot: Codable {
    var key: String
    var savedAt: Date
    var wagons: [CachedWagon]
    var prices: [String: Double]
    var priceNote: String?
}

enum DiskCache {
    private static var dir: URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    private static func file(_ prefix: String, _ key: String) -> URL? {
        let safe = String(key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
        return dir?.appendingPathComponent("\(prefix)-\(safe).json")
    }

    static func load<T: Decodable>(_ type: T.Type, prefix: String, key: String) -> T? {
        guard let url = file(prefix, key), let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            log(.warn, "cache", "uszkodzony plik \(url.lastPathComponent): \(error.localizedDescription) – usuwam")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, prefix: String, key: String) {
        guard let url = file(prefix, key) else { return }
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            prune(prefix: prefix, keep: url)
        } catch {
            log(.warn, "cache", "zapis \(url.lastPathComponent) nieudany: \(error.localizedDescription)")
        }
    }

    private static func prune(prefix: String, keep: URL) {
        guard let dir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let mine = files.filter { $0.lastPathComponent.hasPrefix("\(prefix)-") && $0.pathExtension == "json" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
        for old in mine.dropFirst(8) where old != keep { try? FileManager.default.removeItem(at: old) }
    }

    static func clearAll() {
        guard let dir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" && (f.lastPathComponent.hasPrefix("plan-") || f.lastPathComponent.hasPrefix("details-")) {
            try? FileManager.default.removeItem(at: f)
        }
    }
}
