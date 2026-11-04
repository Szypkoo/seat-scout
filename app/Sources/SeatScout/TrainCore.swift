import Foundation
#if !SKIP
import CSeatScout
#endif


struct CoreError: Error, CustomStringConvertible {
    let code: Int32
    let message: String
    var httpStatus: Int32 = 0

    var isBlocked: Bool {
        #if !SKIP
        return code == TC_ERR_BLOCKED.rawValue
        #else
        return code == -3
        #endif
    }
    var description: String { "Seat Scout (\(code)): \(message)" }

    static func last(_ code: Int32) -> CoreError {
        #if !SKIP
        return CoreError(code: code, message: String(cString: tc_last_error()), httpStatus: tc_last_http_status())
        #else
        return CoreError(code: code, message: "Błąd rdzenia \(code)", httpStatus: 0)
        #endif
    }
}

protocol HTTPTransport: AnyObject, Sendable {
    func send(method: String, url: String, body: String?) -> (status: Int32, body: Data)?
}

struct CoreSeat: Identifiable, Hashable, Sendable {
    enum Position: UInt8, Sendable { case unknown = 0, window = 1, aisle = 2 }
    let number: Int
    let isFree: Bool
    let position: Position
    let isSpecial: Bool
    var xy: (x: Int, y: Int)? = nil
    var id: Int { number }

    static func == (a: CoreSeat, b: CoreSeat) -> Bool { a.number == b.number && a.isFree == b.isFree }
    func hash(into h: inout Hasher) { h.combine(number) }
}

struct CoreDecor: Hashable, Sendable, Identifiable {
    let x: Int, y: Int, w: Int, h: Int
    let isSign: Bool
    let code: String
    let title: String
    var id: String { "\(code)-\(x)-\(y)" }
}

struct CoreWagon: Identifiable, Sendable {
    let wagon: Int
    let travelClass: Int
    let freeCount: Int
    let occupiedCount: Int
    let seats: [CoreSeat]
    var width: Int = 0
    var height: Int = 0
    var decor: [CoreDecor] = []
    var direction: Int = 0
    var compartments: Int = -1
    var id: String { "\(wagon)-\(travelClass)" }
}

struct CoreTrain: Identifiable, Hashable, Sendable {
    let connectionId: Int64
    let number: Int64
    let category: String
    let name: String
    let departure: String
    let arrival: String
    let fromKod: UInt32
    let toKod: UInt32
    var id: Int64 { number }

    var departureHHMM: String { Self.hhmm(departure) }
    var arrivalHHMM: String { Self.hhmm(arrival) }
    var departureCompact: String {
        #if !SKIP
        return departure.filter(\.isNumber).prefix(12).description
        #else
        var res = ""
        for ch in departure {
            if ch >= "0" && ch <= "9" {
                res += String(ch)
                if res.count == 12 { break }
            }
        }
        return res
        #endif
    }
    var arrivalCompact: String {
        #if !SKIP
        return arrival.filter(\.isNumber).prefix(12).description
        #else
        var res = ""
        for ch in arrival {
            if ch >= "0" && ch <= "9" {
                res += String(ch)
                if res.count == 12 { break }
            }
        }
        return res
        #endif
    }

    private static func hhmm(_ s: String) -> String {
        guard s.count >= 16 else { return s }
        let start = s.index(s.startIndex, offsetBy: 11)
        return String(s[start..<s.index(start, offsetBy: 5)])
    }
}

struct CoreStation: Identifiable, Hashable, Sendable {
    let kod: UInt32
    let epa: UInt32
    let eva: UInt32
    let name: String
    var id: UInt32 { kod }
}

struct CoreStop: Identifiable, Sendable {
    let name: String
    let eva: UInt32
    let arrival: String
    let departure: String
    let canBoard: Bool
    let canAlight: Bool
    var platform: String = ""
    var track: String = ""
    var arrivalActual: String = ""
    var departureActual: String = ""
    var messages: String = ""
    var id: UInt32 { eva }
}


struct TripStopInfo: Sendable {
    let schedArr: Int64, schedDep: Int64, arr: Int64, dep: Int64
    let arrActual: Bool, depActual: Bool
}

struct TripInfo: Sendable {
    enum State: Sendable, Equatable {
        case notStarted
        case atStation(Int)
        case between(Int, Int)
        case finished
    }
    let state: State
    let isActual: Bool
    let delay: Int?
    let nextStop: Bool
    let minutesToNext: Int
    let progress: Double
    let stops: [TripStopInfo]
}

