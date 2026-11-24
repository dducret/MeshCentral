// SPDX-License-Identifier: Apache-2.0
import Foundation
import Combine
import CryptoKit
import UIKit
import Security

@MainActor
final class AgentModel: ObservableObject {
    @Published var input = ""
    @Published var deviceName = UIDevice.current.name
    @Published var endpoint = ""
    @Published var serverID = ""
    @Published var meshID = ""
    @Published private(set) var privateCA: Data?
    @Published private(set) var profile: SavedEnrollment?
    @Published private(set) var candidate: SavedEnrollment?
    @Published private(set) var busy = false
    @Published private(set) var status = "Déconnecté"
    @Published private(set) var connecting = false
    @Published private(set) var connected = false
    @Published var error: String?
    @Published private(set) var desktopPrompt: DesktopPrompt?
    @Published private(set) var sharing = false
    @Published private(set) var screenHidden = false
    @Published private(set) var pendingScreenVisibility: ScreenVisibilityRequest?
    @Published private(set) var broadcastID: UUID?
    @Published private(set) var broadcastStage = ""
    private var desktop: DesktopRelay?
    private let simulatorCapture = SimulatorCapture()
    private var broadcastTimer: Timer?
    private var broadcastPreparedAt = ProcessInfo.processInfo.systemUptime
    private var broadcastStartedAt: Double?
    private var stoppingAt: Double?
    private var foregroundActive = true
    private var contentEpoch = UUID()
    private var documentOperation: UUID?
    private var commandSentAt: Double?
    @Published private(set) var preparationRemaining = 120
    @Published private(set) var sessionRemaining: Int?
    @Published private(set) var sessionNotice = ""
    @Published private(set) var hasEndedAssistance = false
    @Published private(set) var finishRevision = UUID()
    @Published private(set) var activityNotice = ""
    @Published private(set) var stopUnconfirmed = false
    private var lastRemoteMessage: UUID?
    private var lastGuideStep = ""
    private var lastOffer: String?
    private var captureWasRequested = false
    private var connection: MeshCentralConnection?
    private var generation = UUID()
    private var importGeneration = UUID()
    @Published private(set) var assistance = AssistanceSnapshot()
    @Published private(set) var diagnostics = ConnectionDiagnostics()
    @Published var chatDraft = ""
    @Published private(set) var documentBusy = false
    @Published private(set) var messengerInvitation: MessengerInvitation?
    @Published private(set) var messengerHost: MessengerWebHost?
    @Published private(set) var messengerNotice = ""
    @Published private(set) var messengerFailure: MessengerRejection?
    @Published private(set) var messengerPageError: String?
    private var messengerConsent: MessengerConsent?
    private var messengerTimer: Timer?
    private var lastMessengerID: UUID?
    private var lastMessengerFailureID: UUID?
    private var commands: [AssistanceCommand] = []
    private var commandSent: UUID?

