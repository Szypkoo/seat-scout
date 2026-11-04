import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if !model.isLive {
                if model.isLoading {
                    loadingSection
                } else {
                    Section {
                        Text("Wybierz połączenie, aby zobaczyć szczegóły.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                TripSection()

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Twoja podróż")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let seat = model.mySeat {
                                Text("Wagon \(seat.wagon) • M. \(seat.number)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.blue, in: Capsule())
                            }
                        }

                        Text("Odjazd z \(model.currentTrain.fromStation) o \(model.currentTrain.departureTime)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if model.hasDepartureTime {
                            #if !SKIP
                            Text(model.formattedCountdown)
                                .font(.system(.largeTitle, design: .rounded).monospacedDigit().weight(.bold))
                                .foregroundStyle(.green)
                                .contentTransition(.numericText())
                            #else
                            Text(model.formattedCountdown)
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .foregroundStyle(.green)
                            #endif
                        } else if model.isLoadingDetails {
                            LoadingBar(width: 165.0, height: 36.0)
                        }

                        let total = model.detailWagons.flatMap(\.seats).filter { !$0.isSpecial }.count
                        if total > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Wolne miejsca")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(model.currentTrain.freeSeatsCount) / \(total)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                }
                                ProgressView(value: Double(model.currentTrain.freeSeatsCount), total: Double(total))
                                    .tint(.green)
                            }
                        } else if model.isLoadingDetails {
                            VStack(alignment: .leading, spacing: 8) {
                                LoadingBar(width: 100.0)
                                LoadingBar(height: 8.0)
                            }
                            .accessibilityLabel("Pobieram dane o miejscach")
                        } else {
                            Text("Brak danych o miejscach")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Na żywo")
                }

                Section("Połączenie") {
                    LabeledContent {
                        Text(model.currentTrain.departureTime)
                    } label: {
                        Label(model.currentTrain.fromStation, systemImage: "circle.fill")
                            .foregroundStyle(.blue)
                    }
                    LabeledContent {
                        Text(model.currentTrain.arrivalTime)
                    } label: {
                        Label(model.currentTrain.toStation, systemImage: "flag.checkered.circle.fill")
                            .foregroundStyle(.green)
                    }
                    LabeledContent("Czas podróży", value: model.currentTrain.duration)
                }

                Section("Bilet") {
                    Picker("Zniżka", selection: $model.selectedDiscountIndex) {
                        ForEach(0..<model.discounts.count, id: \.self) { idx in
                            Text(model.discounts[idx].name).tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)

                    if model.ticketPrices.isEmpty, let note = model.priceNote {
                        Label {
                            Text(note).font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    } else if model.ticketPrices.isEmpty && model.currentTrain.basePrice <= 0 {
                        LabeledContent("Cena") {
                            if model.isLoadingDetails {
                                LoadingBar(width: 75.0, height: 20.0)
                                    .accessibilityLabel("Pobieram cenę")
                            } else {
                                Text("Brak danych").foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        LabeledContent("Cena") {
                            HStack(spacing: 6) {
                                Text(model.currentTrain.basePrice > 0 || !model.ticketPrices.isEmpty
                                     ? model.priceString(model.calculatedPrice) : "…")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.primary)
                                if model.currentDiscount.discountPercent > 0, model.currentTrain.basePrice > 0 {
                                    Text(model.priceString(model.currentTrain.basePrice))
                                        .font(.footnote)
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if model.currentDiscount.discountPercent > 0, model.currentTrain.basePrice > 0, !model.ticketPrices.isEmpty {
                        LabeledContent("Oszczędzasz") {
                            Text(model.priceString(model.savingsAmount))
                                .foregroundStyle(.green)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        #if !SKIP
        .listStyle(.insetGrouped)
        #else
        .listStyle(.automatic)
        #endif
    }
    @ViewBuilder
    private var loadingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                LoadingBar(width: 150.0, height: 18.0)
                LoadingBar(width: 205.0)
                LoadingBar(width: 120.0)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Gdzie jest pociąg")
        }

        Section {
            VStack(alignment: .leading, spacing: 12) {
                LoadingBar(width: 130.0, height: 16.0)
                LoadingBar(width: 190.0)
                LoadingBar(width: 155.0, height: 34.0)
                HStack {
                    LoadingBar(width: 105.0)
                    Spacer()
                    LoadingBar(width: 50.0)
                }
                LoadingBar(height: 6.0)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Na żywo")
        }

        Section("Połączenie") {
            ForEach(0..<3, id: \.self) { _ in
                HStack {
                    LoadingBar(width: 145.0)
                    Spacer()
                    LoadingBar(width: 45.0)
                }
                .padding(.vertical, 2)
            }
        }
        #if !SKIP
        .accessibilityElement(children: .ignore)
        #endif
        .accessibilityLabel("Pobieram połączenia")
    }
}

struct LoadingBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var width: CGFloat? = nil
    var height: CGFloat = 14.0

    var body: some View {
        RoundedRectangle(cornerRadius: min(height / 2, 6.0))
            .fill(Color.secondary.opacity(0.2))
            .frame(width: width, height: height)
            .opacity(isPulsing && !reduceMotion ? 0.45 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .accessibilityHidden(true)
    }
}
