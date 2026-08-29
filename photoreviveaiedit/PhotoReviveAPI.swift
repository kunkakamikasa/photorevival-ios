import Combine
import Foundation

enum PhotoReviveAPIError: LocalizedError {
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case .requestFailed(_, let message):
            EnglishDisplayText.userFacingMessage(
                message,
                fallback: "The request failed. Please try again."
            )
        }
    }
}

struct PhotoReviveUserStatus: Decodable {
    let subscriptionStatus: String?
    let subscriptionExpireAt: String?
    let planType: String?
    let productID: String?
    let creditsBalance: Int
    let isAnonymous: Bool?

    enum CodingKeys: String, CodingKey {
        case subscriptionStatus = "subscription_status"
        case subscriptionExpireAt = "subscription_expire_at"
        case planType = "plan_type"
        case productID = "product_id"
        case creditsBalance = "credits_balance"
        case isAnonymous = "is_anonymous"
    }
}

struct SubscriptionVerificationResult: Decodable {
    let success: Bool
    let subscriptionStatus: String?
    let subscriptionExpireAt: String?
    let planType: String?
    let productID: String?
    let creditsBalance: Int?
    let creditsGranted: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success, message
        case subscriptionStatus = "subscription_status"
        case subscriptionExpireAt = "subscription_expire_at"
        case planType = "plan_type"
        case productID = "product_id"
        case creditsBalance = "credits_balance"
        case creditsGranted = "credits_granted"
    }
}

struct AppleIAPVerificationResult: Decodable {
    let success: Bool
    let type: String?
    let productID: String?
    let creditsGranted: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success, type, message
        case productID = "product_id"
        case creditsGranted = "credits_granted"
    }
}

struct DailyCheckInReward: Identifiable, Decodable {
    let day: Int
    let credits: Int
    let status: String

    var id: Int { day }
}

struct DailyCheckInStatus: Decodable {
    let isActive: Bool
    let signedToday: Bool
    let claimableDay: Int?
    let claimableCredits: Int
    let currentStreakDay: Int
    let sortOrder: Int?
    let rewards: [DailyCheckInReward]

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case signedToday = "signed_today"
        case claimableDay = "claimable_day"
        case claimableCredits = "claimable_credits"
        case currentStreakDay = "current_streak_day"
        case sortOrder = "sort_order"
        case rewards
    }
}

enum RewardCenterGroupKey: String, Decodable {
    case dailyFreeCredits = "daily_free_credits"
    case specialOffer = "special_offer"
    case oneTimeRewards = "one_time_rewards"
}

struct RewardCenterGroup: Identifiable, Decodable {
    let key: RewardCenterGroupKey
    let title: String
    let sortOrder: Int
    let isActive: Bool?

    var id: String { key.rawValue }
    var displayTitle: String {
        EnglishDisplayText.title(title, fallback: key.defaultTitle)
    }

    enum CodingKeys: String, CodingKey {
        case key = "group_key"
        case title
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    static let defaults = [
        RewardCenterGroup(key: .dailyFreeCredits, title: "Daily Free Credits", sortOrder: 1, isActive: true),
        RewardCenterGroup(key: .specialOffer, title: "Special Offer", sortOrder: 2, isActive: true),
        RewardCenterGroup(key: .oneTimeRewards, title: "One-Time Rewards", sortOrder: 3, isActive: true)
    ]
}

private extension RewardCenterGroupKey {
    var defaultTitle: String {
        switch self {
        case .dailyFreeCredits: "Daily Free Credits"
        case .specialOffer: "Special Offer"
        case .oneTimeRewards: "One-Time Rewards"
        }
    }
}

struct RewardCenterSpecialOfferConfig: Decodable {
    let isActive: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case sortOrder = "sort_order"
    }

    static let defaultValue = RewardCenterSpecialOfferConfig(isActive: true, sortOrder: 1)
}

struct DailyCheckInResult: Decodable {
    let alreadySignedToday: Bool
    let creditsGranted: Int
    let creditsBalance: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case alreadySignedToday = "already_signed_today"
        case creditsGranted = "credits_granted"
        case creditsBalance = "credits_balance"
        case message
    }
}

struct RewardTaskClaim: Decodable {
    let status: String
    let creditsGranted: Int

    enum CodingKeys: String, CodingKey {
        case status
        case creditsGranted = "credits_granted"
    }
}

