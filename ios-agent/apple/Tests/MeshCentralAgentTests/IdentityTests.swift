// SPDX-License-Identifier: Apache-2.0
import XCTest
import Foundation
import Security
import CryptoKit
import CMeshCore
#if canImport(MeshCentralAgent)
@testable import MeshCentralAgent
#else
@testable import MeshCentralIOS
#endif

final class IdentityTests: XCTestCase {
    func testNativeSignaturePinAndPersistentIdentity() throws {
        // Isolated test tag; cleanup never targets a real enrollment key.
        let tag = "org.meshcentral.ios.tests." + UUID().uuidString
        defer {
            SecItemDelete([kSecClass as String: kSecClassKey,
                           kSecAttrApplicationTag as String: Data(tag.utf8),
                           kSecAttrKeyType as String: kSecAttrKeyTypeRSA] as CFDictionary)
        }
        let identity = try KeychainIdentity(applicationTag: tag)
        let reloaded = try KeychainIdentity(applicationTag: tag)
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil, identity.certificateDER as CFData))
        let again = try XCTUnwrap(SecCertificateCreateWithData(nil, reloaded.certificateDER as CFData))
        let key = try XCTUnwrap(SecCertificateCopyKey(cert))
        let reloadedKey = try XCTUnwrap(SecCertificateCopyKey(again))
        XCTAssertEqual(try rsaPublicBytes(key), try rsaPublicBytes(reloadedKey))
        let pin = Data(SHA384.hash(data: try rsaPublicBytes(key)))
        let message = [UInt8](repeating: 0x42, count: 144)
        var signature = [UInt8](repeating: 0, count: 384)
        let callbacks = identity.callbacks()
        let signer = try XCTUnwrap(callbacks.sign)
        let count = signer(callbacks.context, message, &signature)
        XCTAssertEqual(count, 384)
        let sig = Data(signature)
        XCTAssertEqual(KeychainIdentity.verifyServer(pin: pin, certificate: identity.certificateDER,
            signature: sig, message: Data(message)), 0)
        XCTAssertEqual(KeychainIdentity.verifyServer(pin: Data(repeating: 0, count: 48), certificate: identity.certificateDER,
            signature: sig, message: Data(message)), 2)
        XCTAssertEqual(KeychainIdentity.verifyServer(pin: pin, certificate: identity.certificateDER,
            signature: sig, message: Data(repeating: 0x43, count: 144)), 3)
        XCTAssertEqual(KeychainIdentity.verifyServer(pin: pin, certificate: Data([0]),
            signature: sig, message: Data(message)), 1)
    }

    func testEnrollmentRejectsUnsafeOrAmbiguousEndpoints() throws {
        let pin = Data(repeating: 1, count: 48), mesh = Data(repeating: 2, count: 48)
        for address in ["http://example.com/agent.ashx", "ws://example.com/agent.ashx",
                        "wss://user:pass@example.com/agent.ashx", "wss://example.com/agent.ashx?token=secret",
                        "wss://example.com/agent.ashx#fragment", "wss://example.com/other",
                        "wss://example.com//agent.ashx", "wss://example.com/a/b/agent.ashx"] {
            XCTAssertThrowsError(try Enrollment(endpoint: XCTUnwrap(URL(string: address)), serverID: pin,
                meshID: mesh, architectureID: 0xfffffff0, deviceName: "Test"))
        }
        let endpoint = try XCTUnwrap(URL(string: "wss://example.com:443/team/agent.ashx"))
        _ = try Enrollment(endpoint: endpoint, serverID: pin, meshID: mesh,
            architectureID: 0xfffffff0, deviceName: "Test")
        XCTAssertThrowsError(try Enrollment(endpoint: endpoint, serverID: pin, meshID: mesh,
            architectureID: 0xfffffff0, deviceName: "Test", privateCA: Data([0])))
    }
}
