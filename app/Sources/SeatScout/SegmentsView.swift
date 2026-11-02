import SwiftUI

struct SegmentsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var reminders = ReminderService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Zobacz wolne miejsca w klasie 2 na kolejnych odcinkach trasy. Plan pokaże Ci, gdzie możesz usiąść i kiedy zmienić miejsce.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if model.isLoadingSegments {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(model.segmentsProgress).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let age = model.planDataAge {
                        Label {
                            Text("Dane z \(age.formatted(date: .omitted, time: .shortened)) (\(Self.ago(age)))"
                                 + (model.isLoadingSegments ? " – odświeżam w tle" : ""))
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .foregroundStyle(.secondary)
                    }
                    if model.failedLegs > 0 {
                        Label("Nie udało się pobrać \(model.failedLegs) odcinków – plan może być niepełny.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if model.planStops.count >= 2 {
                    rangeSection
                    travelersSection
                }

                if let plan = model.balancedPlan {
                    let separate = model.planPeople == 2 && !model.planTogether
                    let together = model.planPeople == 2 && model.planTogether
                    planSection(separate ? "Osoba 1" : (together ? "Najlepszy plan (razem)" : "Najlepszy plan"), plan: plan)
                    if let second = model.secondPersonPlan {
                        planSection("Osoba 2", plan: second)
                    }
                    if let single = model.singleSeatPlan, single.seatedMinutes != plan.seatedMinutes {
                        planSection(together ? "Bez zmiany miejsc (razem)" : "Bez zmiany miejsca", plan: single)
                    }
                    remindersSection
                    Section {
                        LabeledContent(model.planPeople == 2 && model.planTogether ? "Pary obok siebie wolne na całej trasie" : "Miejsca wolne na całej trasie") {
                            Text("\(plan.fullRideSeats)")
                                .fontWeight(.semibold)
                                .foregroundStyle(plan.fullRideSeats > 0 ? .green : .orange)
                        }
                    } footer: {
                        Text(plan.fullRideSeats > 0
                             ? "Tyle foteli znajdzie oficjalna aplikacja przy rezerwacji miejsca na cały przejazd."
                             : "Oficjalna aplikacja nie znajdzie fotela na całą trasę – stąd plan ze zmianami miejsc między wolnymi fotelami.")
                    }
                }

                if model.balancedPlan != nil {
                    Section {
                        Text("Wolne dziś fotele mogą zostać zarezerwowane przez innych przed odjazdem – odśwież plan tuż przed podróżą i w trakcie jazdy.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.segmentsData.contains(where: { !$0.wagons.isEmpty }) {
                    WagonMatrixSection()
                }

                Section("Pododcinki") {
                    ForEach(model.segmentsData) { seg in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(seg.from) → \(seg.to)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(seg.freeSeats) wolnych")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(seg.freeSeats > 25 ? .green : .orange)
                            }
                            Text("\(seg.legIndex >= 0 ? "\(seg.legIndex + 1). " : "")\(seg.depTime) – \(seg.arrTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !seg.wagons.isEmpty {
                                Text(seg.wagons.map { "w\($0.wagon): \($0.free)" }.joined(separator: "  "))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(seg.occupancyPercent), total: 100)
                                .tint(seg.occupancyPercent > 60 ? .orange : .blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Plan miejsc")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { TrainPickerBar() }
            .task(id: model.currentTrain.id) { await model.loadSegments() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshSegments() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingSegments)
                }
            }
        }
    }

    private static func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "przed chwilą" }
        if s < 3600 { return "\(s / 60) min temu" }
        return "\(s / 3600) h \(s % 3600 / 60) min temu"
    }


