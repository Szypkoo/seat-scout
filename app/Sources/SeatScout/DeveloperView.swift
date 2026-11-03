import SwiftUI

struct DeveloperView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var logs = AppLog.shared
    @ObservedObject private var alerts = AlertService.shared

    @State private var minLevel: LogLevel = .info
    @State private var category = "wszystkie"
    @State private var query = ""

    private var categories: [String] {
        ["wszystkie"] + Array(Set(logs.entries.map(\.category))).sorted()
    }

    private var filtered: [LogEntry] {
        let order = LogLevel.allCases
        let minIndex = order.firstIndex(of: minLevel) ?? 0
        return logs.entries.reversed().filter { e in
            (order.firstIndex(of: e.level) ?? 0) >= minIndex
                && (category == "wszystkie" || e.category == category)
                && (query.isEmpty || e.message.lowercased().contains(query.lowercased()))
        }
    }

    var body: some View {
        List {
            Section("Stan") {
                LabeledContent("Rdzeń Seat Scout", value: TrainCoreClient.version)
                LabeledContent("Dane", value: model.isLive ? "na żywo" : "brak danych")
                LabeledContent("Słownik stacji", value: model.dictionary.map { "\($0.count) stacji" } ?? "brak")
                LabeledContent("Pociąg", value: "\(model.currentTrain.number) \(model.currentTrain.name)")
                LabeledContent("Cena bazowa", value: model.currentTrain.basePrice > 0 ? model.priceString(model.currentTrain.basePrice) : "brak")
                LabeledContent("Ceny z API", value: model.ticketPrices.isEmpty ? "brak"
                               : model.ticketPrices.sorted { $0.key < $1.key }
                                    .map { "\($0.key)%: \(model.priceString($0.value))" }.joined(separator: " · "))
                LabeledContent("Odcinki planu", value: "\(model.segmentsData.count) / \(max(model.planStops.count - 1, 0))"
                               + (model.failedLegs > 0 ? " (błędy: \(model.failedLegs))" : ""))
            }

            Section {
                LabeledContent("Zadanie w tle", value: alerts.backgroundStatus)
                if !alerts.diagnostics.isEmpty {
                    #if !SKIP
                    Text(alerts.diagnostics).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    #else
                    Text(alerts.diagnostics).font(.system(.caption2, design: .monospaced))
                    #endif
                }
                Button("Sprawdź zadania w tle (diagnostyka)") { alerts.logBackgroundDiagnostics() }
                Button("Spróbuj zaplanować zadanie w tle teraz") { alerts.scheduleBackgroundRefresh() }
            } header: {
                Text("Tło (alerty)")
            }

            Section("Akcje") {
                Button("Przeładuj dane") { Task { await model.loadLive() } }
                Button("Pobierz plan miejsc ponownie") { Task { await model.refreshSegments() } }
                Button("Wyczyść zapisane ustawienia (trasa, fotele)", role: .destructive) { model.resetPrefs() }
                Button("Wyczyść zapisane plany i szczegóły", role: .destructive) { model.clearCaches() }
                Button("Wyczyść słownik stacji", role: .destructive) { model.resetDictionary() }
            }

            Section {
                Picker("Poziom", selection: $minLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { Text($0.tag).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Kategoria", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                TextField("Szukaj w logach", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Logi (\(filtered.count) z \(logs.entries.count))")
            }

            Section {
                if filtered.isEmpty {
                    Text("Brak wpisów").foregroundStyle(.secondary)
                }
                ForEach(filtered) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            #if !SKIP
                            Text(AppLog.time(e))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            #else
                            Text(AppLog.time(e))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            #endif
                            Text(e.level.tag)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(color(e.level))
                            Text(e.category)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                        #if !SKIP
                        Text(e.message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(e.level == .error ? .red : .primary)
                            .textSelection(.enabled)
                        #else
                        Text(e.message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(e.level == .error ? .red : .primary)
                        #endif
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        #if !SKIP
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif

    }

    private func color(_ l: LogLevel) -> Color {
        switch l {
        case .debug: return .gray
        case .info: return .blue
        case .warn: return .orange
        case .error: return .red
        }
    }
}