struct RewardTask: Identifiable, Decodable {
    let appID: String
    let taskCode: String
    let title: String
    let rewardCredits: Int
    let verificationMode: String
    let repeatPolicy: String
    let rewardCenterGroup: RewardCenterGroupKey?
    let sortOrder: Int
    let claim: RewardTaskClaim?

    var id: String { taskCode }
    var displayTitle: String { EnglishDisplayText.title(title, fallback: "Reward") }
    var isClaimed: Bool { claim != nil }
    var requiresServerVerification: Bool { verificationMode == "server_verified" }

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case taskCode = "task_code"
        case title
        case rewardCredits = "reward_credits"
        case verificationMode = "verification_mode"
        case repeatPolicy = "repeat_policy"
        case rewardCenterGroup = "reward_center_group"
        case sortOrder = "sort_order"
        case claim
    }
}

struct RewardTasksStatus: Decodable {
    let tasks: [RewardTask]
    let groups: [RewardCenterGroup]?
    let specialOffer: RewardCenterSpecialOfferConfig?

    enum CodingKeys: String, CodingKey {
        case tasks, groups
        case specialOffer = "special_offer"
    }
}

struct RewardTaskClaimResult: Decodable {
    let claimed: Bool
    let status: String
    let taskCode: String?
    let creditsGranted: Int
    let creditsBalance: Int?
    let creditsExpireAt: String?

    enum CodingKeys: String, CodingKey {
        case claimed, status
        case taskCode = "task_code"
        case creditsGranted = "credits_granted"
        case creditsBalance = "credits_balance"
        case creditsExpireAt = "credits_expire_at"
    }
}

struct ReferralRewardConfig: Decodable {
    let signupReferrerCredits: Int
    let signupReferredCredits: Int
    let subscriptionReferrerCredits: Int

    enum CodingKeys: String, CodingKey {
        case signupReferrerCredits = "signup_referrer_credits"
        case signupReferredCredits = "signup_referred_credits"
        case subscriptionReferrerCredits = "subscription_referrer_credits"
    }
}

struct ReferralStats: Decodable {
    let invitedCount: Int
    let subscriptionRewardedCount: Int

    enum CodingKeys: String, CodingKey {
        case invitedCount = "invited_count"
        case subscriptionRewardedCount = "subscription_rewarded_count"
    }
}

struct ReferralStatus: Decodable {
    let invitationCode: String
    let rewardConfig: ReferralRewardConfig?
    let stats: ReferralStats
    let hasRedeemedReferral: Bool
    let isActive: Bool
    let sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case code
        case rewardConfig = "reward_config"
        case stats
        case redeemedReferral = "redeemed_referral"
        case isActive = "is_active"
        case sortOrder = "sort_order"
    }

    private struct CodeRecord: Decodable {
        let code: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringCode = try? container.decode(String.self, forKey: .code) {
            invitationCode = stringCode
        } else {
            invitationCode = try container.decode(CodeRecord.self, forKey: .code).code
        }
        rewardConfig = try container.decodeIfPresent(ReferralRewardConfig.self, forKey: .rewardConfig)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 30
        stats = try container.decodeIfPresent(ReferralStats.self, forKey: .stats)
            ?? ReferralStats(invitedCount: 0, subscriptionRewardedCount: 0)
        if container.contains(.redeemedReferral) {
            hasRedeemedReferral = !(try container.decodeNil(forKey: .redeemedReferral))
        } else {
            hasRedeemedReferral = false
        }
    }
}

struct ReferralRedemptionResult: Decodable {
    let redeemed: Bool
    let status: String
    let referredRewardCredits: Int?
    let referrerRewardCredits: Int?
    let creditsBalance: Int?
    let signupRewardCredits: Int?

    enum CodingKeys: String, CodingKey {
        case redeemed, status
        case referredRewardCredits = "referred_reward_credits"
        case referrerRewardCredits = "referrer_reward_credits"
        case creditsBalance = "credits_balance"
        case signupRewardCredits = "signup_reward_credits"
    }
}

struct CreditWallet: Decodable {
    let recurringBalance: Int
    let lifetimeBalance: Int

    var total: Int { recurringBalance + lifetimeBalance }

    enum CodingKeys: String, CodingKey {
        case recurringBalance = "recurring_balance"
        case lifetimeBalance = "lifetime_balance"
    }
}

struct CreditTransactionRecord: Identifiable, Decodable {
    let id: String
    let amount: Int
    let transactionType: String
    let source: String
    let description: String?
    let createdAt: String