func coreClock(_ minutes: Int64) -> String {
    let m = ((minutes % 1440) + 1440) % 1440
    return String(format: "%02d:%02d", Int(m / 60), Int(m % 60))
}

func coreCompactMinutes(_ compact: String) -> Int64? {
    #if !SKIP
    var out: Int64 = 0
    return tc_compact_minutes(compact, &out) == 0 ? out : nil
    #else
    guard compact.count >= 12 else { return nil }
    let s = compact.dropFirst(8)
    guard let h = Int64(s.prefix(2)), let m = Int64(s.dropFirst(2).prefix(2)) else { return nil }
    return h * 60 + m
    #endif
}

#if !SKIP
final class CoreRoute: @unchecked Sendable {
    private let handle: OpaquePointer
    let stops: [CoreStop]

    fileprivate init(handle: OpaquePointer, stops: [CoreStop]) {
        self.handle = handle
        self.stops = stops
    }

    deinit { tc_route_free(handle) }

    func track(nowMinutes: Int64) -> TripInfo? {
        guard let trip = tc_route_track(handle, nowMinutes) else { return nil }
        defer { tc_trip_free(trip) }
        var st = TcTripStatus()
        guard tc_trip_status(trip, &st) == 0 else { return nil }
        let preds: [TripStopInfo] = (0..<stops.count).compactMap { i in
            var p = TcStopPrediction()
            guard tc_trip_stop(trip, i, &p) == 0 else { return nil }
            return TripStopInfo(schedArr: p.sched_arr, schedDep: p.sched_dep, arr: p.arr, dep: p.dep,
                                arrActual: p.arr_actual != 0, depActual: p.dep_actual != 0)
        }
        let state: TripInfo.State
        switch Int(st.state) {
        case Int(TC_TRIP_NOT_STARTED.rawValue): state = .notStarted
        case Int(TC_TRIP_AT_STATION.rawValue): state = .atStation(Int(st.from_index))
        case Int(TC_TRIP_BETWEEN.rawValue): state = .between(Int(st.from_index), Int(st.to_index))
        default: state = .finished
        }
        return TripInfo(state: state, isActual: st.source != 0, delay: st.has_delay != 0 ? Int(st.delay_min) : nil,
                        nextStop: st.has_next != 0, minutesToNext: Int(st.minutes_to_next),
                        progress: Double(st.progress_permille) / 1000, stops: preds)
    }
}
#else
final class CoreRoute: @unchecked Sendable {
    let stops: [CoreStop]
    init(stops: [CoreStop] = []) { self.stops = stops }
    func track(nowMinutes: Int64) -> TripInfo? {
        guard stops.count >= 2 else { return nil }
        var preds: [TripStopInfo] = []
        for (i, _) in stops.enumerated() {
            let sched = Int64(560 + i * 50)
            preds.append(TripStopInfo(schedArr: sched, schedDep: sched + 2, arr: sched, dep: sched + 2, arrActual: i == 0, depActual: i == 0))
        }
        return TripInfo(
            state: .between(0, 1),
            isActual: true,
            delay: 0,
            nextStop: true,
            minutesToNext: 18,
            progress: 0.38,
            stops: preds
        )
    }
}
#endif

func coreCompactTime(_ text: String) -> String? {
    #if !SKIP
    var buf = [CChar](repeating: 0, count: 16)
    guard tc_time_compact(text, &buf, buf.count) == 0 else { return nil }
    return String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    #else
    var res = ""
    for ch in text {
        if ch >= "0" && ch <= "9" {
            res += String(ch)
            if res.count == 12 { break }
        }
    }
    if res.count == 12 { return res }
    if res.count == 4 {
        return "20261104" + res
    }
    return nil
    #endif
}

func coreHHMM(_ text: String) -> String {
    guard let c = coreCompactTime(text) else { return "--:--" }
    return "\(c.dropFirst(8).prefix(2)):\(c.dropFirst(10).prefix(2))"
}


struct PlanRunInfo: Identifiable, Sendable {
    let id = UUID()
    let fromStop: Int
    let toStop: Int
    let wagon: Int
    let seat: Int?
    var seat2: Int? = nil
    let isWindow: Bool
    let minutes: Int
}

struct SeatPlan: Sendable {
    let runs: [PlanRunInfo]
    let seatedMinutes: Int
    let totalMinutes: Int
    let changes: Int
    let fullRideSeats: Int

    var seatedPercent: Int { totalMinutes > 0 ? Int((Double(seatedMinutes) / Double(totalMinutes) * 100).rounded()) : 0 }
}

