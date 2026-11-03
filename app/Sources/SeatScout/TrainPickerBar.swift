import SwiftUI

struct TrainPickerBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Button {
                    model.showSearch = true
                } label: {
                    HStack(spacing: expanded ? 12 : 9) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: expanded ? 17 : 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: expanded ? 38 : 26, height: expanded ? 38 : 26)
                            .background(Color.accentColor.opacity(expanded ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 3) {
                            routeLabel
                            if expanded {
                                Text(dateLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Szukaj pociągu, \(model.searchSummary)")

                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.12)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Zwiń wybór pociągu" : "Rozwiń wybór pociągu")
            }
            .padding(.leading, expanded ? 12 : 10)
            .padding(.trailing, 5)
            .padding(.vertical, expanded ? 9 : 3)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: expanded ? 16 : 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: expanded ? 16 : 13, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))

            if expanded && !model.trains.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.trains.indices, id: \.self) { index in
                            let train = model.trains[index]
                            let selected = index == model.selectedTrainIndex
                            Button {
                                model.selectTrain(index)
                            } label: {
                                Text("\(train.number) \(train.name)")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                                    .background(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, expanded ? 10 : 8)
        .background(.bar)
        .onAppear { expanded = model.selectedTab == .live }
        .onChange(of: model.selectedTab) { _, tab in
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.12)) {
                expanded = tab == .live
            }
        }
    }

    @ViewBuilder
    private var routeLabel: some View {
        if let from = model.fromStation, let to = model.toStation {
            HStack(spacing: 6) {
                Text(shortName(from.name)).lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(shortName(to.name)).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
        } else {
            Text("Znajdź pociąg")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var dateLabel: String {
        guard model.fromStation != nil, model.toStation != nil else { return "Wybierz trasę i datę" }
        return model.searchDate.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pl_PL")))
    }

    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: " Główny", with: " Gł.")
            .replacingOccurrences(of: " Centralna", with: " Centr.")
    }
}
