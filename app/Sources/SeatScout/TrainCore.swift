import Foundation
import CSeatScout


struct CoreError: Error, CustomStringConvertible {
    let code: Int32
    let message: String
    var httpStatus: Int32 = 0

    var isBlocked: Bool { code == TC_ERR_BLOCKED.rawValue }
    var description: String { "Seat Scout (\(code)): \(message)" }

    static func last(_ code: Int32) -> CoreError {
        CoreError(code: code, message: String(cString: tc_last_error()), httpStatus: tc_last_http_status())
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
    var departureCompact: String { departure.filter(\.isNumber).prefix(12).description }
    var arrivalCompact: String { arrival.filter(\.isNumber).prefix(12).description }

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
    var out: Int64 = 0
    return tc_compact_minutes(compact, &out) == 0 ? out : nil
}

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

func coreCompactTime(_ text: String) -> String? {
    var buf = [CChar](repeating: 0, count: 16)
    guard tc_time_compact(text, &buf, buf.count) == 0 else { return nil }
    return String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
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
        var data: UnsafeMutablePointer<UInt8>?
        var len = 0
        let rc = box.withTransport { tc_fetch_stations_packed($0, &data, &len) }
        guard rc == 0, let data else { throw CoreError.last(rc) }
        defer { tc_buffer_free(data, len) }
        let tmp = path + ".tmp"
        try Data(bytes: data, count: len).write(to: URL(fileURLWithPath: tmp))
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
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
