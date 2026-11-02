import SwiftUI

struct TrainPickerBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    model.showSearch = true
                } label: {
                    Label(model.searchSummary, systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)

                ForEach(model.trains.indices, id: \.self) { idx in
                    let train = model.trains[idx]
                    let isSelected = idx == model.selectedTrainIndex
                    Button {
                        model.selectTrain(idx)
                    } label: {
                        Text("\(train.number) \(train.name)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(isSelected ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}
