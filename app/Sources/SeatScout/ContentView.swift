import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct ContentView: View {
    @StateObject private var model = AppModel()
    @ObservedObject private var logs = AppLog.shared
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            NavigationStack {
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
                .navigationTitle(model.selectedTab == .live ? "Seat Scout" : model.selectedTab.title)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if model.selectedTab != .developer {
                        TrainPickerBar()
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if model.selectedTab == .live && model.isLive {
                            Label("Na żywo", systemImage: "circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                        }
                        if model.selectedTab == .segments {
                            Button {
                                Task { await model.refreshSegments() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(model.isLoadingSegments)
                        }
                        if model.selectedTab == .developer {
                            Button {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = logs.text
                                #endif
                                model.showToast("Skopiowano \(logs.entries.count) wpisów")
                            } label: { Image(systemName: "doc.on.doc") }
                            ShareLink(item: logs.text) { Image(systemName: "square.and.arrow.up") }
                            Button(role: .destructive) { logs.clear() } label: { Image(systemName: "trash") }
                        }
                    }
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
        .task(id: model.trackingKey) { await model.trackingLoop() }
        .sheet(isPresented: $model.showSearch) {
            SearchView().environmentObject(model)
        }
    }
}
