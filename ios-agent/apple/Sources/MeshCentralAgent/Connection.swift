// SPDX-License-Identifier: Apache-2.0
import Foundation
import Security
import CryptoKit
import CMeshCore

public struct Enrollment {
    public let endpoint: URL
    public let serverID: Data
    public let meshID: Data
    public let architectureID: UInt32
    public let deviceName: String
    public let privateCA: Data?

    /// Values must come from a trusted enrollment channel, never the same
    /// unauthenticated connection whose server identity is being verified.
    public init(endpoint: URL, serverID: Data, meshID: Data, architectureID: UInt32,
                deviceName: String, privateCA: Data? = nil) throws {
        guard let parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              parts.scheme == "wss", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !parts.percentEncodedPath.contains("%"), serverID.count == 48, meshID.count == 48,
              serverID.contains(where: { $0 != 0 }), meshID.suffix(16).contains(where: { $0 != 0 }),
              !deviceName.isEmpty, deviceName.utf8.count <= 255,
              deviceName.rangeOfCharacter(from: .controlCharacters) == nil,
              architectureID != 0, (1...65535).contains(parts.port ?? 443) else { throw AgentError.configuration }
        let segments = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 2 || segments.count == 3, segments.first == "",
              segments.last == "agent.ashx" else { throw AgentError.configuration }
        if segments.count == 3 {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
            guard !segments[1].isEmpty, segments[1].unicodeScalars.allSatisfy(allowed.contains) else { throw AgentError.configuration }
        }
        if let ca = privateCA, SecCertificateCreateWithData(nil, ca as CFData) == nil { throw AgentError.configuration }
        self.endpoint = endpoint; self.serverID = serverID; self.meshID = meshID
        self.architectureID = architectureID; self.deviceName = deviceName; self.privateCA = privateCA
    }
}

/// One foreground control connection. Create a new object for reconnection.
/// All native/Rust state is confined to one serial queue; callbacks reach the UI
/// on the main queue. Desktop capability requires an explicitly attached host.
public final class MeshCentralConnection: NSObject, URLSessionWebSocketDelegate {
    private enum State { case idle, authenticating, connected, closed }
    private let enrollment: Enrollment
    private let identity: KeychainIdentity
    private let queue = DispatchQueue(label: "MeshCentral.control")
    private let authenticated: () -> Void
    private let ended: (Error?) -> Void
    private var state = State.idle
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var handle: UnsafeMutableRawPointer?
    private var tlsHash: Data?
    private var deadline: DispatchWorkItem?
    private var heartbeat: DispatchSourceTimer?
    private var pingDeadline: DispatchWorkItem?
    private let desktopRequested: ((DesktopRelay, DesktopPrompt) -> Void)?
    private var desktop: DesktopRelay?
    private let broadcastOwner: Bool
    private let messengerRequested: ((MessengerInvitation) -> Void)?
    private let messengerRejected: ((MessengerRejection) -> Void)?
    private var lastMessengerRequest = -Double.infinity
    private var inventoryGate: UnsafeMutableRawPointer?

    public init(enrollment: Enrollment, identity: KeychainIdentity,
                onAuthenticated: @escaping () -> Void, onEnded: @escaping (Error?) -> Void,
                onDesktopRequest: ((DesktopRelay, DesktopPrompt) -> Void)? = nil,
                broadcastOwner: Bool = false,
                onMessengerRequest: ((MessengerInvitation) -> Void)? = nil,
                onMessengerRejected: ((MessengerRejection) -> Void)? = nil) {
        self.enrollment = enrollment; self.identity = identity
        self.authenticated = onAuthenticated; self.ended = onEnded
        self.desktopRequested = onDesktopRequest
        self.broadcastOwner = broadcastOwner
        self.messengerRequested = onMessengerRequest
        self.messengerRejected = onMessengerRejected
        super.init()
    }

    public func start() {
        queue.async {
            guard self.state == .idle else { return }
            self.state = .authenticating
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
            config.timeoutIntervalForRequest = 20
            config.waitsForConnectivity = false
            let delegates = OperationQueue()
            delegates.maxConcurrentOperationCount = 1
            delegates.underlyingQueue = self.queue
            let session = URLSession(configuration: config, delegate: self, delegateQueue: delegates)
            self.session = session
            let task = session.webSocketTask(with: self.enrollment.endpoint)
            task.maximumMessageSize = 8580
            self.socket = task
            let timeout = DispatchWorkItem { [weak self] in self?.finish(AgentError.timeout) }
            self.deadline = timeout
            self.queue.asyncAfter(deadline: .now() + 20, execute: timeout)
            task.resume()
        }
    }

    public func stop() { queue.async { self.finish(nil) } }

