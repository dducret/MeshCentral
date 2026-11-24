// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit
import Security
import CryptoKit

struct ExportedDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}

@MainActor
struct AssistanceView: View {
    @ObservedObject var model: AgentModel
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var documentSelectionEpoch: UUID?
    @State private var exporting = false
    @State private var exported: ExportedDocument?
    @State private var filename = "document"
    @State private var enlarged: CapturePreview?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if model.sharing && geometry.size.width >= 850 && !textSize.isAccessibilitySize {
                    HStack(spacing: 0) {
                        Form { guidance; captures }
                        Form { session; chat; documents; diagnostic }
                    }
                } else {
                    Form { session; guidance; chat; documents; captures; diagnostic }
                }
            }
        }
        .navigationTitle(model.sharing ? "Séance d’assistance" : "Assistance iPad / iPhone")
        .safeAreaInset(edge: .bottom) { SessionControlBar(model: model) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            let epoch = documentSelectionEpoch
            documentSelectionEpoch = nil
            if let epoch = epoch, case .success(let urls) = result, let url = urls.first {
                model.importDocument(url, selectedIn: epoch)
            }
        }
        .fileExporter(isPresented: $exporting, document: exported, contentType: .data, defaultFilename: filename) { result in
            if case .failure = result { model.error = "Le document n’a pas pu être enregistré." }
            exported = nil
        }
        .sheet(item: $enlarged) { preview in CaptureDetail(preview: preview, model: model) }
        .onChange(of: model.sharing) { active in if !active { clearLocalContent() } }
        .onChange(of: model.assistance.revision) { _ in
            if model.assistance.capture == nil && model.assistance.guide?.capture == nil && model.assistance.capturePreview == nil { enlarged = nil }
        }
        .onChange(of: scenePhase) { phase in if phase == .background { clearLocalContent() } }
    }
    @ViewBuilder private var session: some View {
        MessengerInvitationSection(model: model)
        if !model.sharing { AssistanceStartSection(model: model) }
        if model.sharing, let prompt = model.desktopPrompt {
            Section("Technicien") {
                Text(prompt.operatorName).font(.headline)
                Text(prompt.recording ? "Le serveur enregistre la session." : "Le destinataire peut conserver les images.")
                Label("Microphone inactif", systemImage: "mic.slash")
                Label(model.assistance.chatAllowed ? "Chat disponible" : "Chat indisponible", systemImage: "text.bubble")
            }
        }
        if !model.activityNotice.isEmpty {
            Section("À votre retour") {
                Label(model.activityNotice, systemImage: "bell.badge")
                Button("J’ai vu ces nouveautés") { model.acknowledgeActivity() }.frame(minHeight: 44)
            }
        }
        if let error = model.error { Section("Action nécessaire") { Label(error, systemImage: "exclamationmark.triangle") } }
    }
    @ViewBuilder private var guidance: some View {
        if model.sharing {
            if let guide = model.assistance.guide {
                GuidedAssistanceSection(model: model, guide: guide, enlarge: { data, strokes in
                    enlarged = CapturePreview(data: data, strokes: strokes, title: "Étape \(guide.step) sur \(guide.total)")
                })
            } else {
                Section("Guidage") {
                    Text("En attente des instructions du technicien.").font(.headline)
                    Text("Effectuez les gestes vous-même, puis revenez ici pour confirmer les étapes.")
                }
            }
        }
    }
    @ViewBuilder private var chat: some View {
        if model.sharing {
            Section("Chat avec le technicien") {
                ForEach(model.assistance.messages) { line in
                    VStack(alignment: .leading) {
                        Text(line.local ? "Vous" : (model.desktopPrompt?.operatorName ?? "Technicien")).font(.caption).bold()
                        Text(line.text).font(.title2).textSelection(.enabled)
                    }.accessibilityElement(children: .combine)
                }
                TextField("Votre message", text: $model.chatDraft, axis: .vertical)
                Button("Envoyer le message") { model.sendChat() }.frame(minHeight: 44)
                    .disabled(!model.assistance.chatAllowed || model.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.chatDraft.utf8.count > 1024)
                if model.chatDraft.utf8.count > 1024 { Text("Message trop long. Raccourcissez-le pour pouvoir l’envoyer.") }
                if !model.assistance.chatAllowed { Text("Le compte technicien ne possède pas le droit Chat / Notify.").font(.footnote) }
            }
        }
    }
    @ViewBuilder private var documents: some View {
        if model.sharing {
            Section("Documents — 2 Mio maximum") {
                Button("Choisir et envoyer un document") {
                    documentSelectionEpoch = model.documentImportEpoch; importing = true
                }.frame(minHeight: 44)
                    .disabled(model.documentBusy || !model.assistance.documentsAllowed)
                if !model.assistance.documentsAllowed { Text("Les documents sont interdits pour ce compte technicien.") }
                if model.documentBusy { ProgressView("Lecture du document…") }
                if let item = model.assistance.offer, model.assistance.receiving?.state == .offered {
                    Text("Le technicien propose : \(item.name) (\(item.size) octets)")
                    Button("Accepter ce document") { model.assist(AssistanceCommand(action: "accept", transferID: item.id)) }.frame(minHeight: 44)
                    Button("Refuser", role: .destructive) { model.assist(AssistanceCommand(action: "reject", transferID: item.id)) }.frame(minHeight: 44)
                }
                if let progress = model.assistance.sending { TransferStatusView(title: "Envoi", progress: progress) }
                if let progress = model.assistance.receiving { TransferStatusView(title: "Réception", progress: progress) }
                if let item = model.assistance.received, let data = model.assistance.document {
                    Button("Enregistrer « \(item.name) » dans Fichiers") { export(data, name: item.name) }.frame(minHeight: 44)
                    Button("Supprimer le document reçu", role: .destructive) { model.assist(AssistanceCommand(action: "discard")) }
                }
                if !model.assistance.transfer.isEmpty { Text(model.assistance.transfer).font(.footnote) }
                Button("Annuler les transferts en cours", role: .destructive) { model.assist(AssistanceCommand(action: "cancel")) }.frame(minHeight: 44)
                Text("Chaque réception exige votre accord. Aucun accès distant à vos dossiers.").font(.footnote)
            }
        }
    }
    @ViewBuilder private var captures: some View {
        if model.sharing {
            Section("Capture et annotations") {
                if model.screenHidden || model.pendingScreenVisibility != nil {
                    Text("Les nouvelles captures sont suspendues.")
                } else if model.assistance.captureRequested {
                    Text("Le technicien demande une capture. Examinez-la avant de l’envoyer.").bold()
                    if let data = model.assistance.capturePreview, let image = UIImage(data: data) {
                        AnnotatedCapture(image: image, strokes: [])
                        Button("Agrandir l’aperçu") { enlarged = CapturePreview(data: data, strokes: [], title: "Capture à autoriser") }
                        Button("Autoriser l’envoi de cette capture") { model.assist(AssistanceCommand(action: "capture")) }.frame(minHeight: 44)
                    } else { Text("Aucune image disponible. Refusez, puis demandez au technicien de réessayer.") }
                    Button("Refuser cette capture", role: .destructive) { model.assist(AssistanceCommand(action: "declineCapture")) }.frame(minHeight: 44)
                } else {
                    Button("Envoyer la dernière image partagée comme capture") { model.assist(AssistanceCommand(action: "capture")) }.frame(minHeight: 44)
                }
                if !model.assistance.notice.isEmpty { Text(model.assistance.notice).font(.footnote) }
                if let data = model.assistance.capture, let image = UIImage(data: data) {
                    AnnotatedCapture(image: image, strokes: model.assistance.strokes)
                    Button("Agrandir la capture annotée") { enlarged = CapturePreview(data: data, strokes: model.assistance.strokes, title: "Capture annotée") }.frame(minHeight: 44)
                }
                Text("Images figées. Les annotations n’agissent pas sur les autres applications.").font(.footnote)
                Button("Effacer les échanges et arrêter le guidage", role: .destructive) { enlarged = nil; model.assist(AssistanceCommand(action: "clear")) }.frame(minHeight: 44)
            }
        }
    }
    private var diagnostic: some View {
        Section("Diagnostic de connexion") {
            LabeledContent("État", value: model.diagnostics.stageLabel)
            LabeledContent("Identité TLS vérifiée", value: model.diagnostics.tlsVerified ? "Oui" : "Pas encore")
            LabeledContent("Réseau", value: model.diagnostics.networkLabel)
            if model.diagnostics.lowPower == true { Text("Mode économie d’énergie actif.") }
            if model.diagnostics.constrained == true { Text("Mode Faibles données actif.") }
            if model.diagnostics.healthCode != nil { Text(model.diagnostics.recommendation).font(.footnote) }
            Text(String(format: "%.1f images/s · %.0f kbit/s · RTT relais %.0f ms", model.diagnostics.fps, model.diagnostics.kilobitsPerSecond, model.diagnostics.roundTripMS)).font(.footnote)
            if !model.diagnostics.lastError.isEmpty { Text(model.diagnostics.errorLabel).font(.footnote) }
            Button("Exporter le diagnostic sans échanges") { export(model.diagnostics.report(), name: "meshcentral-diagnostic.json") }.frame(minHeight: 44)
        }
    }
    private func clearLocalContent() {
        documentSelectionEpoch = nil; importing = false; exporting = false; exported = nil; enlarged = nil
    }
    private func export(_ bytes: Data, name: String) { exported = ExportedDocument(bytes); filename = name; exporting = true }
}

