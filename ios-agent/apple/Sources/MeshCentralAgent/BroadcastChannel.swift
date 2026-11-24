// SPDX-License-Identifier: Apache-2.0
import Foundation
import Security
import CryptoKit
import CMeshCore

public enum BroadcastConfigurationError: Error, LocalizedError {
    case keychainGroupMissing, extensionMissing, extensionConfiguration

    public var errorDescription: String? {
        switch self {
        case .keychainGroupMissing:
            return "Le groupe de trousseau partagé n’est pas configuré. Faites vérifier MeshCentralKeychainGroup et Keychain Sharing pour l’app et l’extension."
        case .extensionMissing:
            return "L’extension MeshCentral Screen est introuvable dans l’app installée. Vérifiez que MeshCentralBroadcast est intégrée et que son identifiant se termine par .Broadcast."
        case .extensionConfiguration:
            return "Les réglages de l’extension MeshCentral Screen ne correspondent pas à ceux de l’app. Vérifiez les Info.plist compilés et la configuration ReplayKit."
        }
    }
}

public struct BroadcastGrant: Codable {
    public let id: UUID
    public let created: Date
    public let enrollment: SavedEnrollment
    // Written only by the local app after an explicit quick-start button tap.
    // Absent in old grants => separate technician confirmation is required.
    public var approveFirstTechnician: Bool? = nil
    public var createdUptime: Double? = nil
}
public struct BroadcastStatus: Codable {
    public let id: UUID
    public var updated: Date
    public var stage: String
    public var prompt: DesktopPrompt?
    public var message: String?
    public var startedUptime: Double? = nil
    public var updatedUptime: Double? = nil
    public var messenger: MessengerInvitation? = nil
    public var messengerRejection: MessengerRejection? = nil
    public var screenVisibility: ScreenVisibilityRequest? = nil
}
public struct ScreenVisibilityRequest: Codable {
    public let id: UUID
    public let hidden: Bool
    public let createdUptime: Double

    public init(hidden: Bool) {
        id = UUID()
        self.hidden = hidden
        createdUptime = ProcessInfo.processInfo.systemUptime
    }
}
public struct BroadcastDecision: Codable {
    public let id: UUID
    public let request: UUID?
    public let action: String
}