#if !SKIP
final class SeatPlanner: @unchecked Sendable {
    private let handle: OpaquePointer
    private let lock = NSLock()

    init?(arrivals: [Int32], departures: [Int32]) {
        guard arrivals.count == departures.count, arrivals.count >= 2,
              let h = tc_planner_new(arrivals.count, arrivals, departures) else { return nil }
        handle = h
    }

    deinit { tc_planner_free(handle) }

    func setLeg(_ leg: Int, wagons: [CoreWagon]) {
        lock.lock(); defer { lock.unlock() }
        for w in wagons {
            for s in w.seats where s.isFree && !s.isSpecial {
                _ = tc_planner_add_free_seat_xy(handle, leg, Int32(w.wagon), UInt16(s.number), s.position == .window ? 1 : 0,
                                                s.xy != nil ? 1 : 0, Int32(s.xy?.x ?? 0), Int32(s.xy?.y ?? 0))
            }
        }
    }

    func solve(board: Int, alight: Int, changePenaltyMinutes: Int) -> SeatPlan? {
        guard let plan = tc_planner_solve(handle, board, alight, Int32(changePenaltyMinutes)) else { return nil }
        defer { tc_plan_free(plan) }
        return Self.convert(plan)
    }

    func solvePairs(board: Int, alight: Int, changePenaltyMinutes: Int) -> SeatPlan? {
        guard let plan = tc_planner_solve_pairs(handle, board, alight, Int32(changePenaltyMinutes)) else { return nil }
        defer { tc_plan_free(plan) }
        return Self.convert(plan)
    }

    func solveMany(board: Int, alight: Int, changePenaltyMinutes: Int, people: Int) -> [SeatPlan]? {
        var handles = [OpaquePointer?](repeating: nil, count: people)
        guard tc_planner_solve_many(handle, board, alight, Int32(changePenaltyMinutes), people, &handles) == 0 else { return nil }
        defer { for handle in handles { if let handle { tc_plan_free(handle) } } }
        let plans = handles.compactMap { $0.flatMap(Self.convert) }
        return plans.count == people ? plans : nil
    }

    func solveSeparate(board: Int, alight: Int, changePenaltyMinutes: Int) -> (SeatPlan, SeatPlan)? {
        var pa: OpaquePointer?, pb: OpaquePointer?
        guard tc_planner_solve_separate(handle, board, alight, Int32(changePenaltyMinutes), &pa, &pb) == 0,
              let pa, let pb else { return nil }
        defer { tc_plan_free(pa); tc_plan_free(pb) }
        guard let a = Self.convert(pa), let b = Self.convert(pb) else { return nil }
        return (a, b)
    }

    private static func convert(_ plan: OpaquePointer) -> SeatPlan? {
        var sum = TcPlanSummary()
        guard tc_plan_summary(plan, &sum) == 0 else { return nil }
        let runs: [PlanRunInfo] = (0..<tc_plan_run_count(plan)).compactMap { i in
            var r = TcPlanRun()
            guard tc_plan_run(plan, i, &r) == 0 else { return nil }
            return PlanRunInfo(fromStop: Int(r.from_stop), toStop: Int(r.to_stop), wagon: Int(r.wagon),
                               seat: r.has_seat != 0 ? Int(r.seat) : nil,
                               seat2: r.has_seat2 != 0 ? Int(r.seat2) : nil,
                               isWindow: r.window != 0, minutes: Int(r.minutes))
        }
        return SeatPlan(runs: runs, seatedMinutes: Int(sum.seated_minutes), totalMinutes: Int(sum.total_minutes),
                        changes: Int(sum.changes), fullRideSeats: Int(sum.full_ride_seats))
    }
}


final class StationDictionary: @unchecked Sendable {
    private let handle: OpaquePointer

    init?(path: String) {
        guard let h = tc_stations_open(path) else { return nil }
        handle = h
    }

    deinit { tc_stations_close(handle) }

    var count: Int { tc_stations_count(handle) }

    func find(_ query: String) -> CoreStation? {
        var out = TcStation()
        guard tc_stations_find(handle, query, &out) != Int32(TC_MATCH_NONE.rawValue) else { return nil }
        return Self.convert(out)
    }

    func station(eva: UInt32) -> CoreStation? {
        var out = TcStation()
        return tc_stations_find_eva(handle, eva, &out) == 0 ? Self.convert(out) : nil
    }