private struct AssistanceButtonStyle: ButtonStyle {
    enum Appearance { case primary, secondary, destructive }

    var appearance: Appearance = .primary
    var emphasized = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        let pressedOpacity = configuration.isPressed ? 0.84 : 1.0
        return configuration.label
            .font((emphasized ? Font.largeTitle : .title2).bold())
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: emphasized ? 96 : 64)
            .foregroundStyle(appearance == .secondary ? Color.primary : Color.white)
            .background(fill, in: shape)
            .overlay {
                if appearance == .secondary { shape.strokeBorder(Color.primary, lineWidth: 2) }
            }
            .contentShape(shape)
            .opacity(isEnabled ? pressedOpacity : 0.48)
    }

    private var fill: Color {
        switch appearance {
        case .primary: return Color(red: 0.06, green: 0.29, blue: 0.55)
        case .secondary: return Color(uiColor: .systemBackground)
        case .destructive: return Color(red: 0.55, green: 0.08, blue: 0.15)
        }
    }
}

@MainActor
struct MessengerInvitationView: View {
    @ObservedObject var model: AgentModel
    let operatorName: String
    @State private var backgroundAudio = true
    @AccessibilityFocusState private var titleFocused: Bool

    private var keepsAudio: Bool { MessengerWebHost.supportsBackgroundAudio && backgroundAudio }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Invitation à discuter")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Text("\(operatorName) souhaite discuter avec vous.").font(.title2)
                if let error = model.error { Text(error).font(.body).foregroundStyle(.red) }
                if MessengerWebHost.supportsBackgroundAudio {
                    Toggle("Garder le son dans les autres apps", isOn: $backgroundAudio)
                        .font(.title2.bold())
                        .accessibilityHint("S’applique seulement à cet appel avec le micro.")
                    if backgroundAudio {
                        Text("En acceptant avec le micro, vous autorisez l’appel à continuer si vous changez d’app ou verrouillez l’écran. Pour couper le micro, revenez dans l’app et touchez Terminer.")
                    }
                }
                VStack(spacing: 14) {
                    Button("Accepter avec le micro") {
                        model.acceptMessenger(startWithMicrophone: true, backgroundAudio: keepsAudio)
                    }
                    .buttonStyle(AssistanceButtonStyle())
                    .accessibilityHint(keepsAudio
                        ? "Le micro peut rester actif dans une autre app ou quand l’écran est verrouillé."
                        : "Ouvre la conversation avec le microphone au premier plan.")
                    .accessibilityIdentifier("acceptMessengerWithMicrophone")
                    Button("Accepter sans micro") { model.acceptMessenger(startWithMicrophone: false) }
                        .buttonStyle(AssistanceButtonStyle(appearance: .secondary))
                        .accessibilityIdentifier("acceptMessengerWithoutMicrophone")
                    Button("Refuser", role: .destructive) { model.closeMessenger("Invitation refusée sur cet appareil.") }
                        .buttonStyle(AssistanceButtonStyle(appearance: .destructive))
                        .accessibilityIdentifier("declineMessenger")
                }
            }.padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.broadcastID != nil || model.sharing { SessionControlBar(model: model) }
        }
        .accessibilityIdentifier("messengerInvitationBanner")
        .onAppear { titleFocused = true }
    }
}

@MainActor
struct MessengerAttentionBanner: View {
    @ObservedObject var model: AgentModel
    var body: some View {
        if let failure = model.messengerFailure {
            VStack(alignment: .leading, spacing: 8) {
                Label("Invitation Chat bloquée", systemImage: "exclamationmark.bubble").font(.headline)
                Text(failure.reason.message)
                Button("J’ai compris") { model.dismissMessengerFailure() }
                    .buttonStyle(AssistanceButtonStyle(appearance: .secondary, emphasized: false))
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial).accessibilityIdentifier("messengerFailureBanner")
        } else if let message = model.messengerPageError {
            VStack(alignment: .leading, spacing: 8) {
                Label("Conversation interrompue", systemImage: "exclamationmark.bubble").font(.headline)
                Text(message)
                Button("J’ai compris") { model.dismissMessengerPageError() }
                    .buttonStyle(AssistanceButtonStyle(appearance: .secondary, emphasized: false))
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
        }
    }
}

@MainActor
struct MessengerInvitationSection: View {
    @ObservedObject var model: AgentModel
    var body: some View {
        Section("Conversation vocale — MeshMessenger") {
            Text(model.messengerNotice.isEmpty ? "Le technicien peut vous envoyer une invitation Chat quand votre appareil est connecté." : model.messengerNotice)
                .font(.footnote)
        }
    }
}

/// Owns a transient WebKit session. No Safari handoff, persistent cookies or native JS bridge.
@MainActor
final class MessengerWebHost: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    static var supportsBackgroundAudio: Bool {
        guard !AgentModel.isSimulator, #available(iOS 17.5.1, *) else { return false }
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("audio") == true
    }

    let id: UUID
    let invitation: MessengerInvitation
    let webView: WKWebView
    let backgroundAudio: Bool
    @Published private(set) var status = "Connexion à MeshMessenger…"
    @Published private(set) var microphone = "Microphone inactif"
    @Published private(set) var muted = false
    @Published private(set) var connected = false
    @Published private(set) var pageReady = false
    @Published private(set) var canStartMicrophone = false
    @Published private(set) var microphonePending = false
    @Published private(set) var microphoneStatus = ""
    @Published private(set) var sending = false
    @Published private(set) var sendError: String?
    @Published private(set) var backgroundAudioReady = false
    private enum AudioRecovery: Equatable { case idle, interrupted, resuming(Double) }
    @Published private var audioRecovery: AudioRecovery = .idle
    @Published private(set) var relayPaired = false
    private let privateCA: Data?
    private let onEnded: (String) -> Void
    private var stopped = false
    private var captureObservation: NSKeyValueObservation?
    private var started = false
    private var timer: Timer?
    private var pollPending = false
    private var pollStarted = 0.0
    private var navigationStarted = 0.0
    private var pageEpoch = UUID()
    private var messageTextSize = 24.0
    private var wasConnected = false
    private var microphoneCommandRunning = false
    private var microphonePermissionRequested = false
    private var audioAttemptStarted: Double?
    private var microphoneStartDeadline: Double?
    private var beganNavigation = false
    private var lastLiveAudio: Double?
    private var backgroundCallEstablished = false
    private var awaitingForeground = false
    private var checkingAudioOnReturn = false
    private var userMuted = false

    var audioInterrupted: Bool { audioRecovery != .idle }
    var audioResuming: Bool { resumeStarted != nil }
    private var resumeStarted: Double? {
        if case .resuming(let started) = audioRecovery { return started }
        return nil
    }

