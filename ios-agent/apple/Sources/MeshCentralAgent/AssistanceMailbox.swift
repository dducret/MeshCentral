// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum AssistanceMailboxError: Error, LocalizedError, Equatable {
    case groupNotConfigured, groupUnavailable, storageUnavailable

    public var errorDescription: String? {
        switch self {
        case .groupNotConfigured:
            return "Le groupe partagé de l’app n’est pas configuré. Faites vérifier MeshCentralAppGroup dans les Info.plist de l’app et de l’extension."
        case .groupUnavailable:
            return "Le conteneur App Group est inaccessible. Activez le même App Group pour MeshCentralIOS et MeshCentralBroadcast, y compris dans les profils de signature Release."
        case .storageUnavailable:
            return "Impossible de lire ou écrire dans le conteneur App Group. Déverrouillez l’appareil et vérifiez l’espace disponible et la configuration App Groups."
        }
    }
}

/// App Group IPC for user content. Never place documents in the credential
/// Keychain. One writer per atomic slot, request IDs prevent replay.
public enum AssistanceMailbox {
    private struct Envelope<T: Codable>: Codable {
        let session: UUID
        let updated: Date
        let payload: T
    }
    // The lookup is injected in unit tests; production always uses the signed
    // App Group container provided by iOS, never a fallback app directory.
    static func resolveContainer(group: String?, lookup: (String) -> URL?) throws -> URL {
        guard let group = group, group.hasPrefix("group."), group.count > 6,
              !group.contains("$("), !group.contains("${"),
              group == group.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AssistanceMailboxError.groupNotConfigured
        }
        guard let directory = lookup(group) else { throw AssistanceMailboxError.groupUnavailable }
        return directory
    }
    private static func container() throws -> URL {
        try resolveContainer(group: Bundle.main.object(forInfoDictionaryKey: "MeshCentralAppGroup") as? String,
            lookup: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) })
    }
    private static func file(_ slot: String, session: UUID) throws -> URL {
        let directory = try container()
        return directory.appendingPathComponent("assistance-" + session.uuidString + "-" + slot + ".json")
    }
    /// Verify app-side access before closing the ordinary control connection.
    /// This cannot prove the extension has the same signed entitlements.
    public static func validateAccess() throws { try checkAccess(to: container()) }
    static func checkAccess(to directory: URL) throws {
        let probe = directory.appendingPathComponent(".meshcentral-probe-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: probe) }
        do {
            let expected = Data([0x4d, 0x43])
            try expected.write(to: probe, options: [.atomic, .completeFileProtection])
            guard try Data(contentsOf: probe) == expected else { throw AssistanceMailboxError.storageUnavailable }
            try FileManager.default.removeItem(at: probe)
        } catch { throw AssistanceMailboxError.storageUnavailable }
    }
    private static func write<T: Codable>(_ payload: T, session: UUID, slot: String) throws {
        let bytes = try JSONEncoder().encode(Envelope(session: session, updated: Date(), payload: payload))
        guard bytes.count <= 6 * 1024 * 1024 else { throw AgentError.configuration }
        var destination = try file(slot, session: session)
        try bytes.write(to: destination, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try destination.setResourceValues(values)
    }
    private static func read<T: Codable>(_ type: T.Type, session: UUID, slot: String) throws -> T? {
        let url = try file(slot, session: session)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 6 * 1024 * 1024 + 1) ?? Data()
        guard bytes.count <= 6 * 1024 * 1024 else { throw AgentError.configuration }
        let item = try JSONDecoder().decode(Envelope<T>.self, from: bytes)
        guard item.session == session, (0...600).contains(Date().timeIntervalSince(item.updated)) else { return nil }
        return item.payload
    }
    public static func publish(_ snapshot: AssistanceSnapshot, session: UUID) throws { try write(snapshot, session: session, slot: "state") }
    public static func snapshot(session: UUID) throws -> AssistanceSnapshot? { try read(AssistanceSnapshot.self, session: session, slot: "state") }
    public static func command(_ command: AssistanceCommand, session: UUID) throws { try write(command, session: session, slot: "command") }
    public static func command(session: UUID) throws -> AssistanceCommand? { try read(AssistanceCommand.self, session: session, slot: "command") }
    public static func diagnostics(_ value: ConnectionDiagnostics, session: UUID) throws { try write(value, session: session, slot: "diagnostics") }
    public static func diagnostics(session: UUID) throws -> ConnectionDiagnostics? { try read(ConnectionDiagnostics.self, session: session, slot: "diagnostics") }
    public static func clear(session: UUID? = nil) throws {
        try clear(in: container(), session: session)
    }
    static func clear(in directory: URL, session: UUID? = nil) throws {
        let urls: [URL]
        if let session = session {
            urls = ["state", "command", "diagnostics"].map {
                directory.appendingPathComponent("assistance-" + session.uuidString + "-" + $0 + ".json")
            }
        } else {
            // Startup/preparation only. Include the three legacy 0.3 slots;
            // never delete unrelated files in the shared container.
            urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter {
                let name = $0.lastPathComponent
                if ["assistance-state.json", "assistance-command.json", "assistance-diagnostics.json"].contains(name) { return true }
                guard name.hasPrefix("assistance-") else { return false }
                return ["-state.json", "-command.json", "-diagnostics.json"].contains { suffix in
                    guard name.hasSuffix(suffix) else { return false }
                    let identifier = String(name.dropFirst(11).dropLast(suffix.count))
                    return UUID(uuidString: identifier) != nil
                }
            }
        }
        for url in urls {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