    var isSpent: Bool { transactionType == "spent" || amount < 0 }

    enum CodingKeys: String, CodingKey {
        case id, amount, source, description
        case transactionType = "transaction_type"
        case createdAt = "created_at"
    }
}

struct CreditTransactionsResponse: Decodable {
    let wallet: CreditWallet
    let transactions: [CreditTransactionRecord]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case wallet, transactions
        case nextCursor = "next_cursor"
    }
}

struct GenerationHistoryTask: Identifiable, Decodable {
    let id: String
    let scene: String?
    let status: String
    let outputURL: String?
    let convertedURL: String?
    let thumbnailURL: String?
    let thumbnailSource: String?
    let creditsUsed: Int?
    let createdAt: String
    let contentType: String?
    let sectionMenu: String?
    let errorMessage: String?

    var resultURL: URL? {
        (convertedURL ?? outputURL).flatMap(URL.init(string:))
    }

    var coverURL: URL? {
        thumbnailURL.flatMap(URL.init(string:)) ?? (isVideo ? nil : resultURL)
    }

    var isVideo: Bool {
        contentType == "video" || sectionMenu == "video" || resultURL?.pathExtension.lowercased() == "mp4"
    }

    var userFacingErrorMessage: String {
        EnglishDisplayText.userFacingMessage(
            errorMessage,
            fallback: "Generation failed. Please try again."
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, scene, status
        case outputURL = "output_url"
        case convertedURL = "converted_url"
        case thumbnailURL = "thumbnail_url"
        case thumbnailSource = "thumbnail_source"
        case creditsUsed = "credits_used"
        case createdAt = "created_at"
        case contentType = "content_type"
        case sectionMenu = "section_menu"
        case errorMessage = "error_message"
    }
}

struct GenerationHistoryResponse: Decodable {
    let tasks: [GenerationHistoryTask]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case tasks
        case nextCursor = "next_cursor"
    }
}

struct PhotoReviveVideoGenerationOptions: Encodable, Equatable {
    let resolution: String
    let aspectRatio: String
    let duration: Int
    let sound: Bool
    let multiShot: Bool

    enum CodingKeys: String, CodingKey {
        case resolution
        case aspectRatio = "aspect_ratio"
        case duration, sound
        case multiShot = "multi_shot"
    }
}

struct PhotoReviveVideoGenerationSubmission: Decodable {
    let taskID: String
    let creditsUsed: Int
    let creditsBalance: Int

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case creditsUsed = "credits_used"
        case creditsBalance = "credits_balance"
    }
}

struct PhotoReviveImageGenerationOptions: Encodable {
    static let providerDefaultResolution = "2K"

    let resolution: String
    let aspectRatio: String
    let outputCount: Int

    enum CodingKeys: String, CodingKey {
        case resolution
        case aspectRatio = "aspect_ratio"
        case outputCount = "output_count"
    }
}

struct PhotoReviveImageGenerationSubmission: Decodable {
    let taskID: String
    let outputURL: String
    let creditsUsed: Int
    let creditsBalance: Int

    var resultURL: URL? { URL(string: outputURL) }

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case outputURL = "output_url"
        case creditsUsed = "credits_used"
        case creditsBalance = "credits_balance"
    }
}

struct PhotoReviveGenerationTask: Decodable {
    let id: String
    let status: String
    let outputURL: String?
    let convertedURL: String?
    let errorMessage: String?

    var resultURL: URL? {
        (convertedURL ?? outputURL).flatMap(URL.init(string:))
    }

    func userFacingErrorMessage(fallback: String) -> String {
        EnglishDisplayText.userFacingMessage(errorMessage, fallback: fallback)
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case outputURL = "output_url"
        case convertedURL = "converted_url"
        case errorMessage = "error_message"
    }
}

private struct PhotoReviveImageUploadResponse: Decodable {
    let imageURL: String

    private enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let canonicalURL = try container.decodeIfPresent(String.self, forKey: .imageURL),
           !canonicalURL.isEmpty {
            imageURL = canonicalURL
        } else {
            imageURL = try container.decode(String.self, forKey: .url)
        }
    }
}

struct SuggestionSubmissionResult: Decodable {
    let success: Bool
    let id: String
    let createdAt: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success, id, message
        case createdAt = "created_at"
    }
}

struct AccountDeletionResult: Decodable {
    let success: Bool
    let message: String?
}

@MainActor
final class PhotoReviveAPIClient {
    static let shared = PhotoReviveAPIClient()
    static let longRunningGenerationTimeout: TimeInterval = 300

