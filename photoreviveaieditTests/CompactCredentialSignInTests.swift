import Foundation
import Testing
@testable import photoreviveaiedit

@MainActor
struct CompactCredentialSignInTests {
    @Test
    func reviewAliasUsesPasswordGrantAndStoresTheReturnedSession() async throws {
        let observedPasswordGrant = LockedFlag()
        let accessToken = Self.testAccessToken(
            userID: "compact-user-id",
            email: "review-tester-photorevival@review.local"
        )

        CompactCredentialURLProtocol.handler = { request in
            let url = try #require(request.url)

            if url.path == "/auth/v1/token",
               URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains(where: { $0.name == "grant_type" && $0.value == "password" }) == true {
                let body = try #require(Self.bodyData(from: request))
                let object = try #require(
                    JSONSerialization.jsonObject(with: body) as? [String: String]
                )
                #expect(object["email"] == "review-tester-photorevival@review.local")
                #expect(object["password"] == "unit-test-only-password")
                observedPasswordGrant.setTrue()
                return try Self.response(
                    for: url,
                    json: [
                        "access_token": accessToken,
                        "refresh_token": "refresh-token",
                        "expires_in": 3_600,
                    ]
                )
            }

            if url.path == "/functions/v1/bind-app-context" {
                return try Self.response(
                    for: url,
                    json: ["success": true, "app_id": "photorevival"]
                )
            }

            if url.path == "/auth/v1/token" {
                return try Self.response(
                    for: url,
                    json: [
                        "access_token": accessToken,
                        "refresh_token": "refresh-token",
                        "expires_in": 3_600,
                    ]
                )
            }

            return try Self.response(for: url, json: [:])
        }
        defer { CompactCredentialURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompactCredentialURLProtocol.self]
        let client = PhotoReviveAuthClient(session: URLSession(configuration: configuration))

        let session = try await client.signInWithPassword(
            email: "review",
            password: "unit-test-only-password"
        )

        #expect(observedPasswordGrant.value)
        #expect(session.accessToken == accessToken)
        #expect(client.currentUserID == "compact-user-id")
        #expect(client.currentUserEmail == "review-tester-photorevival@review.local")

        await client.signOut()
    }

    private static func response(
        for url: URL,
        json: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, try JSONSerialization.data(withJSONObject: json))
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func testAccessToken(userID: String, email: String) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let payload: [String: Any] = [
            "sub": userID,
            "email": email,
            "user_metadata": ["is_compact_account": true],
        ]

        return [header, payload]
            .compactMap { try? JSONSerialization.data(withJSONObject: $0) }
            .map {
                $0.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
            .joined(separator: ".") + ".signature"
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.withLock { storage }
    }

    func setTrue() {
        lock.withLock { storage = true }
    }
}

private final class CompactCredentialURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
