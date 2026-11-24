// SPDX-License-Identifier: Apache-2.0
import XCTest
import Foundation
import CMeshCore
#if canImport(MeshCentralAgent)
@testable import MeshCentralAgent
#else
@testable import MeshCentralIOS
#endif

final class DesktopRequestTests: XCTestCase {
    private func enrollment() throws -> Enrollment {
        try Enrollment(endpoint: XCTUnwrap(URL(string: "wss://example.invalid/team/agent.ashx")),
            serverID: Data(repeating: 1, count: 48), meshID: Data(repeating: 2, count: 48),
            architectureID: 0xfffffff0, deviceName: "Test")
    }
    private func command() -> [String: Any] {
        ["action": "msg", "type": "tunnel", "userid": "user/team/helper", "realname": "Technicien",
         "rights": 256, "value": "*/team/meshrelay.ashx?p=2&id=synthetic&rauth=synthetic"]
    }
    func testSameOriginDesktopAndViewOnlyRights() throws {
        let tls = Data(repeating: 3, count: 48)
        let request = try DesktopRequest.parse(command(), enrollment: enrollment(), controlTLS: tls)
        XCTAssertEqual(request.url.absoluteString, "wss://example.invalid/team/meshrelay.ashx?p=2&id=synthetic&rauth=synthetic")
        XCTAssertEqual(request.tlsHash, tls); XCTAssertEqual(request.rights, 256)
        XCTAssertEqual(request.operatorName, "Technicien")
    }
    func testRejectsArbitraryEndpointsProtocolsAndAmbiguousQueries() throws {
        for url in ["ws://example.invalid/team/meshrelay.ashx?p=2&id=a&rauth=b",
                    "wss://evil.invalid/team/meshrelay.ashx?p=2&id=a&rauth=b",
                    "wss://example.invalid:444/team/meshrelay.ashx?p=2&id=a&rauth=b",
                    "wss://user@example.invalid/team/meshrelay.ashx?p=2&id=a&rauth=b",
                    "*/other/meshrelay.ashx?p=2&id=a&rauth=b", "*/team/meshrelay.ashx?p=1&id=a&rauth=b",
                    "*/team/meshrelay.ashx?p=2&id=a", "*/team/meshrelay.ashx?p=2&id=a&rauth=b&p=2",
                    "*/team/meshrelay.ashx?p=2&id=a&rauth=b&tcpport=22",
                    "*/team/meshrelay.ashx?p=2&id=a&rauth=b#fragment",
                    "*/team/%6deshrelay.ashx?p=2&id=a&rauth=b"] {
            var value = command(); value["value"] = url
            XCTAssertThrowsError(try DesktopRequest.parse(value, enrollment: enrollment(), controlTLS: Data(repeating: 3, count: 48)), url)
        }
    }
    func testRejectsBadRightsGuestsForwardingAndOtherDomains() throws {
        let patches: [[String: Any]] = [["rights": 0], ["rights": 65544], ["rights": -1], ["rights": 8.5],
            ["rights": true], ["rights": "8"], ["userid": "user/other/helper"], ["userid": "user/team/"],
            ["guestname": "guest"], ["tcpport": 22], ["udpport": 53], ["usage": 1],
            ["soptions": ["usages": [1, 5]]], ["servertlshash": "invalid"]]
        for patch in patches {
            XCTAssertThrowsError(try DesktopRequest.parse(command().merging(patch) { _, new in new },
                enrollment: enrollment(), controlTLS: Data(repeating: 3, count: 48)))
        }
    }
    func testRustFrameABI() {
        var out = [UInt8](repeating: 0, count: 8)
        XCTAssertEqual(mc_screen_size(720, 1280, &out, 8), 8)
        XCTAssertEqual(out, [0, 7, 0, 8, 2, 208, 5, 0])
        XCTAssertEqual(mc_screen_size(0, 1280, &out, 8), -1)
    }
}