    var canContinueAudioInBackground: Bool {
        guard backgroundAudio, !stopped, !audioInterrupted, !userMuted, relayPaired, backgroundAudioReady,
              webView.microphoneCaptureState == .active, let lastLiveAudio else { return false }
        return ProcessInfo.processInfo.systemUptime - lastLiveAudio < 5
    }
    var canKeepMessengerRelayInBackground: Bool {
        !stopped && backgroundCallEstablished && relayPaired && invitation.matchesPage(webView.url)
    }

    func prepareForBackground() {
        awaitingForeground = true
        checkingAudioOnReturn = false
        backgroundCallEstablished = backgroundAudio && !userMuted && (audioInterrupted ||
            (lastLiveAudio.map { ProcessInfo.processInfo.systemUptime - $0 < 5 } ?? false))
        if audioResuming { pauseInterruptedAudio() }
    }

    func refreshAfterBackground() {
        awaitingForeground = false
        // A JavaScript poll issued before suspension cannot validate the return.
        pollPending = false
        checkingAudioOnReturn = backgroundCallEstablished && !audioInterrupted
        pollPage()
    }

    func pauseInterruptedAudio() {
        guard !audioInterrupted || audioResuming else { return }
        if audioResuming {
            webView.evaluateJavaScript("if (window.__meshIOSMedia) ++window.__meshIOSMedia.captureEpoch;")
        }
        audioRecovery = .interrupted
        backgroundAudioReady = false; lastLiveAudio = nil
        microphoneStartDeadline = nil
        resetMicrophoneRequest()
        webView.setMicrophoneCaptureState(.muted)
        webView.setAllMediaPlaybackSuspended(true)
    }