    private let authClient: PhotoReviveAuthClient
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(authClient: PhotoReviveAuthClient? = nil, session: URLSession? = nil) {
        self.authClient = authClient ?? .shared
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 20
            // Some CMS video templates synchronously preprocess or merge the
            // uploaded images before returning a task ID. Image generation
            // endpoints can likewise take over a minute before responding.
            configuration.timeoutIntervalForResource = Self.longRunningGenerationTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    func userStatus() async throws -> PhotoReviveUserStatus {
        try await get("user-status")
    }

    func verifySubscription(
        transactionID: String,
        signedTransactionInfo: String
    ) async throws -> SubscriptionVerificationResult {
        try await post(
            "subscription-verify",
            body: SubscriptionVerificationRequest(
                transactionID: transactionID,
                signedTransactionInfo: signedTransactionInfo
            )
        )
    }

    func verifyAppleIAP(
        transactionID: String,
        signedTransactionInfo: String
    ) async throws -> AppleIAPVerificationResult {
        try await post(
            "apple-iap-verify",
            body: AppleIAPVerificationRequest(
                transactionID: transactionID,
                signedTransactionInfo: signedTransactionInfo
            )
        )
    }

    func dailyCheckInStatus() async throws -> DailyCheckInStatus {
        try await get("daily-checkin-status")
    }

    func signDailyCheckIn() async throws -> DailyCheckInResult {
        try await post("daily-checkin-sign", body: EmptyBody())
    }

    func rewardTasksStatus() async throws -> RewardTasksStatus {
        try await get("reward-tasks-status", query: ["app_id": PhotoReviveAPIConfig.appID])
    }

    func claimRewardTask(code: String, evidence: [String: String] = [:]) async throws -> RewardTaskClaimResult {
        try await post(
            "claim-reward-task",
            body: RewardClaimRequest(
                taskCode: code,
                evidence: evidence,
                appID: PhotoReviveAPIConfig.appID
            )
        )
    }

    func referralStatus() async throws -> ReferralStatus {
        try await get("referral-status", query: ["app_id": PhotoReviveAPIConfig.appID])
    }

    func redeemReferral(code: String, deviceKey: String) async throws -> ReferralRedemptionResult {
        try await post(
            "redeem-referral",
            body: ReferralRedemptionRequest(
                code: code,
                deviceKey: deviceKey,
                appID: PhotoReviveAPIConfig.appID
            )
        )
    }

    func creditTransactions(type: String? = nil) async throws -> CreditTransactionsResponse {
        var query = ["limit": "100"]
        if let type { query["type"] = type }
        return try await get("credit-transactions", query: query)
    }

    func generationHistory(cursor: String? = nil, limit: Int = 50) async throws -> GenerationHistoryResponse {
        var query = ["limit": String(min(max(limit, 1), 100))]
        if let cursor, !cursor.isEmpty { query["cursor"] = cursor }
        return try await get("photorevive-history", query: query)
    }

    func uploadGenerationImage(_ imageData: Data) async throws -> String {
        let boundary = "PhotoReviveGenerationBoundary-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"generation.jpg\"\r\n")
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("functions/v1/upload-image")
        )
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let response: PhotoReviveImageUploadResponse = try await send(request)
        return response.imageURL
    }

    func uploadProfileAvatar(_ imageData: Data) async throws -> String {
        let boundary = "PhotoReviveAvatarBoundary-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"profile-avatar.jpg\"\r\n")
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("functions/v1/upload-image")
        )
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let response: PhotoReviveImageUploadResponse = try await send(request)
        return response.imageURL
    }

    func createImageToVideo(
        itemID: String,
        imageURLs: [String],
        prompt: String?,
        appVersion: String?,
        options: PhotoReviveVideoGenerationOptions
    ) async throws -> PhotoReviveVideoGenerationSubmission {
        guard let firstImageURL = imageURLs.first else {
            throw PhotoReviveAPIError.invalidResponse
        }
        return try await post(
            "image-to-video",
            body: PhotoReviveImageToVideoRequest(
                itemID: itemID,
                imageURL: imageURLs.count == 1 ? .single(firstImageURL) : .multiple(imageURLs),
                prompt: prompt,
                version: appVersion,
                resolution: options.resolution,
                aspectRatio: options.aspectRatio,
                duration: options.duration,
                sound: options.sound,
                multiShot: options.multiShot
            ),
            timeoutInterval: Self.longRunningGenerationTimeout
        )
    }

    func createImageToImage(
        itemID: String,
        imageURLs: [String],
        prompt: String?,
        options: PhotoReviveImageGenerationOptions
    ) async throws -> PhotoReviveImageGenerationSubmission {
        guard let firstImageURL = imageURLs.first else {
            throw PhotoReviveAPIError.invalidResponse
        }
        return try await post(
            "image-to-image",
            body: PhotoReviveImageToImageRequest(
                itemID: itemID,
                imageURL: imageURLs.count == 1 ? .single(firstImageURL) : .multiple(imageURLs),
                prompt: prompt,
                resolution: options.resolution,
                aspectRatio: options.aspectRatio,
                outputCount: options.outputCount
            ),
            timeoutInterval: Self.longRunningGenerationTimeout
        )
    }

    func createTextToImage(
        itemID: String,
        prompt: String?,
        options: PhotoReviveImageGenerationOptions
    ) async throws -> PhotoReviveImageGenerationSubmission {
        try await post(
            "text-to-image",
            body: PhotoReviveTextToImageRequest(
                itemID: itemID,
                prompt: prompt,
                resolution: options.resolution,
                aspectRatio: options.aspectRatio,
                outputCount: options.outputCount
            ),
            timeoutInterval: Self.longRunningGenerationTimeout
        )
    }

    func createTextToVideo(
        itemID: String,
        prompt: String?,
        options: PhotoReviveVideoGenerationOptions
    ) async throws -> PhotoReviveVideoGenerationSubmission {
        try await post(
            "text-to-video",
            body: PhotoReviveTextToVideoRequest(
                itemID: itemID,
                prompt: prompt,
                resolution: options.resolution,
                aspectRatio: options.aspectRatio,
                duration: options.duration,
                sound: options.sound,
                multiShot: options.multiShot
            )
        )
    }

    func generationTask(id: String) async throws -> PhotoReviveGenerationTask {
        try await get("get-task", query: ["task_id": id])
    }

    func deleteHistoryTask(id: String) async throws {
        let _: DeleteTaskResponse = try await post("delete-task", body: DeleteTaskRequest(taskID: id))
    }

    func deleteAccount() async throws -> AccountDeletionResult {
        var request = URLRequest(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("functions/v1/delete-account")
        )
        request.httpMethod = "DELETE"
        return try await send(request)
    }

    func submitSuggestion(
        content: String,
        contactEmail: String,
        screenshotData: Data?
    ) async throws -> SuggestionSubmissionResult {
        try await submitFeedbackRequest(
            content: content,
            contactEmail: contactEmail,
            screenshotData: screenshotData,
            feedbackType: "suggestion"
        )
    }

    func submitFeedback(
        content: String,
        contactEmail: String,
        screenshotData: Data?
    ) async throws -> SuggestionSubmissionResult {
        try await submitFeedbackRequest(
            content: content,
            contactEmail: contactEmail,
            screenshotData: screenshotData,
            feedbackType: "feedback"
        )
    }

    private func submitFeedbackRequest(
        content: String,
        contactEmail: String,
        screenshotData: Data?,
        feedbackType: String
    ) async throws -> SuggestionSubmissionResult {
        let token = try await authClient.feedbackAccessToken()
        let attachmentURL: String?
        if let screenshotData {
            attachmentURL = try await uploadSuggestionScreenshot(
                screenshotData,
                accessToken: token
            )
        } else {
            attachmentURL = nil
        }

        var request = URLRequest(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent(
                "functions/v1/submit-feedback"
            )
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            SuggestionSubmissionRequest(
                content: content,
                contactEmail: contactEmail,
                feedbackType: feedbackType,
                attachmentURL: attachmentURL,
                appVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String
            )
        )
        return try await send(request, accessToken: token)
    }

    private func get<Response: Decodable>(
        _ path: String,
        query: [String: String] = [:]
    ) async throws -> Response {
        var components = URLComponents(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("functions/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw PhotoReviveAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func post<Response: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> Response {
        var request = URLRequest(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("functions/v1/\(path)")
        )
        request.httpMethod = "POST"
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    private func uploadSuggestionScreenshot(
        _ screenshotData: Data,
        accessToken: String
    ) async throws -> String {
        let boundary = "PhotoReviveBoundary-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"suggestion.jpg\"\r\n")
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(screenshotData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent(
                "functions/v1/upload-image"
            )
        )
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        let response: SuggestionScreenshotUploadResponse = try await send(
            request,
            accessToken: accessToken
        )
        return response.imageURL
    }

    private func send<Response: Decodable>(
        _ originalRequest: URLRequest,
        accessToken suppliedAccessToken: String? = nil
    ) async throws -> Response {
        var request = originalRequest
        let token: String
        if let suppliedAccessToken {
            token = suppliedAccessToken
        } else {
            token = try await authClient.accessToken()
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw PhotoReviveAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw PhotoReviveAPIError.requestFailed(
                statusCode: response.statusCode,
                message: Self.errorMessage(from: data)
            )
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw PhotoReviveAPIError.invalidResponse
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return (object["message"] as? String)
            ?? (object["error"] as? String)
            ?? (object["msg"] as? String)
            ?? ""
    }
}

private struct EmptyBody: Encodable {}

private enum PhotoReviveImageURLRequestValue: Encodable {
    case single(String)
    case multiple([String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let url):
            try container.encode(url)
        case .multiple(let urls):
            try container.encode(urls)
        }
    }
}

private struct PhotoReviveImageToVideoRequest: Encodable {
    let itemID: String
    let imageURL: PhotoReviveImageURLRequestValue
    let prompt: String?
    let version: String?
    let resolution: String
    let aspectRatio: String
    let duration: Int
    let sound: Bool
    let multiShot: Bool

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case imageURL = "image_url"
        case prompt, version, resolution, duration, sound
        case aspectRatio = "aspect_ratio"
        case multiShot = "multi_shot"
    }
}

