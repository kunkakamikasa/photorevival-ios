import FacebookCore
import Foundation

enum MetaSubscriptionEventKind: String, CaseIterable {
    case purchase
    case subscribe
    case startTrial
}

enum MetaSubscriptionAnalytics {
    private static let reportedEventIDsKey = "meta.subscription.reported-event-ids"
    private static let maximumRememberedEventIDs = 512
    private static let stateQueue = DispatchQueue(label: "com.photorevive.meta.subscription-events")

    static func eventKinds(isStartTrial: Bool) -> [MetaSubscriptionEventKind] {
        if isStartTrial {
            return [.startTrial]
        }
        return [.purchase, .subscribe]
    }

    static func reportVerifiedPurchase(
        productID: String,
        value: Double,
        currency: String,
        transactionID: String,
        originalTransactionID: String,
        isStartTrial: Bool
    ) {
        let parameters: [AppEvents.ParameterName: Any] = [
            .contentID: productID,
            .contentType: "subscription",
            .currency: currency,
            .numItems: 1,
            .orderID: originalTransactionID,
            .transactionID: transactionID,
            .inAppPurchaseType: "subs",
            .isStartTrial: isStartTrial ? "1" : "0"
        ]

        for kind in eventKinds(isStartTrial: isStartTrial) {
            guard reserve(kind: kind, transactionID: transactionID) else { continue }

            switch kind {
            case .purchase:
                AppEvents.shared.logPurchase(
                    amount: value,
                    currency: currency,
                    parameters: parameters
                )
            case .subscribe:
                AppEvents.shared.logEvent(
                    .subscribe,
                    valueToSum: value,
                    parameters: parameters
                )
            case .startTrial:
                AppEvents.shared.logEvent(
                    .startTrial,
                    valueToSum: value,
                    parameters: parameters
                )
            }
        }

        AppEvents.shared.flush()
    }

    private static func reserve(
        kind: MetaSubscriptionEventKind,
        transactionID: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        stateQueue.sync {
            let eventID = "\(kind.rawValue):\(transactionID)"
            var reportedEventIDs = defaults.stringArray(forKey: reportedEventIDsKey) ?? []
            guard !reportedEventIDs.contains(eventID) else { return false }

            reportedEventIDs.append(eventID)
            if reportedEventIDs.count > maximumRememberedEventIDs {
                reportedEventIDs.removeFirst(reportedEventIDs.count - maximumRememberedEventIDs)
            }
            defaults.set(reportedEventIDs, forKey: reportedEventIDsKey)
            return true
        }
    }
}
