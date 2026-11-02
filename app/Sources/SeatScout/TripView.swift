import SwiftUI

struct TripSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            if let trip = model.trip, !model.tripStops.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title(trip)).font(.headline)
                            if let sub = subtitle(trip) {
                                Text(sub).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let detail = detail(trip) {
                                Text(detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        delayBadge(trip)
                    }
                    ProgressView(value: trip.progress).tint(.blue)
                }
                .padding(.vertical, 4)

                if let note = currentMessages(trip) {
                    Label(note, systemImage: "exclamationmark.bubble.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                DisclosureGroup("Wszystkie stacje (\(model.tripStops.count))") {
                    ForEach(model.tripStops.indices, id: \.self) { i in
                        stopRow(i, trip)
                    }
                }
            } else if let err = model.tripError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Sprawdzam, gdzie jest pociąg…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Gdzie jest pociąg")
        } footer: {
            if let trip = model.trip {
                Text((trip.isActual ? "Rzeczywiste godziny z Intercity" : "Wg rozkładu – Intercity jeszcze nie podaje rzeczywistych godzin")
                     + (model.tripUpdated.map { " · zaktualizowano \($0.formatted(date: .omitted, time: .standard))" } ?? ""))
            }
        }
    }


    private func name(_ i: Int) -> String { model.tripStops[i].name }

    private func title(_ t: TripInfo) -> String {
        switch t.state {
        case .notStarted: return "Przed odjazdem"
        case .atStation(let i): return "Stoi na stacji \(name(i))"
        case .between(let a, _): return "Odjechał z \(name(a))"
        case .finished: return "Dojechał do \(name(model.tripStops.count - 1))"
        }
    }

    private func subtitle(_ t: TripInfo) -> String? {
        switch t.state {
        case .notStarted:
            return "Odjazd z \(name(0)) o \(coreClock(t.stops[0].dep))\(t.nextStop ? " · za \(minutes(t.minutesToNext))" : "")"
        case .atStation(let i):
            return i == model.tripStops.count - 1 ? nil : "Odjazd o \(coreClock(t.stops[i].dep))"
        case .between(_, let b):
            return "Jedzie do \(name(b)) · przyjazd \(coreClock(t.stops[b].arr))\(t.minutesToNext > 0 ? " (za \(minutes(t.minutesToNext)))" : "")"
        case .finished:
            return nil
        }
    }

    private func detail(_ t: TripInfo) -> String? {
        let idx: Int?
        switch t.state {
        case .notStarted: idx = 0
        case .atStation(let i): idx = i
        case .between(_, let b): idx = b
        case .finished: idx = nil
        }
        guard let i = idx else { return nil }
        let s = model.tripStops[i]
        let parts = [s.platform.isEmpty ? nil : "peron \(s.platform)", s.track.isEmpty ? nil : "tor \(s.track)"].compactMap { $0 }
        return parts.isEmpty ? nil : "\(name(i)): " + parts.joined(separator: ", ")
    }

    private func currentMessages(_ t: TripInfo) -> String? {
        let all = model.tripStops.map(\.messages).filter { !$0.isEmpty }
        return all.isEmpty ? nil : all.joined(separator: "\n")
    }

    private func minutes(_ m: Int) -> String {
        m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(max(m, 0)) min"
    }

    @ViewBuilder
    private func delayBadge(_ t: TripInfo) -> some View {
        if let d = t.delay {
            Text(d > 0 ? "+\(d) min" : (d == 0 ? "o czasie" : "\(d) min"))
                .font(.footnote.weight(.bold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background((d > 0 ? Color.orange : Color.green).opacity(0.2), in: Capsule())
                .foregroundStyle(d > 0 ? .orange : .green)
        }
    }


    private enum Status { case passed, current, next, upcoming }

    private func status(_ i: Int, _ t: TripInfo) -> Status {
        switch t.state {
        case .finished: return i == model.tripStops.count - 1 ? .current : .passed
        case .notStarted: return i == 0 ? .next : .upcoming
        case .atStation(let k): return i < k ? .passed : (i == k ? .current : .upcoming)
        case .between(let a, let b): return i <= a ? .passed : (i == b ? .next : .upcoming)
        }
    }

    private func stopRow(_ i: Int, _ t: TripInfo) -> some View {
        let s = model.tripStops[i]
        let p = t.stops[i]
        let st = status(i, t)
        let isLast = i == model.tripStops.count - 1
        let time = isLast ? p.arr : (st == .passed || st == .current ? p.dep : p.arr)
        let sched = isLast ? p.schedArr : (st == .passed || st == .current ? p.schedDep : p.schedArr)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: st == .passed ? "checkmark.circle.fill" : (st == .current ? "tram.fill" : (st == .next ? "arrow.right.circle.fill" : "circle")))
                .foregroundStyle(st == .passed ? .green : (st == .upcoming ? .secondary : .blue))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .font(.subheadline.weight(st == .current || st == .next ? .bold : .regular))
                    .foregroundStyle(st == .passed ? .secondary : .primary)
                let loc = [s.platform.isEmpty ? nil : "peron \(s.platform)", s.track.isEmpty ? nil : "tor \(s.track)"].compactMap { $0 }
                if !loc.isEmpty {
                    Text(loc.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                }
                if !s.messages.isEmpty {
                    Text(s.messages).font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(coreClock(time))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(time > sched ? .orange : .primary)
                if time != sched {
                    Text(coreClock(sched)).font(.caption2.monospacedDigit()).strikethrough().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
    }
}