    func suggest(_ query: String, limit: Int = 8) -> [CoreStation] {
        var buf = [TcStation](repeating: TcStation(), count: max(1, min(limit, 64)))
        let n = tc_stations_suggest(handle, query, &buf, buf.count)
        return buf.prefix(n).map(Self.convert)
    }

    private static func convert(_ s: TcStation) -> CoreStation {
        CoreStation(kod: s.kod, epa: s.epa, eva: s.eva, name: String(cString: s.name))
    }
}


final class TrainCoreClient: @unchecked Sendable {
    private let box: TransportBox

    init(transport: any HTTPTransport) {
        box = TransportBox(transport)
    }

    static var version: String { String(cString: tc_version()) }

    func downloadStations(to path: String) throws {
        #if !SKIP
        var data: UnsafeMutablePointer<UInt8>?
        var len = 0
        let rc = box.withTransport { tc_fetch_stations_packed($0, &data, &len) }
        guard rc == 0, let data else { throw CoreError.last(rc) }
        defer { tc_buffer_free(data, len) }
        let tmp = path + ".tmp"
        try Data(bytes: data, count: len).write(to: URL(fileURLWithPath: tmp))
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
        #endif
    }

    func searchConnections(date: String, from: CoreStation, to: CoreStation) throws -> [CoreTrain] {
        let list = box.withTransport { tc_search_connections($0, date, from.kod, to.kod) }
        guard let list else { throw CoreError.last(Int32(TC_ERR_PARSE.rawValue)) }
        defer { tc_connections_free(list) }
        return (0..<tc_connections_count(list)).compactMap { i in
            var t = TcTrain()
            guard tc_connections_get(list, i, &t) == 0 else { return nil }
            return CoreTrain(
                connectionId: t.id_polaczenia, number: t.number,
                category: String(cString: t.category), name: String(cString: t.name),
                departure: String(cString: t.dep), arrival: String(cString: t.arr),
                fromKod: t.from_kod, toKod: t.to_kod)
        }
    }

    func seats(
        train: CoreTrain, from: CoreStation, to: CoreStation,
        travelClass: Int = 2, excludeSpecial: Bool = true, delayMs: UInt32 = 100, concurrency: UInt32 = 4
    ) throws -> [CoreWagon] {
        try seats(train: train, from: from, to: to, departure: train.departureCompact, arrival: train.arrivalCompact,
                  travelClass: travelClass, excludeSpecial: excludeSpecial, delayMs: delayMs, concurrency: concurrency)
    }

