import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import GoogleSignIn
import Security
import UIKit

enum PhotoReviveAPIConfig {
    static let projectURL = URL(string: "https://api.alihantakaz.site")!
    static let appID = "photorevival"
}

enum PhotoReviveAuthProvider: String {
    case apple
    case google

    var title: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }
}

struct PhotoReviveSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval

    var isFresh: Bool {
        Date().addingTimeInterval(60).timeIntervalSince1970 < expiresAt
    }
}

private struct PhotoReviveSessionResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_at: TimeInterval?
    let expires_in: TimeInterval?
}

private struct PhotoReviveAnonymousSessionResponse: Decodable {
    let session: PhotoReviveAnonymousSession?
}

private struct PhotoReviveAnonymousSession: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct PhotoReviveAnonymousLoginRequest: Encodable {
    let appID: String
    let platform: String
    let idfv: String?
    let appVersion: String?
    let timezoneName: String
    let timezoneAbbreviation: String?

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case platform
        case idfv
        case appVersion = "app_version"
        case timezoneName = "timezone_name"
        case timezoneAbbreviation = "timezone_abbr"
    }
}

private struct PhotoReviveIDTokenRequest: Encodable {
    let provider: String
    let id_token: String
    let access_token: String?
    let nonce: String?
}

private struct PhotoReviveAppContextRequest: Encodable {
    let app_id: String
    let timezone_name: String
    let timezone_abbr: String?
}

private struct PhotoReviveAppContextResponse: Decodable {
    let success: Bool
    let app_id: String
}

private struct PhotoReviveAdjustAttributionRequest: Encodable {
    let user_id: String
    let app_id: String
    let adjust_adid: String?
    let network: String?
    let campaign: String?
    let adgroup: String?
    let creative: String?
    let tracker_name: String?
    let tracker_token: String?
    let click_label: String?
    let referrer: String
    let adjust_environment: String
    let attribution_data: [String: String]
}

private struct PhotoReviveAdjustAttributionResponse: Decodable {
    let success: Bool
}

private struct PhotoReviveProfileUpdateRequest: Encodable {
    let data: [String: String]
}

private struct PhotoReviveUpdatedUser: Decodable {
    let id: String
}

enum PhotoReviveAuthError: LocalizedError {
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case signInCancelled
    case missingGoogleConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The sign-in service returned an invalid response."
        case let .requestFailed(_, message):
            return message.isEmpty ? "Sign-in failed. Please try again." : message
        case .signInCancelled:
            return nil
        case .missingGoogleConfiguration:
            return "Google Sign-In is not configured for this app yet."
        }
    }
}

@MainActor
final class PhotoReviveAuthStore: ObservableObject {
    @Published private(set) var activeProvider: PhotoReviveAuthProvider?
    @Published private(set) var didAuthenticate = false
    @Published var errorMessage: String?

    private let client: PhotoReviveAuthClient

    init(client: PhotoReviveAuthClient? = nil) {
        self.client = client ?? PhotoReviveAuthClient.shared
    }

    var isBusy: Bool { activeProvider != nil }

