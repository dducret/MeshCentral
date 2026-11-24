// SPDX-License-Identifier: Apache-2.0
import Foundation
import CoreFoundation
import CMeshCore

/// Allowlisted local diagnosis only: never retains an invitation URL or user ID.
public enum MessengerInvitationError: String, Error, Codable {
    case command, address, origin, identity, rights
    public var message: String {
        switch self {
        case .command: return "Commande Chat reçue mais non reconnue. Faites vérifier la version du serveur."
        case .address: return "Invitation Chat reçue, mais son lien Messenger est invalide ou contient des paramètres inattendus."
        case .origin: return "Invitation Chat reçue, mais son serveur, son port ou son chemin diffère de l’enrôlement. Vérifiez l’adresse publique et le port HTTPS configurés sur le serveur."
        case .identity: return "Invitation Chat reçue, mais elle ne correspond pas à cet iPad et à son domaine, ou l’identité du technicien est invalide."
        case .rights: return "Invitation Chat reçue, mais les droits Chat et accès distant du technicien sont absents ou invalides."
        }
    }
}
public struct MessengerRejection: Codable, Identifiable {
    public let id: UUID
    public let reason: MessengerInvitationError
    public init(_ reason: MessengerInvitationError) { self.id = UUID(); self.reason = reason }
}

/// A server-authenticated invitation, never an arbitrary remote browser command.
public struct MessengerInvitation: Codable, Identifiable {
    public let id: UUID
    public let createdUptime: Double
    public let url: URL
    public let operatorName: String
    public let tlsHash: Data

    static func parse(_ object: [String: Any], enrollment: Enrollment, controlTLS: Data,
                      nodeKey: String) throws -> MessengerInvitation {
        guard isCommand(object), controlTLS.count == 48 else { throw MessengerInvitationError.command }
        guard
              let address = object["url"] as? String, address.utf8.count <= 4096,
              let parts = URLComponents(string: address), let base = URLComponents(url: enrollment.endpoint, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1, items[0].name == "id", let identifier = items[0].value
              else { throw MessengerInvitationError.address }
        guard parts.scheme == "https", parts.host?.lowercased() == base.host?.lowercased(),
              (parts.port ?? 443) == (base.port ?? 443),
              parts.percentEncodedPath == base.path.replacingOccurrences(of: "agent.ashx", with: "messenger")
              else { throw MessengerInvitationError.origin }
        guard let user = object["userid"] as? String, user.utf8.count <= 512,
              object["guestname"] == nil, object["guestuserid"] == nil else { throw MessengerInvitationError.identity }
        guard
              let rights = object["rights"] as? NSNumber, CFGetTypeID(rights) != CFBooleanGetTypeID(),
              rights.doubleValue >= 0, rights.doubleValue <= Double(UInt32.max), rights.doubleValue == Double(rights.uint32Value),
              rights.uint32Value & 0x4000 != 0, rights.uint32Value & 0x108 != 0 else { throw MessengerInvitationError.rights }
        let domain = base.path.split(separator: "/").dropLast().map(String.init).first ?? ""
        let node = Array(("node/" + domain + "/" + nodeKey).utf8)
        let userBytes = Array(user.utf8), idBytes = Array(identifier.utf8)
        guard mc_messenger_validate(idBytes, idBytes.count, node, node.count, userBytes, userBytes.count, rights.uint32Value) == 1,
              let url = parts.url else { throw MessengerInvitationError.identity }
        let names = [object["realname"] as? String, object["username"] as? String, user.split(separator: "/").last.map(String.init)]
        let name = names.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.utf8.count <= 256 && $0.rangeOfCharacter(from: .controlCharacters) == nil } ?? "Technicien"
        return MessengerInvitation(id: UUID(), createdUptime: ProcessInfo.processInfo.systemUptime,
                                   url: url, operatorName: name, tlsHash: controlTLS)
    }
    static func isCommand(_ object: [String: Any]) -> Bool {
        object["action"] as? String == "openUrl" ||
            (object["action"] as? String == "msg" && object["type"] as? String == "openUrl")
    }
    /// WebKit may remove :443 or normalize percent encoding. Compare the exact
    /// enrolled page/ID semantically, never an arbitrary same-origin URL.
    public func matchesPage(_ candidate: URL?) -> Bool {
        guard let candidate = candidate, candidate.absoluteString.utf8.count <= 4096,
              let expected = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let actual = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              actual.scheme?.lowercased() == "https", actual.host?.lowercased() == expected.host?.lowercased(),
              (actual.port ?? 443) == (expected.port ?? 443), actual.user == nil, actual.password == nil,
              actual.fragment == nil, actual.percentEncodedPath == expected.percentEncodedPath,
              let query = actual.queryItems, let original = expected.queryItems,
              query.count == 1, original.count == 1, original[0].name == "id", original[0].value != nil,
              query[0].name == "id", query[0].value == original[0].value
              else { return false }
        return true
    }
}

