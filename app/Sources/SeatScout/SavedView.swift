import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

struct SavedView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var alerts = AlertService.shared

    private var currentTarget: WatchTarget? { model.currentWatchTarget() }
    private var targetDiffers: Bool {
        guard let cur = currentTarget, let t = alerts.settings.target else { return false }
        return cur.key != t.key
    }

    var body: some View {
        List {
            alertSection
            if alerts.settings.enabled { optionsSection }
            permissionSection
            historySection
        }
        #if !SKIP
        .listStyle(.insetGrouped)
        #else
        .listStyle(.automatic)
        #endif
        .task { await alerts.refreshPermission() }
    }


    private var alertSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { alerts.settings.enabled },
                set: { on in Task { await alerts.setEnabled(on, target: currentTarget) } })
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Powiadom, gdy zwolni się miejsce").font(.subheadline.weight(.semibold))
                    Text(currentTarget.map { "\($0.label) · \($0.route)" } ?? "Najpierw wybierz pociąg")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(currentTarget == nil && !alerts.settings.enabled)

            if let t = alerts.settings.target, alerts.settings.enabled {
                LabeledContent("Pilnuję", value: t.label)
                LabeledContent("Trasa", value: "\(t.route) · \(t.day)")
                if targetDiffers, let cur = currentTarget {
                    Button("Zmień na: \(cur.label) (\(cur.day))") {
                        alerts.retarget(cur)
                        Task { await alerts.runCheck(source: "zmiana pociągu") }
                    }
                }
            }
        } header: {
            Text("Alert wolnych miejsc")
        } footer: {
            Text("Sprawdzam miejsca wolne na całej trasie (jak oficjalna aplikacja) co 5 min, gdy aplikacja jest otwarta. W tle iOS uruchamia sprawdzanie sam i zwykle nie częściej niż co ok. 15 minut – otwórz aplikację, by wymusić sprawdzenie.")
        }
    }

    private var optionsSection: some View {
        Section("Co zgłaszać") {
            Toggle("Tylko miejsca przy oknie", isOn: Binding(get: { alerts.settings.windowOnly }, set: { alerts.setWindowOnly($0) }))
            Toggle("Pary miejsc obok siebie (2 osoby)", isOn: Binding(get: { alerts.settings.pairs }, set: { alerts.setPairs($0) }))

            if let last = alerts.settings.lastCheck {
                LabeledContent("Ostatnie sprawdzenie") {
                    Text("\(last.formatted(date: .omitted, time: .shortened))\(alerts.settings.lastFreeCount.map { " · wolnych: \($0)" } ?? "")")
                }
            }
            if let next = alerts.nextCheck {
                LabeledContent("Następne w aplikacji", value: "ok. \(next.formatted(date: .omitted, time: .shortened))")
            }
            Button {
                Task { await alerts.runCheck(source: "ręcznie") }
            } label: {
                HStack {
                    Text("Sprawdź teraz")
                    if alerts.isChecking { Spacer(); ProgressView() }
                }
            }
            .disabled(alerts.isChecking)
        }
    }

    private var permissionSection: some View {
        Section {
            LabeledContent("Zgoda na powiadomienia") {
                Text(permissionText).foregroundStyle(permissionColor)
            }
            if alerts.permission == .denied {
                Button("Otwórz ustawienia") {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    #endif
                }
            }
        } header: {
            Text("Powiadomienia")
        }
    }

    private var historySection: some View {
        Section {
            if alerts.history.isEmpty {
                Text("Brak wpisów").foregroundStyle(.secondary)
            }
            ForEach(alerts.history) { e in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(e.kind)).foregroundStyle(color(e.kind)).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.text).font(.footnote)
                        Text(e.date.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if !alerts.history.isEmpty {
                Button("Wyczyść historię", role: .destructive) { alerts.clearHistory() }
            }
        } header: {
            Text("Historia sprawdzeń")
        }
    }


    private var permissionText: String {
        switch alerts.permission {
        case .authorized, .provisional, .ephemeral: return "włączona"
        case .denied: return "wyłączona"
        default: return "nie zapytano"
        }
    }

    private var permissionColor: Color {
        switch alerts.permission {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        default: return .secondary
        }
    }

    private func icon(_ k: AlertEvent.Kind) -> String {
        switch k {
        case .notified: return "bell.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "checkmark.circle"
        }
    }

    private func color(_ k: AlertEvent.Kind) -> Color {
        switch k {
        case .notified: return .green
        case .error: return .orange
        case .info: return .secondary
        }
    }
}