    func signIn(with provider: PhotoReviveAuthProvider) {
        guard activeProvider == nil else { return }

        activeProvider = provider
        errorMessage = nil
        AppAnalytics.authAttempt(method: provider.rawValue)

        Task {
            do {
                switch provider {
                case .apple:
                    let nonce = try PhotoReviveAuthClient.randomNonce()
                    let coordinator = PhotoReviveAppleSignInCoordinator(
                        presentationContextProvider: PhotoReviveAuthPresentationContextProvider(),
                        nonceHash: PhotoReviveAuthClient.sha256(nonce)
                    )
                    let result = try await coordinator.start()
                    _ = try await client.signInWithApple(idToken: result.idToken, nonce: nonce)
                case .google:
                    let configuration = try PhotoReviveGoogleConfiguration.load()
                    let coordinator = PhotoReviveGoogleSignInCoordinator(
                        configuration: configuration,
                        presentationContextProvider: PhotoReviveAuthPresentationContextProvider()
                    )
                    let result = try await coordinator.start()
                    _ = try await client.signInWithGoogle(
                        idToken: result.idToken,
                        accessToken: result.accessToken,
                        nonce: result.nonce
                    )
                }

                UserDefaults.standard.set(true, forKey: "isLoggedIn")
                let userID = client.currentUserID
                AdjustService.shared.setExternalDeviceID(userID)
                AdjustService.shared.trackCompleteRegistration(userID: userID)
                AppAnalytics.updateUser(userID: userID, isSignedIn: true)
                AppAnalytics.authResult(method: provider.rawValue, result: "success")
                await client.bindAdjustAttributionIfAvailable()
                didAuthenticate = true
            } catch let error as PhotoReviveAuthError {
                if case .signInCancelled = error {
                    errorMessage = nil
                    AppAnalytics.authResult(
                        method: provider.rawValue,
                        result: "cancelled",
                        failureType: "user_cancelled"
                    )
                } else {
                    errorMessage = error.localizedDescription
                    AppAnalytics.authResult(
                        method: provider.rawValue,
                        result: "failed",
                        failureType: analyticsFailureType(error)
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
                AppAnalytics.authResult(
                    method: provider.rawValue,
                    result: "failed",
                    failureType: error is URLError ? "network" : "unknown"
                )
            }

            activeProvider = nil
        }
    }

    private func analyticsFailureType(_ error: PhotoReviveAuthError) -> String {
        switch error {
        case .invalidResponse:
            return "invalid_response"
        case .signInCancelled:
            return "user_cancelled"
        case .missingGoogleConfiguration:
            return "configuration"
        case .requestFailed(let statusCode, _):
            switch statusCode {
            case 401, 403: return "authorization"
            case 400..<500: return "client_error"
            case 500..<600: return "server_error"
            default: return "http_error"
            }
        }
    }
}

@MainActor
final class PhotoReviveAuthClient {
    static let shared = PhotoReviveAuthClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private var cachedSession: PhotoReviveSession?
    private var hasBoundAppContext = false
    private var boundTimeZoneIdentifier: String?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
        cachedSession = Self.loadStoredSession()
    }

    var currentUserID: String? {
        guard let accessToken = cachedSession?.accessToken else { return nil }
        return Self.tokenPayload(from: accessToken)?["sub"] as? String
    }

    var currentUserEmail: String? {
        guard let accessToken = cachedSession?.accessToken,
              let payload = Self.tokenPayload(from: accessToken),
              payload["is_anonymous"] as? Bool != true,
              let email = payload["email"] as? String else { return nil }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    var currentUserDisplayName: String? {
        guard let metadata = currentUserMetadata else { return nil }
        for key in ["display_name", "full_name", "name"] {
            guard let value = metadata[key] as? String else { continue }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty { return normalized }
        }
        return nil
    }

    var currentUserAvatarURL: URL? {
        guard let metadata = currentUserMetadata else { return nil }
        for key in ["avatar_url", "picture"] {
            guard let value = metadata[key] as? String,
                  let url = URL(string: value),
                  !value.isEmpty else { continue }
            return url
        }
        return nil
    }

    private var currentUserMetadata: [String: Any]? {
        guard let accessToken = cachedSession?.accessToken,
              let payload = Self.tokenPayload(from: accessToken) else { return nil }
        return payload["user_metadata"] as? [String: Any]
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> PhotoReviveSession {
        try await signInWithOpenID(
            provider: .apple,
            idToken: idToken,
            accessToken: nil,
            nonce: nonce
        )
    }

    func signInWithGoogle(
        idToken: String,
        accessToken: String,
        nonce: String
    ) async throws -> PhotoReviveSession {
        try await signInWithOpenID(
            provider: .google,
            idToken: idToken,
            accessToken: accessToken,
            nonce: nonce
        )
    }

    func accessToken() async throws -> String {
        guard let cachedSession else {
            throw PhotoReviveAuthError.requestFailed(statusCode: 401, message: "Please sign in to continue.")
        }

        if cachedSession.isFresh {
            try await bindAppContextIfNeeded(accessToken: cachedSession.accessToken)
            return cachedSession.accessToken
        }

        guard !cachedSession.refreshToken.isEmpty else {
            clearSession()
            throw PhotoReviveAuthError.requestFailed(statusCode: 401, message: "Your session has expired. Please sign in again.")
        }

        do {
            let refreshed = try await refreshSession(refreshToken: cachedSession.refreshToken)
            try await bindAppContextIfNeeded(accessToken: refreshed.accessToken)
            return refreshed.accessToken
        } catch {
            clearSession()
            throw error
        }
    }

    /// Feedback remains available before OAuth sign-in. The anonymous session
    /// gives the server a stable user_id while leaving the App's visible login
    /// state unchanged.
    func feedbackAccessToken() async throws -> String {
        if cachedSession != nil {
            return try await accessToken()
        }

        var request = URLRequest(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent(
                "functions/v1/anonymous-login"
            )
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PhotoReviveAnonymousLoginRequest(
                appID: PhotoReviveAPIConfig.appID,
                platform: "ios",
                idfv: UIDevice.current.identifierForVendor?.uuidString.lowercased(),
                appVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String,
                timezoneName: Self.currentTimeZoneIdentifier,
                timezoneAbbreviation: Self.currentTimeZoneAbbreviation
            )
        )

        let response: PhotoReviveAnonymousSessionResponse = try await send(request)
        guard let anonymous = response.session else {
            throw PhotoReviveAuthError.requestFailed(
                statusCode: 401,
                message: "Unable to start a feedback session. Please try again."
            )
        }
        let session = PhotoReviveSession(
            accessToken: anonymous.accessToken,
            refreshToken: anonymous.refreshToken,
            expiresAt: Date().addingTimeInterval(anonymous.expiresIn).timeIntervalSince1970
        )
        hasBoundAppContext = true
        boundTimeZoneIdentifier = Self.currentTimeZoneIdentifier
        persist(session)
        return session.accessToken
    }

    func updateProfile(displayName: String? = nil, avatarURL: String? = nil) async throws {
        var metadata: [String: String] = [:]
        if let displayName {
            let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw PhotoReviveAuthError.requestFailed(
                    statusCode: 400,
                    message: "Name cannot be empty."
                )
            }
            metadata["display_name"] = String(normalized.prefix(50))
        }
        if let avatarURL {
            metadata["avatar_url"] = avatarURL
        }
        guard !metadata.isEmpty else { return }

        let token = try await accessToken()
        var request = URLRequest(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("auth/v1/user")
        )
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            PhotoReviveProfileUpdateRequest(data: metadata)
        )

        let _: PhotoReviveUpdatedUser = try await send(request)

        // Refresh so subsequent screens receive the updated user_metadata from
        // the access token instead of relying only on local UI state.
        if let refreshToken = cachedSession?.refreshToken, !refreshToken.isEmpty {
            _ = try? await refreshSession(refreshToken: refreshToken)
        }
    }

    /// Persist the current Adjust attribution against the authenticated user.
    /// The server derives `ad`/`noad` from `network`; this method is intentionally
    /// best-effort so an attribution outage never blocks sign-in.
    func bindAdjustAttributionIfAvailable() async {
        guard let userID = currentUserID,
              let snapshot = AdjustService.shared.attributionSnapshot else {
            return
        }

        do {
            let token = try await accessToken()
            var request = URLRequest(
                url: PhotoReviveAPIConfig.projectURL.appendingPathComponent(
                    "functions/v1/bind-user-adjust-attribution"
                )
            )
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(
                PhotoReviveAdjustAttributionRequest(
                    user_id: userID,
                    app_id: PhotoReviveAPIConfig.appID,
                    adjust_adid: snapshot.adjustAdid,
                    network: snapshot.network,
                    campaign: snapshot.campaign,
                    adgroup: snapshot.adgroup,
                    creative: snapshot.creative,
                    tracker_name: snapshot.trackerName,
                    tracker_token: snapshot.trackerToken,
                    click_label: snapshot.clickLabel,
                    referrer: snapshot.referrer,
                    adjust_environment: snapshot.adjustEnvironment,
                    attribution_data: snapshot.attributionData
                )
            )

            let response: PhotoReviveAdjustAttributionResponse = try await send(request)
            guard response.success else {
                print("[Adjust] Server rejected attribution binding")
                return
            }
            print("[Adjust] Attribution bound for user \(userID)")
        } catch {
            print("[Adjust] Attribution binding failed: \(error.localizedDescription)")
        }
    }

    func signOut() async {
        let accessToken = cachedSession?.accessToken
        clearSession()
        AppAnalytics.signedOut()

        guard let accessToken, !accessToken.isEmpty else { return }

        var request = URLRequest(url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    private func signInWithOpenID(
        provider: PhotoReviveAuthProvider,
        idToken: String,
        accessToken: String?,
        nonce: String?
    ) async throws -> PhotoReviveSession {
        var components = URLComponents(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]

        guard let url = components?.url else {
            throw PhotoReviveAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PhotoReviveIDTokenRequest(
                provider: provider.rawValue,
                id_token: idToken,
                access_token: accessToken,
                nonce: nonce
            )
        )

        let response: PhotoReviveSessionResponse = try await send(request)
        let expiresAt = response.expires_at
            ?? response.expires_in.map { Date().addingTimeInterval($0).timeIntervalSince1970 }
            ?? Date().addingTimeInterval(3600).timeIntervalSince1970

        let session = PhotoReviveSession(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: expiresAt
        )
        try await bindAppContext(accessToken: session.accessToken)
        hasBoundAppContext = true
        persist(session)

        // Refresh once so the access token also contains the new app metadata.
        // The binding itself is already durable, so a transient refresh failure
        // must not discard an otherwise valid OAuth session.
        return (try? await refreshSession(refreshToken: session.refreshToken)) ?? session
    }

    private func refreshSession(refreshToken: String) async throws -> PhotoReviveSession {
        var components = URLComponents(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        guard let url = components?.url else {
            throw PhotoReviveAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let response: PhotoReviveSessionResponse = try await send(request)
        let expiresAt = response.expires_at
            ?? response.expires_in.map { Date().addingTimeInterval($0).timeIntervalSince1970 }
            ?? Date().addingTimeInterval(3600).timeIntervalSince1970
        let session = PhotoReviveSession(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: expiresAt
        )
        persist(session)
        return session
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoReviveAuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.serverErrorMessage(from: data)
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw PhotoReviveAuthError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw PhotoReviveAuthError.invalidResponse
        }
    }

    private func bindAppContextIfNeeded(accessToken: String) async throws {
        let currentTimeZoneIdentifier = Self.currentTimeZoneIdentifier
        guard !hasBoundAppContext || boundTimeZoneIdentifier != currentTimeZoneIdentifier else { return }
        try await bindAppContext(accessToken: accessToken)
        hasBoundAppContext = true
        boundTimeZoneIdentifier = currentTimeZoneIdentifier
    }

    private func bindAppContext(accessToken: String) async throws {
        var request = URLRequest(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent(
                "functions/v1/bind-app-context"
            )
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            PhotoReviveAppContextRequest(
                app_id: PhotoReviveAPIConfig.appID,
                timezone_name: Self.currentTimeZoneIdentifier,
                timezone_abbr: Self.currentTimeZoneAbbreviation
            )
        )

        let response: PhotoReviveAppContextResponse = try await send(request)
        guard response.success, response.app_id == PhotoReviveAPIConfig.appID else {
            throw PhotoReviveAuthError.requestFailed(
                statusCode: 409,
                message: "Unable to bind this account to Photo Revival."
            )
        }
        boundTimeZoneIdentifier = Self.currentTimeZoneIdentifier
    }

    private func persist(_ session: PhotoReviveSession) {
        cachedSession = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        PhotoReviveKeychain.save(data, service: PhotoReviveKeychain.service)
    }

    private func clearSession() {
        cachedSession = nil
        hasBoundAppContext = false
        boundTimeZoneIdentifier = nil
        PhotoReviveKeychain.delete(service: PhotoReviveKeychain.service)
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
    }

    private static func loadStoredSession() -> PhotoReviveSession? {
        guard let data = PhotoReviveKeychain.load(service: PhotoReviveKeychain.service) else { return nil }
        return try? JSONDecoder().decode(PhotoReviveSession.self, from: data)
    }

    private static var currentTimeZoneIdentifier: String {
        let identifier = TimeZone.autoupdatingCurrent.identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? "America/New_York" : identifier
    }

    private static var currentTimeZoneAbbreviation: String? {
        let abbreviation = TimeZone.autoupdatingCurrent.abbreviation()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return abbreviation?.isEmpty == false ? abbreviation : nil
    }

    private static func serverErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return (object["msg"] as? String)
            ?? (object["message"] as? String)
            ?? (object["error_description"] as? String)
            ?? (object["error"] as? String)
    }

    static func randomNonce(length: Int = 32) throws -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var nonce = ""
        nonce.reserveCapacity(length)

        while nonce.count < length {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
                throw PhotoReviveAuthError.invalidResponse
            }
            for byte in randomBytes where nonce.count < length {
                if byte < charset.count { nonce.append(charset[Int(byte)]) }
            }
        }
        return nonce
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func tokenPayload(from accessToken: String) -> [String: Any]? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var encodedPayload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encodedPayload += String(repeating: "=", count: (4 - encodedPayload.count % 4) % 4)

        guard let payloadData = Data(base64Encoded: encodedPayload) else { return nil }
        return try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
    }
}

private enum PhotoReviveKeychain {
    static let service = "com.alihantakaz.photorevival.auth"