    func seats(
        train: CoreTrain, from: CoreStation, to: CoreStation, departure: String, arrival: String,
        travelClass: Int = 2, excludeSpecial: Bool = true, delayMs: UInt32 = 100, concurrency: UInt32 = 4
    ) throws -> [CoreWagon] {
        let report = box.withTransport {
            tc_seats_for_segment(
                $0, train.category, train.number, from.epa, to.epa,
                departure, arrival, Int32(travelClass), excludeSpecial ? 1 : 0, delayMs, concurrency)
        }
        guard let report else {
            let err = CoreError.last(Int32(TC_ERR_PARSE.rawValue))
            log(.error, "core", "seats \(train.category) \(train.number) \(from.name)→\(to.name): \(err.message) [HTTP \(err.httpStatus)]")
            throw err
        }
        defer { tc_report_free(report) }
        for i in 0..<tc_report_warning_count(report) {
            if let w = tc_report_warning(report, i) {
                log(.warn, "core", "\(from.name)→\(to.name): \(String(cString: w))")
            }
        }
        return (0..<tc_report_count(report)).compactMap { i in
            var w = TcWagon()
            guard tc_report_get(report, i, &w) == 0 else { return nil }
            let seats = (0..<w.seats_len).map { j -> CoreSeat in
                let s = w.seats[j]
                return CoreSeat(
                    number: Int(s.number), isFree: s.free != 0,
                    position: CoreSeat.Position(rawValue: s.position) ?? .unknown, isSpecial: s.special != 0,
                    xy: s.has_xy != 0 ? (Int(s.x), Int(s.y)) : nil)
            }
            let decor: [CoreDecor] = (0..<w.decor_len).map { j in
                let d = w.decor[j]
                let code = withUnsafePointer(to: d.code) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 8) { String(cString: $0) }
                }
                return CoreDecor(x: Int(d.x), y: Int(d.y), w: Int(d.w), h: Int(d.h), isSign: d.kind != 0,
                                 code: code, title: d.title.map { String(cString: $0) } ?? "")
            }
            return CoreWagon(
                wagon: Int(w.wagon), travelClass: Int(w.klasa),
                freeCount: Int(w.free_count), occupiedCount: Int(w.occupied_count), seats: seats,
                width: Int(w.width), height: Int(w.height), decor: decor, direction: Int(tc_report_direction(report)),
                compartments: Int(tc_report_compartments(report, i)))
        }
    }

    func route(train: CoreTrain, from: CoreStation, to: CoreStation) throws -> [CoreStop] {
        try routeHandle(train: train, from: from, to: to).stops
    }

    func routeHandle(train: CoreTrain, from: CoreStation, to: CoreStation) throws -> CoreRoute {
        let route: OpaquePointer? = box.withTransport { tr in
            train.category.withCString { cat in
                train.name.withCString { name in
                    train.departure.withCString { dep in
                        train.arrival.withCString { arr in
                            var t = TcTrain(
                                id_polaczenia: train.connectionId, number: train.number,
                                category: cat, name: name, dep: dep, arr: arr,
                                from_kod: train.fromKod, to_kod: train.toKod)
                            return tc_train_route(tr, &t, from.eva, to.eva)
                        }
                    }
                }
            }
        }
        guard let route else { throw CoreError.last(Int32(TC_ERR_PARSE.rawValue)) }
        let stops: [CoreStop] = (0..<tc_route_count(route)).compactMap { i in
            var s = TcStop()
            guard tc_route_get(route, i, &s) == 0 else { return nil }
            return CoreStop(name: String(cString: s.name), eva: s.eva, arrival: String(cString: s.arr),
                            departure: String(cString: s.dep), canBoard: s.can_board != 0, canAlight: s.can_alight != 0,
                            platform: String(cString: s.platform), track: String(cString: s.track),
                            arrivalActual: String(cString: s.arr_actual), departureActual: String(cString: s.dep_actual),
                            messages: String(cString: s.messages))
        }
        return CoreRoute(handle: route, stops: stops)
    }

    func price(train: CoreTrain, travelClass: Int = 2, discountCode: Int32) throws -> Double {
        var out = 0.0
        let rc: Int32 = box.withTransport { tr in
            train.category.withCString { cat in
                train.name.withCString { name in
                    train.departure.withCString { dep in
                        train.arrival.withCString { arr in
                            var t = TcTrain(
                                id_polaczenia: train.connectionId, number: train.number,
                                category: cat, name: name, dep: dep, arr: arr,
                                from_kod: train.fromKod, to_kod: train.toKod)
                            return tc_ticket_price(tr, &t, Int32(travelClass), discountCode, &out)
                        }
                    }
                }
            }
        }
        guard rc == 0 else { throw CoreError.last(rc) }
        return out
    }
}


private final class TransportBox: @unchecked Sendable {
    let transport: any HTTPTransport
    init(_ t: any HTTPTransport) { transport = t }

    func withTransport<R>(_ body: (UnsafePointer<TcTransport>) -> R) -> R {
        var tr = TcTransport(ctx: Unmanaged.passUnretained(self).toOpaque(), fn: transportCallback)
        return withUnsafePointer(to: &tr, body)
    }
}

private let transportCallback: TcHttpFn = { ctx, method, url, body, out in
    guard let ctx, let method, let url, let out else { return 1 }
    let box = Unmanaged<TransportBox>.fromOpaque(ctx).takeUnretainedValue()
    let bodyString = body.map { String(cString: $0) }
    guard let resp = box.transport.send(method: String(cString: method), url: String(cString: url), body: bodyString) else {
        return 1
    }
    out.pointee.status = resp.body.isEmpty && resp.status == 0 ? 0 : resp.status
    out.pointee.len = resp.body.count
    guard let mem = malloc(resp.body.count + 1) else { return 1 }
    resp.body.copyBytes(to: mem.assumingMemoryBound(to: UInt8.self), count: resp.body.count)
    mem.assumingMemoryBound(to: UInt8.self)[resp.body.count] = 0
    out.pointee.data = mem.assumingMemoryBound(to: CChar.self)
    return 0
}
#else
final class SeatPlanner: @unchecked Sendable {
    init?(arrivals: [Int32], departures: [Int32]) {}
    func setLeg(_ leg: Int, wagons: [CoreWagon]) {}
    func solve(board: Int, alight: Int, changePenaltyMinutes: Int) -> SeatPlan? {
        let mins = 145
        return SeatPlan(
            runs: [
                PlanRunInfo(fromStop: board, toStop: alight, wagon: 2, seat: 34, seat2: nil, isWindow: true, minutes: mins)
            ],
            seatedMinutes: mins,
            totalMinutes: mins,
            changes: 0,
            fullRideSeats: 1
        )
    }
    func solvePairs(board: Int, alight: Int, changePenaltyMinutes: Int) -> SeatPlan? {
        let mins = 145
        return SeatPlan(
            runs: [
                PlanRunInfo(fromStop: board, toStop: alight, wagon: 2, seat: 33, seat2: 34, isWindow: false, minutes: mins)
            ],
            seatedMinutes: mins,
            totalMinutes: mins,
            changes: 0,
            fullRideSeats: 2
        )
    }
    func solveMany(board: Int, alight: Int, changePenaltyMinutes: Int, people: Int) -> [SeatPlan]? {
        let mins = 145
        return (0..<people).map { i in
            SeatPlan(
                runs: [
                    PlanRunInfo(fromStop: board, toStop: alight, wagon: 2, seat: 31 + i, seat2: nil, isWindow: i % 2 == 0, minutes: mins)
                ],
                seatedMinutes: mins,
                totalMinutes: mins,
                changes: 0,
                fullRideSeats: 1
            )
        }
    }
    func solveSeparate(board: Int, alight: Int, changePenaltyMinutes: Int) -> (SeatPlan, SeatPlan)? {
        let s = solve(board: 0, alight: 1, changePenaltyMinutes: 10)!
        return (s, s)
    }
}

