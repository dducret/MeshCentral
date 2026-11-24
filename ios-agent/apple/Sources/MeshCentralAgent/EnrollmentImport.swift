// SPDX-License-Identifier: Apache-2.0
import Foundation
import Security

public enum EnrollmentImportError: Error, LocalizedError {
    case invalid, ambiguous, tooLarge, unavailable, redirected
    public var errorDescription: String? {
        switch self {
        case .invalid: return "Configuration invalide. Utilisez un lien d’invitation HTTPS, un lien mc:// ou un fichier .msh MeshCentral."
        case .ambiguous: return "La configuration contient plusieurs valeurs contradictoires."
        case .tooLarge: return "Le document dépasse la taille autorisée."
        case .unavailable: return "Invitation introuvable, expirée ou incompatible. Demandez un nouveau lien à votre administrateur."
        case .redirected: return "Le serveur redirige cette invitation. Utilisez son adresse HTTPS définitive."
        }
    }
}

/// Stored in the Keychain; invitation URLs/tokens are deliberately not retained.
public struct SavedEnrollment: Codable {
    public var endpoint: String
    public var serverID: Data
    public var meshID: Data
    public var deviceName: String
    public var privateCA: Data?

    public func validated() throws -> Enrollment {
        guard let url = URL(string: endpoint) else { throw EnrollmentImportError.invalid }
        // Experimental unassigned ID. Never impersonate an Android/macOS agent.
        return try Enrollment(endpoint: url, serverID: serverID, meshID: meshID,
                              architectureID: 0xfffffff0, deviceName: deviceName, privateCA: privateCA)
    }
}

public enum EnrollmentImport {
    public static let inputLimit = 16 * 1024
    public static let pageLimit = 512 * 1024

