import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import GoogleSignIn
import Security
import UIKit

enum PhotoReviveAPIConfig {
    static let projectURL = URL(string: "https://lrenlgqppvqfbibxppbi.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxyZW5sZ3FwcHZxZmJpYnhwcGJpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI1MTIxODMsImV4cCI6MjA3ODA4ODE4M30.xVbKv4Es1sZRtWYsqbcu4eBoL1XZlMcyLcEJTTpddP4"
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

private struct PhotoReviveIDTokenRequest: Encodable {
    let provider: String
    let id_token: String
    let access_token: String?
    let nonce: String?
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
                        accessToken: result.accessToken
                    )
                }

                UserDefaults.standard.set(true, forKey: "isLoggedIn")
                didAuthenticate = true
            } catch let error as PhotoReviveAuthError {
                if case .signInCancelled = error {
                    errorMessage = nil
                } else {
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            activeProvider = nil
        }
    }
}

@MainActor
final class PhotoReviveAuthClient {
    static let shared = PhotoReviveAuthClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private var cachedSession: PhotoReviveSession?

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

    func signInWithApple(idToken: String, nonce: String) async throws -> PhotoReviveSession {
        try await signInWithOpenID(
            provider: .apple,
            idToken: idToken,
            accessToken: nil,
            nonce: nonce
        )
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> PhotoReviveSession {
        try await signInWithOpenID(
            provider: .google,
            idToken: idToken,
            accessToken: accessToken,
            nonce: nil
        )
    }

    func accessToken() async throws -> String {
        guard let cachedSession else {
            throw PhotoReviveAuthError.requestFailed(statusCode: 401, message: "Please sign in to continue.")
        }

        if cachedSession.isFresh {
            return cachedSession.accessToken
        }

        guard !cachedSession.refreshToken.isEmpty else {
            clearSession()
            throw PhotoReviveAuthError.requestFailed(statusCode: 401, message: "Your session has expired. Please sign in again.")
        }

        do {
            let refreshed = try await refreshSession(refreshToken: cachedSession.refreshToken)
            return refreshed.accessToken
        } catch {
            clearSession()
            throw error
        }
    }

    func signOut() async {
        let accessToken = cachedSession?.accessToken
        clearSession()

        guard let accessToken, !accessToken.isEmpty else { return }

        var request = URLRequest(url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(PhotoReviveAPIConfig.anonKey, forHTTPHeaderField: "apikey")
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
        request.setValue(PhotoReviveAPIConfig.anonKey, forHTTPHeaderField: "apikey")
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
        persist(session)
        return session
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
        request.setValue(PhotoReviveAPIConfig.anonKey, forHTTPHeaderField: "apikey")
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

    private func persist(_ session: PhotoReviveSession) {
        cachedSession = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        PhotoReviveKeychain.save(data, service: PhotoReviveKeychain.service)
    }

    private func clearSession() {
        cachedSession = nil
        PhotoReviveKeychain.delete(service: PhotoReviveKeychain.service)
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
    }

    private static func loadStoredSession() -> PhotoReviveSession? {
        guard let data = PhotoReviveKeychain.load(service: PhotoReviveKeychain.service) else { return nil }
        return try? JSONDecoder().decode(PhotoReviveSession.self, from: data)
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

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: configuration.clientID,
            serverClientID: configuration.serverClientID
        )

        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
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
                        accessToken: user.accessToken.tokenString
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