    private var messengerConnected: Bool {
        stoppingAt == nil && (connected || (broadcastID != nil && ["ready", "consent", "starting", "sharing"].contains(broadcastStage)))
    }
    private func receiveMessenger(_ invitation: MessengerInvitation) {
        guard invitation.id != lastMessengerID else { return }
        guard messengerInvitation == nil, messengerHost == nil, foregroundActive, messengerConnected else { return }
        lastMessengerID = invitation.id
        let consent = MessengerConsent(invitation)
        guard consent.event(connected: true, foreground: true) == 0 else { return }
        messengerConsent = consent; messengerInvitation = invitation
        messengerFailure = nil
        messengerPageError = nil
        messengerNotice = "Invitation à une conversation avec \(invitation.operatorName)."
        messengerTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollMessenger() }
        }
        messengerTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func receiveMessengerRejection(_ rejection: MessengerRejection) {
        guard rejection.id != lastMessengerFailureID, foregroundActive, messengerConnected,
              messengerInvitation == nil, messengerHost == nil else { return }
        lastMessengerFailureID = rejection.id
        messengerFailure = rejection; messengerNotice = rejection.reason.message
    }
    func dismissMessengerFailure() { messengerFailure = nil }
    func dismissMessengerPageError() { messengerPageError = nil }
    private func pollMessenger() {
        guard let consent = messengerConsent else { return }
        if !foregroundActive {
            if let host = messengerHost, host.canKeepMessengerRelayInBackground {
                let interrupted = !host.canContinueAudioInBackground
                if consent.pollBackgroundAudio(connected: backgroundMessengerConnected, interrupted: interrupted) == 1 {
                    if interrupted { host.pauseInterruptedAudio() }
                    return
                }
            }
            endBackgroundMessenger("L’appel a été interrompu. Revenez dans l’app et demandez une nouvelle invitation Chat.")
            return
        }
        // Refresh the extension's authorization/heartbeat before allowing WebKit to continue.
        if broadcastID != nil { pollBroadcast() }
        guard messengerConsent === consent else { return }
        if consent.event(connected: messengerConnected, foreground: foregroundActive) == 2 {
            closeMessenger("Conversation terminée ou invitation expirée. Demandez une nouvelle invitation Chat.")
        }
    }
    private var backgroundMessengerConnected: Bool {
        guard stoppingAt == nil else { return false }
        guard let id = broadcastID else { return connected && desktop == nil }
        guard let status = try? BroadcastChannel.status(), status.id == id,
              ["ready", "consent", "starting", "sharing"].contains(status.stage),
              let started = status.startedUptime, let heartbeat = status.updatedUptime else { return false }
        return BroadcastTiming.policy(phase: 1, since: started, heartbeat: heartbeat) == 0
    }
    func resumeMessengerAudio(_ host: MessengerWebHost) {
        host.resumeAudio { [weak self, weak host] in
            guard let self, let host, self.messengerHost === host, self.foregroundActive,
                  let consent = self.messengerConsent else { return false }
            return consent.event(connected: self.backgroundMessengerConnected, foreground: true) == 1
        }
    }
    func acceptMessenger(startWithMicrophone: Bool, backgroundAudio: Bool = false) {
        if broadcastID != nil { pollBroadcast() }
        guard let invitation = messengerInvitation, let consent = messengerConsent,
              let profile = profile, messengerHost == nil else { return }
        guard let purpose = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String, !purpose.isEmpty else {
            error = "L’autorisation microphone manque dans la configuration de l’app. Appliquez le complément Messenger au projet Xcode."; return
        }
        let keepAudio = startWithMicrophone && backgroundAudio && MessengerWebHost.supportsBackgroundAudio
        guard consent.accept(connected: messengerConnected, foreground: foregroundActive, backgroundAudio: keepAudio) == 1 else {
            closeMessenger("Invitation expirée. Demandez au technicien de cliquer à nouveau sur Chat."); return
        }
        messengerInvitation = nil
        messengerHost = MessengerWebHost(invitation: invitation, privateCA: profile.privateCA,
            startWithMicrophone: startWithMicrophone, backgroundAudio: keepAudio,
            onEnded: { [weak self] message in
                guard let self else { return }
                if self.foregroundActive {
                    self.closeMessenger(message)
                    self.messengerPageError = message
                } else { self.endBackgroundMessenger(message) }
            })
        messengerNotice = "Invitation acceptée. Connexion à la conversation…"
    }
    func closeMessenger(_ message: String = "Conversation fermée. Une nouvelle invitation Chat est nécessaire.") {
        _ = messengerConsent?.event(2, connected: false, foreground: false)
        messengerConsent = nil; messengerTimer?.invalidate(); messengerTimer = nil
        messengerHost?.stop(); messengerHost = nil; messengerInvitation = nil
        messengerFailure = nil
        messengerPageError = nil
        messengerNotice = message
    }

    // The extension owns a separate connection; do not display the closed
    // ordinary app connection as the status of an active broadcast.
    var connectionDisplayStatus: String {
        if sharing {
            if let pendingScreenVisibility {
                return pendingScreenVisibility.hidden ? "Masquage de l’écran en cours…" : "Reprise du partage en cours…"
            }
            return screenHidden ? "Écran masqué" : "Écran partagé — lecture seule"
        }
        guard broadcastID != nil else { return status }
        switch broadcastStage {
        case "prepared": return "Partage préparé — lancez la diffusion iPadOS"
        case "connecting": return "Connexion de la diffusion à MeshCentral…"
        case "ready": return "Connecté à MeshCentral — diffusion prête"
        case "consent": return "Connecté — autorisation de l’assistance attendue"
        case "starting": return "Connecté — démarrage du partage…"
        case "sharing": return "Connecté — écran partagé"
        case "stopping": return "Arrêt de la diffusion…"
        default: return "Vérification de la diffusion…"
        }
    }
    var connectionDisplayActive: Bool {
        if broadcastID != nil { return ["ready", "consent", "starting", "sharing"].contains(broadcastStage) }
        return connected
    }

    func toggleScreenVisibility() {
        guard sharing, foregroundActive, stoppingAt == nil, pendingScreenVisibility == nil else { return }
        let request = ScreenVisibilityRequest(hidden: !screenHidden)
        pendingScreenVisibility = request
        if let id = broadcastID {
            do { try BroadcastChannel.requestScreenVisibility(request, owner: id) }
            catch { stopSharing(reason: "Commande d’écran inaccessible. Arrêt de la diffusion demandé.") }
        } else if let relay = desktop {
            simulatorCapture.stop()
            let pump = request.hidden ? nil : ScreenFramePump(relay: relay)
            relay.setScreenSource(pump?.id) { [weak self, weak relay] success in
                Task { @MainActor in
                    guard let self, let relay, self.desktop === relay, self.pendingScreenVisibility?.id == request.id else { return }
                    guard success else { self.stopSharing(reason: "Impossible de confirmer l’état du partage d’écran."); return }
                    self.simulatorCapture.resume(pump)
                    self.confirmScreenVisibility(request)
                }
            }
        }
    }

    private func confirmScreenVisibility(_ request: ScreenVisibilityRequest) {
        if screenHidden != request.hidden { screenHidden = request.hidden }
        if pendingScreenVisibility?.id == request.id { pendingScreenVisibility = nil }
    }

    private func checkScreenVisibilityDeadline() {
        if let request = pendingScreenVisibility, BroadcastTiming.policy(phase: 2, since: request.createdUptime) != 0 {
            stopSharing(reason: "Commande d’écran non confirmée. Arrêt du partage demandé.")
        }
    }

    func assist(_ command: AssistanceCommand) {
        guard sharing, foregroundActive, stoppingAt == nil else { return }
        if broadcastID != nil {
            guard commands.count < 8 else { error = "Attendez la fin des échanges en cours."; return }
            commands.append(command); flushCommand()
        } else { desktop?.assistanceCommand(command) }
    }
    private func flushCommand() {
        guard sharing, stoppingAt == nil, let id = broadcastID, commandSent == nil, let first = commands.first else { return }
        do { try AssistanceMailbox.command(first, session: id); commandSent = first.id; commandSentAt = ProcessInfo.processInfo.systemUptime }
        catch { self.error = Self.message(error) }
    }
    func sendChat() {
        guard sharing, commands.count < 8, !chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, chatDraft.utf8.count <= 1024 else { return }
        assist(AssistanceCommand(action: "chat", text: chatDraft)); chatDraft = ""
    }
    var documentImportEpoch: UUID { contentEpoch }
    func importDocument(_ url: URL, selectedIn epoch: UUID) {
        guard sharing, foregroundActive, epoch == contentEpoch, !documentBusy else { return }
        documentBusy = true
        let operation = UUID()
        documentOperation = operation
        Task {
            defer { if documentOperation == operation { documentBusy = false; documentOperation = nil } }
            do {
                let result = try await Task.detached(priority: .userInitiated) { () throws -> (String, Data) in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    var coordinationError: NSError?
                    var result: Result<(String, Data), Error> = .failure(AgentError.configuration)
                    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
                        result = Result {
                            let name = source.lastPathComponent
                            guard AssistanceEngine.validName(name) else { throw AgentError.configuration }
                            let resource = try source.resourceValues(forKeys: [.isRegularFileKey])
                            guard resource.isRegularFile == true else { throw AgentError.configuration }
                            let file = try FileHandle(forReadingFrom: source); defer { try? file.close() }
                            let data = try file.read(upToCount: AssistanceEngine.maximum + 1) ?? Data()
                            guard !data.isEmpty, data.count <= AssistanceEngine.maximum else { throw AgentError.configuration }
                            return (name, data)
                        }
                    }
                    if let failure = coordinationError { throw failure }
                    return try result.get()
                }.value
                guard sharing, foregroundActive, contentEpoch == epoch, documentOperation == operation else { return }
                assist(AssistanceCommand(action: "document", data: result.1, name: result.0))
            } catch {
                guard contentEpoch == epoch, documentOperation == operation else { return }
                self.error = "Document illisible, nom invalide ou taille supérieure à 2 Mio."
            }
        }
    }

    init() {
        do { profile = try EnrollmentStore.load() }
        catch { self.error = Self.message(error) }
        #if !targetEnvironment(simulator)
        do {
            if let id = try BroadcastChannel.currentID() {
                if try BroadcastChannel.isComplete(id) {
                    try? AssistanceMailbox.clear()
                } else if let current = try BroadcastChannel.status(), current.id == id, current.stage == "stopped" {
                    try BroadcastChannel.revoke(id); try BroadcastChannel.complete(id); try? AssistanceMailbox.clear()
                } else {
                    broadcastID = id; broadcastStage = "verifying"
                    pendingScreenVisibility = try? BroadcastChannel.screenVisibilityRequest(owner: id)
                    startBroadcastPolling(); pollBroadcast()
                }
            } else { try? AssistanceMailbox.clear() }
        } catch { self.error = Self.message(error) }
        #endif
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    func desktopRequested(_ relay: DesktopRelay, prompt: DesktopPrompt) {
        guard foregroundActive, connected, desktop == nil else { relay.stop(); return }
        desktop = relay; desktopPrompt = prompt
        relay.setAssistanceHandlers(onChange: { [weak self, weak relay] value in
            Task { @MainActor in guard self?.desktop === relay else { return }; self?.updateAssistance(value) }
        }, onDiagnostics: { [weak self, weak relay] value in
            Task { @MainActor in guard self?.desktop === relay else { return }; self?.diagnostics = value }
        })
        relay.setHandlers(onCapture: { [weak self, weak relay] in
            Task { @MainActor in
                guard let self = self, let relay = relay, self.desktop === relay, self.connected else { return }
                self.sharing = true; self.sessionNotice = ""; self.broadcastStartedAt = ProcessInfo.processInfo.systemUptime
                self.startBroadcastPolling(); self.simulatorCapture.start(relay: relay)
            }
        }, onEnded: { [weak self, weak relay] failure in
            Task { @MainActor in
                guard let self = self, self.desktop === relay else { return }
                self.simulatorCapture.stop(); self.desktop = nil; self.desktopPrompt = nil; self.sharing = false
                self.clearSessionContent(); self.diagnostics.stage = "closed"; self.sessionRemaining = nil
                self.broadcastTimer?.invalidate(); self.broadcastTimer = nil; self.hasEndedAssistance = true
                self.sessionNotice = "Session terminée. Une nouvelle assistance nécessite votre accord."
                if let failure = failure { self.error = Self.message(failure) }
            }
        })
    }
    func acceptDesktop() {
        guard stoppingAt == nil, foregroundActive else { return }
        if let id = broadcastID, let prompt = desktopPrompt {
            do { try BroadcastChannel.decide(id: id, request: prompt.id, action: "approve"); broadcastStage = "starting" }
            catch { self.error = Self.message(error) }
        } else { desktop?.approve() }
    }
    private func clearSessionContent() {
        closeMessenger("")
        pendingScreenVisibility = nil; screenHidden = false
        contentEpoch = UUID(); documentOperation = nil; documentBusy = false
        assistance = AssistanceSnapshot(); commands = []; commandSent = nil; commandSentAt = nil; chatDraft = ""
        activityNotice = ""; lastRemoteMessage = nil; lastGuideStep = ""; lastOffer = nil; captureWasRequested = false
    }
    func acknowledgeActivity() { activityNotice = "" }
    private func updateAssistance(_ value: AssistanceSnapshot) {
        guard foregroundActive, sharing, stoppingAt == nil else { return }
        var notices: [String] = []
        if let message = value.messages.last(where: { !$0.local }), message.id != lastRemoteMessage {
            notices.append("Nouveau message du technicien"); lastRemoteMessage = message.id
        }
        let step = value.guide.map { "\($0.id):\($0.step)" } ?? ""
        if !step.isEmpty, step != lastGuideStep { notices.append("Nouvelle étape de guidage") }
        lastGuideStep = step
        if let offer = value.offer, offer.id != lastOffer { notices.append("Document à accepter ou refuser") }
        lastOffer = value.offer?.id
        if value.captureRequested && !captureWasRequested { notices.append("Capture à examiner") }
        captureWasRequested = value.captureRequested
        if !notices.isEmpty { activityNotice = notices.joined(separator: " · ") }
        assistance = value
    }
    func stopSharing(reason: String = "Assistance arrêtée sur cet appareil.") {
        clearSessionContent()
        simulatorCapture.stop(); desktop?.stop(); desktop = nil; desktopPrompt = nil; sharing = false
        sessionNotice = reason; hasEndedAssistance = true; sessionRemaining = nil
        guard let id = broadcastID else {
            diagnostics.stage = "stopped"; broadcastTimer?.invalidate(); broadcastTimer = nil; return
        }
        if stoppingAt == nil { stoppingAt = ProcessInfo.processInfo.systemUptime }
        broadcastStage = "stopping"; diagnostics.stage = "stopping"
        do {
            let pending = try BroadcastChannel.pendingGrant(id)
            try BroadcastChannel.revoke(id)
            // An unconsumed grant cannot start later: the owner is now revoked,
            // and takeGrant/identity/capture callbacks all recheck that owner.
            if pending { completeBroadcast(reason) }
        } catch { self.error = Self.message(error) }
    }
    func finishAssistance() {
        let reason = "Assistance terminée sur cet appareil."
        if broadcastID != nil {
            // The extension owns this connection. Keep polling until iPadOS
            // confirms its stop or the existing recovery control is needed.
            stopSharing(reason: reason)
        } else {
            disconnect()
            hasEndedAssistance = true
            sessionNotice = reason
        }
        finishRevision = UUID()
    }
    func confirmSystemStopped() {
        guard stopUnconfirmed, let id = broadcastID else { return }
        do {
            try BroadcastChannel.revoke(id)
            completeBroadcast("Arrêt système confirmé par vous. Une relance exige une nouvelle préparation et un nouvel accord.")
        } catch { self.error = Self.message(error) }
    }
    private func completeBroadcast(_ reason: String) {
        if let id = broadcastID {
            do { try BroadcastChannel.revoke(id); try BroadcastChannel.complete(id) }
            catch {
                self.error = Self.message(error); broadcastStage = "stopping"
                if stoppingAt == nil { stoppingAt = ProcessInfo.processInfo.systemUptime }
                return
            }
            try? AssistanceMailbox.clear(session: id)
        }
        clearSessionContent()
        broadcastID = nil; desktopPrompt = nil; sharing = false; broadcastStage = ""
        stoppingAt = nil; broadcastStartedAt = nil; sessionRemaining = nil; stopUnconfirmed = false
        broadcastTimer?.invalidate(); broadcastTimer = nil
        diagnostics.stage = "closed"; sessionNotice = reason; hasEndedAssistance = true
    }
    func prepareBroadcast(approveFirstTechnician: Bool = false) {
        guard let profile = profile, broadcastID == nil, foregroundActive else { return }
        error = nil
        do {
            _ = try profile.validated()
            try BroadcastPicker.validateEmbeddedExtension()
            try AssistanceMailbox.validateAccess(); try AssistanceMailbox.clear()
            let id = try BroadcastChannel.prepare(profile, approveFirstTechnician: approveFirstTechnician)
            disconnect()
            broadcastID = id; stoppingAt = nil; broadcastStartedAt = nil; stopUnconfirmed = false
            diagnostics = ConnectionDiagnostics(); diagnostics.stage = "broadcast_prepared"
            broadcastPreparedAt = ProcessInfo.processInfo.systemUptime
            preparationRemaining = 120; broadcastStage = "prepared"; sessionNotice = ""; error = nil
            startBroadcastPolling()
        } catch {
            self.error = Self.message(error); diagnostics.lastError = ConnectionDiagnostics.errorCode(error)
        }
    }
    private func startBroadcastPolling() {
        broadcastTimer?.invalidate()
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollBroadcast() }
        }
        if let timer = broadcastTimer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func pollBroadcast() {
        guard foregroundActive else { return }
        guard let id = broadcastID else {
            if sharing, let start = broadcastStartedAt {
                sessionRemaining = BroadcastTiming.remaining(phase: 1, since: start)
                checkScreenVisibilityDeadline()
            }
            return
        }
        do {
            let current = try BroadcastChannel.status()
            if let current = current, current.id == id, current.stage == "stopped" {
                completeBroadcast(current.message ?? "Diffusion terminée. Une nouvelle autorisation est nécessaire."); return
            }
            if let stop = stoppingAt {
                try BroadcastChannel.revoke(id)
                if BroadcastTiming.policy(phase: 2, since: stop) == 3 {
                    stopUnconfirmed = true
                    sessionNotice = "Arrêt non confirmé. Arrêtez la diffusion avec le contrôle iPadOS. La relance reste bloquée jusqu’à confirmation."
                }
                return
            }
            if let current = current, current.id == id {
                guard let start = current.startedUptime, let heartbeat = current.updatedUptime else {
                    stopSharing(reason: "État de diffusion incompatible. Arrêtez la diffusion iPadOS puis relancez avec l’app et l’extension du même build."); return
                }
                let policy = BroadcastTiming.policy(phase: 1, since: start, heartbeat: heartbeat)
                if policy != 0 {
                    stopSharing(reason: policy == 1 ? "Limite de dix minutes atteinte." : "La diffusion ne répond plus. Son arrêt a été demandé."); return
                }
                guard ["connecting", "ready", "consent", "starting", "sharing"].contains(current.stage) else {
                    stopSharing(reason: "État de diffusion invalide. Son arrêt a été demandé."); return
                }
                broadcastStartedAt = start; sessionRemaining = BroadcastTiming.remaining(phase: 1, since: start)
                broadcastStage = current.stage; desktopPrompt = current.prompt; sharing = current.stage == "sharing"
                if let visibility = current.screenVisibility { confirmScreenVisibility(visibility) }
                checkScreenVisibilityDeadline()
                guard stoppingAt == nil else { return }
                if let invitation = current.messenger { receiveMessenger(invitation) }
                if let rejection = current.messengerRejection { receiveMessengerRejection(rejection) }
                if let value = try AssistanceMailbox.snapshot(session: id) {
                    updateAssistance(value)
                    if let sent = commandSent, sent == value.commandID {
                        if commands.first?.id == sent { commands.removeFirst() }
                        commandSent = nil; commandSentAt = nil; flushCommand()
                    }
                }
                if let sent = commandSentAt, BroadcastTiming.policy(phase: 2, since: sent) == 3 {
                    stopSharing(reason: "L’action locale n’a pas été confirmée. L’assistance a été interrompue pour éviter de rejouer une ancienne action."); return
                }
                if let value = try AssistanceMailbox.diagnostics(session: id) { diagnostics = value }
            } else {
                preparationRemaining = BroadcastTiming.remaining(phase: 0, since: broadcastPreparedAt)
                if broadcastStage != "prepared" || BroadcastTiming.policy(phase: 0, since: broadcastPreparedAt) != 0 {
                    stopSharing(reason: "Préparation expirée ou diffusion introuvable. Préparez une nouvelle assistance.")
                }
            }
        } catch {
            self.error = Self.message(error)
            if stoppingAt == nil { stopSharing(reason: "État local inaccessible. Déverrouillez l’appareil et vérifiez l’arrêt dans iPadOS.") }
        }
    }

    func readFile(_ url: URL, asCertificate: Bool) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: EnrollmentImport.inputLimit + 1) ?? Data()
            guard data.count <= EnrollmentImport.inputLimit else { throw EnrollmentImportError.tooLarge }
            if asCertificate { privateCA = try EnrollmentImport.certificate(data) }
            else {
                guard let text = String(data: data, encoding: .utf8) else { throw EnrollmentImportError.invalid }
                input = text
            }
            candidate = nil; error = nil
        } catch { self.error = Self.message(error) }
    }
    func clearCA() { privateCA = nil; candidate = nil }

    func prepareImport() {
        guard !busy else { return }
        candidate = nil; error = nil
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("https:") || text.hasPrefix("http:") {
            do {
                let url = try EnrollmentImport.invitationURL(text)
                busy = true
                let token = UUID(); importGeneration = token
                let name = deviceName, ca = privateCA
                Task {
                    do {
                        let data = try await InvitationResolver(url: url, privateCA: ca).load()
                        guard importGeneration == token else { return }
                        candidate = try EnrollmentImport.invitationPage(data, deviceName: name, privateCA: ca)
                    } catch {
                        guard importGeneration == token else { return }
                        self.error = Self.message(error)
                    }
                    busy = false
                }
            } catch { self.error = Self.message(error) }
        } else {
            do { candidate = try EnrollmentImport.parse(text, deviceName: deviceName, privateCA: privateCA) }
            catch { self.error = Self.message(error) }
        }
    }

    func prepareManual() {
        error = nil; candidate = nil
        do {
            let value = SavedEnrollment(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                serverID: try EnrollmentImport.identifier(serverID), meshID: try EnrollmentImport.identifier(meshID),
                deviceName: deviceName, privateCA: privateCA)
            _ = try value.validated(); candidate = value
        } catch { self.error = Self.message(error) }
    }

    func saveCandidate() {
        guard let candidate = candidate else { return }
        do {
            try EnrollmentStore.save(candidate)
            profile = candidate; self.candidate = nil
            input = ""; endpoint = ""; serverID = ""; meshID = ""; privateCA = nil
            error = nil; status = "Prêt à se connecter"
        } catch { self.error = Self.message(error) }
    }

    func forget() {
        stopSharing()
        disconnect()
        do { try EnrollmentStore.forget(); profile = nil; error = nil }
        catch { self.error = Self.message(error) }
    }

    func connect() {
        guard let profile = profile, !connecting, !connected, broadcastID == nil else { return }
        do {
            let enrollment = try profile.validated()
            error = nil; connecting = true; status = "Connexion sécurisée…"
            diagnostics = ConnectionDiagnostics(); diagnostics.stage = "connecting"
            let token = UUID(); generation = token
            let tag = BroadcastChannel.identityTag(enrollment)
            let accessGroup = Self.isSimulator ? nil : BroadcastChannel.accessGroup
            // RSA generation can take time: never block the UI thread.
            Task {
                do {
                    let identity = try await Task.detached(priority: .userInitiated) {
                        try KeychainIdentity(applicationTag: tag, accessGroup: accessGroup)
                    }.value
                    guard generation == token else { return }
                    let client = MeshCentralConnection(enrollment: enrollment, identity: identity,
                        onAuthenticated: { [weak self] in
                            Task { @MainActor in
                                guard let self = self, self.generation == token else { return }
                                self.connecting = false; self.connected = true; self.status = "Connecté à MeshCentral"
                                self.diagnostics.stage = "authenticated"; self.diagnostics.tlsVerified = true
                            }
                        }, onEnded: { [weak self] failure in
                            Task { @MainActor in
                                guard let self = self, self.generation == token else { return }
                                self.connection = nil; self.connecting = false; self.connected = false
                                self.simulatorCapture.stop(); self.desktop?.stop(); self.desktop = nil
                                self.desktopPrompt = nil; self.sharing = false
                                self.status = "Déconnecté"
                                self.clearSessionContent(); self.diagnostics.stage = "disconnected"
                                self.sessionRemaining = nil; self.broadcastTimer?.invalidate(); self.broadcastTimer = nil
                                self.hasEndedAssistance = true; self.sessionNotice = "Connexion interrompue. Reconnectez l’app puis autorisez une nouvelle assistance."
                                self.diagnostics.lastError = ConnectionDiagnostics.errorCode(failure)
                                if let failure = failure { self.error = Self.message(failure) }
                            }
                        }, onDesktopRequest: Self.isSimulator ? { [weak self] relay, prompt in
                            Task { @MainActor in
                                guard let self = self, self.generation == token else { relay.stop(); return }
                                self.desktopRequested(relay, prompt: prompt)
                            }
                        } : nil, onMessengerRequest: { [weak self] invitation in
                            Task { @MainActor in
                                guard let self = self, self.generation == token else { return }
                                self.receiveMessenger(invitation)
                            }
                        }, onMessengerRejected: { [weak self] rejection in
                            Task { @MainActor in
                                guard let self = self, self.generation == token else { return }
                                self.receiveMessengerRejection(rejection)
                            }
                        })
                    connection = client; client.start()
                } catch {
                    guard generation == token else { return }
                    connecting = false; status = "Échec de connexion"; self.error = Self.message(error)
                    diagnostics.stage = "failed"; diagnostics.lastError = ConnectionDiagnostics.errorCode(error)
                }
            }
        } catch { self.error = Self.message(error) }
    }

    func disconnect() {
        clearSessionContent()
        if broadcastID == nil { sessionRemaining = nil; broadcastTimer?.invalidate(); broadcastTimer = nil }
        diagnostics.stage = "disconnected"
        simulatorCapture.stop(); desktop?.stop(); desktop = nil; desktopPrompt = nil; sharing = false
        generation = UUID(); connection?.stop(); connection = nil
        connecting = false; connected = false; status = "Déconnecté"
    }
    func background() {
        foregroundActive = false
        messengerHost?.prepareForBackground()
        if messengerHost != nil { pollMessenger() }
        else if broadcastID == nil { disconnect() }
        else { closeMessenger() }
        if broadcastID != nil {
            // The extension remains the owner of the screen-sharing session.
            contentEpoch = UUID(); documentOperation = nil; documentBusy = false
            assistance = AssistanceSnapshot(); chatDraft = ""
        }
        importGeneration = UUID(); busy = false; input = ""; candidate = nil
    }
    private func endBackgroundMessenger(_ message: String) {
        if broadcastID == nil { disconnect() } else { closeMessenger(message) }
        messengerNotice = message
        messengerPageError = message
    }
    func foreground() {
        let returning = !foregroundActive
        if returning, messengerHost != nil { pollMessenger() }
        foregroundActive = true
        if messengerConsent != nil { pollMessenger() } else { pollBroadcast() }
        if returning { messengerHost?.refreshAfterBackground() }
    }

    static func message(_ error: Error) -> String {
        if let error = error as? AssistanceMailboxError { return error.localizedDescription }
        if let error = error as? BroadcastConfigurationError { return error.localizedDescription }
        if let error = error as? EnrollmentImportError { return error.localizedDescription }
        if let error = error as? AgentError {
            switch error {
            case .configuration: return "Paramètres invalides. Vérifiez l’adresse WSS, les identifiants et le nom de l’appareil."
            case .keychain(let code):
                if code == errSecMissingEntitlement {
                    return "Accès au trousseau partagé refusé (-34018). Vérifiez Keychain Sharing et les profils de signature de l’app et de l’extension."
                }
                return "Le trousseau n’est pas accessible (code \(code)). Déverrouillez l’appareil ; si l’erreur persiste, faites vérifier le groupe de trousseau partagé."
            case .cryptography: return "L’identité cryptographique n’a pas pu être créée ou vérifiée."
            case .protocolViolation: return "L’authentification MeshCentral a échoué. Vérifiez l’enrôlement et la configuration du serveur."
            case .timeout: return "Le serveur n’a pas répondu à temps."
            case .closed: return "Le serveur a fermé la connexion."
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .secureConnectionFailed:
                return "Le certificat HTTPS n’est pas valide pour ce serveur. Vérifiez son nom et sa chaîne de certificats ; importez l’autorité privée si nécessaire."
            case .timedOut: return "Le serveur n’a pas répondu à temps."
            default: return "Connexion impossible. Vérifiez le réseau, l’adresse du serveur et l’autorisation d’accès au réseau local."
            }
        }
        // Do not display Foundation errors that may embed an invitation token/URL.
        return "L’opération a échoué. Vérifiez le fichier et les paramètres, puis réessayez."
    }
}