    init(invitation: MessengerInvitation, privateCA: Data?, startWithMicrophone: Bool, backgroundAudio: Bool,
         onEnded: @escaping (String) -> Void) {
        self.id = invitation.id; self.invitation = invitation; self.privateCA = privateCA; self.onEnded = onEnded
        self.backgroundAudio = backgroundAudio
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = false
        // This host exists only after explicit local acceptance. Playback does
        // not activate the microphone; media capture still requires a user action.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Install before the server page can create the data or media peers.
        configuration.userContentController.addUserScript(WKUserScript(source: Self.rtcScriptSource,
            injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        // Limit the visible embedded interface to chat/audio. Native delegates
        // independently deny camera, new windows, navigation and downloads.
        let script = Self.pageScript
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        if startWithMicrophone {
            microphoneStartDeadline = ProcessInfo.processInfo.systemUptime + 30
            microphoneStatus = "Le micro sera demandé à la connexion."
        }
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        captureObservation = webView.observe(\.microphoneCaptureState, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateMicrophone() }
        }
    }
    private static var rtcScriptSource: String {
        #if DEBUG
        return rtcPromiseScript + "(" + rtcDiagnosticsScript + ");"
        #else
        return rtcPromiseScript + "();"
        #endif
    }

    // MeshCentral 1.3.1 owns the negotiation. Translate only its legacy
    // callback overloads here and let it perform signaling and error cleanup.
    private static let rtcPromiseScript = """
        (observe => {
            const prototypes = new Set([window.RTCPeerConnection?.prototype, window.webkitRTCPeerConnection?.prototype]);
            let pageClosed = false;
            window.addEventListener('pagehide', () => { pageClosed = true; }, {once:true});
            for (const prototype of prototypes) {
                if (!prototype) continue;
                for (const name of ['createOffer', 'createAnswer', 'setLocalDescription', 'setRemoteDescription']) {
                    const descriptor = Object.getOwnPropertyDescriptor(prototype, name);
                    if (!descriptor || typeof descriptor.value !== 'function' ||
                        (!descriptor.configurable && !descriptor.writable)) continue;
                    const original = descriptor.value;
                    const callbackIndex = name.startsWith('create') ? 0 : 1;
                    Object.defineProperty(prototype, name, {...descriptor, value: function(...args) {
                        const success = args[callbackIndex];
                        const failure = args[callbackIndex + 1];
                        if (typeof success !== 'function' || typeof failure !== 'function') {
                            return Reflect.apply(original, this, args);
                        }
                        const modernArgs = name === 'createOffer' ? args.slice(2, 3) : args.slice(0, callbackIndex);
                        const invoke = (callback, value, event) => {
                            // A stale callback could signal on a newer relay or
                            // hang up a different peer that reused the same ID.
                            if (pageClosed || this.signalingState === 'closed') return;
                            observe?.(name, event);
                            try { callback(value); }
                            catch (_) { observe?.(name, 'callback-failed'); }
                        };
                        Reflect.apply(original, this, modernArgs).then(
                            value => invoke(success, value, 'fulfilled'),
                            error => invoke(failure, error, 'rejected')
                        );
                        // The legacy result is a resolved Promise<void>; the
                        // callbacks report the separate operation's outcome.
                        return Promise.resolve();
                    }});
                }
            }
        })
        """

    #if DEBUG
    private static let rtcDiagnosticsScript = """
        ((operation, event) => {
            if (!['createOffer', 'createAnswer', 'setLocalDescription', 'setRemoteDescription'].includes(operation) ||
                !['fulfilled', 'rejected', 'callback-failed'].includes(event)) return;
            try { console.debug('MeshMessenger RTC', operation, event); } catch (_) {}
        })
        """
    #endif

    // No script-message handler or native object is exposed to the page.
    private static let pageScript = """
        (() => {
        const style = document.createElement('style');
        style.textContent = `
            #camButton,#micButton,#hangupButton,#fileButton,#saveButton,#notifyButton,#uploadFileInput,#xbottom { display:none !important; }
            #xmiddle { bottom:0 !important; }
            #xmsgparent { -webkit-text-size-adjust: 100%; }
            #xmsg .remoteBubble:not([id]), #xmsg .localBubble:not([id]) {
                font-family: system-ui, sans-serif;
                font-size: var(--mesh-ios-message-size, 24px);
                line-height: 1.35;
                box-sizing: border-box;
                max-width: calc(100% - 20px);
                overflow-wrap: anywhere;
                white-space: pre-wrap;
            }
        `;
        document.head.appendChild(style);
        // The upstream page starts the relay before document-end injection.
        // A new relay after disconnect requires a new local invitation.
        if (typeof start === 'function' && typeof socket !== 'undefined' && socket) {
            start = function() {};
        }
        const player = document.getElementById('remoteVideoCanvas');
        if (player) player.playsInline = true;
        if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia && !window.__meshIOSMedia) {
            const relay = typeof socket === 'undefined' ? null : socket;
            const info = window.__meshIOSMedia = {error:0, approved:false, closed:false, restarted:false, recovering:false, captureEpoch:0,
                relayPaired:() => !info.closed && !!relay && relay.readyState === 1 && socket === relay && state === 2};
            window.addEventListener('pagehide', () => { info.closed = true; });
            const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
            navigator.mediaDevices.getUserMedia = function(constraints) {
                if (!info.approved || info.closed || !constraints || constraints.audio !== true || constraints.video !== false) {
                    return Promise.reject(new DOMException('Microphone action required', 'NotAllowedError'));
                }
                info.approved = false;
                info.error = 0;
                const recovering = info.recovering;
                const captureEpoch = info.captureEpoch;
                return original(constraints).then(stream => {
                    if (!info.relayPaired() || localStream !== 1 ||
                        (recovering && (captureEpoch !== info.captureEpoch || document.visibilityState !== 'visible'))) {
                        stream.getTracks().forEach(track => track.stop());
                        throw new DOMException('Conversation ended', 'AbortError');
                    }
                    // The pre-permission data peer may have gathered a limited set
                    // of ICE candidates. Retry only that existing negotiation once.
                    const peer = webrtcSessions[0];
                    if (!info.restarted && peer && peer.remoteDescription && peer.signalingState === 'stable' &&
                        (!webchannel || webchannel.readyState === 'connecting') &&
                        ['new','checking','disconnected'].includes(peer.iceConnectionState) &&
                        typeof peer.restartIce === 'function') {
                        info.restarted = true;
                        try { peer.restartIce(); } catch (_) { /* retain the approved audio stream */ }
                    }
                    return stream;
                }, error => {
                    info.error = ({NotAllowedError:1,NotFoundError:2,NotReadableError:3})[error.name] || 4;
                    throw error;
                });
            };
        }
        })();
        """
    func start() {
        guard !started, !stopped else { return }
        started = true; navigationStarted = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPage() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        webView.load(URLRequest(url: invitation.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
    }
    func setMessageTextSize(_ size: Double) {
        guard size.isFinite else { return }
        messageTextSize = min(96, max(16, size))
    }

    // The size is supplied by SwiftUI, not by the page or the chat message.
    private static let messageTextSizeScript = """
        const transcript = document.getElementById('xmsgparent');
        if (transcript && Number.isFinite(messageTextSize) && messageTextSize >= 16 && messageTextSize <= 96) {
            const style = transcript.style;
            const size = messageTextSize + 'px';
            if (style.getPropertyValue('--mesh-ios-message-size') !== size) {
                const followingLatest = transcript.scrollHeight - transcript.scrollTop - transcript.clientHeight <= 24;
                style.setProperty('--mesh-ios-message-size', size);
                if (followingLatest) transcript.scrollTop = transcript.scrollHeight;
            }
        }
        """
    private static let stateScript = """
    (() => {
        const data = typeof webchannel !== 'undefined' && !!webchannel && webchannel.ok === true && webchannel.readyState === 'open';
        const separate = typeof multiWebRtc !== 'undefined' && multiWebRtc === true;
        const peer = typeof webrtcSessions !== 'undefined' && webrtcSessions[separate ? 1 : 0];
        const capturing = typeof localStream !== 'undefined' && !!localStream && localStream !== 1;
        const connectedPeer = value => !!value && ['connected','completed'].includes(value.iceConnectionState);
        const liveAudio = stream => !!stream && typeof stream.getAudioTracks === 'function' &&
            stream.getAudioTracks().some(track => track.readyState === 'live' && track.enabled && !track.muted);
        const outbound = capturing && connectedPeer(peer);
        const remotePlayer = document.getElementById('remoteVideoCanvas');
        const remotePeer = typeof webrtcSessions !== 'undefined' && webrtcSessions[separate ? 2 : 0];
        const duplex = navigator.audioSession?.state !== 'interrupted' &&
            outbound && liveAudio(localStream) && connectedPeer(remotePeer) &&
            !!remotePlayer && !remotePlayer.paused && !remotePlayer.muted && liveAudio(remotePlayer.srcObject);
        return {ready:typeof xsend === 'function' && !!document.getElementById('xouttext'),
            state:typeof state === 'number' && [0,1,2].includes(state) ? state : 0,
            paired:window.__meshIOSMedia?.relayPaired() === true,
            data,
            canStart:!!window.__meshIOSMedia && typeof micButtonClick === 'function' &&
                (typeof RTCPeerConnection !== 'undefined' || typeof webkitRTCPeerConnection !== 'undefined') && (separate || data),
            pending:typeof localStream !== 'undefined' && localStream === 1,
            outbound, duplex,
            error:window.__meshIOSMedia && [1,2,3,4].includes(window.__meshIOSMedia.error) ? window.__meshIOSMedia.error : 0};
    })()
    """
    private static let pollScript = messageTextSizeScript + "\nreturn (\n" + stateScript + "\n);"
    private func pollPage() {
        guard !stopped else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if pollPending && awaitingForeground && backgroundCallEstablished { return }
        if (!pageReady && now - navigationStarted > 20) || (pollPending && now - pollStarted > 10) {
            fail("La page Messenger ne répond pas. Vérifiez le serveur et sa page Messenger, puis demandez une nouvelle invitation."); return
        }
        guard !pollPending, invitation.matchesPage(webView.url) else { return }
        pollPending = true; pollStarted = now
        let epoch = pageEpoch
        webView.callAsyncJavaScript(Self.pollScript, arguments: ["messageTextSize": messageTextSize], in: nil, in: .page) { [weak self] response in
            guard let self = self, !self.stopped, self.pageEpoch == epoch,
                  self.pollPending, self.pollStarted == now else { return }
            self.pollPending = false
            guard case .success(let value) = response, let result = value as? [String: Any], result["ready"] as? Bool == true else {
                self.backgroundAudioReady = false
                self.status = "Chargement de la page Messenger…"; return
            }
            self.pageReady = true
            let state = result["state"] as? Int ?? 0
            self.connected = state == 2
            self.relayPaired = result["paired"] as? Bool == true
            if self.backgroundAudio {
                let ready = self.relayPaired && result["duplex"] as? Bool == true &&
                    self.webView.microphoneCaptureState == .active && !self.userMuted
                if self.backgroundAudioReady != ready { self.backgroundAudioReady = ready }
                if ready { self.lastLiveAudio = now }
                if self.checkingAudioOnReturn {
                    self.checkingAudioOnReturn = false
                    if self.relayPaired && !ready && !self.userMuted { self.pauseInterruptedAudio() }
                }
                if let resumeStarted = self.resumeStarted, now >= resumeStarted {
                    if ready && !self.microphoneCommandRunning {
                        self.audioRecovery = .idle
                    } else if now - resumeStarted >= 20 && result["pending"] as? Bool != true &&
                                UIApplication.shared.applicationState == .active {
                        self.pauseInterruptedAudio()
                        self.microphoneStatus = "Le son n’a pas repris. Réessayez quand le micro est disponible."
                    }
                }
                if self.audioInterrupted && self.wasConnected && !self.relayPaired {
                    self.fail("La liaison Messenger est fermée. Demandez une nouvelle invitation Chat."); return
                }
            }
            self.canStartMicrophone = self.connected && result["canStart"] as? Bool == true
            if !self.microphoneCommandRunning {
                self.microphonePending = result["pending"] as? Bool == true
                if !self.microphonePending { self.microphonePermissionRequested = false }
            }
            if self.connected { self.wasConnected = true }
            if state == 0 && (self.wasConnected || now - self.navigationStarted > 20) {
                self.fail("La liaison Messenger est déconnectée. Ce n’est pas un refus local : demandez au technicien une nouvelle invitation Chat."); return
            }
            if state == 0 { self.status = "Connexion au relais Messenger…" }
            else if state == 1 { self.status = "En attente du technicien dans sa fenêtre Chat…" }
            else if result["data"] as? Bool == true { self.status = "Conversation connectée." }
            else if self.canStartMicrophone { self.status = "Chat connecté. Vous pouvez activer le micro pendant la connexion WebRTC." }
            else { self.status = "Chat connecté. Le canal WebRTC ou la fonction microphone reste indisponible." }

            if !self.microphoneCommandRunning {
                self.updateAudioStatus(error: result["error"] as? Int ?? 0, outbound: result["outbound"] as? Bool == true)
            }
            self.startRequestedMicrophone()
        }
    }
    private func startRequestedMicrophone() {
        guard let deadline = microphoneStartDeadline else { return }
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            microphoneStartDeadline = nil
            microphoneStatus = "Pour parler, touchez Activer le microphone."
            return
        }
        if canStartMicrophone && UIApplication.shared.applicationState == .active { startMicrophone() }
    }
    private func updateAudioStatus(error: Int, outbound: Bool) {
        if microphonePending {
            audioAttemptStarted = ProcessInfo.processInfo.systemUptime
            microphoneStatus = "Autorisez l’accès au microphone si le système le demande."
            return
        }
        switch error {
        case 1: microphoneStatus = "Accès au micro refusé. Vérifiez l’autorisation du site et, si l’app apparaît dans Réglages, l’autorisation du microphone."
        case 2: microphoneStatus = "Aucun microphone disponible sur cet appareil."
        case 3: microphoneStatus = "Le microphone est occupé ou inaccessible. Libérez-le puis réessayez."
        case 4: microphoneStatus = "Le microphone n’a pas pu démarrer. Touchez de nouveau Activer le microphone."
        default:
            guard let started = audioAttemptStarted else { return }
            if outbound {
                microphoneStatus = "Liaison audio sortante établie."
            } else if ProcessInfo.processInfo.systemUptime - started > 15 {
                microphoneStatus = "Liaison audio indisponible. Faites vérifier la connexion WebRTC (STUN/TURN)."
            } else {
                microphoneStatus = "Connexion de la liaison audio…"
            }
        }
    }
    private func updateMicrophone() {
        guard !stopped else { return }
        muted = webView.microphoneCaptureState == .muted
        switch webView.microphoneCaptureState {
        case .active: microphone = "Microphone actif sur cet appareil"
        case .muted: microphone = "Microphone coupé"
        default: microphone = "Microphone inactif"
        }
    }
    // Also works when WebKit has not enumerated a microphone before its first
    // permission prompt. Calls only the audited server page's audio-only action.
    private static let microphoneScript = """
    (() => {
        if (typeof micButtonClick !== 'function' || !window.__meshIOSMedia || window.__meshIOSMedia.closed) return 'unsupported';
        if (typeof RTCPeerConnection === 'undefined' && typeof webkitRTCPeerConnection === 'undefined') return 'unsupported';
        if (typeof state === 'undefined' || state !== 2) return 'waiting';
        const separate = typeof multiWebRtc !== 'undefined' && multiWebRtc === true;
        if (!separate && (typeof webchannel === 'undefined' || !webchannel || !webchannel.ok || webchannel.readyState !== 'open')) return 'waiting';
        if (typeof localStream === 'undefined') return 'unsupported';
        const info = window.__meshIOSMedia;
        const recovering = typeof restartCapture === 'boolean';
        if (recovering) {
            if (!info.relayPaired()) return 'closed';
            if (document.visibilityState !== 'visible') return 'waiting';
            const player = document.getElementById('remoteVideoCanvas');
            if (player?.srcObject && player.paused) player.play()?.catch(() => {});
            if (localStream && localStream !== 1) {
                const peer = webrtcSessions[separate ? 1 : 0];
                const live = localStream.getAudioTracks().some(track => track.readyState === 'live');
                if (live && !restartCapture && peer && !['failed','closed'].includes(peer.iceConnectionState)) return 'active';
                if (!separate || typeof hangUpButtonClick !== 'function' || typeof sendws !== 'function') return 'unsupported';
                if (!peer) localStream.getTracks().forEach(track => track.stop());
                hangUpButtonClick(1, true);
                // Order the stop and the next offer on the same signaling socket.
                sendws({action:'videoStop', id:1});
            }
        }
        if (localStream === 1) return 'pending';
        if (localStream) return 'active';
        info.approved = true;
        info.recovering = recovering;
        try { micButtonClick(); } finally { info.approved = false; info.recovering = false; }
        return localStream === 1 ? 'requested' : 'waiting';
    })();
    """
    func startMicrophone() {
        guard !audioInterrupted else { return }
        userMuted = false
        requestMicrophone()
    }
    func resumeAudio(authorize: @escaping () -> Bool) {
        guard !stopped, audioInterrupted, !audioResuming, relayPaired,
              UIApplication.shared.applicationState == .active, invitation.matchesPage(webView.url), authorize() else { return }
        let began = ProcessInfo.processInfo.systemUptime
        audioRecovery = .resuming(began)
        microphoneStatus = "Reprise du son…"
        webView.evaluateJavaScript("window.__meshIOSMedia?.relayPaired() === true") { [weak self] value, error in
            guard let self, self.resumeStarted == began else { return }
            guard UIApplication.shared.applicationState == .active, authorize() else {
                self.pauseInterruptedAudio(); return
            }
            if error != nil {
                self.pauseInterruptedAudio()
                self.microphoneStatus = "Le son n’a pas repris. Réessayez."
                return
            }
            guard value as? Bool == true else {
                self.fail("La liaison Messenger est fermée. Demandez une nouvelle invitation Chat."); return
            }
            self.webView.setAllMediaPlaybackSuspended(false) { [weak self] in
                guard let self, self.resumeStarted == began else { return }
                guard UIApplication.shared.applicationState != .background, authorize() else {
                    self.pauseInterruptedAudio(); return
                }
                self.requestMicrophone(resuming: true, authorize: authorize)
            }
        }
    }
    private func requestMicrophone(resuming: Bool = false, authorize: @escaping () -> Bool = { true }) {
        guard !stopped, !microphoneCommandRunning, !microphonePending else { return }
        guard UIApplication.shared.applicationState == .active, invitation.matchesPage(webView.url), canStartMicrophone else {
            microphoneStatus = "Attendez que la conversation soit connectée avant d’activer le microphone."
            return
        }
        microphoneStartDeadline = nil
        let epoch = pageEpoch
        microphoneCommandRunning = true
        microphonePermissionRequested = true
        microphonePending = true
        microphoneStatus = "Activation du microphone…"
        let resume = resumeStarted
        let source = resuming
            ? "(() => { const restartCapture = \(webView.microphoneCaptureState == .none); return \(Self.microphoneScript) })()"
            : Self.microphoneScript
        webView.evaluateJavaScript(source) { [weak self] result, error in
            guard let self = self, !self.stopped, self.pageEpoch == epoch, self.resumeStarted == resume else { return }
            self.microphoneCommandRunning = false
            let value = result as? String
            if resuming {
                guard UIApplication.shared.applicationState == .active, authorize() else {
                    self.pauseInterruptedAudio(); return
                }
                if value == "requested" || value == "active" {
                    self.webView.setMicrophoneCaptureState(.active)
                }
            }
            switch value {
            case "requested", "pending":
                self.audioAttemptStarted = ProcessInfo.processInfo.systemUptime
                self.microphoneStatus = "Autorisez l’accès au microphone si le système le demande."
                return
            case "waiting": self.microphoneStatus = "La liaison audio n’est pas prête. Réessayez ou faites vérifier WebRTC."
            case "active": self.microphoneStatus = "Le microphone est déjà actif sur cet appareil."
            case "closed":
                self.fail("La liaison Messenger est fermée. Demandez une nouvelle invitation Chat."); return
            default: self.microphoneStatus = error == nil ? "Cette page Messenger ne propose pas l’accès au micro." : "La demande de microphone a échoué. Réessayez."
            }
            self.microphonePermissionRequested = false
            self.microphonePending = false
            if resuming && value != "active" {
                self.pauseInterruptedAudio()
                self.microphoneStatus = "Le son n’a pas repris. Réessayez quand le micro est disponible."
            }
        }
    }
    private static let sendScript = """
    if (typeof message !== 'string' || !message.trim() || new TextEncoder().encode(message).length > 4096) return 'invalid';
    if (typeof state === 'undefined' || state !== 2) return 'waiting';
    const rtc = typeof serverRecording !== 'undefined' && !serverRecording && typeof webchannel !== 'undefined' && webchannel && webchannel.ok;
    const transport = rtc ? webchannel : (typeof socket !== 'undefined' ? socket : null);
    if (!transport || transport.readyState !== (rtc ? 'open' : 1) || transport.bufferedAmount > 65536) return 'waiting';
    if (rtc && Array.isArray(transport.xoutBuffer) && transport.xoutBuffer.length >= 16) return 'waiting';
    const input = document.getElementById('xouttext');
    if (!input || typeof xsend !== 'function') return 'unsupported';
    const focus = input.focus;
    try { input.focus = function(){}; input.value = message; xsend(); }
    finally { input.focus = focus; }
    return 'sent';
    """
    func sendText(_ text: String, completion: @escaping (Bool) -> Void) {
        guard !stopped, !sending, connected, invitation.matchesPage(webView.url),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 4096 else { completion(false); return }
        sending = true; sendError = nil; let epoch = pageEpoch
        webView.callAsyncJavaScript(Self.sendScript, arguments: ["message": text], in: nil, in: .page) { [weak self] result in
            guard let self = self, !self.stopped, self.pageEpoch == epoch else { completion(false); return }
            self.sending = false
            if case .success(let value) = result, value as? String == "sent" { completion(true) }
            else { self.sendError = "Message non transmis. Vérifiez la connexion ; votre texte est conservé."; completion(false) }
        }
    }
    func toggleMute() {
        guard !stopped, !audioInterrupted else { return }
        if webView.microphoneCaptureState == .active {
            userMuted = true; lastLiveAudio = nil
            webView.setMicrophoneCaptureState(.muted)
        } else if webView.microphoneCaptureState == .muted {
            userMuted = false
            webView.setMicrophoneCaptureState(.active)
        }
    }
    func stop() {
        guard !stopped else { return }; stopped = true
        timer?.invalidate(); timer = nil; connected = false; canStartMicrophone = false; sending = false
        resetMicrophoneRequest()
        backgroundAudioReady = false; lastLiveAudio = nil
        relayPaired = false; audioRecovery = .idle
        microphoneStartDeadline = nil
        captureObservation?.invalidate(); captureObservation = nil
        webView.setMicrophoneCaptureState(.none)
        webView.setCameraCaptureState(.none)
        webView.setAllMediaPlaybackSuspended(true)
        webView.stopLoading(); webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllUserScripts()
        webView.loadHTMLString("", baseURL: nil)
        microphone = "Microphone inactif"
    }
    private func resetMicrophoneRequest() {
        microphonePermissionRequested = false
        microphoneCommandRunning = false
        microphonePending = false
        audioAttemptStarted = nil
        microphoneStatus = ""
    }
    private func fail(_ message: String) { guard !stopped else { return }; stop(); onEnded(message) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = !stopped && !navigationAction.shouldPerformDownload && navigationAction.targetFrame?.isMainFrame == true && invitation.matchesPage(navigationAction.request.url)
        decisionHandler(allowed ? .allow : .cancel)
        if !allowed, !stopped, navigationAction.targetFrame?.isMainFrame == true {
            fail("La navigation Messenger a été bloquée : le serveur a renvoyé une autre page. Vérifiez son adresse publique et les redirections.")
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard !stopped, navigationResponse.isForMainFrame, invitation.matchesPage(navigationResponse.response.url),
              let response = navigationResponse.response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType == "text/html", navigationResponse.canShowMIMEType else {
            decisionHandler(.cancel); fail("La page Messenger n’est pas disponible. Vérifiez la configuration du serveur."); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !stopped else { return }
        pollPage()
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !beganNavigation else {
            fail("La page Messenger a été rechargée. Demandez une nouvelle invitation Chat."); return
        }
        beganNavigation = true
        pageEpoch = UUID(); pageReady = false; connected = false; canStartMicrophone = false; pollPending = false; sending = false
        resetMicrophoneRequest()
        backgroundAudioReady = false; lastLiveAudio = nil
        if microphoneStartDeadline != nil { microphoneStatus = "Le micro sera demandé à la connexion." }
        navigationStarted = ProcessInfo.processInfo.systemUptime
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("Connexion Messenger impossible. Vérifiez le réseau, le certificat et le serveur.")
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("La conversation Messenger a été interrompue.")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("Messenger a été fermé par le système. Demandez une nouvelle invitation.") }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard !stopped, microphonePermissionRequested, UIApplication.shared.applicationState != .background,
              type == .microphone, frame.isMainFrame,
              invitation.matchesPage(frame.request.url), origin.protocol == "https",
              origin.host.lowercased() == invitation.url.host?.lowercased(),
              (origin.port == 0 ? 443 : origin.port) == (invitation.url.port ?? 443) else { decisionHandler(.deny); return }
        microphonePermissionRequested = false
        decisionHandler(.prompt)
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard !stopped, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == invitation.url.host?.lowercased(),
              challenge.protectionSpace.port == (invitation.url.port ?? 443),
              let host = invitation.url.host, let trust = challenge.protectionSpace.serverTrust,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        if let data = privateCA {
            guard let root = SecCertificateCreateWithData(nil, data as CFData),
                  SecTrustSetAnchorCertificates(trust, [root] as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        }
        guard SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first,
              Data(SHA384.hash(data: SecCertificateCopyData(leaf) as Data)) == invitation.tlsHash else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

@MainActor
private struct MessengerBrowser: UIViewRepresentable {
    let host: MessengerWebHost
    let messageTextSize: Double
    func makeUIView(context: Context) -> WKWebView {
        host.setMessageTextSize(messageTextSize)
        host.start()
        return host.webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { host.setMessageTextSize(messageTextSize) }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.setMicrophoneCaptureState(.none); uiView.setAllMediaPlaybackSuspended(true); uiView.stopLoading()
    }
}

@MainActor
struct MessengerConversationView: View {
    @ObservedObject var host: MessengerWebHost
    @ObservedObject var model: AgentModel
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var messageTextSize = 24.0
    @State private var draft = ""
    @FocusState private var composing: Bool
    var body: some View {
        NavigationStack {
            GeometryReader { space in
                // The geometry is measured inside the keyboard safe area.
                // Resize the history first and keep a single text field mounted.
                let compact = space.size.height < 360
                let inlineFinish = space.size.height < 190 && space.size.width >= 520
                VStack(spacing: 0) {
                    if !inlineFinish { finishBar(compact: compact).layoutPriority(2) }
                    if host.audioInterrupted {
                        Button(host.audioResuming ? "Reprise du son…" : "Reprendre le son",
                               action: { model.resumeMessengerAudio(host) })
                            .buttonStyle(AssistanceButtonStyle())
                            .accessibilityIdentifier("resumeMessengerAudio")
                            .accessibilityHint("Rétablit le microphone et le son de cette conversation.")
                            .disabled(host.audioResuming || !host.relayPaired)
                            .padding(.horizontal, compact ? 8 : 16)
                            .layoutPriority(2)
                    }
                    GeometryReader { history in
                        VStack(alignment: .leading, spacing: 8) {
                            if !compact {
                                ViewThatFits(in: .vertical) {
                                    microphoneControls.fixedSize(horizontal: false, vertical: true)
                                    ScrollView { microphoneControls }
                                }.frame(maxHeight: history.size.height * 0.45)
                            }
                            MessengerBrowser(host: host, messageTextSize: messageTextSize)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }.padding(.horizontal, compact ? 8 : 16)
                    }.clipped()
                    composer(compact: compact, inlineFinish: inlineFinish,
                             availableHeight: space.size.height, width: space.size.width)
                        .layoutPriority(1)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if composing {
                            Button { composing = false } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.title2).frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel("Masquer le clavier")
                        }
                        if compact && !host.audioInterrupted { compactMicrophoneButton }
                        if compact && model.sharing { ScreenVisibilityButton(model: model, compact: true) }
                        if model.broadcastID != nil || model.sharing {
                            Menu {
                                Button("Fermer seulement le chat") { model.closeMessenger() }
                            } label: {
                                Image(systemName: "ellipsis.circle").accessibilityLabel("Options du chat")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Séance d’assistance")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: host.audioInterrupted) { interrupted in
            if interrupted { composing = false }
        }
        .onDisappear { draft = "" }
    }
    private func finishBar(compact: Bool) -> some View {
        VStack(spacing: 4) {
            Button("Terminer", role: .destructive, action: finish)
                .buttonStyle(AssistanceButtonStyle(appearance: .destructive, emphasized: !compact))
                .accessibilityLabel("Terminer l’assistance")
                .accessibilityIdentifier("finishMessengerAssistance")
            if compact {
                compactSessionStatus
            } else if model.sharing {
                ScreenVisibilityButton(model: model)
            }
        }.padding(.horizontal, compact ? 8 : 16)
            .padding(.bottom, compact ? 4 : 8)
            .background(Color(uiColor: .systemBackground))
    }
    private var compactSessionStatus: some View {
        VStack(spacing: 2) {
            Text(host.invitation.operatorName).font(.caption.bold()).lineLimit(1)
            Text(host.connected ? "Chat connecté · " + host.microphone : host.status)
                .font(.caption).lineLimit(1)
            Text(screenStatus).font(.caption.bold()).lineLimit(1)
                .accessibilityIdentifier("assistanceState")
        }
    }
    private var screenStatus: String {
        model.broadcastID != nil || model.sharing ? model.connectionDisplayStatus : "Écran non partagé"
    }
    private func composer(compact: Bool, inlineFinish: Bool, availableHeight: CGFloat, width: CGFloat) -> some View {
        let stackControls = textSize.isAccessibilitySize && width < 600 && availableHeight >= 250
        let layout = stackControls
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
        return VStack(spacing: 6) {
            if inlineFinish {
                Text(screenStatus).font(.caption.bold()).lineLimit(1)
                    .accessibilityIdentifier("assistanceState")
            }
            if draft.utf8.count > 4096 {
                Text("Message trop long. Raccourcissez-le.").font(.caption).lineLimit(compact ? 1 : nil)
            } else if let error = host.sendError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(compact ? 1 : nil)
            }
            layout {
                TextField("Votre message", text: $draft,
                          prompt: Text("Votre message").foregroundColor(Color(uiColor: .secondaryLabel)), axis: .vertical)
                    .font(.title2)
                    .lineLimit(1...(compact ? 1 : 3))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.65)) }
                    .focused($composing)
                    .accessibilityIdentifier("messengerMessage")
                Button { sendDraft() } label: {
                    Text("Envoyer").font(.title3.bold())
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minHeight: 48)
                }.buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.06, green: 0.29, blue: 0.55))
                    .accessibilityIdentifier("sendMessengerMessage")
                    .disabled(!host.connected || host.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf8.count > 4096)
                if inlineFinish {
                    Button(role: .destructive, action: finish) {
                        Text("Terminer").font(.title3.bold())
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minHeight: 48)
                    }.buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.55, green: 0.08, blue: 0.15))
                        .accessibilityLabel("Terminer l’assistance")
                        .accessibilityIdentifier("finishMessengerAssistance")
                }
            }
            if !compact { SessionControlBar(model: model, showFinishAction: false) }
        }.padding(.horizontal, compact ? 8 : 16)
            .padding(.vertical, compact ? 4 : 8)
            .background(.regularMaterial)
    }
    private var microphoneInUse: Bool {
        host.webView.microphoneCaptureState == .active || host.webView.microphoneCaptureState == .muted
    }
    private var microphoneAction: String {
        guard microphoneInUse else { return "Activer le microphone" }
        return host.muted ? "Réactiver le microphone" : "Couper le microphone"
    }
    private var microphoneActionEnabled: Bool {
        microphoneInUse || (host.canStartMicrophone && !host.microphonePending)
    }
    private func performMicrophoneAction() {
        if microphoneInUse { host.toggleMute() } else { host.startMicrophone() }
    }
    private var compactMicrophoneButton: some View {
        Button(action: performMicrophoneAction) {
            Image(systemName: host.muted ? "mic.slash" : microphoneInUse ? "mic.fill" : "mic")
                .font(.title2).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(microphoneAction)
        .accessibilityValue(host.microphoneStatus.isEmpty ? host.microphone : "\(host.microphone). \(host.microphoneStatus)")
        .disabled(!microphoneActionEnabled)
    }
    private var microphoneControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(host.invitation.operatorName).font(.title2.bold())
            Text(host.microphone).font(.headline).accessibilityIdentifier("messengerMicrophone")
            Text(host.status)
            if let prompt = model.desktopPrompt, model.sharing {
                Text("Partage d’écran avec " + prompt.operatorName)
            }
            if model.broadcastID == nil && !model.sharing { Text(screenStatus) }
            if !host.microphoneStatus.isEmpty {
                Text(host.microphoneStatus).accessibilityIdentifier("messengerAudioStatus")
            }
            if host.backgroundAudio && !host.audioInterrupted {
                Text(host.canContinueAudioInBackground ? "Appel prêt pour le changement d’app." : "Attendez que le son fonctionne dans les deux sens avant de changer d’app.")
                    .font(.headline)
            }
            if !host.pageReady { ProgressView("Chargement de la conversation…") }
            if !host.audioInterrupted {
                Button(microphoneAction, action: performMicrophoneAction)
                    .buttonStyle(AssistanceButtonStyle(appearance: .secondary, emphasized: false))
                    .disabled(!microphoneActionEnabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func finish() {
        composing = false
        model.finishAssistance()
    }
    private func sendDraft() {
        let submitted = draft
        host.sendText(submitted) { success in
            if success && draft == submitted { draft = "" }
        }
    }
}

@MainActor
struct AssistanceHomeSection: View {
    @ObservedObject var model: AgentModel
    var body: some View {
        Section {
            VStack(spacing: 18) {
                Image(systemName: model.sharing ? "checkmark.shield.fill" : "ipad.and.iphone")
                    .font(.system(size: 48)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                Text(model.sharing ? "Assistance en cours" : "Besoin d’aide ?").font(.title2).bold()
                if model.broadcastID == nil && !model.sharing {
                    if AgentModel.isSimulator {
                        if !model.connecting {
                            Text(model.connected ? "En attente du technicien." : "Connectez le simulateur à votre serveur.")
                        }
                        if !model.connected && !model.connecting {
                            Button("Démarrer l’assistance") { model.connect() }
                                .buttonStyle(AssistanceButtonStyle())
                        }
                    } else {
                        if !model.connected && !model.connecting {
                            Button("Se connecter pour le chat") { model.connect() }
                                .buttonStyle(AssistanceButtonStyle()).accessibilityIdentifier("connectForChat")
                        } else if model.connected {
                            Text("En attente d’une invitation du technicien.").font(.headline)
                        }
                        Text("Le partage d’écran autorise le premier technicien habilité pendant dix minutes. Il peut conserver les images. Vous pouvez arrêter à tout moment.")
                        Button("Préparer le partage d’écran") { model.prepareBroadcast(approveFirstTechnician: true) }
                            .buttonStyle(AssistanceButtonStyle(appearance: .secondary))
                            .accessibilityIdentifier("startAssistance")
                        Text("À la connexion, le modèle et l’état matériel sont transmis à votre serveur.").foregroundStyle(.secondary)
                    }
                } else if model.broadcastStage == "prepared" {
                    Text("Touchez le bouton ci-dessous, puis confirmez « Lancer la diffusion » dans iPadOS.")
                    BroadcastPicker().frame(width: 64, height: 64).accessibilityLabel("Partager mon écran avec iPadOS")
                    Text("Prêt pendant encore \(model.preparationRemaining) s").font(.caption)
                } else if model.broadcastStage == "connecting" || model.broadcastStage == "starting" {
                    ProgressView("Connexion au technicien…")
                } else if model.broadcastStage == "ready" {
                    Text("Diffusion prête. Le technicien peut ouvrir Desktop ou demander une session dans Assistance iOS.")
                        .font(.headline)
                } else {
                    Text(model.sharing ? "Effectuez les gestes demandés par le technicien." : "En attente du technicien…")
                }
                if let prompt = model.desktopPrompt, !model.sharing, model.broadcastStage != "starting", model.broadcastStage != "stopping" {
                    Text("\(prompt.operatorName) demande à voir votre écran.")
                    Button("Autoriser cette assistance") { model.acceptDesktop() }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                    Button("Refuser", role: .destructive) { model.stopSharing(reason: "Demande refusée sur cet appareil.") }.frame(minHeight: 44)
                }
                if !model.sessionNotice.isEmpty { Text(model.sessionNotice).font(.footnote) }
                if model.stopUnconfirmed {
                    Text("Arrêtez d’abord la diffusion dans iPadOS.")
                    Button("J’ai arrêté la diffusion") { model.confirmSystemStopped() }
                        .buttonStyle(AssistanceButtonStyle(appearance: .secondary, emphasized: false))
                }
                if !model.activityNotice.isEmpty {
                    NavigationLink("Voir la demande du technicien", value: AgentDestination.assistance)
                }
            }.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 24)
        }
    }
}

private struct TransferStatusView: View {
    let title: String
    let progress: AssistanceTransfer
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title + " : " + progress.name).bold()
            Text(progress.label)
            if progress.state == .transferring {
                ProgressView(value: progress.fraction).accessibilityLabel(title).accessibilityValue("\(Int(progress.fraction * 100)) pour cent confirmés")
            }
        }.accessibilityElement(children: .combine)
    }
}

