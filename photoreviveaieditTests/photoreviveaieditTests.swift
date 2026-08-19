//
//  photoreviveaieditTests.swift
//  photoreviveaieditTests
//
//  Created by 马颖昆 on 2026/8/15.
//

import Foundation
import Testing
@testable import photoreviveaiedit

struct photoreviveaieditTests {

    @Test func trackingAuthorizationBypassArguments() {
        #expect(!TrackingAuthorizationPolicy.shouldBypassSystemPrompt(arguments: []))
        #expect(TrackingAuthorizationPolicy.shouldBypassSystemPrompt(
            arguments: ["-skipTrackingAuthorization"]
        ))
        #expect(TrackingAuthorizationPolicy.shouldBypassSystemPrompt(
            arguments: ["-skipOnboarding"]
        ))
        #expect(TrackingAuthorizationPolicy.shouldBypassSystemPrompt(
            arguments: ["-forceOnboarding"]
        ))
    }

    @Test func returningOfferEligibility() {
        #expect(!ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: false,
            isSubscribed: false,
            isLoggedIn: true,
            arguments: []
        ))
        #expect(ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: true,
            isSubscribed: false,
            isLoggedIn: true,
            arguments: []
        ))
        #expect(!ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: true,
            isSubscribed: false,
            isLoggedIn: false,
            arguments: []
        ))
        #expect(!ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: true,
            isSubscribed: true,
            isLoggedIn: true,
            arguments: []
        ))
        #expect(ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: false,
            isSubscribed: false,
            isLoggedIn: false,
            arguments: ["-forceReturningOffer"]
        ))
        #expect(!ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: true,
            isSubscribed: false,
            isLoggedIn: true,
            arguments: ["-skipOnboarding"]
        ))
    }

    @Test func subscriptionProductIDs() {
        #expect(SubscriptionProductID.proYearly.rawValue == "pro_yearly")
        #expect(SubscriptionProductID.proWeekly.rawValue == "pro_weekly")
        #expect(SubscriptionProductID.proPlusYearly.rawValue == "proplus_yearly")
        #expect(SubscriptionProductID.proPlusWeekly.rawValue == "proplus_weekly")
        #expect(SubscriptionProductID.loggedProYearly.rawValue == "loged_pro_yearly")
        #expect(SubscriptionProductID.loggedProWeekly.rawValue == "loged_pro_weekly")
        #expect(SubscriptionProductID.loggedProPlusYearly.rawValue == "loged_proplus_yearly")
        #expect(SubscriptionProductID.loggedProPlusWeekly.rawValue == "loged_proplus_weekly")
        #expect(SubscriptionProductID.limitedTimeOfferYearly.rawValue == "limited_time_offer_yearly")
        #expect(SubscriptionProductID.specialGiftYearly.rawValue == "special_gift_yearly")
        #expect(SubscriptionProductID.specialGiftWeekly.rawValue == "special_gift_weekly")
        #expect(SubscriptionProductID.familyExclusiveWeekly.rawValue == "family_exclusive_weekly")
        #expect(SubscriptionProductID.superPrizeWeekly.rawValue == "super_prize_weekly")
        #expect(SubscriptionProductID.threeDayFreeTrialYearly.rawValue == "3dayfreetrial_yearly")
    }

    @Test func returningOfferVariantSelection() {
        #expect(ReturningOfferVariant.select(
            arguments: ["-forceSuperPrizeReturningOffer"],
            randomValue: false
        ) == .superPrize)
        #expect(ReturningOfferVariant.select(
            arguments: ["-forceFamilyExclusiveReturningOffer"],
            randomValue: true
        ) == .familyExclusive)
        #expect(ReturningOfferVariant.select(arguments: [], randomValue: true) == .superPrize)
        #expect(ReturningOfferVariant.select(arguments: [], randomValue: false) == .familyExclusive)
    }

    @Test func limitedOfferIsDaily() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dayKey = LimitedOfferEligibility.dayKey(for: date, calendar: calendar)

        #expect(!LimitedOfferEligibility.canPresent(
            lastPresentedDay: dayKey,
            now: date,
            calendar: calendar
        ))
        #expect(LimitedOfferEligibility.canPresent(
            lastPresentedDay: dayKey,
            now: date.addingTimeInterval(86_400),
            calendar: calendar
        ))
    }

    @Test func returningOfferIsDaily() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dayKey = calendar.startOfDay(for: date).timeIntervalSince1970

        #expect(ReturningOfferEligibility.canPresent(
            lastPresentedDay: 0,
            now: date,
            calendar: calendar
        ))
        #expect(!ReturningOfferEligibility.canPresent(
            lastPresentedDay: dayKey,
            now: date,
            calendar: calendar
        ))
        #expect(ReturningOfferEligibility.canPresent(
            lastPresentedDay: dayKey,
            now: date.addingTimeInterval(86_400),
            calendar: calendar
        ))
    }

}
