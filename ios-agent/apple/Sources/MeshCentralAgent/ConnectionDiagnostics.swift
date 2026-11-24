// SPDX-License-Identifier: Apache-2.0
import Foundation
import CMeshCore
#if canImport(UIKit)
import UIKit
#endif
import Darwin
import CryptoKit

public struct VideoProfile {
    public let interval: Double
    public let longSide: Double
    public let shortSide: Double
    public let quality: Double
    public static func level(_ level: UInt32) -> VideoProfile {
        switch level {
        case 0: return VideoProfile(interval: 1, longSide: 640, shortSide: 360, quality: 0.30)
        case 2: return VideoProfile(interval: 1.0 / 3, longSide: 1600, shortSide: 900, quality: 0.65)
        default: return VideoProfile(interval: 0.5, longSide: 1280, shortSide: 720, quality: 0.50)
        }
    }
}

/// Minimal inventory for the standard MeshCentral Details tab. Never includes
/// UIDevice.name, identifiers, storage, network addresses or boot time.
struct HardwareInventory: Sendable {
    var model: String
    var machine: String
    var memoryBytes: UInt64
    var processors: UInt32
    var architecture: UInt32
    var simulator: Bool
    var batteryPercent: Int32
    var batteryState: UInt32

    static func percentage(_ level: Float) -> Int32 {
        guard level.isFinite, (0...1).contains(level) else { return -1 }
        return Int32((level * 100).rounded())
    }