    private var rangeSection: some View {
        Section("Twój przejazd") {
            Picker("Wsiadam", selection: Binding(
                get: { model.planBoard },
                set: { model.setPlanRange(board: $0, alight: max($0 + 1, model.planAlight)) })) {
                ForEach(model.planStops.indices.dropLast(), id: \.self) { i in
                    Text("\(model.planStops[i].name) · \(coreHHMM(departureText(i)))").tag(i)
                }
            }
            Picker("Wysiadam", selection: Binding(
                get: { model.planAlight },
                set: { model.setPlanRange(board: model.planBoard, alight: $0) })) {
                ForEach(Array(model.planStops.indices.dropFirst()), id: \.self) { i in
                    Text("\(model.planStops[i].name) · \(coreHHMM(arrivalText(i)))").tag(i)
                }
            }
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.remindersActive }, set: { on in Task { await model.setReminders(on) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Przypomnienia o zmianie fotela").font(.subheadline.weight(.semibold))
                    Text("Powiadomienie kilka minut przed stacją, na której trzeba wstać lub się przesiąść")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.remindersActive {
                if reminders.scheduled.isEmpty {
                    Text("Brak nadchodzących przypomnień").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(reminders.scheduled) { r in
                    HStack(alignment: .top, spacing: 10) {
                        Text(r.fireDate.formatted(date: .omitted, time: .shortened))
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title).font(.footnote.weight(.semibold))
                            Text(r.body).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } footer: {
            Text("Godziny przesuwają się razem z opóźnieniem pociągu, gdy aplikacja jest otwarta (odświeżanie co 45 s). Już zaplanowane przypomnienia pokażą się też po jej zamknięciu.")
        }
    }

    private var travelersSection: some View {
        Section {
            Picker("Podróżni", selection: Binding(get: { model.planPeople }, set: { model.setPlanPeople($0) })) {
                Text("1 osoba").tag(1)
                Text("2 osoby").tag(2)
            }
            .pickerStyle(.segmented)
            if model.planPeople == 2 {
                Toggle("Siedzimy obok siebie", isOn: Binding(get: { model.planTogether }, set: { model.setPlanTogether($0) }))
            }
        } footer: {
            if model.planPeople == 2 {
                Text(model.planTogether
                     ? "Szukamy par sąsiednich foteli (obok siebie lub naprzeciw) wolnych na tych samych odcinkach i przesiadamy się razem."
                     : "Każda osoba dostaje własny plan; drugi plan nie używa foteli pierwszego.")
            }
        }
    }

    private func departureText(_ i: Int) -> String {
        let s = model.planStops[i]
        return s.departure.isEmpty ? s.arrival : s.departure
    }

    private func arrivalText(_ i: Int) -> String {
        let s = model.planStops[i]
        return s.arrival.isEmpty ? s.departure : s.arrival
    }


    private func planSection(_ title: String, plan: SeatPlan) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Siedzisz \(plan.seatedPercent)% przejazdu")
                        .font(.headline)
                        .foregroundStyle(plan.seatedPercent >= 90 ? .green : (plan.seatedPercent >= 50 ? .primary : .orange))
                    Spacer()
                    Text(changesLabel(plan.changes))
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
                Text("\(duration(plan.seatedMinutes)) z \(duration(plan.totalMinutes))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(plan.seatedMinutes), total: Double(max(plan.totalMinutes, 1)))
                    .tint(.green)
            }
            .padding(.vertical, 4)

            ForEach(plan.runs) { run in
                runRow(run)
            }
        } header: {
            Text(title)
        }
    }

    private func runRow(_ run: PlanRunInfo) -> some View {
        let from = model.planStops[run.fromStop], to = model.planStops[run.toStop]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: run.seat != nil ? "chair.lounge.fill" : "figure.stand")
                .foregroundStyle(run.seat != nil ? .green : .orange)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                if let seat = run.seat {
                    Text(run.seat2 != nil
                         ? "Siedźcie: wagon \(run.wagon), miejsca \(seat) + \(run.seat2!)\(run.isWindow ? " · okno" : "")"
                         : "Siedź: wagon \(run.wagon), miejsce \(seat)\(run.isWindow ? " · okno" : "")")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Stoisz (brak wolnych miejsc)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text(run.seat != nil ? "\(from.name) → wstań w: \(to.name)" : "\(from.name) → \(to.name)")
                    .font(.footnote)
                Text("\(coreHHMM(departureText(run.fromStop))) – \(coreHHMM(arrivalText(run.toStop))) · \(duration(run.minutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func changesLabel(_ n: Int) -> String {
        switch n {
        case 0: return "bez zmiany miejsca"
        case 1: return "1 zmiana miejsca"
        case 2...4: return "\(n) zmiany miejsca"
        default: return "\(n) zmian miejsca"
        }
    }

    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))min" : "\(minutes) min"
    }
}


private struct WagonMatrixSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: (wagon: Int, leg: Int)?

    private let cell: CGFloat = 32

    private var legs: [SegmentItem] { model.segmentsData.filter { $0.legIndex >= 0 }.sorted { $0.legIndex < $1.legIndex } }
    private var wagons: [Int] { Array(Set(legs.flatMap { $0.wagons.map(\.wagon) })).sorted() }

    private var planned: Set<[Int]> {
        var out = Set<[Int]>()
        for r in model.balancedPlan?.runs ?? [] where r.seat != nil {
            for leg in r.fromStop..<r.toStop { out.insert([r.wagon, leg]) }
        }
        return out
    }

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("").frame(width: 36)
                        ForEach(legs) { l in
                            Text("\(l.legIndex + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: cell)
                        }
                    }
                    ForEach(wagons, id: \.self) { w in
                        HStack(spacing: 4) {
                            Text("W\(w)")
                                .font(.caption.weight(.bold))
                                .frame(width: 36, alignment: .leading)
                            ForEach(legs) { l in
                                cellView(wagon: w, leg: l)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let sel = selected, let leg = legs.first(where: { $0.legIndex == sel.leg }),
               let c = leg.wagons.first(where: { $0.wagon == sel.wagon }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wagon \(c.wagon): \(c.free) wolnych z \(c.total)")
                        .font(.subheadline.weight(.semibold))
                    Text("\(leg.legIndex + 1). \(leg.from) → \(leg.to) · \(leg.depTime)–\(leg.arrTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Dotknij komórki, żeby zobaczyć odcinek. Numery kolumn odpowiadają liście „Pododcinki” poniżej.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Mapa wagonów")
        } footer: {
            Text("Zielone – dużo wolnych, pomarańczowe – kilka, szare – brak. Niebieska obwódka – Twój plan.")
        }
    }

    @ViewBuilder
    private func cellView(wagon: Int, leg: SegmentItem) -> some View {
        let c = leg.wagons.first { $0.wagon == wagon }
        let isPlanned = planned.contains([wagon, leg.legIndex])
        let isSel = selected?.wagon == wagon && selected?.leg == leg.legIndex
        Button {
            selected = (wagon, leg.legIndex)
        } label: {
            Text(c.map { "\($0.free)" } ?? "–")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(c == nil ? Color.secondary : .primary)
                .frame(width: cell, height: 26)
                .background(color(c), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSel ? Color.white : (isPlanned ? Color.blue : Color.clear), lineWidth: isSel ? 2 : 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func color(_ c: WagonCount?) -> Color {
        guard let c else { return Color(.tertiarySystemFill) }
        if c.free == 0 { return Color(.tertiarySystemFill) }
        let ratio = Double(c.free) / Double(max(c.total, 1))
        return ratio > 0.25 ? .green.opacity(0.45) : .orange.opacity(0.45)
    }
}