    public static func identifier(_ text: String) throws -> Data {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("0x") { value.removeFirst(2) }
        if value.count == 96, value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) {
            let chars = Array(value)
            return Data(stride(from: 0, to: 96, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16)! })
        }
        value = value.replacingOccurrences(of: "@", with: "+").replacingOccurrences(of: "$", with: "/")
        guard value.utf8.count == 64, let bytes = Data(base64Encoded: value), bytes.count == 48,
              bytes.base64EncodedString() == value else { throw EnrollmentImportError.invalid }
        return bytes
    }

    public static func parse(_ text: String, deviceName: String, privateCA: Data? = nil) throws -> SavedEnrollment {
        guard text.utf8.count <= inputLimit else { throw EnrollmentImportError.tooLarge }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        let profile: SavedEnrollment
        if text.hasPrefix("mc://") {
            let parts = text.dropFirst(5).split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 3, !parts[0].hasSuffix("/") else { throw EnrollmentImportError.invalid }
            profile = SavedEnrollment(endpoint: "wss://" + String(parts[0]) + "/agent.ashx",
                serverID: try identifier(String(parts[1])), meshID: try identifier(String(parts[2])),
                deviceName: deviceName, privateCA: privateCA)
        } else {
            var fields: [String: String] = [:]
            for line in text.components(separatedBy: .newlines) {
                let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2 else { continue }
                let key = pair[0].trimmingCharacters(in: .whitespaces)
                guard ["MeshServer", "ServerID", "MeshID", "MeshType"].contains(key) else { continue }
                guard fields[key] == nil else { throw EnrollmentImportError.ambiguous }
                fields[key] = pair[1].trimmingCharacters(in: .whitespaces)
            }
            guard let endpoint = fields["MeshServer"], let pin = fields["ServerID"], let mesh = fields["MeshID"],
                  fields["MeshType"] == nil || fields["MeshType"] == "2" else { throw EnrollmentImportError.invalid }
            profile = SavedEnrollment(endpoint: endpoint, serverID: try identifier(pin),
                meshID: try identifier(mesh), deviceName: deviceName, privateCA: privateCA)
        }
        _ = try profile.validated()
        return profile
    }

    public static func invitationURL(_ text: String) throws -> URL {
        guard text.utf8.count <= inputLimit,
              let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              (1...65535).contains(parts.port ?? 443), !parts.percentEncodedPath.contains("%"),
              let url = parts.url else { throw EnrollmentImportError.invalid }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        guard (path.count == 2 || path.count == 3), path.first == "", path.last == "agentinvite",
              path.dropFirst().dropLast().allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy {
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).contains($0)
              }}), let items = parts.queryItems else { throw EnrollmentImportError.invalid }
        let selectors = items.filter { $0.name == "c" || $0.name == "m" }
        guard selectors.count == 1, let value = selectors[0].value, !value.isEmpty,
              Set(items.map(\.name)).count == items.count else { throw EnrollmentImportError.invalid }
        return url
    }

    /// Parse the literal mobile link emitted by upstream agentinvite.handlebars.
    /// No HTML/JavaScript is executed, and no page-provided downloads are followed.
    public static func invitationPage(_ data: Data, deviceName: String, privateCA: Data? = nil) throws -> SavedEnrollment {
        guard data.count <= pageLimit else { throw EnrollmentImportError.tooLarge }
        guard let html = String(data: data, encoding: .utf8) else { throw EnrollmentImportError.invalid }
        let regex = try NSRegularExpression(pattern: #"\bvar\s+magenturl\s*=\s*['"](mc://[^'"\s<>\\]+)['"]\s*;"#)
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: html) else {
            throw EnrollmentImportError.unavailable
        }
        return try parse(String(html[range]), deviceName: deviceName, privateCA: privateCA)
    }

    public static func certificate(_ input: Data) throws -> Data {
        guard input.count <= inputLimit else { throw EnrollmentImportError.tooLarge }
        let der: Data
        if let pem = String(data: input, encoding: .utf8), pem.contains("-----BEGIN") {
            let begin = "-----BEGIN CERTIFICATE-----", end = "-----END CERTIFICATE-----"
            let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(begin), trimmed.hasSuffix(end) else { throw EnrollmentImportError.invalid }
            let body = trimmed.dropFirst(begin.count).dropLast(end.count).filter { !$0.isWhitespace }
            guard let decoded = Data(base64Encoded: String(body)) else { throw EnrollmentImportError.invalid }
            der = decoded
        } else { der = input }
        guard SecCertificateCreateWithData(nil, der as CFData) != nil else { throw EnrollmentImportError.invalid }
        return der
    }
}

/// A bounded, ephemeral HTTPS fetch. System trust (or an explicitly imported CA),
/// hostname verification and the original origin are mandatory; redirects fail.
public final class InvitationResolver: NSObject, URLSessionDataDelegate {
    private var bytes = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private let url: URL
    private let privateCA: Data?

    public init(url: URL, privateCA: Data?) { self.url = url; self.privateCA = privateCA }

    public func load() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            self.session = session
            var request = URLRequest(url: url)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            session.dataTask(with: request).resume()
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        session?.invalidateAndCancel(); session = nil
        continuation.resume(with: result)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= EnrollmentImport.pageLimit,
              ["text/html", "application/xhtml+xml"].contains(response.mimeType ?? "") else {
            completionHandler(.cancel); finish(.failure(EnrollmentImportError.unavailable)); return
        }
        completionHandler(.allow)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= EnrollmentImport.pageLimit else {
            finish(.failure(EnrollmentImportError.tooLarge)); return
        }
        bytes.append(data)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { finish(.failure(error)) } else { finish(.success(bytes)) }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(EnrollmentImportError.redirected))
    }
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == url.host?.lowercased(),
              challenge.protectionSpace.port == (url.port ?? 443), let trust = challenge.protectionSpace.serverTrust,
              let host = url.host,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        if let data = privateCA {
            guard let ca = SecCertificateCreateWithData(nil, data as CFData),
                  SecTrustSetAnchorCertificates(trust, [ca] as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else {
                completionHandler(.cancelAuthenticationChallenge, nil); return
            }
        }
        guard SecTrustEvaluateWithError(trust, nil) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