@MainActor
struct AssistanceStartSection: View {
    @ObservedObject var model: AgentModel
    var body: some View {
        Section("Démarrer une assistance") {
            if !model.sessionNotice.isEmpty { Text(model.sessionNotice) }
            if AgentModel.isSimulator {
                Text("Connectez l’app, puis ouvrez Assistance iOS dans la fiche MeshCentral de cet appareil et demandez une session. Le simulateur partage uniquement cette application.")
            } else if model.broadcastID == nil {
                Text("Vous autorisez le premier technicien habilité de votre serveur pour cette diffusion, limitée à dix minutes. Le destinataire peut conserver les images. Les documents et captures gardent leurs confirmations séparées.")
                Button(model.hasEndedAssistance ? "Relancer l’assistance avec mon accord" : "Préparer et autoriser l’assistance") { model.prepareBroadcast(approveFirstTechnician: true) }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
                    .accessibilityIdentifier("prepareAssistance")
                DisclosureGroup("Vérifier le technicien avant de partager") {
                    Text("Préparez la diffusion, puis revenez accepter le technicien affiché.")
                    Button("Préparer avec validation séparée") { model.prepareBroadcast() }.frame(minHeight: 44)
                }
            } else if model.broadcastStage == "prepared" {
                Text("Étape suivante : touchez le bouton de diffusion, puis « Lancer la diffusion » dans la fenêtre iPadOS.").font(.headline)
                BroadcastPicker().frame(width: 60, height: 60).accessibilityLabel("Ouvrir le sélecteur de diffusion iPadOS")
                Text("Préparation valable encore \(model.preparationRemaining) secondes. Aucun écran n’est envoyé avant la validation système et l’accord d’assistance.")
            } else if model.broadcastStage == "ready" {
                Text("Diffusion prête. Le technicien peut ouvrir Plugins → Assistance iOS, puis « Demander une session ».").font(.headline)
            } else if model.broadcastStage == "connecting" || model.broadcastStage == "starting" {
                ProgressView(model.connectionDisplayStatus)
            }
            if let prompt = model.desktopPrompt {
                Text("Technicien : " + prompt.operatorName).font(.headline)
                Text(prompt.recording ? "Le serveur enregistre la session." : "Le destinataire peut conserver les images.")
                if !model.sharing && model.broadcastStage != "starting" && model.broadcastStage != "stopping" {
                    Button("Autoriser cette assistance") { model.acceptDesktop() }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                    Button("Refuser", role: .destructive) { model.stopSharing(reason: "Demande refusée sur cet appareil.") }.frame(minHeight: 44)
                }
            }
            if model.stopUnconfirmed {
                Text("Utilisez d’abord le contrôle de diffusion iPadOS pour arrêter. Confirmez uniquement après son arrêt.")
                Button("J’ai arrêté la diffusion dans iPadOS") { model.confirmSystemStopped() }
                    .buttonStyle(AssistanceButtonStyle(appearance: .secondary, emphasized: false))
            }
        }
    }
}

