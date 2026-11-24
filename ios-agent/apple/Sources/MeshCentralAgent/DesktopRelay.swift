// SPDX-License-Identifier: Apache-2.0
import Foundation
import Security
import CryptoKit
import CMeshCore
import Network

/// One read-only viewer. Queue-confined protocol state; callbacks arrive on main.
public final class DesktopRelay: NSObject, URLSessionWebSocketDelegate {
    private enum State { case waiting, protocolSelection, consent, capture, sharing, closed }
    private let queue = DispatchQueue(label: "MeshCentral.desktop")
    private let request: DesktopRequest
    private let privateCA: Data?
    private var gate: UnsafeMutableRawPointer?
    private let requested: (DesktopRelay, DesktopPrompt) -> Void
    private let finished: () -> Void
    private var state = State.waiting
    private var recording = false
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var deadline: DispatchWorkItem?
    private var sendDeadline: DispatchWorkItem?
    private var pingTimer: DispatchSourceTimer?
    private var pingDeadline: DispatchWorkItem?
    private var captureCallback: (() -> Void)?
    private var endCallback: ((Error?) -> Void)?
    private var terminalError: Error?
    private var paused = false
    private var sending = false
    private var screenSource: UUID?
    private var maskCompletion: ((Bool) -> Void)?
    private var dimensions: (UInt16, UInt16)?
    private var promptID = UUID()
    private var trustValidated = false
    private let assistance: AssistanceEngine
    private var assistanceCallback: ((AssistanceSnapshot) -> Void)?
    private var diagnosticsCallback: ((ConnectionDiagnostics) -> Void)?
    private var latestJPEG: Data?
    private var quality = mc_quality_new()
    private let profileLock = NSLock()
    private var profileLevel: UInt32 = 1
    private var metrics = ConnectionDiagnostics()
    private var metricsTimer: DispatchSourceTimer?
    private var previousFrames: UInt64 = 0, previousBytes: UInt64 = 0
    private var lastMetrics = ProcessInfo.processInfo.systemUptime
    private var lastSent = 0.0
    private var pendingControl = 0
    private let networkMonitor = NWPathMonitor()
    private var sharingSince = 0.0
    private var broadcastStartedAt: Double?
    public func setBroadcastStart(_ uptime: Double) {
        queue.async { self.broadcastStartedAt = uptime }
    }

    deinit { if let quality = quality { mc_quality_free(quality) } }
    public func videoProfile() -> VideoProfile {
        profileLock.lock(); defer { profileLock.unlock() }
        return VideoProfile.level(profileLevel)
    }
    public func setAssistanceHandlers(onChange: @escaping (AssistanceSnapshot) -> Void,
                                      onDiagnostics: @escaping (ConnectionDiagnostics) -> Void) {
        queue.async {
            self.assistanceCallback = onChange; self.diagnosticsCallback = onDiagnostics
            let snapshot = self.assistance.snapshot
            DispatchQueue.main.async { onChange(snapshot) }
        }
    }
    public func assistanceCommand(_ command: AssistanceCommand) {
        queue.async {
            guard self.authorizedSharing() else { return }
            self.assistance.local(command, capture: self.latestJPEG)
        }
    }
    private func authorizedSharing() -> Bool {
        guard state == .sharing, let gate = gate else { return false }
        guard BroadcastTiming.policy(phase: 1, since: broadcastStartedAt ?? sharingSince) == 0 else {
            finish(AgentError.timeout); return false
        }
        return mc_share_event(gate, 6) == 1
    }

    init(request: DesktopRequest, privateCA: Data?, gate: UnsafeMutableRawPointer,
         requested: @escaping (DesktopRelay, DesktopPrompt) -> Void, finished: @escaping () -> Void) {
        self.request = request; self.privateCA = privateCA; self.gate = gate
        assistance = AssistanceEngine(chatAllowed: request.rights & 0x4000 != 0,
            documentsAllowed: request.rights == UInt32.max || request.rights & 0x400 == 0)
        self.requested = requested; self.finished = finished
        super.init()
        assistance.send = { [weak self] value in
            guard let self = self, self.authorizedSharing(),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let text = String(data: data, encoding: .utf8) else { return }
            self.sendControl(text)
        }
        assistance.changed = { [weak self] value in
            let callback = self?.assistanceCallback
            DispatchQueue.main.async { callback?(value) }
        }
    }

