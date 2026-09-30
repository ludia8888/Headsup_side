import Foundation
import JiminCore

/// No network operation occurs at all while the Apple approval gate is closed.
/// Background uploads may be delayed by iOS; the server rejects stale signals.
final class MonitorDispatcher: NSObject, URLSessionTaskDelegate {
    static let shared = MonitorDispatcher()
    var backgroundCompletion: (() -> Void)?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: SharedResources.transferIdentifier)
        config.sharedContainerIdentifier = SharedResources.group
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 45
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    func resume() { _ = session }
    func dispatch(callID: UUID, at: Date) {
        guard SharedResources.automaticDispatchApproved else { return }
        do {
            guard let connection = try SecureConnectionStore.read() else { throw DispatchError.noConnection }
            let store = try SharedResources.store()
            let folder = store.directory.appendingPathComponent("Transfers")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(callID.uuidString + ".json")
            let body: [String: Any] = ["requestId": callID.uuidString, "mode": "automatic",
                "createdAt": ISO8601DateFormatter().string(from: at)]
            try JSONSerialization.data(withJSONObject: body).write(to: file, options: .atomic)
            var request = URLRequest(url: connection.baseURL.appendingPathComponent("v1/calls"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
            let task = session.uploadTask(with: request, fromFile: file)
            task.taskDescription = callID.uuidString
            task.resume()
        } catch {
            fail(callID, reason: "통화 요청 전송 실패: \(error.localizedDescription)")
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let rawID = task.taskDescription, let id = UUID(uuidString: rawID) else { return }
        let code = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        if error != nil || !(200..<300).contains(code) { fail(id, reason: "통화 요청 전송 실패 (HTTP \(code))") }
        if let store = try? SharedResources.store() {
            try? FileManager.default.removeItem(at: store.directory.appendingPathComponent("Transfers/\(rawID).json"))
        }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { self.backgroundCompletion?(); self.backgroundCompletion = nil }
    }
    private func fail(_ id: UUID, reason: String) {
        try? SharedResources.store().update { state in
            InterventionPolicy.finish(&state, callID: id, outcome: .failed, now: Date())
            state.lastMonitorError = reason
        }
    }
    enum DispatchError: LocalizedError {
        case noConnection
        var errorDescription: String? { "시험 서버 연결이 없습니다." }
    }
}
