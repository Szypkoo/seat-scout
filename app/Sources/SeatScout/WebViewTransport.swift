import Foundation
import WebKit

@MainActor
final class WebSession: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var ready = false
    private var nextSlot = ContinuousClock.now

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        super.init()
        webView.navigationDelegate = self
    }

    func start() async throws {
        if ready { return }
        log(.info, "net", "ładuję ebilet.intercity.pl (sesja Akamai)…")
        let t0 = ContinuousClock.now
        do {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                loadContinuation = c
                webView.load(URLRequest(url: URL(string: "https://ebilet.intercity.pl")!))
            }
        } catch {
            log(.error, "net", "nie udało się załadować ebilet.intercity.pl: \(error.localizedDescription)")
            throw error
        }
        try await Task.sleep(for: .seconds(2))
        ready = true
        log(.info, "net", "sesja gotowa (\(Self.ms(ContinuousClock.now - t0)) ms)")
    }

    nonisolated static func ms(_ d: Duration) -> Int {
        Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }

    nonisolated static func shortURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://api-gateway.intercity.pl", with: "")
    }

    private var inFlight = 0
    private var limit = 4
    private var successStreak = 0

    private func acquire() async {
        while inFlight >= limit { try? await Task.sleep(for: .milliseconds(40)) }
        inFlight += 1
    }

    private func release(success: Bool) {
        inFlight -= 1
        if !success {
            successStreak = 0
            if limit > 1 {
                limit -= 1
                log(.warn, "net", "timeout – zmniejszam liczbę równoległych zapytań do \(limit)")
            }
        } else {
            successStreak += 1
            if successStreak >= 12, limit < 4 {
                limit += 1
                successStreak = 0
                log(.info, "net", "połączenie ok – zwiększam liczbę równoległych zapytań do \(limit)")
            }
        }
    }

    func fetch(method: String, url: String, body: String?) async -> (status: Int32, body: Data)? {
        guard (try? await start()) != nil else {
            log(.error, "net", "\(method) \(Self.shortURL(url)) – brak sesji (strona nie załadowana)")
            return nil
        }
        await acquire()
        let result = await performFetch(method: method, url: url, body: body)
        release(success: result != nil)
        return result
    }

    private func performFetch(method: String, url: String, body: String?) async -> (status: Int32, body: Data)? {
        guard (try? await start()) != nil else {
            log(.error, "net", "\(method) \(Self.shortURL(url)) – brak sesji (strona nie załadowana)")
            return nil
        }
        let now = ContinuousClock.now
        let slot = max(now, nextSlot)
        nextSlot = slot + .milliseconds(100)
        if slot > now { try? await Task.sleep(until: slot, clock: .continuous) }

        let script = """
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), 12000);
        const opts = { method: method, headers: {}, signal: ctrl.signal };
        if (body) { opts.headers["Content-Type"] = "application/json"; opts.body = body; }
        try {
            const r = await fetch(url, opts);
            const text = await r.text();
            clearTimeout(timer);
            return { status: r.status, text: text };
        } catch (e) { clearTimeout(timer); return { status: 0, text: "" }; }
        """
        let args: [String: Any] = ["method": method, "url": url, "body": body ?? NSNull()]
        let t0 = ContinuousClock.now
        let name = "\(method) \(Self.shortURL(url))"
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(script, arguments: args, in: nil, contentWorld: .page)
        } catch {
            log(.error, "net", "\(name) – błąd JS: \(error.localizedDescription)")
            return nil
        }
        guard let dict = result as? [String: Any], let status = dict["status"] as? Int else {
            log(.error, "net", "\(name) – nieoczekiwana odpowiedź JS: \(String(describing: result))")
            return nil
        }
        let text = dict["text"] as? String ?? ""
        let took = Self.ms(ContinuousClock.now - t0)
        if status == 0 {
            log(.warn, "net", "\(name) – błąd sieci / timeout 12 s (\(took) ms)")
            return nil
        }
        let ok = (200..<300).contains(status)
        log(ok ? .debug : .warn, "net", "\(name) → \(status) (\(text.utf8.count / 1024) KB, \(took) ms)")
        if !ok || url.contains("/Sprzedaz") {
            log(ok ? .info : .warn, "net", "treść \(status) dla \(Self.shortURL(url)): \(text.prefix(400))")
        }
        return (Int32(status), Data(text.utf8))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            loadContinuation?.resume()
            loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            loadContinuation?.resume(throwing: error)
            loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            loadContinuation?.resume(throwing: error)
            loadContinuation = nil
        }
    }
}

final class WebViewTransport: HTTPTransport, @unchecked Sendable {
    private let session: WebSession

    @MainActor init(session: WebSession) { self.session = session }

    private final class Slot: @unchecked Sendable {
        private let lock = NSLock()
        private var value: (status: Int32, body: Data)?
        func set(_ v: (status: Int32, body: Data)?) { lock.lock(); value = v; lock.unlock() }
        func get() -> (status: Int32, body: Data)? { lock.lock(); defer { lock.unlock() }; return value }
    }

    func send(method: String, url: String, body: String?) -> (status: Int32, body: Data)? {
        let sem = DispatchSemaphore(value: 0)
        let slot = Slot()
        let session = self.session
        Task { @MainActor in
            slot.set(await session.fetch(method: method, url: url, body: body))
            sem.signal()
        }
        guard sem.wait(timeout: .now() + 45) == .success else {
            log(.error, "net", "\(method) \(WebSession.shortURL(url)) – twardy timeout 45 s")
            return nil
        }
        return slot.get()
    }
}