/// A private Keychain mailbox shared only by the containing app and extension.
/// No app-group files or long-lived enrollment token; grants expire in 120 s.
public enum BroadcastChannel {
    // This extra slot is a revocation fence, not an additional permission.
    // A delayed extension must not publish into or authorize a newer broadcast.
    private struct Owner: Codable { let id: UUID; var revoked: Bool; var ended: Bool? = nil }
    private struct ScreenIntent: Codable { let owner: UUID; let request: ScreenVisibilityRequest }
    public static func currentID() throws -> UUID? { try get("owner", type: Owner.self)?.id }
    public static func isAuthorized(_ id: UUID) throws -> Bool {
        guard let owner = try get("owner", type: Owner.self) else { return false }
        return owner.id == id && !owner.revoked
    }
    public static func isComplete(_ id: UUID) throws -> Bool {
        guard let owner = try get("owner", type: Owner.self) else { return false }
        return owner.id == id && owner.revoked && owner.ended == true
    }
    public static func complete(_ id: UUID) throws {
        guard var owner = try get("owner", type: Owner.self), owner.id == id, owner.revoked else { throw AgentError.closed }
        owner.ended = true; try put(owner, account: "owner")
    }
    public static func pendingGrant(_ id: UUID) throws -> Bool { try get("grant", type: BroadcastGrant.self)?.id == id }
    public static var hostID: String { Bundle.main.object(forInfoDictionaryKey: "MeshCentralHostBundleID") as? String ?? Bundle.main.bundleIdentifier ?? "org.meshcentral.iosagent.demo" }
    public static var extensionID: String { hostID + ".Broadcast" }
    public static var accessGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MeshCentralKeychainGroup") as? String,
              !group.isEmpty, !group.contains("$("), !group.contains("${") else { return nil }
        return group
    }
    public static func identityTag(_ enrollment: Enrollment) -> String {
        let scope = enrollment.endpoint.absoluteString.lowercased() + enrollment.serverID.base64EncodedString()
        let hash = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return hostID + ".identity." + hash
    }
    private static func query(_ account: String) throws -> [String: Any] {
        guard let group = accessGroup else { throw BroadcastConfigurationError.keychainGroupMissing }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: hostID + ".broadcast",
                kSecAttrAccount as String: account, kSecAttrAccessGroup as String: group]
    }
    private static func put<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 65536 else { throw AgentError.configuration }
        let query = try query(account)
        let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw AgentError.keychain(status) }
    }
    private static func get<T: Decodable>(_ account: String, type: T.Type) throws -> T? {
        var query = try query(account)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 65536 else { throw AgentError.keychain(status) }
        return try JSONDecoder().decode(type, from: data)
    }
    private static func remove(_ account: String) throws {
        let status = SecItemDelete(try query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AgentError.keychain(status) }
    }
    public static func prepare(_ enrollment: SavedEnrollment, approveFirstTechnician: Bool = false) throws -> UUID {
        _ = try enrollment.validated()
        if let owner = try get("owner", type: Owner.self), !(owner.revoked && owner.ended == true) { throw AgentError.configuration }
        let grant = BroadcastGrant(id: UUID(), created: Date(), enrollment: enrollment,
            approveFirstTechnician: approveFirstTechnician, createdUptime: ProcessInfo.processInfo.systemUptime)
        try remove("decision"); try remove("status"); try remove("screenIntent")
        try put(Owner(id: grant.id, revoked: false), account: "owner")
        do { try put(grant, account: "grant") }
        catch { try? put(Owner(id: grant.id, revoked: true, ended: true), account: "owner"); throw error }
        return grant.id
    }
    public static func takeGrant() throws -> BroadcastGrant {
        guard let grant = try get("grant", type: BroadcastGrant.self) else { throw AgentError.configuration }
        try remove("grant")
        guard let uptime = grant.createdUptime,
              BroadcastTiming.policy(phase: 0, since: uptime) == 0,
              (0..<120).contains(Date().timeIntervalSince(grant.created)),
              try isAuthorized(grant.id) else { throw AgentError.timeout }
        _ = try grant.enrollment.validated()
        return grant
    }
    public static func status() throws -> BroadcastStatus? { try get("status", type: BroadcastStatus.self) }
    public static func publish(_ status: BroadcastStatus) throws {
        guard try currentID() == status.id else { throw AgentError.closed }
        // A revoked owner can acknowledge stop, never publish live state again.
        if status.stage != "stopped" { guard try isAuthorized(status.id) else { throw AgentError.closed } }
        try put(status, account: "status")
    }
    public static func revoke(_ id: UUID) throws {
        guard var owner = try get("owner", type: Owner.self), owner.id == id else { return }
        if !owner.revoked { owner.revoked = true; try put(owner, account: "owner") }
        try decide(id: id, request: nil, action: "stop")
    }
    public static func decide(id: UUID, request: UUID?, action: String) throws {
        guard ["approve", "reject", "stop"].contains(action), try currentID() == id else { throw AgentError.closed }
        if action == "approve" { guard try isAuthorized(id) else { throw AgentError.closed } }
        try put(BroadcastDecision(id: id, request: request, action: action), account: "decision")
        if action == "stop" { try remove("grant") }
    }
    public static func decision() throws -> BroadcastDecision? {
        // Non-destructive reads: deleting after a read could erase a newer stop
        // written concurrently by the UI. Consumer state makes actions idempotent.
        try get("decision", type: BroadcastDecision.self)
    }
    public static func requestScreenVisibility(_ request: ScreenVisibilityRequest, owner: UUID) throws {
        guard try isAuthorized(owner) else { throw AgentError.closed }
        try put(ScreenIntent(owner: owner, request: request), account: "screenIntent")
    }
    public static func screenVisibilityRequest(owner: UUID) throws -> ScreenVisibilityRequest? {
        guard let intent = try get("screenIntent", type: ScreenIntent.self), intent.owner == owner else { return nil }
        return intent.request
    }
}

/// Native clock adapter for the portable, revocation-only Rust policy.
public enum BroadcastTiming {
    static func milliseconds(since start: Double, now: Double) -> UInt64 {
        guard start.isFinite, now.isFinite, start >= 0, now >= start else { return UInt64.max }
        return UInt64(min(1_000_000_000, (now - start) * 1000))
    }
    public static func policy(phase: UInt32, since start: Double, heartbeat: Double? = nil,
                              now: Double = ProcessInfo.processInfo.systemUptime) -> UInt32 {
        mc_broadcast_policy(phase, milliseconds(since: start, now: now),
            heartbeat.map { milliseconds(since: $0, now: now) } ?? 0)
    }
    public static func remaining(phase: UInt32, since start: Double,
                                 now: Double = ProcessInfo.processInfo.systemUptime) -> Int {
        Int((mc_broadcast_remaining_ms(phase, milliseconds(since: start, now: now)) + 999) / 1000)
    }
}
