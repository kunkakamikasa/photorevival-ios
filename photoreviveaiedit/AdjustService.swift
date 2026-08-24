import Foundation

#if canImport(AdjustSdk)
import AdjustSdk
#endif

struct AdjustAttributionSnapshot: Codable, Equatable, Sendable {
    let adjustAdid: String?
    let network: String?
    let campaign: String?
    let adgroup: String?
    let creative: String?
    let trackerName: String?
    let trackerToken: String?
    let clickLabel: String?
    let costType: String?
    let costAmount: String?
    let costCurrency: String?
    let referrer: String
    let adjustEnvironment: String
    let attributionProvider: String
    let attributionData: [String: String]

    enum CodingKeys: String, CodingKey {
        case adjustAdid = "adjust_adid"
        case network
        case campaign
        case adgroup
        case creative
        case trackerName = "tracker_name"
        case trackerToken = "tracker_token"
        case clickLabel = "click_label"
        case costType = "cost_type"
        case costAmount = "cost_amount"
        case costCurrency = "cost_currency"
        case referrer
        case adjustEnvironment = "adjust_environment"
        case attributionProvider = "attribution_provider"
        case attributionData = "attribution_data"
    }
}

extension Notification.Name {
    static let adjustAttributionDidChange = Notification.Name("AdjustAttributionDidChange")
}

final class AdjustService: NSObject {
    static let shared = AdjustService()

    private static let referrerKey = "adjust.referrer"
    private static let attributionKey = "adjust.attribution"
    private static let registrationIDsKey = "adjust.registration.ids"
    private static let subscribeIDsKey = "adjust.subscribe.ids"

    private let stateQueue = DispatchQueue(label: "com.photorevive.adjust.state")
    private var hasStarted = false
    private var hasReceivedAttribution = false
    private var appOpenedTracked = false
    private var externalDeviceID: String?
    private var currentSnapshot: AdjustAttributionSnapshot?
    private var pendingRegistrationIDs = Set<String>()
    private var pendingSubscriptions: [PendingSubscribe] = []
    private var reportedRegistrationIDs: Set<String>
    private var reportedSubscribeIDs: Set<String>

    private struct PendingSubscribe {
        let productID: String
        let revenue: Double?
        let currency: String?
        let transactionID: String?
        let orderID: String?

        var deduplicationID: String {
            transactionID ?? orderID ?? "\(productID)-anonymous"
        }
    }

    private override init() {
        let defaults = UserDefaults.standard
        reportedRegistrationIDs = Set(defaults.stringArray(forKey: Self.registrationIDsKey) ?? [])
        reportedSubscribeIDs = Set(defaults.stringArray(forKey: Self.subscribeIDsKey) ?? [])
        currentSnapshot = defaults.data(forKey: Self.attributionKey).flatMap {
            try? JSONDecoder().decode(AdjustAttributionSnapshot.self, from: $0)
        }
        // A saved snapshot is a fallback only. Wait for this launch's callback
        // before making the audience-sensitive feature-config request.
        hasReceivedAttribution = false
        super.init()
    }

    var referrer: String {
        stateQueue.sync {
            guard hasReceivedAttribution else { return "noad" }
            return currentSnapshot?.referrer
                ?? UserDefaults.standard.string(forKey: Self.referrerKey)
                ?? "noad"
        }
    }

    var attributionSnapshot: AdjustAttributionSnapshot? {
        // Do not bind a previous launch's persisted snapshot to a new user
        // before this launch has delivered its Adjust callback.
        stateQueue.sync {
            guard hasReceivedAttribution else { return nil }
            return currentSnapshot
        }
    }

    func startIfNeeded(externalDeviceID: String? = nil) {
        if let externalDeviceID {
            setExternalDeviceID(externalDeviceID)
        }

        let shouldStart = stateQueue.sync { () -> Bool in
            guard !hasStarted else { return false }
            hasStarted = true
            return true
        }
        guard shouldStart else { return }

        #if canImport(AdjustSdk)
        let appToken = Self.infoString("AdjustAppToken", fallback: "kz8k3gu2jf9c")
        let environment = Self.infoString("AdjustEnvironment", fallback: Self.defaultEnvironment)
        let config = ADJConfig(appToken: appToken, environment: environment)
        config?.delegate = self
        if let externalDeviceID {
            config?.externalDeviceId = externalDeviceID
        }
        Adjust.initSdk(config)
        #else
        // Keep the wrapper usable by unit tests and non-iOS build environments.
        stateQueue.sync { hasReceivedAttribution = true }
        #endif

        trackAppOpenedIfNeeded()
        flushPendingEvents()
    }

