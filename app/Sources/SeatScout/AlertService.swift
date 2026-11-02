import BackgroundTasks
import SwiftUI
import UserNotifications

@MainActor
final class AlertService: ObservableObject {
    static let shared = AlertService()
    nonisolated static let taskId: String = {
        let ids = Bundle.main.infoDictionary?["BGTaskSchedulerPermittedIdentifiers"] as? [String]
        return ids?.first { $0.hasSuffix(".refresh") } ?? ids?.first ?? "com.example.seatscout.refresh"
    }()
    static let interval: TimeInterval = 5 * 60
    private static let warsaw = TimeZone(identifier: "Europe/Warsaw") ?? .current

    @Published private(set) var settings: AlertSettings
    @Published private(set) var history: [AlertEvent]
    @Published private(set) var isChecking = false
    @Published private(set) var testAt: Date?
    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined

    @Published private(set) var backgroundStatus = "jeszcze nie planowano"
    @Published private(set) var diagnostics = ""

    private var client: TrainCoreClient?

    private init() {
        settings = AlertStore.loadSettings()
        history = AlertStore.loadHistory()
    }


    private func save() { AlertStore.saveSettings(settings) }

    private func addEvent(_ kind: AlertEvent.Kind, _ text: String) {
        history = AlertStore.append(AlertEvent(date: Date(), kind: kind, text: text), to: history)
        log(kind == .error ? .error : .info, "alert", text)
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: AlertStore.historyKey)
    }

    func setWindowOnly(_ on: Bool) {
        settings.windowOnly = on
        save()
    }

    func setPairs(_ on: Bool) {
        settings.pairs = on
        save()
    }

    func setEnabled(_ on: Bool, target: WatchTarget?) async {
        if !on {
            settings.enabled = false
            save()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskId)
            addEvent(.info, "Alert wyłączony")
            return
        }
        guard let target else {
            addEvent(.error, "Nie można włączyć alertu: brak wybranego pociągu")
            return
        }
        guard await requestPermission() else {
            settings.enabled = false
            save()
            addEvent(.error, "Brak zgody na powiadomienia – włącz je w Ustawieniach iOS")
            return
        }
        retarget(target)
        settings.enabled = true
        save()
        addEvent(.info, "Alert włączony: \(target.label), \(target.route), \(target.day)")
        scheduleBackgroundRefresh()
        _ = await runCheck(source: "start")
    }

    func retarget(_ target: WatchTarget) {
        if let old = settings.target, old.key != target.key { AlertStore.clearSnapshot(old.key) }
        if settings.target != target {
            AlertStore.clearSnapshot(target.key)
            settings.lastCheck = nil
            settings.lastFreeCount = nil
        }
        settings.target = target
        save()
    }


    func refreshPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshPermission()
        return granted || permission == .authorized || permission == .provisional
    }


    @discardableResult
    func runCheck(source: String, timeout: Double = 120) async -> Bool {
        guard settings.enabled, let target = settings.target, !isChecking else { return false }
        if AlertEngine.isExpired(target, now: Date(), timeZone: Self.warsaw) {
            settings.enabled = false
            save()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskId)
            addEvent(.info, "Pociąg \(target.label) już dojechał – alert wyłączony")
            return true
        }
        isChecking = true
        defer { isChecking = false }

        let client = self.client ?? TrainCoreClient(transport: WebViewTransport(session: WebSession()))
        self.client = client
        let train = CoreTrain(connectionId: target.connectionId, number: target.trainNumber, category: target.category,
                              name: target.name, departure: target.departure, arrival: target.arrival,
                              fromKod: target.fromKod, toKod: target.toKod)
        let from = CoreStation(kod: target.fromKod, epa: target.fromEpa, eva: target.fromEva, name: target.fromName)
        let to = CoreStation(kod: target.toKod, epa: target.toEpa, eva: target.toEva, name: target.toName)

        do {
            let wagons = try await Self.withTimeout(timeout) {
                try client.seats(train: train, from: from, to: to, travelClass: 2, excludeSpecial: true)
            }
            let free: [WatchSeat] = wagons.flatMap { w in
                w.seats.filter { $0.isFree && !$0.isSpecial }.map {
                    WatchSeat(wagon: w.wagon, number: $0.number, window: $0.position == .window, x: $0.xy?.x, y: $0.xy?.y)
                }
            }
            let previous = AlertStore.loadSnapshot(target.key)
            let fresh = AlertEngine.newlyFree(previous: previous, current: free, windowOnly: settings.windowOnly, pairs: settings.pairs)
            AlertStore.saveSnapshot(free, key: target.key)
            settings.lastCheck = Date()
            settings.lastFreeCount = free.count
            save()

            if previous == nil {
                addEvent(.info, "Sprawdzenie (\(source)): baza ustawiona, wolnych na całej trasie: \(free.count)")
            } else if fresh.isEmpty {
                addEvent(.info, "Sprawdzenie (\(source)): wolnych \(free.count), nic nowego")
            } else {
                let n = AlertEngine.notification(newSeats: fresh, totalFree: free.count, target: target, pairs: settings.pairs)
                await notify(title: n.title, body: n.body)
                addEvent(.notified, "\(n.title) – \(n.body)")
            }
            return true
        } catch {
            let msg = (error as? CoreError).map { $0.isBlocked ? "Intercity zablokowało zapytanie (HTTP \($0.httpStatus))" : $0.message }
                ?? error.localizedDescription
            addEvent(.error, "Sprawdzenie (\(source)) nieudane: \(msg)")
            return false
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
    }

    private static func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { cont in
            let once = Once()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let v = try op()
                    if once.claim() { cont.resume(returning: v) }
                } catch {
                    if once.claim() { cont.resume(throwing: error) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                if once.claim() { cont.resume(throwing: CoreError(code: -2, message: "przekroczono limit czasu (\(Int(seconds)) s)")) }
            }
        }
    }

    func foregroundLoop() async {
        await refreshPermission()
        logBackgroundDiagnostics()
        while !Task.isCancelled {
            if settings.enabled, !isChecking {
                let last = settings.lastCheck ?? .distantPast
                if Date().timeIntervalSince(last) >= Self.interval { await runCheck(source: "aplikacja") }
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    var nextCheck: Date? {
        guard settings.enabled else { return nil }
        return (settings.lastCheck ?? Date()).addingTimeInterval(Self.interval)
    }


    private func notify(title: String, body: String, delay: TimeInterval? = nil, id: String = UUID().uuidString) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = delay.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch {
            addEvent(.error, "Nie udało się dodać powiadomienia: \(error.localizedDescription)")
        }
    }

    func scheduleTestNotification() async {
        guard await requestPermission() else {
            addEvent(.error, "Test: brak zgody na powiadomienia – włącz je w Ustawieniach iOS")
            return
        }
        let t = settings.target
        let title = "Test · zwolniło się miejsce" + (t.map { " · \($0.label)" } ?? "")
        let body = (t.map { "\($0.route), \($0.day): " } ?? "") + "wagon 14, miejsce 61 (okno). Tak będzie wyglądać alert."
        await notify(title: title, body: body, delay: 60, id: "test-alert")
        testAt = Date().addingTimeInterval(60)
        addEvent(.info, "Zaplanowano powiadomienie testowe na \((testAt ?? Date()).formatted(date: .omitted, time: .standard))")
    }


    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            let box = TaskBox(task)
            Task { @MainActor in AlertService.shared.handleBackground(box) }
        }
    }

    final class TaskBox: @unchecked Sendable {
        let task: BGTask
        private let lock = NSLock()
        private var completed = false
        init(_ t: BGTask) { task = t }
        func complete(_ ok: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: ok)
        }
    }

    func scheduleBackgroundRefresh() {
        guard settings.enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.interval)
        do {
            try BGTaskScheduler.shared.submit(request)
            backgroundStatus = "zaplanowano (najwcześniej za \(Int(Self.interval / 60)) min)"
            log(.info, "alert", "zaplanowano odświeżenie w tle (najwcześniej za \(Int(Self.interval / 60)) min)")
        } catch {
            let why = Self.describeBackgroundError(error)
            backgroundStatus = why
            log(.warn, "alert", "nie udało się zaplanować zadania w tle: \(why) [\((error as NSError).domain) \((error as NSError).code)]")
            logBackgroundDiagnostics()
        }
    }

    private static func describeBackgroundError(_ error: Error) -> String {
        guard let e = error as? BGTaskScheduler.Error else { return error.localizedDescription }
        switch e.code {
        case .unavailable:
            return "odświeżanie w tle jest niedostępne (Ustawienia → Ogólne → Odświeżanie aplikacji w tle)"
        case .tooManyPendingTaskRequests:
            return "za dużo oczekujących zadań"
        case .notPermitted:
            return "iOS nie pozwala tej instalacji planować zadań w tle (brak identyfikatora w zainstalowanym Info.plist albo ograniczenie podpisu)"
        case .immediateRunIneligible:
            return e.localizedDescription
        @unknown default:
            return e.localizedDescription
        }
    }

    func backgroundDiagnostics() async -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let ids = (info["BGTaskSchedulerPermittedIdentifiers"] as? [String]) ?? []
        let modes = (info["UIBackgroundModes"] as? [String]) ?? []
        let status: String
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: status = "dostępne"
        case .denied: status = "WYŁĄCZONE przez użytkownika"
        case .restricted: status = "ograniczone systemowo"
        @unknown default: status = "?"
        }
        let pending = await BGTaskScheduler.shared.pendingTaskRequests().map { "\($0.identifier) od \($0.earliestBeginDate?.formatted(date: .omitted, time: .shortened) ?? "?")" }
        return """
        bundle: \(Bundle.main.bundleIdentifier ?? "?")
        BGTaskSchedulerPermittedIdentifiers: \(ids.isEmpty ? "BRAK" : ids.joined(separator: ", ")) (używany: \(Self.taskId))
        UIBackgroundModes: \(modes.isEmpty ? "BRAK" : modes.joined(separator: ", "))
        Odświeżanie w tle: \(status)
        oczekujące zadania: \(pending.isEmpty ? "brak" : pending.joined(separator: "; "))
        """
    }

    func logBackgroundDiagnostics() {
        Task {
            let d = await backgroundDiagnostics()
            diagnostics = d
            log(.info, "alert", "diagnostyka tła:\n\(d)")
        }
    }

    func handleBackground(_ box: TaskBox) {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            let ok = await self.runCheck(source: "tło", timeout: 24)
            box.complete(ok)
        }
        box.task.expirationHandler = {
            work.cancel()
            box.complete(false)
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            scheduleBackgroundRefresh()
        case .active:
            Task { await refreshPermission() }
        default:
            break
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
