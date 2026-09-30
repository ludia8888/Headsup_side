import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        CallCoordinator.shared.start(); return true
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == SharedResources.transferIdentifier else { completionHandler(); return }
        MonitorDispatcher.shared.backgroundCompletion = completionHandler; MonitorDispatcher.shared.resume()
    }
}

@main struct JiminApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).tint(Palette.rose)
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .preferredColorScheme(.dark)
                .onOpenURL { url in model.connectLocalSimulator(url) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh(); model.calls.tick(); Task { await model.checkConnection() } }
                }
        }
    }
}
