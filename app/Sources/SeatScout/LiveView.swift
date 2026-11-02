import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                TripSection()

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Śledzenie fotela w podróży")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(model.mySeat.map { "Wagon \($0.wagon) • M. \($0.number)" } ?? "Wybierz fotel w zakładce Fotele")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue, in: Capsule())
                        }

                        Text(model.formattedCountdown)
                            .font(.system(.largeTitle, design: .rounded).monospacedDigit().weight(.bold))
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())

                        Text("Odjazd \(model.currentTrain.fromStation) o \(model.currentTrain.departureTime)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Wolne miejsca")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(model.currentTrain.freeSeatsCount) / 60")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            ProgressView(value: Double(model.currentTrain.freeSeatsCount), total: 60)
                                .tint(.green)
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
                        ForEach(model.discounts.indices, id: \.self) { idx in
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
            .listStyle(.insetGrouped)
            .navigationTitle("Seat Scout")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { TrainPickerBar() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Label("Na żywo", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