    /// UIKit access is confined to the main queue, including in ReplayKit.
    @MainActor static func collect() -> HardwareInventory? {
        dispatchPrecondition(condition: .onQueue(.main))
        #if canImport(UIKit)
        let device = UIDevice.current
        var system = utsname()
        let machine: String
        if uname(&system) == 0 {
            machine = withUnsafeBytes(of: &system.machine) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
        } else { machine = "unknown" }
        #if arch(arm64)
        let architecture: UInt32 = 1
        #elseif arch(x86_64)
        let architecture: UInt32 = 2
        #else
        let architecture: UInt32 = 0
        #endif
        #if targetEnvironment(simulator)
        // Host RAM, cores and battery must never masquerade as iPad hardware.
        return HardwareInventory(model: device.model, machine: machine, memoryBytes: 0,
            processors: 0, architecture: architecture, simulator: true, batteryPercent: -1, batteryState: 0)
        #else
        let monitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = monitoring }
        return HardwareInventory(model: device.model, machine: machine,
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            processors: UInt32(clamping: ProcessInfo.processInfo.processorCount),
            architecture: architecture, simulator: false, batteryPercent: percentage(device.batteryLevel),
            batteryState: UInt32(clamping: device.batteryState.rawValue))
        #endif
        #else
        return nil
        #endif
    }

    func body() -> Data? {
        let model = Array(model.utf8), machine = Array(machine.utf8)
        var output = [UInt8](repeating: 0, count: 2048)
        let count = model.withUnsafeBufferPointer { m in machine.withUnsafeBufferPointer { d in
            mc_inventory_write(m.baseAddress, m.count, d.baseAddress, d.count, memoryBytes, processors,
                architecture, simulator ? 1 : 0, batteryPercent, batteryState, &output, 2048)
        } }
        return count > 0 ? Data(output.prefix(count)) : nil
    }

    func message(ifDifferentFrom previousHash: String?) -> Data? {
        guard let body = body(), var data = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        let hash = SHA384.hash(data: body).map { String(format: "%02x", $0) }.joined()
        guard previousHash != hash else { return nil }
        data["hash"] = hash
        return try? JSONSerialization.data(withJSONObject: ["action": "sysinfo", "data": data], options: [.sortedKeys])
    }
}
/// Deliberate allowlist: no URL, account, device name, content, credential or key.
public struct ConnectionDiagnostics: Codable {
    public var version = "0.5.2"
    public var stage = "disconnected"
    public var tlsVerified = false
    public var frames: UInt64 = 0
    public var bytes: UInt64 = 0
    public var fps = 0.0
    public var kilobitsPerSecond = 0.0
    public var roundTripMS = 0.0
    public var sendMS = 0.0
    public var qualityLevel: UInt32 = 1
    public var lastError = ""
    // Optional for compatibility with existing App Group snapshots.
    public var networkState: String?
    public var networkInterface: String?
    public var constrained: Bool?
    public var expensive: Bool?
    public var lowPower: Bool?
    public var thermalState: UInt32?
    public var frameAgeMS: Double?
    public var healthCode: UInt32?
    public var osVersion: String?
    public var featureVersion: String?
    public var remainingSeconds: Int?
    public init() {}
    public static func errorCode(_ error: Error?) -> String {
        guard let error = error else { return "" }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet: return "network_offline"
            case .networkConnectionLost: return "network_lost"
            case .cannotFindHost, .dnsLookupFailed: return "dns_failed"
            case .timedOut: return "timeout"
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .secureConnectionFailed: return "tls_failed"
            default: return "network_failed"
            }
        }
        if let error = error as? AgentError {
            switch error {
            case .cryptography: return "identity_failed"
            case .protocolViolation: return "protocol_failed"
            case .timeout: return "timeout"
            case .closed: return "connection_closed"
            case .configuration, .keychain: return "configuration_failed"
            }
        }
        return "internal_error"
    }
    public mutating func assess(frameAge: Double) {
        func bounded(_ value: Double) -> Double { value.isFinite ? min(600000, max(0, value)) : 0 }
        frameAgeMS = bounded(frameAge * 1000)
        let network: UInt32 = ["available": 1, "unavailable": 2, "requiresConnection": 3][networkState ?? ""] ?? 0
        healthCode = mc_connection_health(network, UInt32(frameAgeMS ?? 0),
            UInt32(bounded(roundTripMS)), UInt32(bounded(sendMS)),
            constrained == true ? 1 : 0, thermalState ?? 0)
    }
    public var recommendation: String {
        switch healthCode ?? 0 {
        case 1: return "Vérifiez la connexion Wi-Fi ou cellulaire. Une nouvelle session demandera votre accord."
        case 2: return "Aucune image récente. Vérifiez que la diffusion iPadOS est active et que l’appareil est déverrouillé."
        case 3: return "Le relais répond lentement. La qualité s’adapte ; rapprochez-vous du point d’accès si possible."
        case 4: return "Le réseau utilise le mode Faibles données. La fluidité peut être réduite."
        case 5: return "L’appareil chauffe. Laissez-le refroidir et évitez les applications exigeantes."
        default: return "Aucun problème détecté dans les mesures disponibles."
        }
    }
    public var stageLabel: String {
        ["disconnected": "Déconnecté", "connecting": "Connexion en cours", "authenticated": "Connexion sécurisée établie",
         "broadcast_prepared": "Prêt à lancer la diffusion iPadOS", "sharing": "Écran partagé",
         "stopping": "Arrêt demandé", "closed": "Session terminée", "stopped": "Arrêté", "failed": "Connexion échouée"][stage] ?? "État en cours de vérification"
    }
    public var networkLabel: String {
        let interface = ["wifi": "Wi-Fi", "cellular": "Cellulaire", "ethernet": "Ethernet", "other": "Autre interface"][networkInterface ?? ""] ?? "Non communiqué"
        let state = ["available": "disponible", "unavailable": "indisponible", "requiresConnection": "connexion à établir"][networkState ?? ""] ?? "état inconnu"
        return interface + " — " + state
    }
    public var errorLabel: String {
        switch lastError {
        case "network_offline", "network_lost": return "Connexion réseau interrompue. Vérifiez le Wi-Fi puis relancez l’assistance."
        case "dns_failed": return "Le nom du serveur n’a pas pu être résolu. Vérifiez le réseau et l’adresse configurée."
        case "tls_failed", "identity_failed": return "La connexion sécurisée n’a pas pu être vérifiée. Faites contrôler le serveur et ses certificats."
        case "timeout": return "Le délai de réponse est dépassé. Vérifiez le réseau et la diffusion."
        case "configuration_failed": return "Configuration ou stockage sécurisé inaccessible. Déverrouillez l’appareil et faites vérifier la configuration."
        case "protocol_failed": return "Les données reçues ne correspondent pas au protocole attendu. Faites vérifier les versions."
        case "connection_closed": return "La connexion est fermée. Toute relance exige votre accord."
        default: return "L’opération a échoué. Consultez le technicien avant de relancer."
        }
    }
    public func report() -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
