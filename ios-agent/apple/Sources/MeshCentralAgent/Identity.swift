// SPDX-License-Identifier: Apache-2.0
import Foundation
import Security
import CryptoKit
import CMeshCore

public enum AgentError: Error {
    case configuration, keychain(OSStatus), cryptography, protocolViolation, timeout, closed
}

func secureRandom(_ count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
        throw AgentError.cryptography
    }
    return Data(bytes)
}

func rsaPublicBytes(_ key: SecKey) throws -> Data {
    guard let attributes = SecKeyCopyAttributes(key) as? [String: Any],
          attributes[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String,
          let bits = attributes[kSecAttrKeySizeInBits as String] as? Int,
          bits == 2048 || bits == 3072 else { throw AgentError.cryptography }
    var error: Unmanaged<CFError>?
    defer { _ = error?.takeRetainedValue() }
    guard let data = SecKeyCopyExternalRepresentation(key, &error) else {
        throw AgentError.cryptography
    }
    // Apple's Security API exports RSA public keys as PKCS#1, matching MeshCentral.
    return data as Data
}

/// Persistent RSA private key in the app's Keychain, never exported or sent to Rust.
/// Load on a background queue. Serialize creation for the same application tag.
public final class KeychainIdentity {
    private static let creationLock = NSLock()
    private let key: SecKey
    public let certificateDER: Data
    public let nodeKey: String

    public init(applicationTag: String, accessGroup: String? = nil) throws {
        guard !applicationTag.isEmpty, applicationTag.utf8.count <= 200 else { throw AgentError.configuration }
        Self.creationLock.lock()
        defer { Self.creationLock.unlock() }
        let tag = Data(applicationTag.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: tag,
            kSecReturnRef as String: true
        ]
        if let accessGroup = accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let privateKey: SecKey
        if status == errSecSuccess, let item = item, CFGetTypeID(item) == SecKeyGetTypeID() {
            privateKey = item as! SecKey
        } else if status == errSecItemNotFound {
            var attributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: 3072,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String: true,
                    kSecAttrApplicationTag as String: tag,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                ]
            ]
            if let accessGroup = accessGroup { attributes[kSecAttrAccessGroup as String] = accessGroup }
            var error: Unmanaged<CFError>?
            defer { _ = error?.takeRetainedValue() }
            guard let generated = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
                throw AgentError.cryptography
            }
            privateKey = generated
        } else {
            // Never replace a key on permission/locked-Keychain errors.
            throw AgentError.keychain(status)
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { throw AgentError.cryptography }
        let publicDER = try rsaPublicBytes(publicKey)
        self.nodeKey = Data(SHA384.hash(data: publicDER)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "@").replacingOccurrences(of: "/", with: "$")
        self.key = privateKey
        // Renew the certificate with the SAME key. MeshCentral's node ID is the
        // public-key hash, so certificate renewal does not create a new device.
        self.certificateDER = try Self.makeCertificate(key: privateKey, publicDER: publicDER)
    }

    private static func sign(_ key: SecKey, _ message: Data) throws -> Data {
        let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA384
        guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else { throw AgentError.cryptography }
        var error: Unmanaged<CFError>?
        defer { _ = error?.takeRetainedValue() }
        guard let result = SecKeyCreateSignature(key, algorithm, message as CFData, &error) else {
            throw AgentError.cryptography
        }
        return result as Data
    }

    private static func makeCertificate(key: SecKey, publicDER: Data) throws -> Data {
        let serial = [UInt8](try secureRandom(16))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        let now = Date()
        let before = Array(formatter.string(from: now.addingTimeInterval(-300)).utf8)
        let after = Array(formatter.string(from: now.addingTimeInterval(5 * 365 * 24 * 3600)).utf8)
        let publicBytes = [UInt8](publicDER)
        var buffer = [UInt8](repeating: 0, count: 2048)
        let length = mc_build_tbs(publicBytes, publicBytes.count, serial, before, after, &buffer, 2048)
        guard length > 0 else { throw AgentError.cryptography }
        let tbs = Array(buffer.prefix(length))
        let signature = [UInt8](try sign(key, Data(tbs)))
        let certLength = mc_finish_certificate(tbs, tbs.count, signature, signature.count, &buffer, 2048)
        guard certLength > 0 else { throw AgentError.cryptography }
        let certificate = Data(buffer.prefix(certLength))
        guard let parsed = SecCertificateCreateWithData(nil, certificate as CFData),
              let parsedKey = SecCertificateCopyKey(parsed),
              try rsaPublicBytes(parsedKey) == publicDER else { throw AgentError.cryptography }
        return certificate
    }

    static func verifyServer(pin: Data, certificate: Data, signature: Data, message: Data) -> Int32 {
        guard let cert = SecCertificateCreateWithData(nil, certificate as CFData),
              let key = SecCertificateCopyKey(cert),
              let publicDER = try? rsaPublicBytes(key) else { return 1 }
        // Application identity is pinned independently of the WSS TLS certificate.
        guard Data(SHA384.hash(data: publicDER)) == pin else { return 2 }
        var error: Unmanaged<CFError>?
        defer { _ = error?.takeRetainedValue() }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA384,
            message as CFData, signature as CFData, &error) ? 0 : 3
    }

    func callbacks() -> MCCallbacks {
        MCCallbacks(context: Unmanaged.passUnretained(self).toOpaque(), verify: {
            _, pin, cert, certLength, signature, signatureLength, message in
            guard let pin = pin, let cert = cert, let signature = signature, let message = message else { return 1 }
            return KeychainIdentity.verifyServer(pin: Data(bytes: pin, count: 48),
                certificate: Data(bytes: cert, count: certLength),
                signature: Data(bytes: signature, count: signatureLength),
                message: Data(bytes: message, count: 144))
        }, sign: { context, message, output in
            guard let context = context, let message = message, let output = output else { return -1 }
            let identity = Unmanaged<KeychainIdentity>.fromOpaque(context).takeUnretainedValue()
            guard let signature = try? KeychainIdentity.sign(identity.key, Data(bytes: message, count: 144)),
                  signature.count == 256 || signature.count == 384 else { return -1 }
            signature.copyBytes(to: output, count: signature.count)
            return Int32(signature.count)
        })
    }
}