    func start() {
        queue.async {
            guard self.state == .waiting, self.session == nil else { return }
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
            config.timeoutIntervalForRequest = 20
            let delegates = OperationQueue(); delegates.maxConcurrentOperationCount = 1; delegates.underlyingQueue = self.queue
            let session = URLSession(configuration: config, delegate: self, delegateQueue: delegates)
            self.session = session
            self.socket = session.webSocketTask(with: self.request.url)
            self.socket?.maximumMessageSize = 16384
            self.expire(after: 30)
            self.networkMonitor.pathUpdateHandler = { [weak self] path in
                guard let self = self, self.state != .closed else { return }
                self.metrics.networkState = path.status == .satisfied ? "available" : (path.status == .requiresConnection ? "requiresConnection" : "unavailable")
                self.metrics.networkInterface = path.usesInterfaceType(.wiredEthernet) ? "ethernet" : (path.usesInterfaceType(.wifi) ? "wifi" : (path.usesInterfaceType(.cellular) ? "cellular" : "other"))
                self.metrics.constrained = path.isConstrained; self.metrics.expensive = path.isExpensive
            }
            self.networkMonitor.start(queue: self.queue)
            self.socket?.resume()
            self.receive()
        }
    }

    public func setHandlers(onCapture: @escaping () -> Void, onEnded: @escaping (Error?) -> Void) {
        queue.async {
            self.captureCallback = onCapture; self.endCallback = onEnded
            if self.state == .closed { DispatchQueue.main.async { onEnded(self.terminalError) } }
        }
    }
    public func approve() {
        queue.async {
            guard self.state == .consent, let gate = self.gate, mc_share_event(gate, 1) == 0 else { return }
            self.state = .capture; self.expire(after: 30)
            let callback = self.captureCallback
            DispatchQueue.main.async { callback?() }
        }
    }
    public func captureStarted(source: UUID) {
        queue.async {
            guard self.state == .capture, let gate = self.gate, mc_share_event(gate, 2) == 0 else { return }
            self.state = .sharing; self.expire(after: 600)
            self.screenSource = source
            self.sharingSince = ProcessInfo.processInfo.systemUptime
            self.metrics.stage = "sharing"; self.metrics.tlsVerified = true
            if let callback = self.assistanceCallback {
                let snapshot = self.assistance.snapshot
                DispatchQueue.main.async { callback(snapshot) }
            }
            let capabilities: [String: Any] = ["type": "iosAssist", "ctrlChannel": "102938", "v": 1, "action": "ready",
                "chatAllowed": self.assistance.snapshot.chatAllowed, "documentsAllowed": self.assistance.snapshot.documentsAllowed,
                "guidedAssistance": 1, "consoleVersion": 1, "sessionTiming": 1, "agentVersion": "0.5.2",
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString]
            if let data = try? JSONSerialization.data(withJSONObject: capabilities), let text = String(data: data, encoding: .utf8) {
                self.sendControl(text)
            }
            self.sendConsole(nil)
        }
    }
    public func stop() { queue.async { self.finish(nil) } }

    /// A nil source masks video. Resuming registers a fresh capture source.
    /// Only the local app or its broadcast extension calls this.
    public func setScreenSource(_ source: UUID?, completion: @escaping (Bool) -> Void) {
        queue.async {
            let reply: (Bool) -> Void = { success in DispatchQueue.main.async { completion(success) } }
            let hidden = source == nil
            guard self.authorizedSharing(), self.maskCompletion == nil, let gate = self.gate,
                  mc_share_event(gate, hidden ? 4 : 5) == 0 else { reply(false); return }
            self.screenSource = source
            if hidden {
                self.maskCompletion = reply
                self.latestJPEG = nil
                self.assistance.hideScreen()
                self.sendMaskIfReady()
            } else {
                self.lastSent = ProcessInfo.processInfo.systemUptime
                self.announceScreen(hidden: false)
                reply(self.state == .sharing)
            }
        }
    }