    static func save(_ data: Data, service: String) {
        delete(service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct PhotoReviveAppleAuthorizationResult {
    let idToken: String
}

private final class PhotoReviveAppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate {
    private let presentationContextProvider: PhotoReviveAuthPresentationContextProvider
    private let nonceHash: String
    private var authorizationController: ASAuthorizationController?
    private var continuation: CheckedContinuation<PhotoReviveAppleAuthorizationResult, Error>?

    init(
        presentationContextProvider: PhotoReviveAuthPresentationContextProvider,
        nonceHash: String
    ) {
        self.presentationContextProvider = presentationContextProvider
        self.nonceHash = nonceHash
    }

    func start() async throws -> PhotoReviveAppleAuthorizationResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = nonceHash

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = presentationContextProvider
            authorizationController = controller
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityTokenData = credential.identityToken,
            let idToken = String(data: identityTokenData, encoding: .utf8),
            !idToken.isEmpty
        else {
            finish(.failure(PhotoReviveAuthError.invalidResponse))
            return
        }
        finish(.success(PhotoReviveAppleAuthorizationResult(idToken: idToken)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            finish(.failure(PhotoReviveAuthError.signInCancelled))
        } else {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<PhotoReviveAppleAuthorizationResult, Error>) {
        let continuation = continuation
        self.continuation = nil
        authorizationController = nil
        switch result {
        case let .success(value): continuation?.resume(returning: value)
        case let .failure(error): continuation?.resume(throwing: error)
        }
    }
}

private struct PhotoReviveGoogleConfiguration {
    let clientID: String
    let serverClientID: String

    static func load() throws -> PhotoReviveGoogleConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        guard
            let clientID = info["GIDClientID"] as? String,
            let serverClientID = info["GIDServerClientID"] as? String,
            !clientID.isEmpty,
            !serverClientID.isEmpty,
            !clientID.contains("REPLACE")
        else {
            throw PhotoReviveAuthError.missingGoogleConfiguration
        }
        return PhotoReviveGoogleConfiguration(clientID: clientID, serverClientID: serverClientID)
    }
}

private struct PhotoReviveGoogleAuthorizationResult {
    let idToken: String
    let accessToken: String
    let nonce: String
}

struct PhotoReviveGoogleNonce {
    let rawValue: String

    var hashedValue: String {
        PhotoReviveAuthClient.sha256(rawValue)
    }

    static func make() throws -> PhotoReviveGoogleNonce {
        PhotoReviveGoogleNonce(rawValue: try PhotoReviveAuthClient.randomNonce())
    }
}

private final class PhotoReviveGoogleSignInCoordinator {
    private let configuration: PhotoReviveGoogleConfiguration
    private let presentationContextProvider: PhotoReviveAuthPresentationContextProvider

    init(
        configuration: PhotoReviveGoogleConfiguration,
        presentationContextProvider: PhotoReviveAuthPresentationContextProvider
    ) {
        self.configuration = configuration
        self.presentationContextProvider = presentationContextProvider
    }

    func start() async throws -> PhotoReviveGoogleAuthorizationResult {
        guard let presentingViewController = presentationContextProvider.currentViewController() else {
            throw PhotoReviveAuthError.requestFailed(statusCode: 500, message: "Could not present Google Sign-In.")
        }

        let nonce = try PhotoReviveGoogleNonce.make()

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: configuration.clientID,
            serverClientID: configuration.serverClientID
        )

        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: nil,
                nonce: nonce.hashedValue
            ) { result, error in
                if let error {
                    if (error as NSError).domain == kGIDSignInErrorDomain,
                       (error as NSError).code == GIDSignInError.canceled.rawValue {
                        continuation.resume(throwing: PhotoReviveAuthError.signInCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard
                    let user = result?.user,
                    let idToken = user.idToken?.tokenString,
                    !idToken.isEmpty
                else {
                    continuation.resume(throwing: PhotoReviveAuthError.invalidResponse)
                    return
                }

                continuation.resume(
                    returning: PhotoReviveGoogleAuthorizationResult(
                        idToken: idToken,
                        accessToken: user.accessToken.tokenString,
                        nonce: nonce.rawValue
                    )
                )
            }
        }
    }
}

private final class PhotoReviveAuthPresentationContextProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.windows.contains(where: \.isKeyWindow) })
        guard let scene else {
            fatalError("Apple Sign-In requires an active window scene.")
        }
        return ASPresentationAnchor(windowScene: scene)
    }

    func currentViewController() -> UIViewController? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return nil
        }

        var controller = window.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
