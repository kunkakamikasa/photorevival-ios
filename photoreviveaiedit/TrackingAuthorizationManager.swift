import AppTrackingTransparency
import Combine

@MainActor
final class TrackingAuthorizationManager: ObservableObject {
    @Published private(set) var authorizationStatus: ATTrackingManager.AuthorizationStatus
    @Published private(set) var hasFinishedInitialRequest: Bool

    private let arguments: [String]
    private var isRequestInFlight = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let status = ATTrackingManager.trackingAuthorizationStatus
        self.arguments = arguments
        authorizationStatus = status
        hasFinishedInitialRequest = status != .notDetermined
            || TrackingAuthorizationPolicy.shouldBypassSystemPrompt(arguments: arguments)
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    func requestAuthorizationIfNeeded() async {
        let currentStatus = ATTrackingManager.trackingAuthorizationStatus
        authorizationStatus = currentStatus

        guard !TrackingAuthorizationPolicy.shouldBypassSystemPrompt(arguments: arguments) else {
            hasFinishedInitialRequest = true
            return
        }

        guard currentStatus == .notDetermined else {
            hasFinishedInitialRequest = true
            return
        }
        guard !isRequestInFlight else { return }

        isRequestInFlight = true
        defer { isRequestInFlight = false }

        // Give SwiftUI one run-loop turn to finish presenting the main interface.
        await Task.yield()
        guard !Task.isCancelled else { return }

        authorizationStatus = await ATTrackingManager.requestTrackingAuthorization()
        hasFinishedInitialRequest = true
    }
}

enum TrackingAuthorizationPolicy {
    static func shouldBypassSystemPrompt(arguments: [String]) -> Bool {
        arguments.contains("-skipTrackingAuthorization")
            || arguments.contains("-skipOnboarding")
            || arguments.contains("-forceOnboarding")
    }
}
