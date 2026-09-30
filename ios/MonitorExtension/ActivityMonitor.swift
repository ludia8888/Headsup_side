import Foundation
import DeviceActivity
import FamilyControls
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
        guard let (appID, kind) = ScreenTimeScheduler.parse(event) else { return }
        let now = Date()
        do {
            let decision = try SharedResources.store().update { state in
                state.screenTimeAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
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
