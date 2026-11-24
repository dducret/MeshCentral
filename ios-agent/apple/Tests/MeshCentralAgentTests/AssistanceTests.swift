// SPDX-License-Identifier: Apache-2.0
import XCTest
import Foundation
import CryptoKit
#if canImport(MeshCentralAgent)
@testable import MeshCentralAgent
#else
@testable import MeshCentralIOS
#endif

final class AssistanceTests: XCTestCase {
    func testMessengerPageAcceptsOnlyEquivalentNormalizedURLs() {
        let id = "meshmessenger/node%2F%2F" + String(repeating: "A", count: 64) + "/user%2F%2Ftech"
        let url = URL(string: "https://example.invalid:443/messenger?id=" + id)!
        let invitation = MessengerInvitation(id: UUID(), createdUptime: 0, url: url,
            operatorName: "Test", tlsHash: Data(repeating: 1, count: 48))
        XCTAssertTrue(invitation.matchesPage(url))
        let normalized = "https://example.invalid/messenger?id=" + id.replacingOccurrences(of: "%2F", with: "/")
        XCTAssertTrue(invitation.matchesPage(URL(string: normalized)))
        XCTAssertTrue(invitation.matchesPage(URL(string: "https://EXAMPLE.invalid/messenger?id=" + id.replacingOccurrences(of: "%2F", with: "%2f"))))
        for changed in [normalized + "&auth=synthetic", normalized + "&id=duplicate", normalized + "#fragment",
                        normalized.replacingOccurrences(of: "https:", with: "http:"),
                        normalized.replacingOccurrences(of: "example.invalid", with: "other.invalid"),
                        normalized.replacingOccurrences(of: "example.invalid", with: "example.invalid:8443"),
                        normalized.replacingOccurrences(of: "example.invalid", with: "user@example.invalid"),
                        normalized.replacingOccurrences(of: "/messenger?", with: "/other?"),
                        normalized.replacingOccurrences(of: "/tech", with: "/other")] {
            XCTAssertFalse(invitation.matchesPage(URL(string: changed)), changed)
        }
        XCTAssertFalse(invitation.matchesPage(nil))
    }
    func testMessengerDefaultDomainEncodedIDAndEmptyRealName() throws {
        let enrollment = try Enrollment(endpoint: URL(string: "wss://example.invalid/agent.ashx")!,
            serverID: Data(repeating: 1, count: 48), meshID: Data(repeating: 2, count: 48), architectureID: 10005, deviceName: "Test")
        let key = "@$" + String(repeating: "A", count: 62)
        let address = "https://example.invalid:443/messenger?id=meshmessenger/node%2F%2F%40%24" + String(repeating: "A", count: 62) + "/user%2F%2Ftech"
        var value: [String: Any] = ["action": "openUrl", "url": address, "userid": "user//tech",
                                  "rights": UInt32.max, "username": "Technicien", "realname": "   "]
        func parse() throws -> MessengerInvitation {
            try MessengerInvitation.parse(value, enrollment: enrollment, controlTLS: Data(repeating: 3, count: 48), nodeKey: key)
        }
        XCTAssertEqual(try parse().operatorName, "Technicien")
        value["action"] = "msg"; value["type"] = "openUrl"
        XCTAssertEqual(try parse().operatorName, "Technicien")
        value["url"] = address + "&auth=synthetic-operator-token"
        XCTAssertThrowsError(try parse()) { XCTAssertEqual($0 as? MessengerInvitationError, .address) }
        value["url"] = address.replacingOccurrences(of: ":443/", with: ":8443/")
        XCTAssertThrowsError(try parse()) { XCTAssertEqual($0 as? MessengerInvitationError, .origin) }
        value["url"] = address; value["rights"] = 8
        XCTAssertThrowsError(try parse()) { XCTAssertEqual($0 as? MessengerInvitationError, .rights) }
        value["rights"] = UInt32.max; value["userid"] = "user//other"
        XCTAssertThrowsError(try parse()) { XCTAssertEqual($0 as? MessengerInvitationError, .identity) }
        value["type"] = "tunnel"
        XCTAssertThrowsError(try parse()) { XCTAssertEqual($0 as? MessengerInvitationError, .command) }
    }
    func testMessengerFailureReportContainsNoRemotePayload() throws {
        let rejection = MessengerRejection(.origin)
        let data = try JSONEncoder().encode(rejection)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["id", "reason"])
        XCTAssertEqual(json["reason"] as? String, "origin")
        XCTAssertEqual(try JSONDecoder().decode(MessengerRejection.self, from: data).id, rejection.id)
    }
    func testHardwareInventoryHashRefreshAndUnavailableBattery() throws {
        var inventory = HardwareInventory(model: "iPad", machine: "iPad14,3", memoryBytes: 8589934592,
            processors: 8, architecture: 1, simulator: false, batteryPercent: 0, batteryState: 1)
        let first = try XCTUnwrap(inventory.message(ifDifferentFrom: nil))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let hash = try XCTUnwrap(data["hash"] as? String)
        XCTAssertEqual(hash.count, 96)
        XCTAssertNil(inventory.message(ifDifferentFrom: hash))
        XCTAssertEqual(inventory.message(ifDifferentFrom: nil), first) // Forced refresh resends.
        inventory.batteryPercent = 1
        XCTAssertNotNil(inventory.message(ifDifferentFrom: hash))
        inventory.batteryPercent = -1; inventory.batteryState = 0
        XCTAssertFalse(String(decoding: try XCTUnwrap(inventory.body()), as: UTF8.self).contains("battery"))
        inventory.simulator = true
        let simulated = String(decoding: try XCTUnwrap(inventory.body()), as: UTF8.self)
        XCTAssertTrue(simulated.contains("Simulator")); XCTAssertFalse(simulated.contains("darwin"))
    }
    func testHardwareBatteryConversion() {
        for unknown: Float in [-1, .nan, .infinity, 1.01] { XCTAssertEqual(HardwareInventory.percentage(unknown), -1) }
        XCTAssertEqual(HardwareInventory.percentage(0), 0)
        XCTAssertEqual(HardwareInventory.percentage(0.715), 72)
        XCTAssertEqual(HardwareInventory.percentage(1), 100)
    }
    func testMessengerInvitationIsBoundToServerNodeOperatorAndRights() throws {
        let enrollment = try Enrollment(endpoint: URL(string: "wss://example.invalid/team/agent.ashx")!,
            serverID: Data(repeating: 1, count: 48), meshID: Data(repeating: 2, count: 48), architectureID: 10005, deviceName: "Test")
        let key = String(repeating: "A", count: 64)
        let id = "meshmessenger/node/team/" + key + "/user/team/tech"
        let address = "https://example.invalid/team/messenger?id=" + id
        let valid: [String: Any] = ["action": "openUrl", "url": address, "userid": "user/team/tech", "rights": 0x4008, "username": "Technicien"]
        func parse(_ value: [String: Any]) throws -> MessengerInvitation {
            try MessengerInvitation.parse(value, enrollment: enrollment, controlTLS: Data(repeating: 3, count: 48), nodeKey: key)
        }
        let invitation = try parse(valid)
        XCTAssertEqual(invitation.url.absoluteString, address)
        XCTAssertEqual(invitation.operatorName, "Technicien")
        var changed = valid
        for address in [address.replacingOccurrences(of: "https:", with: "http:"),
                        address.replacingOccurrences(of: "example.invalid", with: "other.invalid"),
                        address.replacingOccurrences(of: "example.invalid", with: "example.invalid:8443"),
                        address.replacingOccurrences(of: "/team/messenger", with: "/messenger"),
                        address + "&auth=forbidden", address + "&id=duplicate", address + "#fragment",
                        address.replacingOccurrences(of: key, with: String(repeating: "B", count: 64)),
                        address.replacingOccurrences(of: "user/team/tech", with: "user/team/other")] {
            changed["url"] = address; XCTAssertThrowsError(try parse(changed))
        }
        let invalidRights: [Any] = [0, 8, 0x4000, true, -1, 4294967296 as UInt64, 16392.5]
        for rights in invalidRights {
            changed = valid; changed["rights"] = rights; XCTAssertThrowsError(try parse(changed))
        }
        changed = valid; changed["userid"] = "user/other/tech"; XCTAssertThrowsError(try parse(changed))
        changed = valid; changed["guestname"] = "guest"; XCTAssertThrowsError(try parse(changed))
    }
    func testMessengerConsentExpiresAndNeverReopensAfterBackground() {
        let invitation = MessengerInvitation(id: UUID(), createdUptime: 100,
            url: URL(string: "https://example.invalid/messenger?id=test")!, operatorName: "Test", tlsHash: Data(repeating: 3, count: 48))
        let consent = MessengerConsent(invitation)
        XCTAssertEqual(consent.event(connected: true, foreground: true, now: 100), 0)
        XCTAssertEqual(consent.event(1, connected: true, foreground: true, now: 101), 1)
        XCTAssertEqual(consent.event(connected: true, foreground: false, now: 102), 2)
        XCTAssertEqual(consent.event(1, connected: true, foreground: true, now: 103), 2)
        let expired = MessengerConsent(invitation)
        XCTAssertEqual(expired.event(1, connected: true, foreground: true, now: 220), 2)
    }
    func testBroadcastClockCannotRenewConsentOrHideUnconfirmedStop() {
        XCTAssertEqual(BroadcastTiming.remaining(phase: 0, since: 100, now: 100), 120)
        XCTAssertEqual(BroadcastTiming.remaining(phase: 0, since: 100, now: 219.5), 1)
        XCTAssertEqual(BroadcastTiming.policy(phase: 0, since: 100, now: 220), 1)
        XCTAssertEqual(BroadcastTiming.policy(phase: 1, since: 100, heartbeat: 150, now: 160), 2)
        XCTAssertEqual(BroadcastTiming.policy(phase: 2, since: 100, now: 110), 3)
        XCTAssertEqual(BroadcastTiming.remaining(phase: 1, since: .nan, now: 100), 0)
        XCTAssertEqual(BroadcastTiming.policy(phase: 1, since: 200, now: 100), 1)
        XCTAssertEqual(BroadcastTiming.policy(phase: 1, since: 100, heartbeat: 201, now: 200), 2)
    }
    func testTransferProgressCountsAcknowledgedBytesAndClearCancelsUpload() throws {
        let engine = AssistanceEngine(); var sent: [[String: Any]] = []
        engine.send = { sent.append($0) }
        let content = Data(repeating: 7, count: 9000)
        engine.local(AssistanceCommand(action: "document", data: content, name: "test.bin"), capture: nil)
        let id = try XCTUnwrap(engine.snapshot.sending?.id)
        XCTAssertEqual(engine.snapshot.sending?.state, .offered)
        try engine.receive(message("ack", ["id": id, "offset": 0]))
        XCTAssertEqual(engine.snapshot.sending?.completed, 0)
        try engine.receive(message("ack", ["id": id, "offset": 8192]))
        XCTAssertEqual(engine.snapshot.sending?.completed, 8192)
        XCTAssertEqual(engine.snapshot.sending?.state, .transferring)
        try engine.receive(message("ack", ["id": id, "offset": 8192])) // duplicate
        XCTAssertEqual(engine.snapshot.sending?.completed, 8192)
        engine.local(AssistanceCommand(action: "clear"), capture: nil)
        XCTAssertNil(engine.snapshot.sending)
        XCTAssertEqual(sent.last?["action"] as? String, "cancel")
        try engine.receive(message("ack", ["id": id, "offset": 9000]))
        XCTAssertNil(engine.snapshot.sending)
    }
    func testUploadCompletesOnlyAfterFinalAcknowledgmentAndRecognizesRefusal() throws {
        let engine = AssistanceEngine()
        engine.local(AssistanceCommand(action: "document", data: bytes, name: "test.bin"), capture: nil)
        let id = try XCTUnwrap(engine.snapshot.sending?.id)
        try engine.receive(message("ack", ["id": id, "offset": 0]))
        XCTAssertEqual(engine.snapshot.sending?.state, .transferring)
        try engine.receive(message("ack", ["id": id, "offset": bytes.count]))
        XCTAssertEqual(engine.snapshot.sending?.state, .completed)
        engine.local(AssistanceCommand(action: "document", data: bytes, name: "second.bin"), capture: nil)
        let second = try XCTUnwrap(engine.snapshot.sending?.id)
        try engine.receive(message("cancel", ["id": second, "reason": "rejected"]))
        XCTAssertEqual(engine.snapshot.sending?.state, .declined)
    }
    func testReceiveProgressRequiresApprovalAndIntegrity() throws {
        let engine = AssistanceEngine()
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try engine.receive(message("offer", ["id": identifier, "name": "test.bin", "size": bytes.count, "kind": "document", "sha256": digest]))
        XCTAssertEqual(engine.snapshot.receiving?.state, .offered)
        engine.local(AssistanceCommand(action: "accept", transferID: identifier), capture: nil)
        XCTAssertEqual(engine.snapshot.receiving?.state, .transferring)
        try engine.receive(message("chunk", ["id": identifier, "offset": 0, "data": bytes.base64EncodedString()]))
        XCTAssertEqual(engine.snapshot.receiving?.state, .completed)
        XCTAssertEqual(engine.snapshot.document, bytes)
        let snapshot = try JSONDecoder().decode(AssistanceSnapshot.self, from: JSONEncoder().encode(engine.snapshot))
        XCTAssertEqual(snapshot.receiving?.fraction, 1)
        engine.clear(); XCTAssertNil(engine.snapshot.receiving); XCTAssertNil(engine.snapshot.document)
    }
    func testDiagnosticLabelsDoNotRenderUnknownErrorContent() {
        var diagnostic = ConnectionDiagnostics()
        diagnostic.lastError = "secret.example/token"; diagnostic.stage = "private.url"
        XCTAssertFalse(diagnostic.errorLabel.contains("secret"))
        XCTAssertFalse(diagnostic.stageLabel.contains("private"))
        diagnostic.networkInterface = "wifi"; diagnostic.networkState = "available"
        XCTAssertEqual(diagnostic.networkLabel, "Wi-Fi — disponible")
    }
    func testDelayedCleanupCannotDeleteNewSessionOrUnrelatedContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MeshCentralIsolationTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = UUID(), current = UUID()
        let oldName = "assistance-" + old.uuidString + "-state.json"
        let newName = "assistance-" + current.uuidString + "-state.json"
        for name in [oldName, newName, "keep.txt", "assistance-not-a-session-state.json", "assistance-state.json"] {
            try Data([42]).write(to: directory.appendingPathComponent(name))
        }
        try AssistanceMailbox.clear(in: directory, session: old)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(oldName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(newName).path))
        try AssistanceMailbox.clear(in: directory)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), Set(["keep.txt", "assistance-not-a-session-state.json"]))
    }
    func testExtendedDiagnosticsAreNumericAndDoNotLeakErrors() throws {
        var value = ConnectionDiagnostics()
        value.networkState = "unavailable"; value.networkInterface = "wifi"; value.constrained = true
        value.assess(frameAge: 12)
        XCTAssertEqual(value.healthCode, 1)
        value.networkState = "available"; value.assess(frameAge: 12)
        XCTAssertEqual(value.healthCode, 2)
        value.assess(frameAge: 1)
        XCTAssertEqual(value.healthCode, 4)
        XCTAssertEqual(ConnectionDiagnostics.errorCode(URLError(.serverCertificateUntrusted)), "tls_failed")
        XCTAssertEqual(ConnectionDiagnostics.errorCode(URLError(.cannotFindHost)), "dns_failed")
        let privateError = NSError(domain: "secret.example", code: 1, userInfo: [NSLocalizedDescriptionKey: "secret invitation"])
        XCTAssertEqual(ConnectionDiagnostics.errorCode(privateError), "internal_error")
        let roundtrip = try JSONDecoder().decode(ConnectionDiagnostics.self, from: value.report())
        XCTAssertEqual(roundtrip.healthCode, 4)
        XCTAssertFalse(String(decoding: value.report(), as: UTF8.self).contains("secret"))
        value.roundTripMS = .nan; value.sendMS = .infinity; value.assess(frameAge: .nan)
        XCTAssertEqual(value.frameAgeMS, 0)
        XCTAssertEqual(value.healthCode, 4)
    }
    func testLegacyBroadcastGrantRequiresSeparateConsent() throws {
        let enrollment = SavedEnrollment(endpoint: "wss://example.invalid/agent.ashx", serverID: Data(repeating: 1, count: 48),
            meshID: Data(repeating: 2, count: 48), deviceName: "Test", privateCA: nil)
        let grant = BroadcastGrant(id: UUID(), created: Date(), enrollment: enrollment)
        let data = try JSONEncoder().encode(grant)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["approveFirstTechnician"])
        let legacy = try JSONDecoder().decode(BroadcastGrant.self, from: data)
        XCTAssertNotEqual(legacy.approveFirstTechnician, true)
        var quick = grant; quick.approveFirstTechnician = true
        let restored = try JSONDecoder().decode(BroadcastGrant.self, from: JSONEncoder().encode(quick))
        XCTAssertEqual(restored.approveFirstTechnician, true)
        XCTAssertEqual(restored.id, grant.id)
    }
    func testMissingOrUnresolvedAppGroupDoesNotReachContainerLookup() {
        let invalidGroups: [String?] = [nil, "", "group.", "example.app", "group.$(MESH_HOST_BUNDLE_ID)", "group.${UNRESOLVED}", " group.example.app"]
        for group in invalidGroups {
            var lookedUp = false
            XCTAssertThrowsError(try AssistanceMailbox.resolveContainer(group: group, lookup: { _ in
                lookedUp = true; return nil
            })) { error in
                XCTAssertEqual(error as? AssistanceMailboxError, .groupNotConfigured)
            }
            XCTAssertFalse(lookedUp)
        }
    }
    func testUnavailableAppGroupIsNotAnEnrollmentError() {
        XCTAssertThrowsError(try AssistanceMailbox.resolveContainer(group: "group.example.test", lookup: { _ in nil })) { error in
            XCTAssertEqual(error as? AssistanceMailboxError, .groupUnavailable)
            XCTAssertTrue(error.localizedDescription.contains("App Group"))
            XCTAssertFalse(error.localizedDescription.contains("WSS"))
        }
    }
    func testSharedStorageProbeCleansUpAndPreservesExistingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MeshCentralProbeTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("keep.txt")
        try Data([1, 2, 3]).write(to: existing)
        let resolved = try AssistanceMailbox.resolveContainer(group: "group.example.test", lookup: { group in
            XCTAssertEqual(group, "group.example.test"); return directory
        })
        try AssistanceMailbox.checkAccess(to: resolved)
        XCTAssertEqual(try Data(contentsOf: existing), Data([1, 2, 3]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["keep.txt"])
    }
    func testMissingSharedStorageFailsClosed() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("MissingMeshCentralProbe-" + UUID().uuidString)
        XCTAssertThrowsError(try AssistanceMailbox.checkAccess(to: missing)) { error in
            XCTAssertEqual(error as? AssistanceMailboxError, .storageUnavailable)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    private let identifier = "00000000-0000-4000-8000-000000000001"
    private let bytes = Data([0, 1, 128, 255])
    private func guide(_ step: Int = 1, total: Int = 2, id: String? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        message("guideStep", ["id": id ?? identifier, "step": step, "total": total, "text": "Ouvrez Réglages."].merging(extra) { _, new in new })
    }
    func testGuideRequiresMatchingLocalCompletionAndRejectsRemoteCompletion() throws {
        let engine = AssistanceEngine(); var sent: [[String: Any]] = []
        engine.send = { sent.append($0) }
        try engine.receive(guide())
        XCTAssertEqual(engine.snapshot.guide?.status, "waiting")
        try engine.receive(message("guideDone", ["id": identifier, "step": 1]))
        try engine.receive(guide(2))
        XCTAssertEqual(sent.last?["action"] as? String, "guideError")
        XCTAssertEqual(engine.snapshot.guide?.step, 1)
        engine.local(AssistanceCommand(action: "guideDone", transferID: UUID().uuidString, step: 1), capture: nil)
        XCTAssertEqual(engine.snapshot.guide?.status, "waiting")
        engine.local(AssistanceCommand(action: "guideHelp", transferID: identifier, step: 1), capture: nil)
        XCTAssertEqual(engine.snapshot.guide?.status, "help")
        engine.local(AssistanceCommand(action: "guideDone", transferID: identifier, step: 1), capture: nil)
        try engine.receive(guide(2))
        XCTAssertEqual(engine.snapshot.guide?.step, 2)
        engine.local(AssistanceCommand(action: "guideDone", transferID: identifier, step: 1), capture: nil)
        XCTAssertEqual(engine.snapshot.guide?.status, "waiting")
        // Stop applies to this guide even if the next step arrived during app IPC.
        engine.local(AssistanceCommand(action: "guideStop", transferID: identifier, step: 1), capture: nil)
        XCTAssertEqual(engine.snapshot.guide?.status, "stopped")
        try engine.receive(guide())
        XCTAssertEqual(engine.snapshot.guide?.status, "stopped")
    }
    func testGuideValidatesBoundsRightsAndCaptureBinding() throws {
        XCTAssertThrowsError(try AssistanceEngine(chatAllowed: false).receive(guide()))
        let invalid: [[String: Any]] = [["text": String(repeating: "é", count: 401)], ["text": "  "], ["step": true], ["total": 21], ["id": "bad"]]
        for extra in invalid {
            XCTAssertThrowsError(try AssistanceEngine().receive(guide(extra: extra)))
        }
        let engine = AssistanceEngine(); var sent: [[String: Any]] = []
        engine.send = { sent.append($0) }
        try engine.receive(guide(extra: ["captureID": identifier]))
        XCTAssertNil(engine.snapshot.guide)
        XCTAssertEqual(sent.last?["reason"] as? String, "captureUnavailable")
        engine.local(AssistanceCommand(action: "capture"), capture: bytes)
        let captureID = try XCTUnwrap(engine.snapshot.captureID)
        let marks = [["points": [[0.1, 0.2], [0.3, 0.4]]]]
        try engine.receive(guide(extra: ["captureID": captureID, "strokes": marks]))
        XCTAssertEqual(engine.snapshot.guide?.capture, bytes)
        XCTAssertEqual(engine.snapshot.guide?.strokes.count, 1)
        engine.local(AssistanceCommand(action: "cancel"), capture: nil)
        engine.local(AssistanceCommand(action: "capture"), capture: Data([42]))
        XCTAssertEqual(engine.snapshot.capture, Data([42]))
        XCTAssertEqual(engine.snapshot.guide?.capture, bytes) // Immutable step illustration.
        engine.local(AssistanceCommand(action: "clear"), capture: nil)
        XCTAssertNil(engine.snapshot.guide)
        XCTAssertEqual(sent.last?["status"] as? String, "stopped")
        try engine.receive(guide()) // Cannot replay a guide cleared locally.
        XCTAssertNil(engine.snapshot.guide)
    }
    func testRequestedCaptureFreezesBeforeAppReturnAndRequiresLocalSend() throws {
        let engine = AssistanceEngine(); var sent: [[String: Any]] = []
        engine.send = { sent.append($0) }
        try engine.receive(message("captureRequest"), capture: bytes)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(engine.snapshot.capturePreview, bytes)
        engine.local(AssistanceCommand(action: "capture"), capture: Data([99]))
        XCTAssertEqual(engine.snapshot.capture, bytes)
        XCTAssertNil(engine.snapshot.capturePreview)
        XCTAssertFalse(engine.snapshot.captureRequested)
        XCTAssertEqual(sent.last?["action"] as? String, "offer")
        let declined = AssistanceEngine(); declined.send = { sent.append($0) }
        try declined.receive(message("captureRequest"), capture: bytes)
        declined.local(AssistanceCommand(action: "declineCapture"), capture: nil)
        XCTAssertNil(declined.snapshot.capturePreview)
        XCTAssertEqual(sent.last?["action"] as? String, "captureDeclined")
    }
    func testHidingScreenDiscardsPendingCaptureAndKeepsTextChat() throws {
        let engine = AssistanceEngine()
        var sent: [[String: Any]] = []
        engine.send = { sent.append($0) }
        try engine.receive(message("captureRequest"), capture: bytes)
        engine.hideScreen()
        XCTAssertFalse(engine.snapshot.captureRequested)
        XCTAssertNil(engine.snapshot.capturePreview)
        XCTAssertEqual(sent.last?["action"] as? String, "captureDeclined")
        engine.local(AssistanceCommand(action: "capture"), capture: nil)
        XCTAssertEqual(sent.count, 1)
        engine.local(AssistanceCommand(action: "chat", text: "Je suis toujours là."), capture: nil)
        XCTAssertEqual(sent.last?["action"] as? String, "chat")
    }

    func testGuidanceSnapshotAndResponseSurviveMailboxEncoding() throws {
        let engine = AssistanceEngine()
        try engine.receive(guide())
        let snapshot = try JSONDecoder().decode(AssistanceSnapshot.self, from: JSONEncoder().encode(engine.snapshot))
        XCTAssertEqual(snapshot.guide?.id, identifier)
        let command = AssistanceCommand(action: "guideDone", transferID: identifier, step: 1)
        let decoded = try JSONDecoder().decode(AssistanceCommand.self, from: JSONEncoder().encode(command))
        engine.local(decoded, capture: nil)
        XCTAssertEqual(engine.snapshot.guide?.status, "done")
        engine.clear()
        XCTAssertNil(engine.snapshot.guide)
    }
    private func message(_ action: String, _ fields: [String: Any] = [:]) -> [String: Any] {
        fields.merging(["v": 1, "type": "iosAssist", "action": action]) { _, new in new }
    }
    private func offer() -> [String: Any] {
        message("offer", ["id": identifier, "name": "test.bin", "size": bytes.count, "kind": "document",
                         "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()])
    }
    private func chunk(offset: Int = 0, bytes: Data? = nil) -> [String: Any] {
        message("chunk", ["id": identifier, "offset": offset, "data": (bytes ?? self.bytes).base64EncodedString()])
    }
    func testIncomingRequiresPerDocumentAcceptance() throws {
        let engine = AssistanceEngine()
        var sent: [[String: Any]] = []; engine.send = { sent.append($0) }
        try engine.receive(offer()); XCTAssertTrue(sent.isEmpty)
        XCTAssertThrowsError(try engine.receive(chunk()))
        engine.local(AssistanceCommand(action: "accept", transferID: identifier), capture: nil)
        XCTAssertEqual(sent.last?["offset"] as? Int, 0)
        try engine.receive(chunk())
        XCTAssertEqual(engine.snapshot.document, bytes)
        XCTAssertNil(engine.snapshot.offer)
        XCTAssertEqual(sent.last?["offset"] as? Int, 4)
        XCTAssertThrowsError(try engine.receive(chunk())) // No replay after completion.
    }
    func testGapsOverflowsAndIntegrityFailure() throws {
        let engine = AssistanceEngine()
        try engine.receive(offer())
        engine.local(AssistanceCommand(action: "accept", transferID: identifier), capture: nil)
        XCTAssertThrowsError(try engine.receive(chunk(offset: 1)))
        XCTAssertThrowsError(try engine.receive(chunk(bytes: Data(repeating: 0, count: 5))))
        XCTAssertThrowsError(try engine.receive(chunk(bytes: Data(repeating: 0, count: 4))))
        XCTAssertNil(engine.snapshot.document)
    }
    func testRejectAndClearReleaseContents() throws {
        let engine = AssistanceEngine()
        try engine.receive(offer())
        engine.local(AssistanceCommand(action: "reject", transferID: identifier), capture: nil)
        XCTAssertNil(engine.snapshot.offer)
        engine.local(AssistanceCommand(action: "chat", text: "Local test"), capture: nil)
        XCTAssertEqual(engine.snapshot.messages.count, 1)
        engine.clear()
        XCTAssertTrue(engine.snapshot.messages.isEmpty); XCTAssertNil(engine.snapshot.document)
    }
    func testUploadWaitsForAckAndIgnoresDuplicateAck() throws {
        let engine = AssistanceEngine(); var sent: [[String: Any]] = []
        engine.send = { sent.append($0) }
        engine.local(AssistanceCommand(action: "document", data: Data(repeating: 7, count: 9000), name: "a.bin"), capture: nil)
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(sent.first?["action"] as? String, "offer")
        let id = try XCTUnwrap(sent.first?["id"] as? String)
        try engine.receive(message("ack", ["id": id, "offset": 0]))
        XCTAssertEqual(sent.count, 2)
        try engine.receive(message("ack", ["id": id, "offset": 0]))
        XCTAssertEqual(sent.count, 2)
        try engine.receive(message("ack", ["id": id, "offset": 8192]))
        XCTAssertEqual(sent.last?["offset"] as? Int, 8192)
        try engine.receive(message("ack", ["id": id, "offset": 9000]))
        XCTAssertTrue(engine.snapshot.transfer.contains("terminé"))
    }
    func testAnnotationsBoundToLocallyApprovedCapture() throws {
        let engine = AssistanceEngine()
        let marks = [["points": [[0.1, 0.2], [0.3, 0.4]]]]
        XCTAssertThrowsError(try engine.receive(message("annotations", ["id": identifier, "strokes": marks])))
        // A fresh engine avoids annotation rate limiting in this independent case.
        let other = AssistanceEngine()
        other.local(AssistanceCommand(action: "capture"), capture: bytes)
        let id = try XCTUnwrap(other.snapshot.captureID)
        try other.receive(message("annotations", ["id": id, "strokes": marks]))
        XCTAssertEqual(other.snapshot.strokes.count, 1)
        XCTAssertFalse(AnnotationStroke.valid([AnnotationStroke(points: [[0, 0], [1.1, 0]])]))
        XCTAssertFalse(AnnotationStroke.valid([AnnotationStroke(points: Array(repeating: [0, 0], count: 513))]))
    }
    func testMalformedOffersAndNamesAreRejected() throws {
        for name in ["../a", "/a", "a\\b", "", ".", "a\nb"] {
            var item = offer(); item["name"] = name
            XCTAssertThrowsError(try AssistanceEngine().receive(item))
        }
        for size in [0, -1, AssistanceEngine.maximum + 1] {
            var item = offer(); item["size"] = size
            XCTAssertThrowsError(try AssistanceEngine().receive(item))
        }
    }
    func testDiagnosticsHaveOnlyAllowlistedFields() throws {
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: ConnectionDiagnostics().report()) as? [String: Any])
        XCTAssertEqual(Set(report.keys), Set(["version", "stage", "tlsVerified", "frames", "bytes", "fps",
                                              "kilobitsPerSecond", "roundTripMS", "sendMS", "qualityLevel", "lastError"]))
    }
    func testMeshCentralRestrictionsCannotBeBypassedByMessages() throws {
        let engine = AssistanceEngine(chatAllowed: false, documentsAllowed: false)
        var sent: [[String: Any]] = []; engine.send = { sent.append($0) }
        XCTAssertThrowsError(try engine.receive(message("chat", ["text": "forbidden"])))
        XCTAssertThrowsError(try engine.receive(offer()))
        engine.local(AssistanceCommand(action: "chat", text: "forbidden"), capture: nil)
        engine.local(AssistanceCommand(action: "document", data: bytes, name: "a.bin"), capture: nil)
        XCTAssertTrue(sent.isEmpty)
    }
}