@MainActor
struct SessionControlBar: View {
    @ObservedObject var model: AgentModel
    var showFinishAction = true
    var body: some View {
        if model.broadcastID != nil || model.sharing || (showFinishAction && (model.connected || model.connecting)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.connectionDisplayStatus).font(.headline).accessibilityIdentifier("assistanceState")
                if let remaining = model.sessionRemaining {
                    Text("Temps restant : \(remaining / 60) min \(remaining % 60) s").font(.caption).monospacedDigit()
                }
                if showFinishAction && model.sharing { ScreenVisibilityButton(model: model) }
                if showFinishAction && model.broadcastStage != "stopping" {
                    Button("Terminer", role: .destructive) { model.finishAssistance() }
                        .buttonStyle(AssistanceButtonStyle(appearance: .destructive))
                        .accessibilityLabel("Terminer l’assistance").accessibilityIdentifier("stopAssistance")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.regularMaterial)
        }
    }
}

@MainActor
private struct ScreenVisibilityButton: View {
    @ObservedObject var model: AgentModel
    var compact = false

    private var title: String {
        model.screenHidden ? "Partager de nouveau mon écran" : "Masquer mon écran"
    }

    var body: some View {
        Button(action: model.toggleScreenVisibility) {
            if compact {
                Image(systemName: model.screenHidden ? "eye.slash" : "eye")
                    .font(.title2).frame(minWidth: 44, minHeight: 44)
            } else {
                Text(model.pendingScreenVisibility == nil ? title : model.connectionDisplayStatus)
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .buttonStyle(.bordered)
        .disabled(model.pendingScreenVisibility != nil)
        .accessibilityLabel(title)
        .accessibilityValue(model.connectionDisplayStatus)
        .accessibilityIdentifier("screenVisibility")
    }
}

private struct CapturePreview: Identifiable {
    let id = UUID()
    let data: Data
    let strokes: [AnnotationStroke]
    let title: String
}
@MainActor
private struct CaptureDetail: View {
    let preview: CapturePreview
    @ObservedObject var model: AgentModel
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    if let image = UIImage(data: preview.data) {
                        AnnotatedCapture(image: image, strokes: preview.strokes)
                            .frame(width: max(1, geometry.size.width - 24) * CGFloat(zoom)).padding(12)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack {
                    HStack {
                        Button("Réduire") { zoom = max(1, zoom - 0.5) }.disabled(zoom <= 1).frame(minHeight: 44)
                        Button("Agrandir") { zoom = min(4, zoom + 0.5) }.disabled(zoom >= 4).frame(minHeight: 44)
                    }
                    SessionControlBar(model: model)
                }.background(.regularMaterial)
            }
            .navigationTitle(preview.title)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

@MainActor
private struct GuidedAssistanceSection: View {
    @ObservedObject var model: AgentModel
    let guide: GuidedStep
    let enlarge: (Data, [AnnotationStroke]) -> Void
    var body: some View {
        Section("Guidage — étape \(guide.step) sur \(guide.total)") {
            ProgressView(value: Double(guide.status == "done" ? guide.step : guide.step - 1), total: Double(guide.total))
            Text(guide.text).font(.headline).textSelection(.enabled)
            if let data = guide.capture, let image = UIImage(data: data) {
                AnnotatedCapture(image: image, strokes: guide.strokes)
                Button("Agrandir l’illustration") { enlarge(data, guide.strokes) }.frame(minHeight: 44)
                Text("Capture figée associée à cette étape.").font(.caption)
            }
            if guide.status == "waiting" || guide.status == "help" {
                if guide.status == "help" {
                    Label("Aide demandée. Le technicien peut répondre dans le chat ci-dessous.", systemImage: "questionmark.circle")
                }
                Button("Étape terminée") {
                    model.assist(AssistanceCommand(action: "guideDone", transferID: guide.id, step: guide.step))
                }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                Button("J’ai besoin d’aide") {
                    model.assist(AssistanceCommand(action: "guideHelp", transferID: guide.id, step: guide.step))
                }.disabled(guide.status == "help").frame(minHeight: 44)
            } else if guide.status == "done" {
                Label(guide.step == guide.total ? "Parcours terminé." : "Étape confirmée. Attendez la suivante.", systemImage: "checkmark.circle.fill")
            } else { Text("Guidage arrêté. Le chat reste disponible.") }
            if guide.status != "stopped" && !(guide.status == "done" && guide.step == guide.total) {
                Button("Arrêter le guidage", role: .destructive) {
                    model.assist(AssistanceCommand(action: "guideStop", transferID: guide.id, step: guide.step))
                }
            }
            Text("Effectuez vous-même les gestes dans Réglages ou l’app concernée, puis revenez ici pour confirmer. Le technicien ne touche pas votre écran.").font(.footnote)
        }
    }
}

struct AnnotatedCapture: View {
    let image: UIImage
    let strokes: [AnnotationStroke]
    var body: some View {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            .accessibilityLabel(strokes.isEmpty ? "Capture figée" : "Capture avec annotations du technicien")
            .overlay {
                GeometryReader { geometry in
                    Canvas { context, size in
                        for stroke in strokes {
                            var path = Path()
                            for (index, point) in stroke.points.enumerated() where point.count == 2 {
                                let position = CGPoint(x: point[0] * size.width, y: point[1] * size.height)
                                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                            }
                            context.stroke(path, with: .color(.red), lineWidth: 3)
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
    }
}
