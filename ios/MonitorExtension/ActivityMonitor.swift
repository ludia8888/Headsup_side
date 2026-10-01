import Foundation
import DeviceActivity
import JiminCore

final class ActivityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        try? SharedResources.store().update { state in
            // A restarted schedule is not a new day. Only the local date can reset it.
            InterventionPolicy.rollDay(&state, now: Date())
        }
    }
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        #if DEBUG
        if let testID = ScreenTimeScheduler.parseFresh(event) {
            let now = Date()
            do {
                let decision = try SharedResources.store().update { state in
                    InterventionPolicy.handleFreshUsageTest(&state, testID: testID, now: now,
                        approvalGranted: SharedResources.automaticDispatchApproved)
                }
                if case .request(let id) = decision { MonitorDispatcher.shared.dispatch(callID: id, at: now, mode: "testPush") }
            } catch {
                NSLog("Jimin fresh-usage test could not update its local record.")
            }
            DeviceActivityCenter().stopMonitoring([activity])
            return
        }
        #endif
        guard let (appID, kind) = ScreenTimeScheduler.parse(event) else { return }
        let now = Date()
        do {
            let decision = try SharedResources.store().update { state in
                // AuthorizationCenter starts as .notDetermined in a newly
                // launched extension, even when the host app has authorization.
                // The host app records its confirmed status in this shared store;
                // reading the extension's initial value would discard real events.
                return InterventionPolicy.handleThreshold(&state, appID: appID, kind: kind, now: now,
                    approvalGranted: SharedResources.automaticDispatchApproved)
            }
            if case .request(let id) = decision { MonitorDispatcher.shared.dispatch(callID: id, at: now) }
            if kind == .retry { DeviceActivityCenter().stopMonitoring([activity]) }
        } catch {
            // Fail closed: corrupt/missing shared storage never causes an untracked call.
            NSLog("Jimin monitor could not safely update its local ledger.")
        }
    }
}