private struct PhotoReviveImageToImageRequest: Encodable {
    let itemID: String
    let imageURL: PhotoReviveImageURLRequestValue
    let prompt: String?
    let resolution: String
    let aspectRatio: String
    let outputCount: Int

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case imageURL = "image_url"
        case prompt, resolution
        case aspectRatio = "aspect_ratio"
        case outputCount = "output_count"
    }
}

private struct PhotoReviveTextToImageRequest: Encodable {
    let itemID: String
    let prompt: String?
    let resolution: String
    let aspectRatio: String
    let outputCount: Int

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case prompt, resolution
        case aspectRatio = "aspect_ratio"
        case outputCount = "output_count"
    }
}

private struct PhotoReviveTextToVideoRequest: Encodable {
    let itemID: String
    let prompt: String?
    let resolution: String
    let aspectRatio: String
    let duration: Int
    let sound: Bool
    let multiShot: Bool

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case prompt, resolution, duration, sound
        case aspectRatio = "aspect_ratio"
        case multiShot = "multi_shot"
    }
}

private struct SubscriptionVerificationRequest: Encodable {
    let transactionID: String
    let signedTransactionInfo: String

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case signedTransactionInfo = "signed_transaction_info"
    }
}

private struct AppleIAPVerificationRequest: Encodable {
    let transactionID: String
    let signedTransactionInfo: String