    private func announceScreen(hidden: Bool) {
        sendControl(hidden
            ? #"{"type":"iosAssist","ctrlChannel":"102938","v":1,"action":"screenVisibility","hidden":true}"#
            : #"{"type":"iosAssist","ctrlChannel":"102938","v":1,"action":"screenVisibility","hidden":false}"#)
        sendConsole(hidden ? "Écran masqué sur l’appareil." : nil)
    }

    private func sendMaskIfReady() {
        guard !sending, maskCompletion != nil else { return }
        guard authorizedSharing(), let jpeg = ScreenFramePump.privacyImage() else {
            finish(AgentError.closed); return
        }
        announceScreen(hidden: true)
        sendFrame(jpeg: jpeg, width: 320, height: 180, source: nil) { success in
            let completion = self.maskCompletion
            self.maskCompletion = nil
            if !success { self.finish(AgentError.closed) }
            completion?(success)
        }
    }

    private func canSendFrame(source: UUID?) -> Bool {
        guard authorizedSharing(), source == screenSource, let gate = gate else { return false }
        if source == nil { return maskCompletion != nil }
        return !paused && mc_share_event(gate, 3) == 1
    }

    /// The capture pump reserves one frame until completion, including encoding.
    public func submit(jpeg: Data, width: UInt16, height: UInt16, source: UUID, completion: @escaping () -> Void) {
        queue.async {
            let started = ProcessInfo.processInfo.systemUptime
            self.sendFrame(jpeg: jpeg, width: width, height: height, source: source) { success in
                completion()
                guard success, self.screenSource == source else { return }
                self.latestJPEG = jpeg
                self.metrics.sendMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
                self.metrics.frames += 1; self.metrics.bytes += UInt64(jpeg.count)
                self.lastSent = started
                let elapsed = max(self.metrics.sendMS, self.metrics.roundTripMS)
                let level = mc_quality_observe(self.quality, UInt32(min(60000, elapsed)), UInt32(jpeg.count))
                self.profileLock.lock(); self.profileLevel = level; self.profileLock.unlock()
                self.metrics.qualityLevel = level
            }
        }
    }

    private func sendFrame(jpeg: Data, width: UInt16, height: UInt16, source: UUID?, completion: @escaping (Bool) -> Void) {
        guard !sending, canSendFrame(source: source), jpeg.count <= 524288 else { completion(false); return }
        var size = [UInt8](repeating: 0, count: 8)
        guard mc_screen_size(width, height, &size, 8) == 8 else { completion(false); return }
        let bytes = [UInt8](jpeg)
        let capacity = jpeg.count + 16
        var output = [UInt8](repeating: 0, count: capacity)
        let length = mc_screen_jpeg(bytes, bytes.count, &output, capacity)
        guard length > 0 else { completion(false); return }
        sending = true
        let timeout = DispatchWorkItem { [weak self] in self?.finish(AgentError.timeout) }
        sendDeadline = timeout; queue.asyncAfter(deadline: .now() + 10, execute: timeout)
        let tile = Data(output.prefix(length))
        let done: (Bool) -> Void = { success in
            self.sendDeadline?.cancel(); self.sendDeadline = nil
            self.sending = false
            completion(success)
            self.sendMaskIfReady()
        }
        let sendTile: (Bool) -> Void = { sizeSent in
            // A local mask can arrive while the size packet is in flight.
            guard sizeSent, self.canSendFrame(source: source) else { done(false); return }
            self.sendMedia(tile, completion: done)
        }
        if dimensions?.0 != width || dimensions?.1 != height {
            dimensions = (width, height)
            sendMedia(Data(size), completion: sendTile)
        } else { sendTile(true) }
    }

    private func sendMedia(_ data: Data, completion: @escaping (Bool) -> Void) {
        guard authorizedSharing(), let socket = socket else { completion(false); return }
        socket.send(.data(data)) { [weak self] error in
            guard let self = self else { completion(false); return }
            self.queue.async {
                if let error = error { self.finish(error) }
                completion(error == nil && self.state == .sharing)
            }
        }
    }
    private func sendConsole(_ message: String?) {
        let object: [String: Any] = ["ctrlChannel": "102938", "type": "console", "msg": message.map { $0 as Any } ?? NSNull()]
        if let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) {
            sendControl(text)
        }
    }
    private func sendControl(_ text: String) {
        guard state != .closed, text.utf8.count <= 16384, pendingControl < 16 else {
            if state != .closed { finish(AgentError.protocolViolation) }; return
        }
        pendingControl += 1
        socket?.send(.string(text)) { [weak self] error in
            self?.queue.async {
                guard let self = self else { return }
                self.pendingControl -= 1
                if let error = error { self.finish(error) }
            }
        }
    }
    private func receive() {
        guard state != .closed else { return }
        socket?.receive { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard self.state != .closed else { return }
                do {
                    switch try result.get() {
                    case .string(let text): try self.text(text)
                    case .data(let data):
                        if data.first == 123 || self.state == .waiting || self.state == .protocolSelection {
                            guard let text = String(data: data, encoding: .utf8) else { throw AgentError.protocolViolation }
                            try self.text(text)
                        } else { try self.command(data) }
                    @unknown default: throw AgentError.protocolViolation
                    }
                    self.receive()
                } catch { self.finish(error) }
            }
        }
    }
    private func text(_ text: String) throws {
        guard text.utf8.count <= 16384 else { throw AgentError.protocolViolation }
        if state == .waiting {
            guard text == "c" || text == "cr" else { throw AgentError.protocolViolation }
            recording = text == "cr"; state = .protocolSelection; return
        }
        if text.first == "{" {
            guard let data = text.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else { throw AgentError.protocolViolation }
            if type == "iosAssist" {
                guard authorizedSharing() else { return }
                if screenSource == nil, object["action"] as? String == "captureRequest" { return }
                try assistance.receive(object, capture: latestJPEG); return
            }
            if type == "options" { return } // Never treat remote options as consent.
            let channel = object["ctrlChannel"]
            guard channel as? String == "102938" || channel as? Int == 102938 else { return }
            if type == "close" { finish(nil) }
            else if type == "ping" { sendControl(#"{"ctrlChannel":"102938","type":"pong"}"#) }
            else if type == "rtt", let time = object["time"] as? NSNumber {
                if let data = try? JSONSerialization.data(withJSONObject: ["ctrlChannel": "102938", "type": "rtt", "time": time]),
                   let response = String(data: data, encoding: .utf8) { sendControl(response) }
            }
            return // No WebRTC, clipboard or remote input path.
        }
        guard state == .protocolSelection, text == "2" else { throw AgentError.protocolViolation }
        state = .consent; expire(after: 60)
        sendConsole("En attente de l’autorisation sur l’appareil iOS (lecture seule).")
        let prompt = DesktopPrompt(id: promptID, operatorName: request.operatorName, userID: request.userID, recording: recording)
        DispatchQueue.main.async { self.requested(self, prompt) }
    }
    private func command(_ data: Data) throws {
        guard data.count >= 4, data.count <= 16384 else { throw AgentError.protocolViolation }
        let bytes = [UInt8](data)
        let length = Int(bytes[2]) * 256 + Int(bytes[3])
        guard length == bytes.count else { throw AgentError.protocolViolation }
        if bytes[0] == 0 && bytes[1] == 8 && length == 5 { paused = bytes[4] != 0 }
        // All keyboard/mouse/touch, clipboard and display-control input is discarded.
        // Quality requests cannot raise the native capture rate or dimensions.
    }
    private func expire(after seconds: Double) {
        deadline?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.finish(AgentError.timeout) }
        deadline = timeout; queue.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }
    private func finish(_ error: Error?) {
        guard state != .closed else { return }
        state = .closed; terminalError = error
        let completion = maskCompletion
        maskCompletion = nil; screenSource = nil; completion?(false)
        networkMonitor.cancel()
        latestJPEG = nil; assistance.clear(); metricsTimer?.cancel(); metricsTimer = nil
        metrics.stage = "closed"
        metrics.lastError = ConnectionDiagnostics.errorCode(error)
        let metrics = metrics, diagnostic = diagnosticsCallback
        DispatchQueue.main.async { diagnostic?(metrics) }
        deadline?.cancel(); sendDeadline?.cancel(); pingDeadline?.cancel(); pingTimer?.cancel()
        deadline = nil; sendDeadline = nil; pingDeadline = nil; pingTimer = nil
        if let gate = gate { mc_share_free(gate); self.gate = nil }
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        finished()
        let callback = endCallback
        DispatchQueue.main.async { callback?(error) }
    }
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        validateTrust(session, challenge, completionHandler)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        validateTrust(session, challenge, completionHandler)
    }
    private func validateTrust(_ session: URLSession, _ challenge: URLAuthenticationChallenge,
                               _ completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard self.session === session, state != .closed, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == request.url.host?.lowercased(),
              challenge.protectionSpace.port == (request.url.port ?? 443),
              let trust = challenge.protectionSpace.serverTrust, let host = request.url.host,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        if let data = privateCA {
            guard let ca = SecCertificateCreateWithData(nil, data as CFData),
                  SecTrustSetAnchorCertificates(trust, [ca] as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else {
                completionHandler(.cancelAuthenticationChallenge, nil); return
            }
        }
        guard SecTrustEvaluateWithError(trust, nil), let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first, Data(SHA384.hash(data: SecCertificateCopyData(leaf) as Data)) == request.tlsHash else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        trustValidated = true
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(AgentError.configuration)
    }
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol negotiatedProtocol: String?) {
        guard self.session === session, state != .closed, trustValidated else { finish(AgentError.cryptography); return }
        let sampler = DispatchSource.makeTimerSource(queue: queue)
        sampler.schedule(deadline: .now() + 1, repeating: 1)
        sampler.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.assistance.tick()
            let now = ProcessInfo.processInfo.systemUptime, elapsed = max(0.1, now - self.lastMetrics)
            self.metrics.fps = Double(self.metrics.frames - self.previousFrames) / elapsed
            self.metrics.kilobitsPerSecond = Double(self.metrics.bytes - self.previousBytes) * 8 / elapsed / 1000
            self.previousFrames = self.metrics.frames; self.previousBytes = self.metrics.bytes; self.lastMetrics = now
            self.metrics.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            self.metrics.thermalState = UInt32(ProcessInfo.processInfo.thermalState.rawValue)
            self.metrics.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            self.metrics.featureVersion = "console-1"
            if self.state == .sharing {
                self.metrics.assess(frameAge: self.screenSource == nil ? 0 : now - max(self.lastSent, self.sharingSince))
                self.metrics.remainingSeconds = BroadcastTiming.remaining(phase: 1, since: self.broadcastStartedAt ?? self.sharingSince, now: now)
            }
            let value = self.metrics, callback = self.diagnosticsCallback
            DispatchQueue.main.async { callback?(value) }
            if self.state == .sharing,
               let data = try? JSONSerialization.data(withJSONObject: ["type": "iosAssist", "ctrlChannel": "102938", "v": 1, "action": "diagnostics",
                    "fps": value.fps, "kilobitsPerSecond": value.kilobitsPerSecond,
                    "roundTripMS": value.roundTripMS, "qualityLevel": value.qualityLevel, "sendMS": value.sendMS,
                    "networkState": value.networkState ?? "unknown", "networkInterface": value.networkInterface ?? "unknown",
                    "constrained": value.constrained ?? false, "expensive": value.expensive ?? false,
                    "lowPower": value.lowPower ?? false, "thermalState": value.thermalState ?? 0,
                    "frameAgeMS": value.frameAgeMS ?? 0, "healthCode": value.healthCode ?? 0,
                    "remainingSeconds": value.remainingSeconds ?? 0]),
               let text = String(data: data, encoding: .utf8) { self.sendControl(text) }
        }
        metricsTimer = sampler; sampler.resume()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.state != .closed, self.pingDeadline == nil else { return }
            let timeout = DispatchWorkItem { [weak self] in self?.finish(AgentError.timeout) }
            self.pingDeadline = timeout; self.queue.asyncAfter(deadline: .now() + 10, execute: timeout)
            let started = ProcessInfo.processInfo.systemUptime
            self.socket?.sendPing { [weak self] error in
                self?.queue.async {
                    self?.pingDeadline?.cancel(); self?.pingDeadline = nil
                    self?.metrics.roundTripMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
                    if let error = error { self?.finish(error) }
                }
            }
        }
        pingTimer = timer; timer.resume()
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(error ?? AgentError.closed) }
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { finish(nil) }
}
