import Testing
@testable import photoreviveaiedit

struct MetaSubscriptionAnalyticsTests {
    @Test func paidSubscriptionReportsPurchaseAndSubscribe() {
        #expect(MetaSubscriptionAnalytics.eventKinds(isStartTrial: false) == [
            .purchase,
            .subscribe
        ])
    }

    @Test func freeTrialReportsOnlyStartTrialUntilAppleCharges() {
        #expect(MetaSubscriptionAnalytics.eventKinds(isStartTrial: true) == [
            .startTrial
        ])
    }
}