    enum CodingKeys: String, CodingKey {
        case transactionID = "transactionId"
        case signedTransactionInfo
    }
}

private struct RewardClaimRequest: Encodable {
    let taskCode: String
    let evidence: [String: String]
    let appID: String

    enum CodingKeys: String, CodingKey {
        case taskCode = "task_code"
        case evidence
        case appID = "app_id"
    }
}

private struct ReferralRedemptionRequest: Encodable {
    let code: String
    let deviceKey: String
    let appID: String

    enum CodingKeys: String, CodingKey {
        case code
        case deviceKey = "device_key"
        case appID = "app_id"
    }
}

private struct DeleteTaskRequest: Encodable {
    let taskID: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
    }
}

private struct DeleteTaskResponse: Decodable {
    let success: Bool?
}

private struct SuggestionSubmissionRequest: Encodable {
    let content: String
    let contactEmail: String
    let feedbackType: String
    let attachmentURL: String?
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case content
        case contactEmail = "contact_email"
        case feedbackType = "feedback_type"
        case attachmentURL = "attachment_url"
        case appVersion = "app_version"
    }
}

private struct SuggestionScreenshotUploadResponse: Decodable {
    let imageURL: String

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }
}

@MainActor
final class AppAccountStore: ObservableObject {
    static let shared = AppAccountStore()