/// Main-thread owner of the Rust consent state. A dismissed invitation cannot reopen.
public final class MessengerConsent {
    private let handle = mc_messenger_new()
    private let created: Double
    public init(_ invitation: MessengerInvitation) { created = invitation.createdUptime }
    deinit { mc_messenger_free(handle) }
    public func event(_ event: UInt32 = 0, connected: Bool, foreground: Bool,
                      now: Double = ProcessInfo.processInfo.systemUptime) -> Int32 {
        mc_messenger_event(handle, event, BroadcastTiming.milliseconds(since: created, now: now),
                           connected ? 1 : 0, foreground ? 1 : 0)
    }
    public func accept(connected: Bool, foreground: Bool, backgroundAudio: Bool) -> Int32 {
        event(backgroundAudio ? 3 : 1, connected: connected, foreground: foreground)
    }
    public func pollBackgroundAudio(connected: Bool, interrupted: Bool = false) -> Int32 {
        event(interrupted ? 5 : 4, connected: connected, foreground: false)
    }
}

public struct DesktopPrompt: Codable, Identifiable {
    public let id: UUID
    public let operatorName: String
    public let userID: String
    public let recording: Bool
}

struct DesktopRequest {
    let url: URL
    let userID: String
    let operatorName: String
    let rights: UInt32
    let tlsHash: Data

    static func parse(_ object: [String: Any], enrollment: Enrollment, controlTLS: Data) throws -> DesktopRequest {
        guard object["action"] as? String == "msg", object["type"] as? String == "tunnel",
              let address = object["value"] as? String, address.utf8.count <= 8192,
              let number = object["rights"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= Double(UInt32.max),
              number.doubleValue == Double(number.uint32Value),
              number.uint32Value == UInt32.max || (number.uint32Value & 0x108 != 0 && number.uint32Value & 0x10000 == 0),
              let user = object["userid"] as? String, user.utf8.count <= 512,
              user.hasPrefix("user/"), user.rangeOfCharacter(from: .controlCharacters) == nil,
              object["guestname"] == nil, object["guestuserid"] == nil,
              ["tcpaddr", "tcpport", "udpaddr", "udpport"].allSatisfy({ object[$0] == nil }),
              let base = URLComponents(url: enrollment.endpoint, resolvingAgainstBaseURL: false) else { throw AgentError.configuration }
        let domain = base.path.split(separator: "/").dropLast().map(String.init).first ?? ""
        let userParts = user.split(separator: "/", omittingEmptySubsequences: false)
        guard userParts.count == 3, userParts[1] == domain, !userParts[2].isEmpty else { throw AgentError.configuration }
        if let usage = object["usage"] as? Int, usage != 2 { throw AgentError.configuration }
        if let options = object["soptions"] as? [String: Any], let usages = options["usages"] {
            guard let values = usages as? [Int], values.contains(2) else { throw AgentError.configuration }
        }
        var origin = base; origin.path = ""; origin.query = nil
        guard let originURL = origin.url else { throw AgentError.configuration }
        let resolved = address.hasPrefix("*/") ? originURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + String(address.dropFirst()) : address
        guard let parts = URLComponents(string: resolved), parts.scheme == "wss",
              parts.host?.lowercased() == base.host?.lowercased(), (parts.port ?? 443) == (base.port ?? 443),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.percentEncodedPath == base.path.replacingOccurrences(of: "agent.ashx", with: "meshrelay.ashx"),
              let items = parts.queryItems, Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ ["p", "id", "rauth", "nodeid"].contains($0.name) }),
              items.first(where: { $0.name == "p" })?.value == "2",
              let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty, id.utf8.count <= 256,
              let auth = items.first(where: { $0.name == "rauth" })?.value, !auth.isEmpty, auth.utf8.count <= 4096,
              let url = parts.url else { throw AgentError.configuration }
        if let node = items.first(where: { $0.name == "nodeid" })?.value {
            guard node.hasPrefix("node/" + domain + "/"), node.utf8.count <= 256 else { throw AgentError.configuration }
        }
        var name = object["realname"] as? String ?? object["username"] as? String ?? String(userParts[2])
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 256, name.rangeOfCharacter(from: .controlCharacters) == nil else { throw AgentError.configuration }
        let hash: Data
        if let supplied = object["servertlshash"] {
            guard let value = supplied as? String, value.utf8.count == 96 else { throw AgentError.configuration }
            hash = try EnrollmentImport.identifier(value)
        } else { hash = controlTLS }
        return DesktopRequest(url: url, userID: user, operatorName: name, rights: number.uint32Value, tlsHash: hash)
    }
}