    func setExternalDeviceID(_ value: String?) {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return }
        stateQueue.sync { externalDeviceID = normalized }

        #if canImport(AdjustSdk)
        let isStarted = stateQueue.sync { hasStarted }
        guard isStarted else { return }
        Adjust.setExternalDeviceIdInDelay(normalized)
        #endif
    }

    func waitForInitialAttribution(timeout: TimeInterval = 4) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = stateQueue.sync { (hasStarted: hasStarted, hasReceivedAttribution: hasReceivedAttribution) }
            if state.hasStarted && state.hasReceivedAttribution { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func trackCompleteRegistration(userID: String? = nil) {
        let normalizedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = normalizedUserID?.isEmpty == false ? normalizedUserID! : "anonymous"

        let shouldTrack = stateQueue.sync { () -> Bool in
            guard !reportedRegistrationIDs.contains(identifier) else { return false }
            guard hasStarted else {
                pendingRegistrationIDs.insert(identifier)
                return false
            }
            markRegistrationReported(identifier)
            return true
        }
        guard shouldTrack else { return }
        sendEvent(
            tokenKey: "AdjustCompleteRegistrationEventToken",
            callbackParameters: ["registration_id": identifier]
        )
    }

    func trackSubscribe(
        productID: String,
        revenue: Double? = nil,
        currency: String? = nil,
        transactionID: String? = nil,
        orderID: String? = nil,
        wasSubscribedBeforePurchase: Bool = UserDefaults.standard.bool(forKey: "isSubscribed")
    ) {
        guard !wasSubscribedBeforePurchase else { return }
        let pending = PendingSubscribe(
            productID: productID,
            revenue: revenue,
            currency: currency,
            transactionID: transactionID,
            orderID: orderID
        )
        let shouldTrack = stateQueue.sync { () -> Bool in
            guard !reportedSubscribeIDs.contains(pending.deduplicationID),
                  !pendingSubscriptions.contains(where: { $0.deduplicationID == pending.deduplicationID }) else {
                return false
            }
            guard hasStarted else {
                pendingSubscriptions.append(pending)
                return false
            }
            markSubscribeReported(pending.deduplicationID)
            return true
        }
        guard shouldTrack else { return }
        sendSubscribeEvent(pending)
    }

    #if canImport(AdjustSdk)
    private func handleAttributionChanged(_ attribution: ADJAttribution?) {
        let attributionData = (attribution?.dictionary() as? [AnyHashable: Any] ?? [:]).reduce(into: [String: String]()) { result, entry in
            let key = String(describing: entry.key)
            if let value = entry.value as? String {
                result[key] = value
            } else if let value = entry.value as? NSNumber {
                result[key] = value.stringValue
            } else {
                result[key] = String(describing: entry.value)
            }
        }

        let network = Self.normalized(attribution?.network)
        let campaign = Self.normalized(attribution?.campaign)
        let adgroup = Self.normalized(attribution?.adgroup)
        let creative = Self.normalized(attribution?.creative)
        let trackerName = Self.normalized(attribution?.trackerName)
        let trackerToken = Self.normalized(attribution?.trackerToken)
        let clickLabel = Self.normalized(attribution?.clickLabel)
        let costType = Self.normalized(attribution?.costType)
        let costAmount = attribution?.costAmount?.stringValue
        let costCurrency = Self.normalized(attribution?.costCurrency)

        Adjust.adid { [weak self] adid in
            self?.recordAttribution(
                snapshot: AdjustAttributionSnapshot(
                    adjustAdid: Self.normalized(adid),
                    network: network,
                    campaign: campaign,
                    adgroup: adgroup,
                    creative: creative,
                    trackerName: trackerName,
                    trackerToken: trackerToken,
                    clickLabel: clickLabel,
                    costType: costType,
                    costAmount: costAmount,
                    costCurrency: costCurrency,
                    referrer: Self.referrer(for: network),
                    adjustEnvironment: Self.infoString("AdjustEnvironment", fallback: Self.defaultEnvironment),
                    attributionProvider: "adjust",
                    attributionData: attributionData
                )
            )
        }
    }

    private func recordAttribution(snapshot: AdjustAttributionSnapshot) {
        stateQueue.sync {
            currentSnapshot = snapshot
            hasReceivedAttribution = true
            UserDefaults.standard.set(snapshot.referrer, forKey: Self.referrerKey)
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.attributionKey)
            }
        }
        NotificationCenter.default.post(name: .adjustAttributionDidChange, object: snapshot)
    }
    #endif

    private func trackAppOpenedIfNeeded() {
        let shouldTrack = stateQueue.sync { () -> Bool in
            guard !appOpenedTracked else { return false }
            appOpenedTracked = true
            return true
        }
        guard shouldTrack else { return }
        sendEvent(tokenKey: "AdjustAppOpenedEventToken")
    }

    private func flushPendingEvents() {
        let pending = stateQueue.sync { () -> (registration: [String], subscriptions: [PendingSubscribe]) in
            let registration = Array(pendingRegistrationIDs)
            pendingRegistrationIDs.removeAll()
            registration.forEach(markRegistrationReported)

            let subscriptions = pendingSubscriptions
            pendingSubscriptions.removeAll()
            subscriptions.forEach { markSubscribeReported($0.deduplicationID) }
            return (registration, subscriptions)
        }

        pending.registration.forEach {
            sendEvent(tokenKey: "AdjustCompleteRegistrationEventToken", callbackParameters: ["registration_id": $0])
        }
        pending.subscriptions.forEach(sendSubscribeEvent)
    }

    private func sendSubscribeEvent(_ pending: PendingSubscribe) {
        var callbackParameters = [
            "product_id": pending.productID,
            "app_id": Self.infoString("PhotoReviveAppID", fallback: PhotoReviveAPIConfig.appID),
            "referrer": referrer
        ]
        if let orderID = pending.orderID { callbackParameters["order_id"] = orderID }
        sendEvent(
            tokenKey: "AdjustSubscribeEventToken",
            callbackParameters: callbackParameters,
            revenue: pending.revenue,
            currency: pending.currency,
            transactionID: pending.transactionID,
            deduplicationID: pending.deduplicationID,
            productID: pending.productID
        )
    }

    private func sendEvent(
        tokenKey: String,
        callbackParameters: [String: String] = [:],
        revenue: Double? = nil,
        currency: String? = nil,
        transactionID: String? = nil,
        deduplicationID: String? = nil,
        productID: String? = nil
    ) {
        #if canImport(AdjustSdk)
        guard let token = Self.infoString(tokenKey, fallback: "").nonEmpty,
              let event = ADJEvent(eventToken: token) else { return }
        if let revenue, revenue > 0, let currency = currency?.nonEmpty {
            event.setRevenue(revenue, currency: currency)
        }
        if let transactionID { event.setTransactionId(transactionID) }
        if let deduplicationID { event.setDeduplicationId(deduplicationID) }
        if let productID { event.setProductId(productID) }

        var parameters = callbackParameters
        parameters["app_id"] = parameters["app_id"] ?? Self.infoString("PhotoReviveAppID", fallback: PhotoReviveAPIConfig.appID)
        parameters["app_version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        parameters["referrer"] = parameters["referrer"] ?? referrer
        for (key, value) in parameters { event.addCallbackParameter(key, value: value) }
        Adjust.trackEvent(event)
        #endif
    }

    private func markRegistrationReported(_ identifier: String) {
        reportedRegistrationIDs.insert(identifier)
        UserDefaults.standard.set(Array(reportedRegistrationIDs), forKey: Self.registrationIDsKey)
    }

    private func markSubscribeReported(_ identifier: String) {
        reportedSubscribeIDs.insert(identifier)
        UserDefaults.standard.set(Array(reportedSubscribeIDs), forKey: Self.subscribeIDsKey)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func referrer(for network: String?) -> String {
        guard let network, !network.isEmpty, network.caseInsensitiveCompare("Organic") != .orderedSame else {
            return "noad"
        }
        return "ad"
    }

    private static func infoString(_ key: String, fallback: String) -> String {
        normalized(Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? fallback
    }

    private static var defaultEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

#if canImport(AdjustSdk)
extension AdjustService: AdjustDelegate {
    func adjustAttributionChanged(_ attribution: ADJAttribution?) {
        handleAttributionChanged(attribution)
    }
}
#endif