final class StationDictionary: @unchecked Sendable {
    init?(path: String) {}
    var count: Int { Self.knownStations.count }

    private static let knownStations: [CoreStation] = [
        CoreStation(kod: UInt32(1), epa: UInt32(101), eva: UInt32(5100004), name: "Bielsko-Biała Główna"),
        CoreStation(kod: UInt32(2), epa: UInt32(102), eva: UInt32(5100049), name: "Poznań Główny"),
        CoreStation(kod: UInt32(3), epa: UInt32(103), eva: UInt32(5100065), name: "Warszawa Centralna"),
        CoreStation(kod: UInt32(4), epa: UInt32(104), eva: UInt32(5100028), name: "Kraków Główny"),
        CoreStation(kod: UInt32(5), epa: UInt32(105), eva: UInt32(5100014), name: "Gdańsk Główny"),
        CoreStation(kod: UInt32(6), epa: UInt32(106), eva: UInt32(5100069), name: "Wrocław Główny"),
        CoreStation(kod: UInt32(7), epa: UInt32(107), eva: UInt32(5100020), name: "Katowice"),
        CoreStation(kod: UInt32(8), epa: UInt32(108), eva: UInt32(5100015), name: "Gdynia Główna"),
        CoreStation(kod: UInt32(9), epa: UInt32(109), eva: UInt32(5100037), name: "Łódź Fabryczna"),
        CoreStation(kod: UInt32(10), epa: UInt32(110), eva: UInt32(5100057), name: "Szczecin Główny"),
    ]

    func find(_ query: String) -> CoreStation? {
        let q = query.lowercased()
        if q.contains("bielsk") { return Self.knownStations[0] }
        if q.contains("pozna") { return Self.knownStations[1] }
        if q.contains("warszaw") { return Self.knownStations[2] }
        if q.contains("krak") { return Self.knownStations[3] }
        if q.contains("gda") { return Self.knownStations[4] }
        if q.contains("wroc") || q.contains("wrocł") { return Self.knownStations[5] }
        if q.contains("katowic") { return Self.knownStations[6] }
        if q.contains("gdyni") { return Self.knownStations[7] }
        if q.contains("łód") || q.contains("lod") { return Self.knownStations[8] }
        if q.contains("szczec") { return Self.knownStations[9] }

        var hash = 0
        for ch in query.utf8 { hash = (hash * 31 + Int(ch)) & 0x7FFFFFFF }
        let uniqueKod = UInt32((hash % 800000) + 1000)
        let uniqueEva = UInt32(5100000 + (hash % 90000))
        return CoreStation(kod: uniqueKod, epa: uniqueKod, eva: uniqueEva, name: query)
    }

    func station(eva: UInt32) -> CoreStation? {
        if let found = Self.knownStations.first(where: { $0.eva == eva }) {
            return found
        }
        return CoreStation(kod: eva, epa: eva, eva: eva, name: "Stacja \(eva)")
    }

    func suggest(_ query: String, limit: Int = 8) -> [CoreStation] {
        let q = query.lowercased()
        let filtered = Self.knownStations.filter { $0.name.lowercased().contains(q) }
        return filtered.isEmpty ? Array(Self.knownStations.prefix(limit)) : Array(filtered.prefix(limit))
    }
}

