// SPDX-License-Identifier: Apache-2.0
import XCTest
import Foundation
#if canImport(MeshCentralAgent)
@testable import MeshCentralAgent
#else
@testable import MeshCentralIOS
#endif

final class EnrollmentImportTests: XCTestCase {
    private let pin = Data(repeating: 0xfb, count: 48)
    private let mesh = Data(repeating: 0xff, count: 48)
    private func encoded(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "@").replacingOccurrences(of: "/", with: "$")
    }
    private var mobile: String { "mc://example.invalid:4443/team,\(encoded(pin)),\(encoded(mesh))" }

    func testMobileInvitationAndSavedProfileRoundTrip() throws {
        let profile = try EnrollmentImport.parse(mobile, deviceName: "iPhone de test")
        XCTAssertEqual(profile.endpoint, "wss://example.invalid:4443/team/agent.ashx")
        XCTAssertEqual(profile.serverID, pin)
        XCTAssertEqual(profile.meshID, mesh)
        let saved = try JSONDecoder().decode(SavedEnrollment.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(try saved.validated().architectureID, 0xfffffff0)
    }

    func testInvitationHTMLLiteralWithoutExecutingScripts() throws {
        let html = "<script>var magenturl = '\(mobile)';</script>"
        XCTAssertEqual(try EnrollmentImport.invitationPage(Data(html.utf8), deviceName: "Test").serverID, pin)
        XCTAssertThrowsError(try EnrollmentImport.invitationPage(Data((html + html).utf8), deviceName: "Test"))
        XCTAssertThrowsError(try EnrollmentImport.invitationPage(Data("<html>Expired</html>".utf8), deviceName: "Test"))
        XCTAssertThrowsError(try EnrollmentImport.invitationPage(Data("var magenturl = getLink();".utf8), deviceName: "Test"))
    }

    func testHTTPSInviteValidationPreservesCookieCharacters() throws {
        // Deliberately synthetic token, never a real enrollment secret.
        let text = "https://example.invalid/team/agentinvite?c=test$@token=&key=sample"
        XCTAssertEqual(try EnrollmentImport.invitationURL(text).absoluteString, text)
        for invalid in ["http://example.invalid/agentinvite?c=test", "https://user@example.invalid/agentinvite?c=test",
                        "https://example.invalid/agentinvite", "https://example.invalid/agentinvite?c=",
                        "https://example.invalid/agentinvite?c=a&c=b", "https://example.invalid/agentinvite?c=a&m=b",
                        "https://example.invalid/agentinvite?c=a#fragment", "https://example.invalid/a/b/agentinvite?c=a",
                        "https://example.invalid/%61gentinvite?c=a", "https://example.invalid/not-invite?c=a"] {
            XCTAssertThrowsError(try EnrollmentImport.invitationURL(invalid), invalid)
        }
    }

    func testMSHAndHexIdentifiers() throws {
        let pinHex = pin.map { String(format: "%02x", $0) }.joined()
        let meshHex = mesh.map { String(format: "%02X", $0) }.joined()
        let text = "\u{feff}MeshType=2\r\nMeshID=0x\(meshHex)\r\nServerID=\(pinHex)\r\nMeshServer=wss://example.invalid/agent.ashx\r\n"
        let result = try EnrollmentImport.parse(text, deviceName: "Test")
        XCTAssertEqual(result.serverID, pin); XCTAssertEqual(result.meshID, mesh)
        XCTAssertThrowsError(try EnrollmentImport.parse(text + "ServerID=\(pinHex)", deviceName: "Test"))
        XCTAssertThrowsError(try EnrollmentImport.parse(text.replacingOccurrences(of: "MeshType=2", with: "MeshType=1"), deviceName: "Test"))
        XCTAssertThrowsError(try EnrollmentImport.parse(text.replacingOccurrences(of: "wss://example.invalid/agent.ashx", with: "local"), deviceName: "Test"))
    }

    func testBoundsAndInvalidIdentifiers() throws {
        XCTAssertThrowsError(try EnrollmentImport.parse(String(repeating: "a", count: 16385), deviceName: "Test"))
        XCTAssertThrowsError(try EnrollmentImport.invitationPage(Data(repeating: 0, count: 524289), deviceName: "Test"))
        for bad in ["", String(repeating: "!", count: 64), String(repeating: "g", count: 96), pin.base64EncodedString() + "="] {
            XCTAssertThrowsError(try EnrollmentImport.identifier(bad))
        }
        XCTAssertThrowsError(try EnrollmentImport.parse(mobile, deviceName: String(repeating: "a", count: 256)))
        XCTAssertThrowsError(try EnrollmentImport.parse(mobile + ",unexpected", deviceName: "Test"))
    }

    func testCertificateImportRejectsPrivateKeysAndOversizeData() {
        XCTAssertThrowsError(try EnrollmentImport.certificate(Data("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----".utf8)))
        XCTAssertThrowsError(try EnrollmentImport.certificate(Data([0, 1, 2])))
        XCTAssertThrowsError(try EnrollmentImport.certificate(Data(repeating: 0, count: 16385)))
    }
}
