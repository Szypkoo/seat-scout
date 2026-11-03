import SwiftUI

enum LogLevel: String, CaseIterable, Sendable {
    case debug, info, warn, error

    var tag: String { rawValue.uppercased() }
}

struct LogEntry: Identifiable, Sendable {
    let id: Int
    let date: Date
    let level: LogLevel
    let category: String
    let message: String
}

final class AppLog: ObservableObject, @unchecked Sendable {
    static let shared = AppLog()

    @Published private(set) var entries: [LogEntry] = []

    private let lock = NSLock()
    private var buffer: [LogEntry] = []
    private var counter = 0
    private var flushPending = false
    private static let capacity = 3000

    func add(_ level: LogLevel, _ category: String, _ message: String) {
        lock.lock()
        counter += 1
        buffer.append(LogEntry(id: counter, date: Date(), level: level, category: category, message: message))
        if buffer.count > Self.capacity { buffer.removeFirst(buffer.count - Self.capacity + 500) }
        let schedule = !flushPending
        flushPending = true
        lock.unlock()
        if schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in flush() }
        }
    }

    private func flush() {
        lock.lock()
        let snapshot = buffer
        flushPending = false
        lock.unlock()
        entries = snapshot
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        entries = []
    }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func line(_ e: LogEntry) -> String {
        "\(timeFormat.string(from: e.date)) [\(e.level.tag)] \(e.category): \(e.message)"
    }

    static func time(_ e: LogEntry) -> String { timeFormat.string(from: e.date) }

    var text: String { entries.map { Self.line($0) }.joined(separator: "\n") }
}

func log(_ level: LogLevel = .info, _ category: String, _ message: String) {
    AppLog.shared.add(level, category, message)
}