    @Published private(set) var creditsBalance = 0
    @Published private(set) var hasLoadedCredits = false
    @Published private(set) var userStatus: PhotoReviveUserStatus?
    @Published private(set) var checkInStatus: DailyCheckInStatus?
    @Published private(set) var rewardTasks: [RewardTask] = []
    @Published private(set) var rewardGroups: [RewardCenterGroup] = RewardCenterGroup.defaults
    @Published private(set) var specialOfferConfig = RewardCenterSpecialOfferConfig.defaultValue
    @Published private(set) var referralStatus: ReferralStatus?
    @Published private(set) var creditWallet: CreditWallet?
    @Published private(set) var creditTransactions: [CreditTransactionRecord] = []
    @Published private(set) var historyTasks: [GenerationHistoryTask] = []
    @Published private(set) var isLoadingRewards = false
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var isLoadingMoreHistory = false
    @Published private(set) var hasMoreHistory = false
    @Published var lastErrorMessage: String?

    private let api: PhotoReviveAPIClient
    private var nextHistoryCursor: String?

    init(api: PhotoReviveAPIClient? = nil) {
        self.api = api ?? .shared
    }

    var isAuthenticated: Bool {
        PhotoReviveAuthClient.shared.currentUserID != nil
    }

    /// `-loggedIn` is a debug/UI-test presentation override, not a real auth
    /// session. Give that preview mode an anonymous server session so screens
    /// still load the real CMS-controlled reward configuration.
    func prepareRewardSessionIfNeeded() async {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-loggedIn"),
              !isAuthenticated else { return }
        do {
            _ = try await PhotoReviveAuthClient.shared.feedbackAccessToken()
        } catch {
            lastErrorMessage = error.userFacingEnglishMessage()
        }
#endif
    }

    func resetForSignedOutUser() {
        creditsBalance = 0
        hasLoadedCredits = false
        userStatus = nil
        checkInStatus = nil
        rewardTasks = []
        rewardGroups = RewardCenterGroup.defaults
        specialOfferConfig = .defaultValue
        referralStatus = nil
        creditWallet = nil
        creditTransactions = []
        historyTasks = []
        nextHistoryCursor = nil
        hasMoreHistory = false
        lastErrorMessage = nil
    }

    func refreshCredits() async {
        guard isAuthenticated else {
            resetForSignedOutUser()
            return
        }
        do {
            let status = try await api.userStatus()
            userStatus = status
            creditsBalance = status.creditsBalance
            hasLoadedCredits = true
            reconcileSubscriptionStatus(status.subscriptionStatus)
        } catch {
            lastErrorMessage = error.userFacingEnglishMessage()
        }
    }

    func applySubscriptionVerification(_ result: SubscriptionVerificationResult) {
        if let balance = result.creditsBalance {
            creditsBalance = balance
            hasLoadedCredits = true
        }
        reconcileSubscriptionStatus(result.subscriptionStatus)
    }

    private func reconcileSubscriptionStatus(_ rawStatus: String?) {
        guard let status = rawStatus?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !status.isEmpty else { return }

        let entitledStatuses: Set<String> = [
            "active",
            "trial",
            "trialing",
            "grace_period",
            "billing_retry"
        ]
        UserDefaults.standard.set(entitledStatuses.contains(status), forKey: "isSubscribed")
    }

    func refreshRewards() async {
        guard isAuthenticated else {
            resetForSignedOutUser()
            return
        }
        isLoadingRewards = true
        defer { isLoadingRewards = false }

        let checkInTask = Task { try await api.dailyCheckInStatus() }
        let rewardsTask = Task { try await api.rewardTasksStatus() }
        let referralTask = Task { try await api.referralStatus() }

        do { checkInStatus = try await checkInTask.value } catch { lastErrorMessage = error.userFacingEnglishMessage() }
        do {
            let response = try await rewardsTask.value
            rewardTasks = response.tasks
            if let groups = response.groups, !groups.isEmpty {
                rewardGroups = groups
            } else {
                rewardGroups = RewardCenterGroup.defaults
            }
            specialOfferConfig = response.specialOffer ?? .defaultValue
        } catch {
            lastErrorMessage = error.userFacingEnglishMessage()
        }
        do { referralStatus = try await referralTask.value } catch { lastErrorMessage = error.userFacingEnglishMessage() }
    }

    func refreshCreditTransactions() async {
        guard isAuthenticated else { return }
        do {
            let response = try await api.creditTransactions()
            creditWallet = response.wallet
            creditTransactions = response.transactions
            creditsBalance = response.wallet.total
            hasLoadedCredits = true
        } catch {
            lastErrorMessage = error.userFacingEnglishMessage()
        }
    }