final class TrainCoreClient: @unchecked Sendable {
    init(transport: any HTTPTransport) {}
    static var version: String { "0.1.0" }
    func downloadStations(to path: String) throws {}

    func searchConnections(date: String, from: CoreStation, to: CoreStation) throws -> [CoreTrain] {
        [
            CoreTrain(connectionId: 101, number: 45000, category: "EIC", name: "Beskidy",
                      departure: "\(date) 06:15:00", arrival: "\(date) 11:32:00",
                      fromKod: from.kod, toKod: to.kod),
            CoreTrain(connectionId: 102, number: 41100, category: "IC", name: "Korfanty",
                      departure: "\(date) 09:20:00", arrival: "\(date) 14:45:00",
                      fromKod: from.kod, toKod: to.kod),
            CoreTrain(connectionId: 103, number: 38102, category: "TLK", name: "Szyndzielnia",
                      departure: "\(date) 13:40:00", arrival: "\(date) 19:15:00",
                      fromKod: from.kod, toKod: to.kod),
            CoreTrain(connectionId: 104, number: 45102, category: "IC", name: "Hutnik",
                      departure: "\(date) 17:05:00", arrival: "\(date) 22:30:00",
                      fromKod: from.kod, toKod: to.kod),
        ]
    }

    func seats(train: CoreTrain, from: CoreStation, to: CoreStation, travelClass: Int = 2, excludeSpecial: Bool = true) throws -> [CoreWagon] {
        // Wagon 2: 2. klasa bezprzedziałowa (15 rzędów po 4 fotele, szer: 760, wys: 200)
        var seatsW2: [CoreSeat] = []
        for r in 0..<15 {
            let n1 = r * 4 + 1
            let n2 = r * 4 + 2
            let n3 = r * 4 + 3
            let n4 = r * 4 + 4
            let xPos = 70 + r * 44
            seatsW2.append(CoreSeat(number: n1, isFree: n1 % 3 != 0, position: .window, isSpecial: false, xy: (x: xPos, y: 24)))
            seatsW2.append(CoreSeat(number: n2, isFree: n2 % 4 != 0, position: .aisle, isSpecial: false, xy: (x: xPos, y: 64)))
            seatsW2.append(CoreSeat(number: n3, isFree: n3 % 2 == 0, position: .aisle, isSpecial: false, xy: (x: xPos, y: 136)))
            seatsW2.append(CoreSeat(number: n4, isFree: n4 % 3 != 0, position: .window, isSpecial: false, xy: (x: xPos, y: 176)))
        }

        // Wagon 1: 1. klasa (9 przedziałów po 6 miejsc)
        var seatsW1: [CoreSeat] = []
        for r in 0..<9 {
            let comp = r + 1
            let x1 = 80 + r * 72
            let x2 = x1 + 36
            // Rząd 1 naprzeciwko
            seatsW1.append(CoreSeat(number: comp * 10 + 1, isFree: (comp + 1) % 2 == 0, position: .window, isSpecial: false, xy: (x: x1, y: 30)))
            seatsW1.append(CoreSeat(number: comp * 10 + 2, isFree: true, position: .unknown, isSpecial: false, xy: (x: x1, y: 70)))
            seatsW1.append(CoreSeat(number: comp * 10 + 3, isFree: comp % 3 != 0, position: .aisle, isSpecial: false, xy: (x: x1, y: 110)))
            // Rząd 2
            seatsW1.append(CoreSeat(number: comp * 10 + 4, isFree: true, position: .window, isSpecial: false, xy: (x: x2, y: 30)))
            seatsW1.append(CoreSeat(number: comp * 10 + 5, isFree: (comp + 2) % 3 != 0, position: .unknown, isSpecial: false, xy: (x: x2, y: 70)))
            seatsW1.append(CoreSeat(number: comp * 10 + 6, isFree: true, position: .aisle, isSpecial: false, xy: (x: x2, y: 110)))
        }

        // Wagon 3: 2. klasa z miejscami specjalnymi (OzN / rower)
        var seatsW3: [CoreSeat] = []
        for r in 0..<12 {
            let n1 = r * 4 + 1
            let n2 = r * 4 + 2
            let n3 = r * 4 + 3
            let n4 = r * 4 + 4
            let xPos = 80 + r * 48
            let special = r >= 10
            seatsW3.append(CoreSeat(number: n1, isFree: true, position: .window, isSpecial: special, xy: (x: xPos, y: 24)))
            seatsW3.append(CoreSeat(number: n2, isFree: n2 % 3 != 0, position: .aisle, isSpecial: special, xy: (x: xPos, y: 64)))
            seatsW3.append(CoreSeat(number: n3, isFree: n3 % 2 == 0, position: .aisle, isSpecial: false, xy: (x: xPos, y: 136)))
            seatsW3.append(CoreSeat(number: n4, isFree: true, position: .window, isSpecial: false, xy: (x: xPos, y: 176)))
        }

        let decorW2 = [
            CoreDecor(x: 18, y: 18, w: 42, h: 42, isSign: true, code: "401", title: "Toaleta"),
            CoreDecor(x: 720, y: 140, w: 35, h: 35, isSign: true, code: "402", title: "Bagaż"),
        ]

        let decorW1 = [
            CoreDecor(x: 18, y: 18, w: 42, h: 42, isSign: true, code: "401", title: "Toaleta"),
            CoreDecor(x: 720, y: 130, w: 35, h: 35, isSign: true, code: "405", title: "Bufet WARS"),
        ]

        let decorW3 = [
            CoreDecor(x: 18, y: 140, w: 42, h: 42, isSign: true, code: "403", title: "Miejsce na rowery"),
            CoreDecor(x: 18, y: 18, w: 42, h: 42, isSign: true, code: "401", title: "Toaleta z przewijakiem"),
        ]

        return [
            CoreWagon(wagon: 1, travelClass: 1, freeCount: 27, occupiedCount: 27, seats: seatsW1, width: 760, height: 200, decor: decorW1, direction: 1, compartments: 1),
            CoreWagon(wagon: 2, travelClass: 2, freeCount: 38, occupiedCount: 22, seats: seatsW2, width: 760, height: 200, decor: decorW2, direction: 1, compartments: 0),
            CoreWagon(wagon: 3, travelClass: 2, freeCount: 32, occupiedCount: 16, seats: seatsW3, width: 760, height: 200, decor: decorW3, direction: 1, compartments: 0),
        ]
    }

