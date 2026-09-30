import Foundation
import AVFAudio
@preconcurrency import WebRTC

/// Native WebRTC audio and the GPT-Live "oai-events" data channel.
/// The app never receives a standard OpenAI API key.
@MainActor final class RealtimeTransport: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL(); return RTCPeerConnectionFactory()
    }()
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?
    private var ready = false
    private var sessionStarted = false
    private var connected = false
    private var closed = false
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onEvent: (([String: Any]) -> Void)?

    func connect(callID: UUID) async throws {
        let audio = RTCAudioSession.sharedInstance()
        audio.useManualAudio = true
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        // GPT-Live provides server candidates in its SDP answer. No third-party TURN
        // credentials or arbitrary relay infrastructure are embedded in the client.
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else { throw TransportError("WebRTC 연결을 만들지 못했어요.") }
        peer = pc
        let source = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: ["googEchoCancellation": "true", "googNoiseSuppression": "true"], optionalConstraints: nil))
        let track = Self.factory.audioTrack(with: source, trackId: "microphone"); audioTrack = track
        _ = pc.add(track, streamIds: ["jimin-audio"])
        let dataConfig = RTCDataChannelConfiguration(); dataConfig.isOrdered = true
        channel = pc.dataChannel(forLabel: "oai-events", configuration: dataConfig); channel?.delegate = self
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            pc.offer(for: RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)) { sdp, error in
                if let sdp { continuation.resume(returning: sdp) } else { continuation.resume(throwing: error ?? TransportError("음성 연결 제안을 만들지 못했어요.")) }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(offer) { error in error.map { continuation.resume(throwing: $0) } ?? continuation.resume() }
        }
        // Single SDP exchange requires gathered candidates, rather than an unimplemented
        // trickle-ICE signaling path. Poll only this local object, with a bounded timeout.
        for _ in 0..<100 {
            try Task.checkCancellation()
            if closed { throw CancellationError() }
            if pc.iceGatheringState == .complete { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let answer = try await BackendClient.session(callID, offer: pc.localDescription?.sdp ?? offer.sdp)
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer)) { error in
                error.map { continuation.resume(throwing: $0) } ?? continuation.resume()
            }
        }
    }
    func send(_ event: [String: Any]) {
        guard !closed, channel?.readyState == .open,
              let data = try? JSONSerialization.data(withJSONObject: event) else { return }
        _ = channel?.sendData(RTCDataBuffer(data: data, isBinary: false))
    }
    func greet() {
        // Persona, story seed, and consent rules were fixed by the trusted server at session creation.
        send(["type": "session.instructions.append", "event_id": UUID().uuidString, "delegation_id": NSNull(),
              "content": "지금 한국어로 먼저 짧게 인사해. 이번 전화의 새 소재로 예상 밖의 질문 하나를 자연스럽게 건네고 답을 기다려. 매번 같은 안부로 시작하지 마."])
    }
    func accompany() {
        send(["type": "session.instructions.append", "event_id": UUID().uuidString, "delegation_id": NSNull(),
              "content": "사용자가 동의해 지금부터 20분 조용히 함께 있는 중이다. 먼저 말을 걸지 말고, 사용자가 직접 말을 걸 때만 짧게 답해. 기존 성격과 기억 동의 규칙은 계속 지켜."])
    }
    func goodbye() {
        send(["type": "session.instructions.append", "event_id": UUID().uuidString, "delegation_id": NSNull(),
              "content": "함께 있던 시간이 끝났어. 지금 한국어로 짧게 수고했다고 말하고 다정하게 인사해. 실제로 일을 시작했는지는 단정하지 마. 2문장 안에 마무리해."])
    }
    func functionResult(callID: String, result: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: result), let output = String(data: data, encoding: .utf8) else { return }
        send(["type": "response.item.create", "event_id": UUID().uuidString,
              "item": ["type": "function_call_output", "call_id": callID, "output": output]])
    }
    func continueBackend() { send(["type": "response.create", "event_id": UUID().uuidString]) }
    func setMuted(_ muted: Bool) {
        audioTrack?.isEnabled = !muted
        send(["type": muted ? "session.input_audio.mute" : "session.input_audio.unmute", "event_id": UUID().uuidString])
    }
    func close() {
        guard !closed else { return }; closed = true
        audioTrack?.isEnabled = false
        onReady = nil; onFailure = nil
        if sessionStarted, channel?.readyState == .open,
           let data = try? JSONSerialization.data(withJSONObject: ["type": "session.close", "event_id": UUID().uuidString]) {
            _ = channel?.sendData(RTCDataBuffer(data: data, isBinary: false))
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in releaseResources() }
        } else { releaseResources() }
    }
    private func releaseResources() {
        channel?.close(); peer?.close()
        channel = nil; peer = nil; audioTrack = nil; onEvent = nil
    }
    private func checkReady() {
        guard connected, sessionStarted, channel?.readyState == .open, !ready, !closed else { return }
        ready = true; DispatchQueue.main.async { self.onReady?() }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCPeerConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closed else { return }
            self.connected = stateChanged == .connected
            if stateChanged == .connected { self.checkReady() }
            else if stateChanged == .failed { self.onFailure?("음성 연결이 끊겼어요. 네트워크를 확인해 주세요.") }
            else if stateChanged == .disconnected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                    guard let self, !self.closed, !self.connected else { return }; self.onFailure?("음성 연결이 끊겼어요.")
                }
            }
        }
    }
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) { DispatchQueue.main.async { [weak self] in self?.checkReady() } }
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let event = try? JSONSerialization.jsonObject(with: buffer.data) as? [String: Any] else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let type = event["type"] as? String
            if type == "session.started" { self.sessionStarted = true; self.checkReady() }
            self.onEvent?(event)
            if type == "session.closed" { self.releaseResources() }
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        DispatchQueue.main.async { [weak self] in self?.channel = dataChannel; dataChannel.delegate = self; self?.checkReady() }
    }
    struct TransportError: LocalizedError { let text: String; init(_ text: String) { self.text = text }; var errorDescription: String? { text } }
}
