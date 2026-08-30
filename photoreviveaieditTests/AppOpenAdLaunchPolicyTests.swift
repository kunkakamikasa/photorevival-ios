import Foundation
import Testing
@testable import photoreviveaiedit

struct AppOpenAdLaunchPolicyTests {
    @Test
    func debugAdsAreEnabledByDefaultOutsideAutomatedTests() {
        #expect(AppOpenAdConfiguration.shouldEnableAdvertising(
            arguments: [],
            environment: [:],
            isDebugBuild: true
        ))
    }

    @Test
    func adsCanBeDisabledAndStayOffDuringAutomatedTests() {
        #expect(!AppOpenAdConfiguration.shouldEnableAdvertising(
            arguments: ["-disableAppOpenAd"],
            environment: [:],
            isDebugBuild: true
        ))
        #expect(!AppOpenAdConfiguration.shouldEnableAdvertising(
            arguments: [],
            environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"],
            isDebugBuild: true
        ))
        #expect(!AppOpenAdConfiguration.shouldEnableAdvertising(
            arguments: ["-skipOnboarding"],
            environment: [:],
            isDebugBuild: true
        ))
    }

    @Test
    func firstLaunchIsSkippedAndLaterLaunchesAreEligible() throws {
        let suiteName = "AppOpenAdLaunchPolicyTests.firstLaunch"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let policy = AppOpenAdLaunchPolicy(defaults: defaults)

        #expect(!policy.shouldPrepareForLaunch(
            isAdvertisingEnabled: true,
            isSubscribed: false
        ))
        #expect(policy.shouldPrepareForLaunch(
            isAdvertisingEnabled: true,
            isSubscribed: false
        ))
        #expect(policy.shouldPrepareForLaunch(
            isAdvertisingEnabled: true,
            isSubscribed: false
        ))
    }

    @Test
    func disabledAdsStillRecordTheFirstLaunch() throws {
        let suiteName = "AppOpenAdLaunchPolicyTests.disabledAds"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let policy = AppOpenAdLaunchPolicy(defaults: defaults)

        #expect(!policy.shouldPrepareForLaunch(
            isAdvertisingEnabled: false,
            isSubscribed: false
        ))
        #expect(policy.shouldPrepareForLaunch(
            isAdvertisingEnabled: true,
            isSubscribed: false
        ))
    }

    @Test
    func subscribedUsersAreNeverEligibleForAppOpenAds() throws {
        let suiteName = "AppOpenAdLaunchPolicyTests.subscribedUsers"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let policy = AppOpenAdLaunchPolicy(defaults: defaults)

        #expect(!policy.shouldPrepareForLaunch(
            isAdvertisingEnabled: true,
            isSubscribed: true
        ))
        #expect(!policy.shouldPrepareForLaunch(
            isAdvertisingEnabled: true,
            isSubscribed: true
        ))
    }
}
