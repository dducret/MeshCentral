// SPDX-License-Identifier: Apache-2.0
import Foundation
import ReplayKit
import ImageIO
import CoreMedia

/// ReplayKit owns capture. Main queue owns control/UI-mailbox state; media is bounded.
final class SampleHandler: RPBroadcastSampleHandler {
    private var grant: BroadcastGrant?
    private var connection: MeshCentralConnection?
    private var relay: DesktopRelay?
    private var status: BroadcastStatus?
    private var timer: Timer?
    private var stopped = false
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private let mediaLock = NSLock()
    private var pump: ScreenFramePump?
    private var lastCommand: UUID?
    private var lastScreenRequest: UUID?
    private var quickApprovalAvailable = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        DispatchQueue.main.async { self.start() }
    }
    private func start() {
        do {
            guard !stopped else { return }
            let grant = try BroadcastChannel.takeGrant(); self.grant = grant
            quickApprovalAvailable = grant.approveFirstTechnician == true
            let enrollment = try grant.enrollment.validated()
            startedAt = ProcessInfo.processInfo.systemUptime
            status = BroadcastStatus(id: grant.id, updated: Date(), stage: "connecting", prompt: nil, message: nil,
                                     startedUptime: startedAt, updatedUptime: startedAt)
            try publish()
            do { try AssistanceMailbox.validateAccess() }
            catch {
                end((error as? AssistanceMailboxError)?.localizedDescription ??
                    "Impossible d’accéder au conteneur App Group dans l’extension de diffusion.")
                return
            }
            let tag = BroadcastChannel.identityTag(enrollment)
            let group = BroadcastChannel.accessGroup
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try KeychainIdentity(applicationTag: tag, accessGroup: group) }
                DispatchQueue.main.async {
                    guard self.checkAuthorization() else { return }
                    do {
                        let identity = try result.get()
                        let connection = MeshCentralConnection(enrollment: enrollment, identity: identity,
                            onAuthenticated: { [weak self] in
                                guard let self = self, self.checkAuthorization() else { return }
                                self.status?.stage = "ready"; self.safePublish()
                            }, onEnded: { [weak self] error in
                                var diagnostic = ConnectionDiagnostics()
                                diagnostic.lastError = ConnectionDiagnostics.errorCode(error)
                                self?.end(error == nil ? "Connexion MeshCentral interrompue." : diagnostic.errorLabel)
                            },
                            onDesktopRequest: { [weak self] relay, prompt in self?.request(relay, prompt: prompt) }, broadcastOwner: true,
                            onMessengerRequest: { [weak self] invitation in
                                guard let self = self, self.checkAuthorization() else { return }
                                self.status?.messengerRejection = nil
                                self.status?.messenger = invitation; self.safePublish()
                            }, onMessengerRejected: { [weak self] rejection in
                                guard let self = self, self.checkAuthorization() else { return }
                                self.status?.messengerRejection = rejection; self.safePublish()
                            })
                        self.connection = connection; connection.start()
                    } catch { self.end("Impossible de charger l’identité sécurisée. Vérifiez la signature et le groupe du trousseau.") }
                }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        } catch { end("Préparez une nouvelle diffusion depuis l’application MeshCentral avant de démarrer ReplayKit.") }
    }
    private func request(_ relay: DesktopRelay, prompt: DesktopPrompt) {
        guard checkAuthorization(), self.relay == nil else { relay.stop(); return }
        self.relay = relay
        relay.setBroadcastStart(startedAt)
        relay.setAssistanceHandlers(onChange: { [weak self] value in
            guard let self = self, !self.stopped, let id = self.grant?.id else { return }
            do { try AssistanceMailbox.publish(value, session: id) }
            catch { self.end("Le conteneur partagé est inaccessible. Vérifiez App Groups et déverrouillez l’iPhone.") }
        }, onDiagnostics: { [weak self] value in
            guard let self = self, !self.stopped, let id = self.grant?.id else { return }
            try? AssistanceMailbox.diagnostics(value, session: id)
        })
        status?.stage = "consent"; status?.prompt = prompt; safePublish()
        relay.setHandlers(onCapture: { [weak self, weak relay] in
            guard let self = self, let relay = relay, self.checkAuthorization(), self.relay === relay else { return }
            // ReplayKit's system broadcast UI was accepted before broadcastStarted.
            let pump = ScreenFramePump(relay: relay)
            self.setPump(pump)
            self.status?.stage = "sharing"; self.safePublish()
            if !self.stopped { relay.captureStarted(source: pump.id) }
        }, onEnded: { [weak self] _ in self?.end("La session de visualisation est terminée.") })
        // This callback occurs only after ReplayKit's system start and the
        // authenticated, rights-checked desktop request. No network flag grants consent.
        if quickApprovalAvailable {
            quickApprovalAvailable = false
            do {
                if let decision = try BroadcastChannel.decision(), decision.id == grant?.id, decision.action == "stop" {
                    end("Diffusion arrêtée sur l’appareil."); return
                }
                guard checkAuthorization() else { return }
                status?.stage = "starting"; safePublish()
                if !stopped { relay.approve() }
            } catch { end("Impossible de vérifier l’autorisation locale de diffusion.") }
        }
    }
    private func poll() {
        guard checkAuthorization(), let grant = grant else { return }
        do {
            guard BroadcastTiming.policy(phase: 1, since: startedAt) == 0 else { end("La diffusion a atteint sa limite de dix minutes. Relancez une nouvelle assistance si nécessaire."); return }
            if let invitation = status?.messenger,
               BroadcastTiming.policy(phase: 0, since: invitation.createdUptime) != 0 { status?.messenger = nil }
            if let decision = try BroadcastChannel.decision(), decision.id == grant.id {
                if decision.action == "stop" { end("Diffusion arrêtée sur l’appareil."); return }
                if status?.stage == "consent", decision.request == status?.prompt?.id {
                    if decision.action == "approve" { status?.stage = "starting"; relay?.approve() }
                    else if decision.action == "reject" { end("La demande de visualisation a été refusée."); return }
                }
            }
            if status?.stage == "sharing", let request = try BroadcastChannel.screenVisibilityRequest(owner: grant.id),
               request.id != lastScreenRequest, let relay = relay {
                applyScreenVisibility(request, relay: relay)
            }
            if status?.stage == "sharing", let command = try AssistanceMailbox.command(session: grant.id),
               command.id != lastCommand {
                lastCommand = command.id; relay?.assistanceCommand(command)
            }
            try publish()
        } catch { end("Le trousseau partagé n’est plus accessible. La diffusion est arrêtée.") }
    }
    private func setPump(_ newPump: ScreenFramePump?) {
        mediaLock.lock(); defer { mediaLock.unlock() }
        pump?.stop(); pump = newPump
    }
    private func applyScreenVisibility(_ request: ScreenVisibilityRequest, relay: DesktopRelay) {
        lastScreenRequest = request.id
        guard BroadcastTiming.policy(phase: 2, since: request.createdUptime) == 0 else {
            end("La commande d’écran a expiré. Une nouvelle assistance est nécessaire."); return
        }
        let newPump = request.hidden ? nil : ScreenFramePump(relay: relay)
        setPump(nil)
        relay.setScreenSource(newPump?.id) { [weak self, weak relay] success in
            guard let self, let relay, self.relay === relay, self.checkAuthorization(),
                  self.lastScreenRequest == request.id else { return }
            guard success else { self.end("Impossible de confirmer l’état du partage d’écran."); return }
            self.setPump(newPump)
            self.status?.screenVisibility = request
            self.safePublish()
        }
    }
    private func publish() throws {
        guard var status = status else { return }
        status.updated = Date(); status.updatedUptime = ProcessInfo.processInfo.systemUptime; self.status = status
        try BroadcastChannel.publish(status)
    }
    private func safePublish() { do { try publish() } catch { end("Impossible de communiquer avec l’application.") } }
    private func checkAuthorization() -> Bool {
        guard !stopped, let id = grant?.id else { return false }
        do {
            guard try BroadcastChannel.isAuthorized(id) else {
                end("Autorisation révoquée. Une nouvelle assistance nécessite votre accord."); return false
            }
            return true
        } catch { end("Autorisation locale inaccessible. Déverrouillez l’appareil avant de relancer."); return false }
    }
    private func end(_ message: String, tellSystem: Bool = true) {
        guard !stopped else { return }
        stopped = true
        quickApprovalAvailable = false
        setPump(nil)
        timer?.invalidate(); timer = nil
        relay?.stop(); relay = nil
        connection?.stop(); connection = nil
        // Only the containing app writes the owner fence. Extension teardown
        // removes its own content slots, never a later broadcast's files.
        if let id = grant?.id { try? AssistanceMailbox.clear(session: id) }
        status?.stage = "stopped"; status?.prompt = nil; status?.messenger = nil; status?.messengerRejection = nil
        status?.screenVisibility = nil; status?.message = message
        try? publish()
        if tellSystem {
            finishBroadcastWithError(NSError(domain: "MeshCentral.Broadcast", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return } // Never transmit microphone/app audio.
        mediaLock.lock(); let current = pump; mediaLock.unlock()
        guard let current = current else { return }
        let number = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber
        let orientation = CGImagePropertyOrientation(rawValue: number?.uint32Value ?? 1) ?? .up
        current.submit(sample: sampleBuffer, orientation: orientation)
    }
    override func broadcastPaused() { DispatchQueue.main.async { self.end("La capture a été interrompue. Redémarrez une diffusion pour reprendre.") } }
    override func broadcastResumed() { DispatchQueue.main.async { self.end("Une nouvelle autorisation est nécessaire.") } }
    override func broadcastFinished() { DispatchQueue.main.async { self.end("Diffusion terminée.", tellSystem: false) } }
}
