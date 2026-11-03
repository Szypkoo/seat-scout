import SwiftUI
#if !SKIP && canImport(UserNotifications)
import UserNotifications
#endif

@main
struct SeatScoutApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if !SKIP && canImport(BackgroundTasks)
        AlertService.registerBackgroundTask()
        #endif
        #if !SKIP && canImport(UserNotifications)
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
