import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .live
    @Published var remainingSeconds: Int = 16892
    @Published var selectedDiscountIndex: Int = 1 { didSet { savePrefs() } }
    @Published var selectedTrainIndex: Int = 0
    @Published var toastMessage: String?
    @Published var isLive: Bool = false
    @Published var isLoading: Bool = false

    @Published var showSearch = false
    @Published var isSearching = false
    @Published var fromStation: CoreStation?
    @Published var toStation: CoreStation?
    @Published var searchDate = Date().addingTimeInterval(24 * 3600)
    @Published private(set) var dictionary: StationDictionary?

    @Published private(set) var planStops: [CoreStop] = []
    @Published private(set) var planBoard = 0
    @Published private(set) var planAlight = 0
    @Published private(set) var balancedPlan: SeatPlan?
    @Published private(set) var singleSeatPlan: SeatPlan?
    @Published private(set) var secondPersonPlan: SeatPlan?
    @Published private(set) var planPeople = 1
    @Published private(set) var planTogether = true
    @Published private(set) var failedLegs = 0
    @Published private(set) var planDataAge: Date?
    @Published private(set) var ticketPrices: [Int: Double] = [:]
    @Published private(set) var priceNote: String?
    @Published private(set) var trip: TripInfo?
    @Published private(set) var tripStops: [CoreStop] = []
    @Published private(set) var tripUpdated: Date?
    @Published private(set) var tripError: String?
    @Published var isLoadingSegments = false
    @Published var segmentsProgress = ""

    func currentWatchTarget() -> WatchTarget? {
        guard isLive, let core = coreTrains[currentTrain.id], let f = fromStation, let t = toStation else { return nil }
        return WatchTarget(trainNumber: core.number, category: core.category, name: core.name, connectionId: core.connectionId,
                           departure: core.departure, arrival: core.arrival, fromKod: core.fromKod, toKod: core.toKod,
                           fromEva: f.eva, fromEpa: f.epa, fromName: f.name, toEva: t.eva, toEpa: t.epa, toName: t.name)
    }

    private var prefs = Prefs()

    init() {
        var p = PrefsStore.load()
        p.prune(now: Date(), timeZone: Self.warsaw)
        prefs = p
        if let d = p.discountIndex, discounts.indices.contains(d) { selectedDiscountIndex = d }
        if let n = p.planPeople, (1...2).contains(n) { planPeople = n }
        if let t = p.planTogether { planTogether = t }
        PrefsStore.save(p)
    }

    private func savePrefs() {
        var p = prefs
        p.fromEva = fromStation?.eva ?? p.fromEva
        p.toEva = toStation?.eva ?? p.toEva
        if fromStation != nil { p.date = Self.format("yyyy-MM-dd").string(from: searchDate) }
        p.trainNumber = coreTrains[currentTrain.id]?.number ?? p.trainNumber
        p.discountIndex = selectedDiscountIndex
        p.planPeople = planPeople
        p.planTogether = planTogether
        prefs = p
        PrefsStore.save(p)
    }

    private var seatKey: String? {
        guard let core = coreTrains[currentTrain.id] else { return nil }
        return Prefs.seatKey(trainNumber: core.number, date: String(core.departure.prefix(10)))
    }

    private func syncMySeat() {
        guard let key = seatKey else { return }
        mySeat = prefs.seats[key].map { MySeat(wagon: $0.wagon, number: $0.number) }
    }

    func resetPrefs() {
        prefs = Prefs()
        PrefsStore.save(prefs)
        mySeat = nil
        log(.warn, "app", "ustawienia wyczyszczone – po ponownym uruchomieniu wróci trasa domyślna")
    }

    private var client: TrainCoreClient?
    private var segmentsTask: Task<Void, Never>?
    private var segmentsFor: String?
    private var planner: SeatPlanner?
    private var tripRoute: CoreRoute?
    private var legsData: [Int: [CoreWagon]] = [:]
    private var coreTrains: [String: CoreTrain] = [:]
    private var departureDate: Date?
    private var detailsToken = 0

    @Published var trains: [TrainInfo] = [
        TrainInfo(
            id: "4510",
            number: "IC 4510",
            name: "Heweliusz",
            fromStation: "Bielsko-Biała Gł.",
            departureTime: "05:48",
            toStation: "Poznań Gł.",
            arrivalTime: "10:29",
            duration: "4h 41min",
            basePrice: 75.00,
            wagonNumber: 14,
            freeSeatsCount: 28
        ),
        TrainInfo(
            id: "1410",
            number: "IC 1410",
            name: "Klimczok",
            fromStation: "Katowice",
            departureTime: "06:12",
            toStation: "Warszawa Wsch.",
            arrivalTime: "09:34",
            duration: "3h 22min",
            basePrice: 68.00,
            wagonNumber: 14,
            freeSeatsCount: 19
        ),
        TrainInfo(
            id: "38100",
            number: "TLK 38100",
            name: "Lubomirski",
            fromStation: "Kraków Gł.",
            departureTime: "06:15",
            toStation: "Kołobrzeg",
            arrivalTime: "16:42",
            duration: "10h 27min",
            basePrice: 90.00,
            wagonNumber: 14,
            freeSeatsCount: 34
        )
    ]

    let discounts: [DiscountOption] = [
        DiscountOption(name: "37% Szkoła", discountPercent: 37, badgeText: "Ulga 37% (uczniowska)"),
        DiscountOption(name: "51% Student", discountPercent: 51, badgeText: "Ulga 51% (studencka)"),
        DiscountOption(name: "Normalny", discountPercent: 0, badgeText: "Bilet normalny 100%")
    ]

    @Published var segmentsData: [SegmentItem] = [
        SegmentItem(from: "Bielsko-Biała Gł.", to: "Katowice", depTime: "05:48", arrTime: "06:42", freeSeats: 48, occupancyPercent: 32),
        SegmentItem(from: "Katowice", to: "Sosnowiec Gł.", depTime: "06:45", arrTime: "06:58", freeSeats: 42, occupancyPercent: 41),
        SegmentItem(from: "Sosnowiec Gł.", to: "Zawiercie", depTime: "07:00", arrTime: "07:22", freeSeats: 39, occupancyPercent: 45),
        SegmentItem(from: "Zawiercie", to: "Częstochowa", depTime: "07:24", arrTime: "07:54", freeSeats: 31, occupancyPercent: 57),
        SegmentItem(from: "Częstochowa", to: "Kalisz", depTime: "07:56", arrTime: "09:12", freeSeats: 24, occupancyPercent: 67),
        SegmentItem(from: "Kalisz", to: "Poznań Gł.", depTime: "09:14", arrTime: "10:29", freeSeats: 18, occupancyPercent: 75)
    ]

    @Published private(set) var detailWagons: [CoreWagon] = []
    @Published var mySeat: MySeat?

    struct MySeat: Equatable {
        let wagon: Int
        let number: Int
    }

    var currentTrain: TrainInfo {
        trains[min(selectedTrainIndex, trains.count - 1)]
    }

    var currentDiscount: DiscountOption {
        discounts[min(selectedDiscountIndex, discounts.count - 1)]
    }

    var calculatedPrice: Double {
        ticketPrices[currentDiscount.discountPercent]
            ?? currentTrain.basePrice * (100.0 - Double(currentDiscount.discountPercent)) / 100.0
    }

    var savingsAmount: Double {
        max(0, (ticketPrices[0] ?? currentTrain.basePrice) - calculatedPrice)
    }

    var formattedCountdown: String {
        let h = remainingSeconds / 3600
        let m = (remainingSeconds % 3600) / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    func tick() {
        updateTrip()
        if let departureDate {
            remainingSeconds = max(0, Int(departureDate.timeIntervalSinceNow))
        } else if remainingSeconds > 0 {
            remainingSeconds -= 1
        }
    }

    func selectTrain(_ index: Int) {
        selectedTrainIndex = index
        triggerHaptic()
        showToast("Wybrano: \(trains[index].number) \(trains[index].name)")
        syncMySeat()
        savePrefs()
        if isLive { Task { await loadDetails() } }
    }

    func setMySeat(_ seat: MySeat?) {
        mySeat = seat
        if let key = seatKey {
            prefs.seats[key] = seat.map { SavedSeat(wagon: $0.wagon, number: $0.number) }
            savePrefs()
        }
        triggerHaptic()
        if let seat { showToast("Twój fotel: wagon \(seat.wagon), miejsce \(seat.number)") } else { showToast("Usunięto wybór fotela") }
    }

    func legWagons(_ leg: Int) -> [CoreWagon]? { legsData[leg] }

    var legCount: Int { max(planStops.count - 1, 0) }

    func seatTimeline(wagon: Int, number: Int) -> [Bool?] {
        (0..<legCount).map { leg in
            guard let w = legsData[leg]?.first(where: { $0.wagon == wagon }) else { return nil }
            guard let s = w.seats.first(where: { $0.number == number }) else { return nil }
            return s.isFree && !s.isSpecial
        }
    }

    var plannedSeats: Set<[Int]> {
        var out = Set<[Int]>()
        for plan in [balancedPlan, secondPersonPlan] {
            for r in plan?.runs ?? [] {
                if let s = r.seat { out.insert([r.wagon, s]) }
                if let s = r.seat2 { out.insert([r.wagon, s]) }
            }
        }
        return out
    }

    func priceString(_ value: Double) -> String {
        String(format: "%.2f zł", value).replacingOccurrences(of: ".", with: ",")
    }

    func triggerHaptic() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    func showToast(_ msg: String) {
        log(.info, "ui", "toast: \(msg)")
        withAnimation {
            toastMessage = msg
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toastMessage == msg {
                withAnimation { toastMessage = nil }
            }
        }
    }


    private static let defaultFrom = "Bielsko-Biała Gł."
    private static let defaultTo = "Poznań Gł."

    nonisolated private static let warsaw = TimeZone(identifier: "Europe/Warsaw") ?? .current

    nonisolated private static func format(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = warsaw
        f.dateFormat = pattern
        return f
    }

    nonisolated private static func dictionaryPath() throws -> String {
        let dir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return dir.appendingPathComponent("stations.bin").path
    }

    nonisolated private static func needsRefresh(_ path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else { return true }
        return Date().timeIntervalSince(date) > 7 * 24 * 3600
    }

    nonisolated private static func openDictionary(_ client: TrainCoreClient) throws -> StationDictionary {
        let path = try dictionaryPath()
        if needsRefresh(path) {
            log(.info, "app", "pobieram słownik stacji…")
            try client.downloadStations(to: path)
            log(.info, "app", "słownik stacji zapisany")
        }
        guard let dict = StationDictionary(path: path) else {
            try? FileManager.default.removeItem(atPath: path)
            throw CoreError(code: -5, message: "uszkodzony słownik stacji")
        }
        return dict
    }

    func loadLive() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let client = self.client ?? TrainCoreClient(transport: WebViewTransport(session: WebSession()))
        self.client = client
        log(.info, "app", "start: rdzeń \(TrainCoreClient.version)")
        do {
            if dictionary == nil {
                dictionary = try await Task.detached { try Self.openDictionary(client) }.value
                log(.info, "app", "słownik stacji: \(dictionary?.count ?? 0) stacji")
            }
            if fromStation == nil || toStation == nil {
                fromStation = prefs.fromEva.flatMap { dictionary?.station(eva: $0) } ?? dictionary?.find(Self.defaultFrom)
                toStation = prefs.toEva.flatMap { dictionary?.station(eva: $0) } ?? dictionary?.find(Self.defaultTo)
                searchDate = prefs.searchDate(now: Date(), timeZone: Self.warsaw)
                log(.info, "app", "przywrócono ustawienia: \(prefs.fromEva != nil ? "zapisana trasa" : "trasa domyślna"), data \(Self.format("yyyy-MM-dd").string(from: searchDate))")
            }
            log(.info, "app", "trasa: \(fromStation?.name ?? "?") → \(toStation?.name ?? "?")")
            if await search() {
                if let n = prefs.trainNumber, let idx = trains.firstIndex(where: { $0.id == String(n) }), idx != selectedTrainIndex {
                    selectedTrainIndex = idx
                    log(.info, "app", "przywrócono wybrany pociąg \(trains[idx].number)")
                }
                syncMySeat()
                if !showSearch { await loadDetails() }
            }
        } catch {
            log(.error, "app", "loadLive: \(Self.describe(error))")
            showToast(Self.describe(error))
        }
    }

    func resetDictionary() {
        if let path = try? Self.dictionaryPath() { try? FileManager.default.removeItem(atPath: path) }
        dictionary = nil
        log(.warn, "app", "słownik stacji usunięty – kliknij „Przeładuj dane”")
    }

    func suggestStations(_ query: String) -> [CoreStation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return dictionary?.suggest(q, limit: 6) ?? []
    }

    func swapStations() {
        (fromStation, toStation) = (toStation, fromStation)
    }

    @discardableResult
    func search() async -> Bool {
        guard let client, let from = fromStation, let to = toStation else { return false }
        guard from.kod != to.kod else {
            showToast("Wybierz dwie różne stacje")
            return false
        }
        isSearching = true
        defer { isSearching = false }
        let date = Self.format("yyyy-MM-dd").string(from: searchDate)
        do {
            log(.info, "app", "szukam: \(from.name) → \(to.name), \(date)")
            let found = try await Task.detached { try client.searchConnections(date: date, from: from, to: to) }.value
            log(.info, "app", "znaleziono \(found.count) połączeń bezpośrednich")
            guard !found.isEmpty else {
                showToast("Brak bezpośrednich połączeń \(from.name) → \(to.name)")
                return false
            }
            coreTrains = Dictionary(found.map { (String($0.number), $0) }, uniquingKeysWith: { a, _ in a })
            trains = found.map { Self.trainInfo($0, from: from, to: to, price: 0, wagon: 0, free: 0) }
            selectedTrainIndex = 0
            departureDate = nil
            isLive = true
            syncMySeat()
            savePrefs()
            return true
        } catch {
            log(.error, "app", "search: \(Self.describe(error))")
            showToast(Self.describe(error))
            return false
        }
    }

    func pickSearchResult(_ index: Int) {
        guard trains.indices.contains(index) else { return }
        selectedTrainIndex = index
        showSearch = false
        selectedTab = .live
        triggerHaptic()
        syncMySeat()
        savePrefs()
        Task { await loadDetails() }
    }

    var searchSummary: String {
        guard let f = fromStation, let t = toStation else { return "Szukaj pociągu" }
        let day = Self.format("d.MM").string(from: searchDate)
        return "\(Self.shortName(f.name)) → \(Self.shortName(t.name)) · \(day)"
    }

    nonisolated private static func shortName(_ n: String) -> String {
        n.replacingOccurrences(of: " Gł.", with: "").replacingOccurrences(of: " Główny", with: "")
    }

    func loadDetails() async {
        guard let client, let from = fromStation, let to = toStation,
              let core = coreTrains[currentTrain.id] else { return }
        detailsToken += 1
        let token = detailsToken
        departureDate = Self.format("yyyy-MM-dd HH:mm:ss").date(from: core.departure)
        tick()
        log(.info, "app", "szczegóły: \(core.category) \(core.number) \(core.name)")

        let detailsKey = Self.cacheKey(core, from, to)
        let cachedDetails = await Task.detached { DiskCache.load(DetailsSnapshot.self, prefix: "details", key: detailsKey) }.value
        guard token == detailsToken else { return }
        if let c = cachedDetails, !c.wagons.isEmpty {
            let prices = Dictionary(uniqueKeysWithValues: c.prices.compactMap { k, v in Int(k).map { ($0, v) } })
            applyDetails(core: core, from: from, to: to, wagons: c.wagons.map(\.core), prices: prices, note: c.priceNote)
            let age = Int(Date().timeIntervalSince(c.savedAt))
            log(.info, "app", "szczegóły z dysku (sprzed \(age) s)")
            if age < 120 && c.wagons.allSatisfy({ $0.direction != nil && $0.compartments != nil }) { return }
        } else {
            ticketPrices = [:]
            priceNote = nil
        }

        let codes: [(Int, Int32)] = [(0, 1010), (37, 1710), (51, 1990)]
        let (prices, note): ([Int: Double], String?) = await Task.detached {
            var out: [Int: Double] = [:]
            var note: String?
            for (percent, code) in codes {
                do {
                    out[percent] = try client.price(train: core, discountCode: code)
                    log(.info, "price", "ulga \(percent)% (kod \(code)): \(out[percent] ?? 0) zł")
                } catch {
                    let msg = (error as? CoreError)?.message ?? error.localizedDescription
                    log(.warn, "price", "ulga \(percent)% (kod \(code)): \(msg)")
                    note = note ?? msg
                    break
                }
            }
            if out.isEmpty, let first = try? client.price(train: core, travelClass: 1, discountCode: 1010) {
                note = (note.map { $0 + "\n" } ?? "") + "Klasa 1: \(String(format: "%.2f", first).replacingOccurrences(of: ".", with: ",")) zł"
                log(.info, "price", "klasa 1 dostępna: \(first) zł")
            }
            return (out, note)
        }.value
        guard token == detailsToken, let idx0 = trains.firstIndex(where: { $0.id == String(core.number) }) else { return }
        ticketPrices = prices
        priceNote = prices.isEmpty ? note : nil
        if let base = prices[0] {
            let t = trains[idx0]
            trains[idx0] = TrainInfo(id: t.id, number: t.number, name: t.name, fromStation: t.fromStation,
                                     departureTime: t.departureTime, toStation: t.toStation, arrivalTime: t.arrivalTime,
                                     duration: t.duration, basePrice: base, wagonNumber: t.wagonNumber,
                                     freeSeatsCount: t.freeSeatsCount)
        } else {
            showToast(note ?? "Nie udało się pobrać ceny (zobacz Developer → logi)")
        }

        do {
            let t0 = Date()
            let wagons: [CoreWagon] = try await Task.detached {
                try client.seats(train: core, from: from, to: to, travelClass: 2, excludeSpecial: false)
            }.value
            log(.info, "app", "miejsca: \(wagons.count) wagonów w \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
            guard token == detailsToken, let idx = trains.firstIndex(where: { $0.id == String(core.number) }) else { return }

            func free(_ w: CoreWagon) -> Int { w.seats.filter { $0.isFree && !$0.isSpecial }.count }
            let best = wagons.max { free($0) < free($1) }
            trains[idx] = Self.trainInfo(core, from: from, to: to,
                                         price: prices[0] ?? trains[idx].basePrice,
                                         wagon: best?.wagon ?? 0, free: wagons.map(free).reduce(0, +))
            if let best {
                detailWagons = wagons
                log(.info, "app", "wagon \(best.wagon): \(free(best)) wolnych z \(best.seats.count)")
            } else {
                log(.warn, "app", "brak wagonów z miejscami w odpowiedzi")
            }
            if !wagons.isEmpty {
                let snapshot = DetailsSnapshot(key: detailsKey, savedAt: Date(), wagons: wagons.map { CachedWagon($0, withLayout: true) },
                                               prices: Dictionary(uniqueKeysWithValues: prices.map { (String($0.key), $0.value) }),
                                               priceNote: prices.isEmpty ? note : nil)
                await Task.detached { DiskCache.save(snapshot, prefix: "details", key: detailsKey) }.value
            }
        } catch {
            log(.error, "app", "miejsca: \(Self.describe(error))")
            showToast(Self.describe(error))
        }
    }

    nonisolated private static func epochMinutes(_ compact: String?) -> Int32? {
        guard let c = compact, c.count == 12, let n = Int(c) else { return nil }
        var comps = DateComponents()
        comps.year = n / 100_000_000
        comps.month = n / 1_000_000 % 100
        comps.day = n / 10_000 % 100
        comps.hour = n / 100 % 100
        comps.minute = n % 100
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: comps) else { return nil }
        return Int32(d.timeIntervalSince1970 / 60)
    }

    private func applyDetails(core: CoreTrain, from: CoreStation, to: CoreStation, wagons: [CoreWagon],
                              prices: [Int: Double], note: String?) {
        ticketPrices = prices
        priceNote = prices.isEmpty ? note : nil
        guard let idx = trains.firstIndex(where: { $0.id == String(core.number) }) else { return }
        func free(_ w: CoreWagon) -> Int { w.seats.filter { $0.isFree && !$0.isSpecial }.count }
        let best = wagons.max { free($0) < free($1) }
        trains[idx] = Self.trainInfo(core, from: from, to: to, price: prices[0] ?? trains[idx].basePrice,
                                     wagon: best?.wagon ?? 0, free: wagons.map(free).reduce(0, +))
        if best != nil {
            detailWagons = wagons
        }
    }

    func clearCaches() {
        DiskCache.clearAll()
        segmentsFor = nil
        legsData = [:]
        log(.warn, "app", "pamięć podręczna wyczyszczona")
    }

    nonisolated private static func cacheKey(_ t: CoreTrain, _ from: CoreStation, _ to: CoreStation) -> String {
        "\(t.category)\(t.number)-\(t.departure.prefix(10))-\(from.eva)-\(to.eva)"
    }

    nonisolated private static func segmentItem(_ n: Int, stops: [CoreStop], wagons: [CoreWagon]) -> SegmentItem {
        let (a, b) = (stops[n], stops[n + 1])
        let free = wagons.reduce(0) { $0 + $1.freeCount }
        let total = free + wagons.reduce(0) { $0 + $1.occupiedCount }
        let occ = total > 0 ? Int((Double(total - free) / Double(total) * 100).rounded()) : 0
        let counts = wagons.map { w in
            WagonCount(wagon: w.wagon, free: w.seats.filter { $0.isFree && !$0.isSpecial }.count,
                       total: w.seats.filter { !$0.isSpecial }.count)
        }.sorted { $0.wagon < $1.wagon }
        return SegmentItem(from: a.name, to: b.name,
                           depTime: coreHHMM(a.departure.isEmpty ? a.arrival : a.departure),
                           arrTime: coreHHMM(b.arrival.isEmpty ? b.departure : b.arrival),
                           freeSeats: free, occupancyPercent: occ, legIndex: n, wagons: counts)
    }

    nonisolated private static func makePlanner(stops: [CoreStop], legs: [Int: [CoreWagon]]) -> SeatPlanner? {
        func t(_ s: String) -> Int32? { epochMinutes(coreCompactTime(s)) }
        var arr: [Int32] = [], dep: [Int32] = []
        for st in stops {
            guard let a = t(st.arrival.isEmpty ? st.departure : st.arrival),
                  let d = t(st.departure.isEmpty ? st.arrival : st.departure) else { return nil }
            arr.append(a); dep.append(max(d, a))
        }
        let base = arr[0]
        guard let planner = SeatPlanner(arrivals: arr.map { $0 - base }, departures: dep.map { $0 - base }) else { return nil }
        for (n, wagons) in legs where n < stops.count - 1 { planner.setLeg(n, wagons: wagons) }
        return planner
    }

    private func applyPlanData(stops: [CoreStop], legs: [Int: [CoreWagon]], from: CoreStation, to: CoreStation, resetRange: Bool) {
        planStops = stops
        if resetRange {
            planBoard = stops.firstIndex { $0.eva == from.eva } ?? 0
            planAlight = stops.lastIndex { $0.eva == to.eva } ?? (stops.count - 1)
        }
        legsData = legs
        segmentsData = legs.keys.sorted().compactMap { n in n < stops.count - 1 ? Self.segmentItem(n, stops: stops, wagons: legs[n] ?? []) : nil }
        planner = Self.makePlanner(stops: stops, legs: legs)
        recomputePlans()
    }

    func loadSegments(force: Bool = false) async {
        guard isLive, let client, let dict = dictionary, let from = fromStation, let to = toStation,
              let core = coreTrains[currentTrain.id] else { return }
        if !force, segmentsFor == currentTrain.id, !isLoadingSegments, !legsData.isEmpty { return }
        segmentsTask?.cancel()
        let trainId = currentTrain.id
        let key = Self.cacheKey(core, from, to)
        let sameTrain = segmentsFor == trainId
        segmentsFor = trainId

        if !sameTrain {
            segmentsData = []; planStops = []; planner = nil; legsData = [:]
            balancedPlan = nil; singleSeatPlan = nil; secondPersonPlan = nil
            failedLegs = 0; planDataAge = nil
        }
        isLoadingSegments = true
        segmentsProgress = "Wczytuję zapisane dane…"

        if !force, legsData.isEmpty,
           let snap = await Task.detached(operation: { DiskCache.load(PlanSnapshot.self, prefix: "plan", key: key) }).value,
           snap.stops.count >= 2 {
            guard segmentsFor == trainId else { return }
            let stops = snap.stops.map(\.core)
            let legs = Dictionary(uniqueKeysWithValues: snap.legs.compactMap { k, w in Int(k).map { ($0, w.map(\.core)) } })
            applyPlanData(stops: stops, legs: legs, from: from, to: to, resetRange: true)
            planDataAge = snap.savedAt
            log(.info, "plan", "z dysku: \(legs.count) odcinków sprzed \(Int(Date().timeIntervalSince(snap.savedAt))) s")
            if Date().timeIntervalSince(snap.savedAt) < 240 && snap.legs.values.flatMap({ $0 }).allSatisfy({ $0.direction != nil && $0.compartments != nil }) {
                isLoadingSegments = false
                segmentsProgress = ""
                return
            }
        }

        segmentsProgress = legsData.isEmpty ? "Pobieram trasę…" : "Odświeżam dane…"
        let knownStops = planStops
        let task = Task { [weak self] in
            do {
                let stops: [CoreStop]
                if knownStops.count >= 2 {
                    stops = knownStops
                } else {
                    stops = try await Task.detached {
                        try client.route(train: core, from: from, to: to).filter { $0.canBoard || $0.canAlight }
                    }.value
                    log(.info, "plan", "trasa: \(stops.count) stacji handlowych")
                    guard stops.count >= 2 else { throw CoreError(code: -6, message: "za mało stacji na trasie") }
                    await MainActor.run {
                        guard let self, self.segmentsFor == trainId else { return }
                        self.planStops = stops
                        self.planBoard = stops.firstIndex { $0.eva == from.eva } ?? 0
                        self.planAlight = stops.lastIndex { $0.eva == to.eva } ?? (stops.count - 1)
                    }
                }

                var failed = 0, done = 0, nextLeg = 0
                var fresh: [Int: [CoreWagon]] = [:]
                let total = stops.count - 1
                await withTaskGroup(of: (Int, [CoreWagon]?).self) { group in
                    while nextLeg < min(2, total) {
                        let n = nextLeg
                        nextLeg += 1
                        group.addTask { (n, Self.loadLeg(n, stops: stops, client: client, dict: dict, core: core)) }
                    }
                    for await (n, wagons) in group {
                        done += 1
                        if let wagons {
                            fresh[n] = wagons
                            let item = Self.segmentItem(n, stops: stops, wagons: wagons)
                            await MainActor.run {
                                guard let self, self.segmentsFor == trainId else { return }
                                self.segmentsProgress = "Odcinki \(done) z \(total)"
                                self.legsData[n] = wagons
                                if let i = self.segmentsData.firstIndex(where: { $0.legIndex == n }) {
                                    self.segmentsData[i] = item
                                } else {
                                    self.segmentsData.append(item)
                                    self.segmentsData.sort { $0.legIndex < $1.legIndex }
                                }
                            }
                        } else if !Task.isCancelled {
                            failed += 1
                            log(.error, "plan", "odcinek \(n + 1) nie pobrany: \(stops[n].name) → \(stops[n + 1].name)")
                        }
                        if nextLeg < total, !Task.isCancelled {
                            let m = nextLeg
                            nextLeg += 1
                            group.addTask { (m, Self.loadLeg(m, stops: stops, client: client, dict: dict, core: core)) }
                        }
                    }
                }

                if !fresh.isEmpty {
                    let failedCount = failed
                    let merged: [Int: [CoreWagon]] = await MainActor.run { (self?.legsData ?? [:]).merging(fresh) { _, new in new } }
                    let snapshot = PlanSnapshot(
                        key: key, savedAt: Date(), stops: stops.map(CachedStop.init),
                        legs: Dictionary(uniqueKeysWithValues: merged.map { (String($0.key), $0.value.map { CachedWagon($0) }) }))
                    await Task.detached { DiskCache.save(snapshot, prefix: "plan", key: key) }.value
                    await MainActor.run {
                        guard let self, self.segmentsFor == trainId else { return }
                        self.failedLegs = failedCount
                        self.planDataAge = snapshot.savedAt
                        self.applyPlanData(stops: stops, legs: merged, from: from, to: to, resetRange: false)
                        log(.info, "plan", "odświeżono \(fresh.count) z \(total) odcinków (błędy: \(failedCount)), zapisano na dysku")
                    }
                }
            } catch {
                log(.error, "plan", "segmenty: \(Self.describe(error))")
                await MainActor.run { self?.showToast(Self.describe(error)) }
            }
            await MainActor.run {
                if self?.segmentsFor == trainId { self?.isLoadingSegments = false; self?.segmentsProgress = "" }
            }
        }
        segmentsTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func refreshSegments() async {
        await loadSegments(force: true)
    }


    var trackingKey: String {
        let train = coreTrains[currentTrain.id]
        return "\(currentTrain.id)-\(train?.departure ?? "")-\(fromStation?.eva ?? 0)-\(toStation?.eva ?? 0)"
    }

    nonisolated private static func nowMinutes() -> Int64? {
        coreCompactMinutes(format("yyyyMMddHHmm").string(from: Date()))
    }

    @discardableResult
    func refreshTrip() async -> Bool {
        guard let client, let from = fromStation, let to = toStation, let core = coreTrains[currentTrain.id] else { return false }
        let key = trackingKey
        do {
            let t0 = Date()
            let route = try await Task.detached { try client.routeHandle(train: core, from: from, to: to) }.value
            guard !Task.isCancelled, key == trackingKey else { return false }
            tripRoute = route
            tripStops = route.stops
            tripUpdated = Date()
            tripError = nil
            trip = nil
            updateTrip()
            if ReminderService.shared.plan != nil {
                let t = reminderTimes()
                Task { await ReminderService.shared.reschedule(arr: t.arr, dep: t.dep) }
            }
            let actual = route.stops.filter { !$0.arrivalActual.isEmpty || !$0.departureActual.isEmpty }.count
            log(.info, "trip", "trasa: \(route.stops.count) stacji, rzeczywiste godziny: \(actual), \(Int(Date().timeIntervalSince(t0) * 1000)) ms"
                + (trip.map { ", opóźnienie: \($0.delay.map { "\($0) min" } ?? "brak danych")" } ?? ""))
            return true
        } catch {
            guard !Task.isCancelled, key == trackingKey else { return false }
            tripError = Self.describe(error)
            log(.warn, "trip", "śledzenie: \(Self.describe(error))")
            return false
        }
    }

    func reminderTimes() -> (arr: [UInt32: Int64], dep: [UInt32: Int64]) {
        var arr: [UInt32: Int64] = [:], dep: [UInt32: Int64] = [:]
        if let trip, trip.stops.count == tripStops.count {
            for (i, st) in tripStops.enumerated() {
                arr[st.eva] = trip.stops[i].arr
                dep[st.eva] = trip.stops[i].dep
            }
        } else {
            for st in planStops {
                if let a = Self.epochMinutes(coreCompactTime(st.arrival.isEmpty ? st.departure : st.arrival)) { arr[st.eva] = Int64(a) }
                if let d = Self.epochMinutes(coreCompactTime(st.departure.isEmpty ? st.arrival : st.departure)) { dep[st.eva] = Int64(d) }
            }
        }
        return (arr, dep)
    }

    var remindersActive: Bool {
        guard let key = seatKey else { return false }
        return ReminderService.shared.plan?.trainKey == key
    }

    private func planSteps(_ plan: SeatPlan) -> [PlanStep] {
        plan.runs.compactMap { r in
            guard planStops.indices.contains(r.fromStop), planStops.indices.contains(r.toStop) else { return nil }
            let a = planStops[r.fromStop], b = planStops[r.toStop]
            return PlanStep(fromEva: a.eva, toEva: b.eva, fromName: a.name, toName: b.name,
                            wagon: r.wagon, seat: r.seat, seat2: r.seat2, window: r.isWindow)
        }
    }

    func setReminders(_ on: Bool) async {
        guard on else {
            await ReminderService.shared.clear()
            return
        }
        guard let plan = balancedPlan, let key = seatKey else {
            showToast("Najpierw poczekaj na plan miejsc")
            return
        }
        var people = [planSteps(plan)]
        if planPeople == 2, !planTogether, let second = secondPersonPlan { people.append(planSteps(second)) }
        let committed = CommittedPlan(trainKey: key, label: "\(currentTrain.number) \(currentTrain.name)", people: people)
        let t = reminderTimes()
        if await ReminderService.shared.commit(committed, arr: t.arr, dep: t.dep) {
            showToast("Przypomnienia włączone (\(ReminderService.shared.scheduled.count))")
        } else {
            showToast("Włącz powiadomienia w Ustawieniach iOS")
        }
    }

    func updateTrip() {
        guard let route = tripRoute, let now = Self.nowMinutes(), let t = route.track(nowMinutes: now) else { return }
        if let old = trip, old.state == t.state, old.minutesToNext == t.minutesToNext, old.delay == t.delay, old.isActual == t.isActual,
           old.stops.map(\.arr) == t.stops.map(\.arr) { return }
        trip = t
    }

    func trackingLoop() async {
        tripRoute = nil
        trip = nil
        tripStops = []
        tripUpdated = nil
        tripError = nil
        while !Task.isCancelled {
            let ok = await refreshTrip()
            var wait: Duration = ok ? .seconds(300) : .seconds(30)
            if ok, let t = trip, let first = t.stops.first, let last = t.stops.last, let now = Self.nowMinutes(),
               now >= first.schedDep - 90, now <= last.arr + 20 {
                wait = .seconds(45)
            }
            try? await Task.sleep(for: wait)
        }
    }

    nonisolated private static func loadLeg(_ n: Int, stops: [CoreStop], client: TrainCoreClient,
                                            dict: StationDictionary, core: CoreTrain) -> [CoreWagon]? {
        let (a, b) = (stops[n], stops[n + 1])
        guard !Task.isCancelled else { return nil }
        guard let sa = dict.station(eva: a.eva) ?? dict.find(a.name),
              let sb = dict.station(eva: b.eva) ?? dict.find(b.name) else {
            log(.error, "plan", "odcinek \(n + 1): nie znaleziono stacji \(a.name) / \(b.name) w słowniku")
            return nil
        }
        guard let depC = coreCompactTime(a.departure.isEmpty ? a.arrival : a.departure),
              let arrC = coreCompactTime(b.arrival.isEmpty ? b.departure : b.arrival) else {
            log(.error, "plan", "odcinek \(n + 1): nierozpoznane godziny (\(a.departure) / \(b.arrival))")
            return nil
        }
        let t0 = Date()
        do {
            let wagons = try client.seats(train: core, from: sa, to: sb, departure: depC, arrival: arrC)
            log(.debug, "plan", "odcinek \(n + 1): \(wagons.count) wagonów, \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
            return wagons
        } catch {
            log(.error, "plan", "odcinek \(n + 1) \(sa.name) → \(sb.name): \(describe(error))")
            return nil
        }
    }

    func setPlanRange(board: Int, alight: Int) {
        guard planStops.indices.contains(board), planStops.indices.contains(alight) else { return }
        planBoard = board
        planAlight = max(alight, board + 1 < planStops.count ? board + 1 : board)
        recomputePlans()
    }

    func setPlanPeople(_ n: Int) {
        planPeople = n
        savePrefs()
        recomputePlans()
    }

    func setPlanTogether(_ together: Bool) {
        planTogether = together
        savePrefs()
        recomputePlans()
    }

    private func recomputePlans() {
        guard let planner, planAlight > planBoard else {
            balancedPlan = nil
            singleSeatPlan = nil
            secondPersonPlan = nil
            return
        }
        let (b, a, people, together) = (planBoard, planAlight, planPeople, planTogether)
        Task {
            struct Result: Sendable { var main: SeatPlan?; var single: SeatPlan?; var second: SeatPlan? }
            let r: Result = await Task.detached {
                if people == 1 {
                    return Result(main: planner.solve(board: b, alight: a, changePenaltyMinutes: 10),
                                  single: planner.solve(board: b, alight: a, changePenaltyMinutes: 100_000))
                } else if together {
                    return Result(main: planner.solvePairs(board: b, alight: a, changePenaltyMinutes: 10),
                                  single: planner.solvePairs(board: b, alight: a, changePenaltyMinutes: 100_000))
                } else if let (p1, p2) = planner.solveSeparate(board: b, alight: a, changePenaltyMinutes: 10) {
                    return Result(main: p1, single: nil, second: p2)
                }
                return Result()
            }.value
            guard b == planBoard, a == planAlight, people == planPeople, together == planTogether else { return }
            balancedPlan = r.main
            singleSeatPlan = r.single
            secondPersonPlan = r.second
            log(.info, "plan", "plan (\(people) os.\(people == 2 ? (together ? ", razem" : ", osobno") : "")): siedzenie \(r.main?.seatedPercent ?? -1)%\(r.second.map { " / \($0.seatedPercent)%" } ?? ""), przesiadki \(r.main?.changes ?? -1), miejsca na całą trasę \(r.main?.fullRideSeats ?? -1)")
        }
    }

    nonisolated private static func describe(_ error: Error) -> String {
        if let e = error as? CoreError {
            return e.isBlocked ? "Intercity zablokowało zapytanie (HTTP \(e.httpStatus))"
                : "Błąd danych: \(e.message)\(e.httpStatus != 0 ? " [HTTP \(e.httpStatus)]" : "")"
        }
        return "Błąd: \(error.localizedDescription)"
    }

    nonisolated private static func trainInfo(_ t: CoreTrain, from: CoreStation, to: CoreStation,
                                              price: Double, wagon: Int, free: Int) -> TrainInfo {
        let f = format("yyyy-MM-dd HH:mm:ss")
        var duration = ""
        if let d = f.date(from: t.departure), let a = f.date(from: t.arrival) {
            let mins = Int(a.timeIntervalSince(d) / 60)
            duration = "\(mins / 60)h \(String(format: "%02d", mins % 60))min"
        }
        return TrainInfo(
            id: String(t.number), number: "\(t.category) \(t.number)", name: t.name.capitalized,
            fromStation: from.name, departureTime: t.departureHHMM,
            toStation: to.name, arrivalTime: t.arrivalHHMM, duration: duration,
            basePrice: price, wagonNumber: wagon, freeSeatsCount: free)
    }
}
