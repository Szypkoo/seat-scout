import SwiftUI
#if !SKIP && canImport(UserNotifications)
import UserNotifications
#endif

#if !SKIP
@main
struct SeatScoutApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if canImport(BackgroundTasks)
        AlertService.registerBackgroundTask()
        #endif
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        #endif
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
#endif