    private func finish(_ error: Error?) {
        guard state != .closed else { return }
        state = .closed
        if let gate = inventoryGate { mc_inventory_free(gate); inventoryGate = nil }
        desktop?.stop(); desktop = nil
        deadline?.cancel(); deadline = nil
        heartbeat?.cancel(); heartbeat = nil
        pingDeadline?.cancel(); pingDeadline = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        if let handle = handle { mc_free(handle); self.handle = nil }
        DispatchQueue.main.async { self.ended(error) }
    }

    // TLS chain AND hostname validation remain mandatory, even with a serverID pin.
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        validateTrust(session, challenge, completionHandler)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        validateTrust(session, challenge, completionHandler)
    }

    private func validateTrust(_ session: URLSession, _ challenge: URLAuthenticationChallenge,
                               _ complete: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard self.session === session, state != .closed,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == enrollment.endpoint.host?.lowercased(),
              challenge.protectionSpace.port == (enrollment.endpoint.port ?? 443),
              let trust = challenge.protectionSpace.serverTrust,
              let host = enrollment.endpoint.host else { complete(.cancelAuthenticationChallenge, nil); return }
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
            complete(.cancelAuthenticationChallenge, nil); return
        }
        if let data = enrollment.privateCA {
            guard let root = SecCertificateCreateWithData(nil, data as CFData),
                  SecTrustSetAnchorCertificates(trust, [root] as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else {
                complete(.cancelAuthenticationChallenge, nil); return
            }
        }
        guard SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            complete(.cancelAuthenticationChallenge, nil); return
        }
        let hash = Data(SHA384.hash(data: SecCertificateCopyData(leaf) as Data))
        guard tlsHash == nil || tlsHash == hash else { complete(.cancelAuthenticationChallenge, nil); return }
        tlsHash = hash
        complete(.useCredential, URLCredential(trust: trust))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(AgentError.configuration)
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol negotiatedProtocol: String?) {
        guard state == .authenticating, self.socket === webSocketTask, let tlsHash = tlsHash else {
            finish(AgentError.protocolViolation); return
        }
        do {
            let tls = [UInt8](tlsHash), pin = [UInt8](enrollment.serverID)
            let nonce = [UInt8](try secureRandom(48)), cert = [UInt8](identity.certificateDER)
            guard let handle = mc_new(tls, pin, nonce, cert, cert.count, identity.callbacks()) else {
                throw AgentError.protocolViolation
            }
            self.handle = handle
            var hello = [UInt8](repeating: 0, count: 98)
            let count = mc_hello(handle, &hello, 98)
            guard count == 98 else { throw AgentError.protocolViolation }
            send(Data(hello)) { self.receive() }
        } catch { finish(error) }
    }

    private func send(_ data: Data, then: @escaping () -> Void) {
        guard state != .closed, let socket = socket else { return }
        socket.send(.data(data)) { [weak self] error in
            guard let self = self else { return }
            self.queue.async {
                guard self.state != .closed else { return }
                if let error = error { self.finish(error) } else { then() }
            }
        }
    }

    private func receive() {
        guard state != .closed, let socket = socket else { return }
        socket.receive { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard self.state != .closed else { return }
                do {
                    let data: Data
                    switch try result.get() {
                    case .data(let bytes): data = bytes
                    case .string(let string):
                        guard self.state == .connected else { throw AgentError.protocolViolation }
                        data = Data(string.utf8)
                    @unknown default: throw AgentError.protocolViolation
                    }
                    if self.state == .authenticating { try self.handleHandshake(data) }
                    else { try self.handleControl(data) }
                } catch { self.finish(error) }
            }
        }
    }

    private func handleHandshake(_ data: Data) throws {
        guard data.count <= 8580, let handle = handle else { throw AgentError.protocolViolation }
        let bytes = [UInt8](data)
        switch mc_receive(handle, bytes, bytes.count) {
        case 1: receive()
        case 2:
            var registration = MCRegistration()
            registration.architecture_id = enrollment.architectureID
            registration.agent_version = 4
            registration.platform_type = 1 // Generic icon, not an assigned iOS architecture.
            _ = withUnsafeMutableBytes(of: &registration.mesh_id) { destination in
                enrollment.meshID.copyBytes(to: destination)
            }
            var proof = [UInt8](repeating: 0, count: 8580)
            var info = [UInt8](repeating: 0, count: 327)
            var lengths = MCLengths()
            let name = [UInt8](enrollment.deviceName.utf8)
            let status = name.withUnsafeBufferPointer { buffer -> Int32 in
                registration.name = buffer.baseAddress; registration.name_len = buffer.count
                return mc_register(handle, &registration, &proof, 8580, &info, 327, &lengths)
            }
            guard status == 0 else { throw AgentError.protocolViolation }
            send(Data(proof.prefix(lengths.identity))) {
                self.send(Data(info.prefix(lengths.info))) { self.receive() }
            }
        case 3:
            state = .connected
            inventoryGate = mc_inventory_new()
            deadline?.cancel(); deadline = nil
            socket?.maximumMessageSize = 65536
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 60, repeating: 60)
            timer.setEventHandler { [weak self] in self?.ping() }
            heartbeat = timer; timer.resume()
            sendCoreInfo()
        default: throw AgentError.protocolViolation
        }
    }

    private func handleControl(_ data: Data) throws {
        guard data.count <= 65536 else { throw AgentError.protocolViolation }
        if data.first == 0x7b {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = json["action"] as? String else { throw AgentError.protocolViolation }
            if action == "ping" {
                send(Data(#"{"action":"pong"}"#.utf8)) { self.receive() }; return
            }
            if action == "sysinfo" || (action == "msg" && json["type"] as? String == "sysinfo") {
                requestInventory(json, fromOperator: action == "msg")
            }
            if MessengerInvitation.isCommand(json), let requested = messengerRequested, let tls = tlsHash,
               ProcessInfo.processInfo.systemUptime - lastMessengerRequest >= 5 {
                lastMessengerRequest = ProcessInfo.processInfo.systemUptime
                do {
                    let invitation = try MessengerInvitation.parse(json, enrollment: enrollment, controlTLS: tls, nodeKey: identity.nodeKey)
                    DispatchQueue.main.async { requested(invitation) }
                } catch {
                    let rejection = MessengerRejection(error as? MessengerInvitationError ?? .command)
                    DispatchQueue.main.async { self.messengerRejected?(rejection) }
                }
            }
            if action == "msg", json["type"] as? String == "tunnel", desktop == nil,
               let requested = desktopRequested, let tls = tlsHash, let handle = handle,
               let request = try? DesktopRequest.parse(json, enrollment: enrollment, controlTLS: tls),
               let gate = mc_share_new(handle, request.rights) {
                let relay = DesktopRelay(request: request, privateCA: enrollment.privateCA, gate: gate,
                    requested: requested, finished: { [weak self] in self?.queue.async { self?.desktop = nil } })
                desktop = relay; relay.start()
            }
            if action == "msg", json["type"] as? String == "endtunnel" { desktop?.stop() }
            receive(); return
        }
        // This agent registered without a JavaScript core. The clear request is
        // already satisfied; sending an empty core hash would clear native
        // capabilities in MeshCentral's node record, possibly after coreinfo.
        if data == Data([0, 10, 0, 0]) {
            receive(); return
        }
        throw AgentError.protocolViolation
    }

    private func sendCoreInfo() {
        let role = broadcastOwner ? "broadcast-ready" : "app-connected"
        let info: [String: Any] = ["action": "coreinfo", "value": "MeshCentral iOS Rust 0.5.2 [" + role + "] console-1",
                                   "caps": desktopRequested == nil ? 0 : 1,
                                   "osdesc": "iOS / iPadOS " + ProcessInfo.processInfo.operatingSystemVersionString]
        guard let bytes = try? JSONSerialization.data(withJSONObject: info) else { finish(AgentError.configuration); return }
        send(bytes) {
            DispatchQueue.main.async { self.authenticated() }
            self.send(Data(#"{"action":"sysinfocheck"}"#.utf8)) { self.receive() }
        }
    }

    private func requestInventory(_ json: [String: Any], fromOperator: Bool) {
        guard state == .connected, let gate = inventoryGate else { return }
        let rights: UInt32
        if fromOperator {
            guard let value = json["rights"] as? UInt32 else { return }
            rights = value
        } else { rights = 0 }
        var previousHash: String?
        if !fromOperator, let value = json["hash"] {
            guard let hash = value as? String, hash.utf8.count == 96,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return }
            previousHash = hash
        }
        let now = DispatchTime.now().uptimeNanoseconds / 1_000_000
        guard mc_inventory_begin(gate, now, rights, fromOperator ? 1 : 0) == 1 else { return }
        let expectedHash = previousHash
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let inventory = HardwareInventory.collect()
            self.queue.async {
                // A closed connection cannot be restarted; late main-queue work is discarded.
                guard self.state == .connected, let gate = self.inventoryGate else { return }
                guard let message = inventory?.message(ifDifferentFrom: expectedHash) else {
                    mc_inventory_complete(gate); return
                }
                self.send(message) {
                    if let gate = self.inventoryGate { mc_inventory_complete(gate) }
                }
            }
        }
    }

    private func ping() {
        guard state == .connected, pingDeadline == nil else { return }
        let timeout = DispatchWorkItem { [weak self] in self?.finish(AgentError.timeout) }
        pingDeadline = timeout
        queue.asyncAfter(deadline: .now() + 15, execute: timeout)
        socket?.sendPing { [weak self] error in
            guard let self = self else { return }
            self.queue.async {
                self.pingDeadline?.cancel(); self.pingDeadline = nil
                if let error = error { self.finish(error) }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error ?? AgentError.closed)
    }
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish(AgentError.closed)
    }
}
