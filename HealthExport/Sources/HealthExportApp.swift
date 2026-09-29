import SwiftUI
import BackgroundTasks
import HealthKit

@main
struct HealthExportApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Catch up on today's export whenever the app is opened (phone is unlocked here).
                Task { await ExportCoordinator.shared.run(force: false) }
            } else if phase == .background {
                ExportCoordinator.scheduleNextRefresh()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Must be registered before launch finishes.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: ExportCoordinator.refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            ExportCoordinator.scheduleNextRefresh()
            let work = Task { @MainActor in
                let ok = await ExportCoordinator.shared.run(force: false)
                task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = { work.cancel() }
        }
        ExportCoordinator.scheduleNextRefresh()
        HealthExporter.startBackgroundDelivery()
        // If the app is alive in the background, export as soon as the phone is unlocked.
        NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in await ExportCoordinator.shared.run(force: false) }
        }
        return true
    }
}
