import Combine
import SwiftUI

public struct ContentView: View {
    @StateObject private var model = AppModel()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $model.selectedTab) {
                Tab("Na żywo", systemImage: "bolt.fill", value: AppTab.live) {
                    LiveView()
                }

                Tab("Plan miejsc", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: AppTab.segments) {
                    SegmentsView()
                }

                Tab("Fotele", systemImage: "chair.lounge.fill", value: AppTab.seats) {
                    SeatsView()
                }
                .badge(model.currentTrain.freeSeatsCount)

                Tab("Śledzone", systemImage: "bell.fill", value: AppTab.saved) {
                    SavedView()
                }

                Tab("Developer", systemImage: "terminal.fill", value: AppTab.developer) {
                    DeveloperView()
                }
            }

            if let toast = model.toastMessage {
                ToastView(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .environmentObject(model)
        .onReceive(timer) { _ in model.tick() }
        .task { await model.loadLive() }
        .task { await AlertService.shared.foregroundLoop() }
        .task(id: model.currentTrain.id) { await model.trackingLoop() }
        .sheet(isPresented: $model.showSearch) {
            SearchView().environmentObject(model)
        }
    }
}