    func seats(train: CoreTrain, from: CoreStation, to: CoreStation, departure: String, arrival: String, travelClass: Int = 2, excludeSpecial: Bool = true) throws -> [CoreWagon] {
        try seats(train: train, from: from, to: to, travelClass: travelClass, excludeSpecial: excludeSpecial)
    }

    func route(train: CoreTrain, from: CoreStation, to: CoreStation) throws -> [CoreStop] {
        let day = String(train.departure.prefix(10))
        return [
            CoreStop(name: from.name, eva: from.eva,
                     arrival: "\(day) 09:20:00", departure: "\(day) 09:20:00",
                     canBoard: true, canAlight: false, platform: "1", track: "2",
                     arrivalActual: "\(day) 09:20:00", departureActual: "\(day) 09:21:00", messages: ""),
            CoreStop(name: "Katowice", eva: UInt32(5100020),
                     arrival: "\(day) 10:15:00", departure: "\(day) 10:20:00",
                     canBoard: true, canAlight: true, platform: "3", track: "1",
                     arrivalActual: "\(day) 10:14:00", departureActual: "\(day) 10:20:00", messages: ""),
            CoreStop(name: "Wrocław Główny", eva: UInt32(5100069),
                     arrival: "\(day) 12:30:00", departure: "\(day) 12:35:00",
                     canBoard: true, canAlight: true, platform: "2", track: "4",
                     arrivalActual: "", departureActual: "", messages: ""),
            CoreStop(name: to.name, eva: to.eva,
                     arrival: "\(day) 14:45:00", departure: "\(day) 14:45:00",
                     canBoard: false, canAlight: true, platform: "4", track: "2",
                     arrivalActual: "", departureActual: "", messages: ""),
        ]
    }

    func routeHandle(train: CoreTrain, from: CoreStation, to: CoreStation) throws -> CoreRoute {
        let stops = try route(train: train, from: from, to: to)
        return CoreRoute(stops: stops)
    }

    func price(train: CoreTrain, travelClass: Int = 2, discountCode: Int32) throws -> Double {
        let base = (train.category == "EIC" || train.category == "EIP") ? 149.00 : 78.00
        let classMultiplier = travelClass == 1 ? 1.4 : 1.0
        let fullPrice = base * classMultiplier
        switch discountCode {
        case 1710: return (fullPrice * 0.63).rounded()
        case 1990: return (fullPrice * 0.49).rounded()
        default: return fullPrice
        }
    }
}
#endif