    func refreshHistory() async {
        guard isAuthenticated else {
            historyTasks = []
            nextHistoryCursor = nil
            hasMoreHistory = false
            return
        }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let response = try await api.generationHistory()
            historyTasks = response.tasks
            nextHistoryCursor = response.nextCursor
            hasMoreHistory = response.nextCursor != nil
        } catch {
            lastErrorMessage = error.userFacingEnglishMessage()
        }
    }

    func loadMoreHistory() async {
        guard isAuthenticated,
              !isLoadingHistory,
              !isLoadingMoreHistory,
              let cursor = nextHistoryCursor else { return }

        isLoadingMoreHistory = true
        defer { isLoadingMoreHistory = false }
        do {
            let response = try await api.generationHistory(cursor: cursor)
            let knownIDs = Set(historyTasks.map(\.id))
            historyTasks.append(contentsOf: response.tasks.filter { !knownIDs.contains($0.id) })
            nextHistoryCursor = response.nextCursor
            hasMoreHistory = response.nextCursor != nil
        } catch {
            lastErrorMessage = error.userFacingEnglishMessage()
        }
    }

    func refreshAll() async {
        await prepareRewardSessionIfNeeded()
        guard isAuthenticated else {
            resetForSignedOutUser()
            return
        }
        let creditsTask = Task { await refreshCredits() }
        let rewardsTask = Task { await refreshRewards() }
        let transactionsTask = Task { await refreshCreditTransactions() }
        let historyTask = Task { await refreshHistory() }
        _ = await (creditsTask.value, rewardsTask.value, transactionsTask.value, historyTask.value)
    }

    func checkIn() async throws -> DailyCheckInResult {
        let result = try await api.signDailyCheckIn()
        if let balance = result.creditsBalance {
            creditsBalance = balance
            hasLoadedCredits = true
        }
        checkInStatus = try await api.dailyCheckInStatus()
        await refreshCreditTransactions()
        return result
    }

    func claimRewardTask(
        _ task: RewardTask,
        evidence: [String: String] = ["source": "ios_app"]
    ) async throws -> RewardTaskClaimResult {
        let result = try await api.claimRewardTask(
            code: task.taskCode,
            evidence: evidence
        )
        if let balance = result.creditsBalance {
            creditsBalance = balance
            hasLoadedCredits = true
        }
        rewardTasks = try await api.rewardTasksStatus().tasks
        await refreshCreditTransactions()
        return result
    }

    func claimSubscriberScratchReward() async throws -> RewardTaskClaimResult {
        let result = try await api.claimRewardTask(
            code: SubscriberScratchCampaign.rewardTaskCode,
            evidence: [
                "source": "subscriber_return_scratch",
                "campaign_version": String(SubscriberScratchCampaign.version),
                "expires_in_seconds": String(Int(SubscriberScratchCampaign.freeCreditLifetime))
            ]
        )
        if let balance = result.creditsBalance {
            creditsBalance = balance
            hasLoadedCredits = true
        }
        await refreshCreditTransactions()
        return result
    }

    func verifyCreditPurchase(
        transactionID: String,
        signedTransactionInfo: String
    ) async throws -> AppleIAPVerificationResult {
        let result = try await api.verifyAppleIAP(
            transactionID: transactionID,
            signedTransactionInfo: signedTransactionInfo
        )
        guard result.success, result.type == "consumable" else {
            throw PhotoReviveAPIError.requestFailed(
                statusCode: 409,
                message: result.message ?? "The credit purchase could not be verified."
            )
        }
        await refreshCredits()
        await refreshCreditTransactions()
        return result
    }

    func redeemReferral(code: String) async throws -> ReferralRedemptionResult {
        let result = try await api.redeemReferral(
            code: code,
            deviceKey: PhotoReviveInstallIdentity.deviceKey
        )
        if let balance = result.creditsBalance {
            creditsBalance = balance
            hasLoadedCredits = true
        }
        referralStatus = try await api.referralStatus()
        await refreshCreditTransactions()
        return result
    }

    func deleteHistoryTask(id: String) async throws {
        try await api.deleteHistoryTask(id: id)
        historyTasks.removeAll { $0.id == id }
    }
}

enum PhotoReviveInstallIdentity {
    private static let key = "photoReviveInstallDeviceKey"

    static var deviceKey: String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}

extension String {
    var photoReviveDisplayDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: self) ?? ISO8601DateFormatter().date(from: self)
        guard let date else { return self }

        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}
