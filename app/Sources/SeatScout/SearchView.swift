import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Field { case from, to }
    @FocusState private var focus: Field?
    @State private var fromText = ""
    @State private var toText = ""

    var body: some View {
        NavigationStack {
            Form {
                if model.dictionary == nil {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(model.isLoading ? "Pobieram słownik stacji…" : "Słownik stacji niedostępny")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !model.isLoading {
                                Button("Ponów") { Task { await model.loadLive() } }
                            }
                        }
                    }
                }

                Section("Trasa") {
                    stationRow("Skąd", systemImage: "circle", text: $fromText, field: .from) { model.fromStation = $0 }
                    suggestions(for: fromText, field: .from) { model.fromStation = $0; fromText = $0.name; focus = nil }

                    stationRow("Dokąd", systemImage: "flag.checkered", text: $toText, field: .to) { model.toStation = $0 }
                    suggestions(for: toText, field: .to) { model.toStation = $0; toText = $0.name; focus = nil }

                    Button {
                        model.swapStations()
                        syncTexts()
                    } label: {
                        Label("Zamień stacje", systemImage: "arrow.up.arrow.down")
                    }
                }

                Section {
                    DatePicker("Data", selection: $model.searchDate, in: Date()...Date().addingTimeInterval(30 * 24 * 3600),
                               displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "pl_PL"))

                    Button {
                        focus = nil
                        Task { await model.search() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isSearching { ProgressView() } else { Text("Szukaj połączeń").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(model.isSearching || model.fromStation == nil || model.toStation == nil)
                }

                if model.isLive, !model.trains.isEmpty {
                    Section("Połączenia bezpośrednie (\(model.trains.count))") {
                        ForEach(model.trains.indices, id: \.self) { idx in
                            resultRow(model.trains[idx], selected: idx == model.selectedTrainIndex) {
                                model.pickSearchResult(idx)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Szukaj pociągu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") { closeSheet() }
                }
            }
            .onAppear(perform: syncTexts)
            .onChange(of: model.dictionary == nil) { _, _ in syncTexts() }
        }
        .presentationDetents([.large])
    }


    private func syncTexts() {
        fromText = model.fromStation?.name ?? ""
        toText = model.toStation?.name ?? ""
    }

    private func closeSheet() {
        model.showSearch = false
        if model.isLive, model.currentTrain.wagonNumber == 0 { Task { await model.loadDetails() } }
    }

    private func stationRow(_ title: String, systemImage: String, text: Binding<String>, field: Field,
                            onClear: @escaping (CoreStation?) -> Void) -> some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 22)
            TextField(title, text: text)
                .focused($focus, equals: field)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: text.wrappedValue) { _, new in
                    let current = field == .from ? model.fromStation : model.toStation
                    if let current, current.name != new { onClear(nil) }
                }
        }
    }

    @ViewBuilder
    private func suggestions(for text: String, field: Field, pick: @escaping (CoreStation) -> Void) -> some View {
        let chosen = field == .from ? model.fromStation : model.toStation
        if focus == field, chosen == nil {
            ForEach(model.suggestStations(text)) { st in
                Button { pick(st) } label: {
                    Label(st.name, systemImage: "tram.fill").foregroundStyle(.primary)
                }
            }
        }
    }

    private func resultRow(_ t: TrainInfo, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(t.departureTime) → \(t.arrivalTime)")
                        .font(.headline.monospacedDigit())
                    Text("\(t.number) \(t.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(t.duration).font(.subheadline.weight(.semibold))
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
