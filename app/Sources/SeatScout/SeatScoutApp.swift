import SwiftUI
import UserNotifications

@main
struct SeatScoutApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AlertService.registerBackgroundTask()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            AlertService.shared.scenePhaseChanged(phase)
        }
    }
}
