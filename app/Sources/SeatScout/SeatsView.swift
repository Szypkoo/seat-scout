import SwiftUI

struct SeatsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var legChoice: Int?
    @State private var wagonChoice: Int?
    @State private var selected: Int?


    private var sourceWagons: [CoreWagon] {
        if let leg = legChoice, let w = model.legWagons(leg) { return w }
        return model.detailWagons
    }

    private var currentWagon: CoreWagon? {
        let list = sourceWagons
        if let n = wagonChoice, let w = list.first(where: { $0.wagon == n }) { return w }
        return list.max { free($0) < free($1) }
    }

    private func free(_ w: CoreWagon) -> Int { w.seats.filter { $0.isFree && !$0.isSpecial }.count }
    private func total(_ w: CoreWagon) -> Int { w.seats.filter { !$0.isSpecial }.count }

    private func layout(for w: CoreWagon) -> (width: Int, height: Int, decor: [CoreDecor]) {
        if let d = model.detailWagons.first(where: { $0.wagon == w.wagon }), d.width > 0 {
            return (d.width, max(d.height, 200), d.decor)
        }
        if w.width > 0 { return (w.width, max(w.height, 200), w.decor) }
        let maxX = w.seats.compactMap { $0.xy?.x }.max() ?? 1000
        return (maxX + 120, 200, [])
    }

    private func adjacentPairs(_ w: CoreWagon) -> Int {
        let f = w.seats.filter { $0.isFree && !$0.isSpecial && $0.xy != nil }
        var n = 0
        for i in f.indices {
            for j in f.indices where j > i {
                let (a, b) = (f[i].xy!, f[j].xy!)
                if (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) <= 45 * 45 { n += 1 }
            }
        }
        return n
    }

    private var sourceTitle: String {
        guard let leg = legChoice, model.planStops.indices.contains(leg + 1) else { return "Cała trasa" }
        return "\(leg + 1). \(model.planStops[leg].name) → \(model.planStops[leg + 1].name)"
    }


    var body: some View {
        NavigationStack {
            List {
                sourceSection
                if sourceWagons.isEmpty {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(model.isLive ? "Pobieram miejsca w wagonach…" : "Brak danych na żywo").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    wagonChips
                    if let w = currentWagon {
                        summarySection(w)
                        mapSection(w)
                        legendSection
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Fotele")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { TrainPickerBar() }
            .safeAreaInset(edge: .bottom) {
                if let w = currentWagon, let n = selected, let seat = w.seats.first(where: { $0.number == n }) {
                    SeatDetailPanel(wagon: w, seat: seat, onClose: { selected = nil })
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selected)
            .task { await model.loadSegments() }
            .onChange(of: model.currentTrain.id) { _, _ in
                legChoice = nil; wagonChoice = nil; selected = nil
            }
        }
    }


    private var sourceSection: some View {
        Section {
            Picker(selection: $legChoice) {
                Text("Cała trasa").tag(Int?.none)
                ForEach(0..<model.legCount, id: \.self) { i in
                    if model.legWagons(i) != nil {
                        Text("\(i + 1). \(model.planStops[i].name) → \(model.planStops[i + 1].name)").tag(Int?.some(i))
                    }
                }
            } label: {
                Label("Odcinek", systemImage: "arrow.left.and.right")
            }
            .onChange(of: legChoice) { _, _ in selected = nil }
        } footer: {
            Text(legChoice == nil
                 ? "Miejsca wolne na całej trasie Twojego przejazdu – takie jak widzi oficjalna aplikacja."
                 : "Miejsca wolne tylko na wybranym odcinku: \(sourceTitle).")
        }
    }

    private var wagonChips: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sourceWagons.sorted { $0.wagon < $1.wagon }) { w in
                        wagonChip(w)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Wagon")
        }
    }

    private func wagonChip(_ w: CoreWagon) -> some View {
        let isCurrent = w.wagon == currentWagon?.wagon
        let count = free(w)
        let countColor: Color = count == 0 ? Color.secondary : (isCurrent ? Color.white : Color.green)
        let background: Color = isCurrent ? Color.accentColor : Color(.tertiarySystemFill)
        let textColor: Color = isCurrent ? Color.white : Color.primary
        return Button {
            wagonChoice = w.wagon
            selected = nil
        } label: {
            VStack(spacing: 2) {
                Text("W\(w.wagon)").font(.subheadline.weight(.bold))
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(countColor)
            }
            .frame(minWidth: 44)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(textColor)
        }
        .buttonStyle(.plain)
    }

    private func summarySection(_ w: CoreWagon) -> some View {
        Section {
            LabeledContent("Wagon \(w.wagon) · klasa \(w.travelClass)") {
                Text("\(free(w)) wolnych z \(total(w))").fontWeight(.semibold).foregroundStyle(free(w) > 0 ? .green : .secondary)
            }
            LabeledContent("Pary obok siebie") {
                let p = adjacentPairs(w)
                Text("\(p)").fontWeight(.semibold).foregroundStyle(p > 0 ? .green : .secondary)
            }
            if let my = model.mySeat {
                LabeledContent("Twój fotel") {
                    Text("wagon \(my.wagon), miejsce \(my.number)").fontWeight(.semibold).foregroundStyle(.yellow)
                }
            }
        }
    }

    private func mapSection(_ w: CoreWagon) -> some View {
        let lay = layout(for: w)
        return Section {
            VStack(spacing: 6) {
                Text("początek wagonu").font(.caption2).foregroundStyle(.secondary)
                WagonMapView(
                    wagon: w, width: lay.width, height: lay.height, decor: lay.decor,
                    selected: selected, planned: model.plannedSeats, mine: model.mySeat,
                    onSelect: { selected = $0 == selected ? nil : $0 })
                Text("koniec wagonu").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } header: {
            Text("Mapa wagonu")
        }
    }

    private struct LegendItem: Identifiable {
        let label: String
        let fill: Color
        let stroke: Color
        var id: String { label }
    }

    private var legendItems: [LegendItem] {
        [
            LegendItem(label: "Wolne", fill: Color.green.opacity(0.4), stroke: .green),
            LegendItem(label: "Zajęte", fill: Color(.tertiarySystemFill), stroke: .clear),
            LegendItem(label: "OzN / wózek", fill: Color.orange.opacity(0.4), stroke: .clear),
            LegendItem(label: "Wybrane", fill: .blue, stroke: .clear),
            LegendItem(label: "Z planu", fill: .clear, stroke: .blue),
            LegendItem(label: "Twój fotel", fill: .clear, stroke: .yellow),
        ]
    }

    private var legendSection: some View {
        Section("Legenda") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(legendItems) { item in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(item.fill)
                            .frame(width: 16, height: 16)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(item.stroke, lineWidth: 2))
                        Text(item.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Label("Niebieski pasek przy fotelu = przy oknie", systemImage: "rectangle.portrait.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}


private struct WagonMapView: View {
    let wagon: CoreWagon
    let width: Int
    let height: Int
    let decor: [CoreDecor]
    let selected: Int?
    let planned: Set<[Int]>
    let mine: AppModel.MySeat?
    let onSelect: (Int) -> Void

    private let scale: CGFloat = 1.25
    private let cell: CGFloat = 40

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.5))

            ForEach(decor) { d in decorView(d) }
            ForEach(wagon.seats) { s in
                if let xy = s.xy { seatView(s, xy: xy) }
            }
        }
        .frame(width: CGFloat(height) * scale, height: CGFloat(width) * scale)
    }

    private func center(x: Int, y: Int, w: Int, h: Int) -> CGPoint {
        CGPoint(x: (CGFloat(y) + CGFloat(h) / 2) * scale, y: (CGFloat(x) + CGFloat(w) / 2) * scale)
    }

    @ViewBuilder
    private func decorView(_ d: CoreDecor) -> some View {
        let c = center(x: d.x, y: d.y, w: d.w, h: d.h)
        let size = CGSize(width: CGFloat(d.h) * scale, height: CGFloat(d.w) * scale)
        if d.isSign {
            Image(systemName: symbol(for: d))
                .font(.system(size: min(size.width, size.height) * 0.55))
                .foregroundStyle(.secondary)
                .frame(width: size.width, height: size.height)
                .position(c)
                .accessibilityLabel(d.title)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: size.width - 4, height: size.height - 4)
                .position(c)
        }
    }

    private func symbol(for d: CoreDecor) -> String {
        let t = d.title.lowercased()
        if t.contains("toalet") || d.code == "401" { return "toilet.fill" }
        if t.contains("bagaż") || t.contains("bagaz") || d.code == "402" { return "suitcase.fill" }
        if t.contains("rower") { return "bicycle" }
        if t.contains("wózk") || t.contains("wozk") { return "figure.roll" }
        if t.contains("bufet") || t.contains("wars") { return "fork.knife" }
        return "info.circle.fill"
    }

    private func seatView(_ s: CoreSeat, xy: (x: Int, y: Int)) -> some View {
        let c = center(x: xy.x, y: xy.y, w: Int(cell), h: Int(cell))
        let side = cell * scale - 4
        let isSel = selected == s.number
        let isPlanned = planned.contains([wagon.wagon, s.number])
        let isMine = mine?.wagon == wagon.wagon && mine?.number == s.number
        let usable = s.isFree && !s.isSpecial
        let fill: Color = isSel ? .blue : (s.isSpecial ? .orange.opacity(0.35) : (usable ? Color.green.opacity(0.38) : Color(.tertiarySystemFill)))
        let border: Color = isMine ? .yellow : (isPlanned ? .blue : (usable && !isSel ? .green : .clear))
        return Button { onSelect(s.number) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill)
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(border, lineWidth: isMine || isPlanned ? 3 : 1.5)
                if s.isSpecial {
                    Image(systemName: "figure.roll").font(.system(size: side * 0.42)).foregroundStyle(.orange)
                } else {
                    Text("\(s.number)")
                        .font(.system(size: side * 0.34, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isSel ? .white : (usable ? .primary : .secondary))
                }
                if s.position == .window {
                    let leftEdge = CGFloat(xy.y) + cell / 2 < CGFloat(height) / 2
                    Capsule().fill(Color.cyan.opacity(usable ? 0.95 : 0.4))
                        .frame(width: 3, height: side * 0.55)
                        .frame(maxWidth: .infinity, alignment: leftEdge ? .leading : .trailing)
                        .padding(.horizontal, 2)
                }
            }
            .frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .position(c)
    }
}


private struct SeatDetailPanel: View {
    @EnvironmentObject private var model: AppModel
    let wagon: CoreWagon
    let seat: CoreSeat
    let onClose: () -> Void

    private var timeline: [Bool?] { model.seatTimeline(wagon: wagon.wagon, number: seat.number) }

    private var isMine: Bool { model.mySeat == AppModel.MySeat(wagon: wagon.wagon, number: seat.number) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wagon \(wagon.wagon) · miejsce \(seat.number)").font(.headline)
                    Text(statusText).font(.subheadline).foregroundStyle(statusColor)
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }

            if model.legCount > 0 {
                if timeline.contains(where: { $0 != nil }) {
                    timelineBar
                    Text(freeText).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Dane odcinków jeszcze się ładują…").font(.footnote).foregroundStyle(.secondary)
                }
            }

            if seat.isFree && !seat.isSpecial {
                Button {
                    model.setMySeat(isMine ? nil : AppModel.MySeat(wagon: wagon.wagon, number: seat.number))
                } label: {
                    Label(isMine ? "To już Twój fotel (usuń)" : "To mój fotel", systemImage: isMine ? "star.fill" : "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isMine ? .gray : .yellow)
                .foregroundStyle(.black)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 10, y: 2)
    }

    private var statusText: String {
        let pos = seat.position == .window ? "przy oknie" : (seat.position == .aisle ? "przy korytarzu" : "")
        let base = seat.isSpecial ? "miejsce dla OzN / wózka" : (seat.isFree ? "wolne" : "zajęte")
        return [base, pos].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var statusColor: Color { seat.isSpecial ? .orange : (seat.isFree ? .green : .secondary) }

    private var timelineBar: some View {
        HStack(spacing: 2) {
            ForEach(Array(timeline.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 3)
                    .fill(v == true ? Color.green : (v == false ? Color.gray.opacity(0.5) : Color.gray.opacity(0.15)))
                    .frame(height: 10)
            }
        }
    }

    private var freeText: String {
        var runs: [String] = []
        var start: Int?
        let tl = timeline
        for i in 0...tl.count {
            let isFree = i < tl.count && tl[i] == true
            if isFree, start == nil { start = i }
            if !isFree, let s = start {
                runs.append("\(model.planStops[s].name) → \(model.planStops[i].name)")
                start = nil
            }
        }
        if runs.isEmpty { return "Nie jest wolne na żadnym odcinku." }
        if tl.allSatisfy({ $0 == true }) { return "Wolne na całej trasie – możesz siedzieć do końca." }
        return "Wolne: " + runs.prefix(3).joined(separator: "; ") + (runs.count > 3 ? "…" : "")
    }
}
