// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct MeshCentralIOSApp: App {
    @StateObject private var model = AgentModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AgentView(model: model)
                .onChange(of: scenePhase) { phase in
                    if phase == .background { model.background() }
                    if phase == .active { model.foreground() }
                }
        }
    }
}

enum AgentDestination: Hashable { case options, assistance }

@MainActor
struct AgentView: View {
    @ObservedObject var model: AgentModel
    @State private var importing = false
    @State private var importingCA = false
    @State private var path: [AgentDestination] = []
    var body: some View {
        Group {
            if let host = model.messengerHost {
                MessengerConversationView(host: host, model: model).id(host.id)
            } else if model.sharing {
                NavigationStack { AssistanceView(model: model) }
            } else {
                home
            }
        }
        .onChange(of: model.finishRevision) { _ in path.removeAll() }
        .accessibilityHidden(model.messengerInvitation != nil)
        .allowsHitTesting(model.messengerInvitation == nil)
        .safeAreaInset(edge: .top, spacing: 0) { MessengerAttentionBanner(model: model) }
        .overlay {
            if let invitation = model.messengerInvitation {
                MessengerInvitationView(model: model, operatorName: invitation.operatorName)
                    .id(invitation.id)
            }
        }
    }

    private var home: some View {
        NavigationStack(path: $path) {
            Form {
                if model.profile != nil {
                    AssistanceHomeSection(model: model)
                } else {
                    Section("Enrôler cet appareil") {
                        TextField("Nom de l’appareil", text: $model.deviceName)
                        Text("Collez le lien d’invitation HTTPS fourni par votre administrateur, un lien mc:// ou le contenu d’un fichier .msh.")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextEditor(text: $model.input).frame(minHeight: 100)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Lien ou configuration d’enrôlement")
                            .privacySensitive()
                        Button("Importer un fichier .msh") { importingCA = false; importing = true }
                        Button("Lire l’invitation") { model.prepareImport() }
                            .disabled(model.input.isEmpty || model.busy)
                        if model.busy { ProgressView("Lecture sécurisée de l’invitation…") }
                    }.disabled(model.busy)
                    Section {
                        DisclosureGroup("Configuration manuelle") {
                            TextField("wss://serveur/agent.ashx", text: $model.endpoint)
                            TextField("ServerID", text: $model.serverID)
                            TextField("MeshID", text: $model.meshID)
                            Button("Vérifier les paramètres") { model.prepareManual() }
                        }.textInputAutocapitalization(.never).autocorrectionDisabled()
                        DisclosureGroup("Autorité de certification privée") {
                            Text("Uniquement si votre administrateur vous a fourni un certificat public d’autorité au format .crt, .cer ou PEM.")
                                .font(.footnote)
                            Button("Importer un certificat") { importingCA = true; importing = true }
                            if model.privateCA != nil {
                                Label("Certificat importé", systemImage: "checkmark.seal")
                                Button("Retirer le certificat", role: .destructive) { model.clearCA() }
                            }
                        }
                    }.disabled(model.busy)
                    if let candidate = model.candidate {
                        Section("Vérifier avant d’enregistrer") {
                            Text(candidate.endpoint).textSelection(.enabled)
                            LabeledContent("Appareil", value: candidate.deviceName)
                            Text("Empreinte du serveur : " + candidate.serverID.map { String(format: "%02x", $0) }.joined())
                                .font(.caption.monospaced()).textSelection(.enabled)
                            Text("Enregistrez uniquement les paramètres d’un administrateur de confiance. Vous choisirez ensuite quand vous connecter.")
                                .font(.footnote)
                            Button("Enregistrer l’enrôlement") { model.saveCandidate() }
                        }
                    }
                }
                if let error = model.error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle(model.profile == nil ? "MeshCentral" : "Assistance")
            .toolbar {
                if model.profile != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink(value: AgentDestination.options) {
                            Image(systemName: "gearshape").accessibilityLabel("Options")
                        }
                    }
                }
            }
            .navigationDestination(for: AgentDestination.self) { destination in
                switch destination {
                case .options: AgentOptionsView(model: model)
                case .assistance: AssistanceView(model: model)
                }
            }
            .safeAreaInset(edge: .bottom) { SessionControlBar(model: model) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .plainText]) { result in
                switch result {
                case .success(let url): model.readFile(url, asCertificate: importingCA)
                case .failure(let error): model.error = AgentModel.message(error)
                }
            }

        }
    }
}

@MainActor
private struct AgentOptionsView: View {
    @ObservedObject var model: AgentModel
    @Environment(\.dismiss) private var dismiss
    @State private var showForget = false
    var body: some View {
        Form {
            if let profile = model.profile {
                Section("Connexion") {
                    LabeledContent("Appareil", value: profile.deviceName)
                    Text(profile.endpoint).font(.footnote).textSelection(.enabled)
                    Label(model.connectionDisplayStatus, systemImage: model.connectionDisplayActive ? "checkmark.shield.fill" : "shield")
                        .accessibilityIdentifier("connectionStatus")
                    Text("La connexion communique au serveur le modèle, la mémoire, les cœurs et la batterie. L’inventaire reste consultable après la déconnexion.").font(.footnote)
                }
                Section("Outils") {
                    NavigationLink("Guidage, échanges et diagnostics", value: AgentDestination.assistance)
                    if !AgentModel.isSimulator && model.broadcastID == nil {
                        Button("Choisir le technicien avant de partager") { model.prepareBroadcast(); dismiss() }.frame(minHeight: 44)
                    }
                }
                Section {
                    Text(MessengerWebHost.supportsBackgroundAudio
                         ? "Vous pouvez choisir de garder le son d’un appel quand vous changez d’app. La diffusion d’écran reste indépendante."
                         : "Le chat vocal se ferme lorsque vous quittez l’app. La diffusion d’écran suit les contrôles système.")
                        .font(.footnote)
                    Button("Changer d’enrôlement", role: .destructive) { showForget = true }
                        .disabled(model.broadcastID != nil)
                }
            }
        }.navigationTitle("Options")
        .safeAreaInset(edge: .bottom) { SessionControlBar(model: model) }
        .confirmationDialog("Oublier cet enrôlement ?", isPresented: $showForget, titleVisibility: .visible) {
            Button("Oublier et se déconnecter", role: .destructive) { model.forget(); dismiss() }
        } message: { Text("Les paramètres seront retirés de l’app. L’identité reste dans le trousseau et l’appareil n’est pas supprimé du serveur.") }
    }
}
