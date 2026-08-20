import Foundation
import XCTest
@testable import Playtivity

/// Tests for `ActivitiesScreen.mismatchBadgeText`, the pure port of `_HeaderTitle`'s mismatch-
/// badge threshold (ref_activities_screen.dart:263-266):
/// `apiCount > 0 && parsedCount >= 0 && parsedCount < apiCount`.
final class ActivitiesScreenLogicTests: XCTestCase {
    func testNoBadgeWhenCountsMatch() {
        XCTAssertNil(ActivitiesScreen.mismatchBadgeText(apiCount: 5, parsedCount: 5))
    }

    func testNoBadgeWhenParsedExceedsApi() {
        // Cross-session accumulation can make parsed > api; that is not a mismatch to flag.
        XCTAssertNil(ActivitiesScreen.mismatchBadgeText(apiCount: 5, parsedCount: 6))
    }

    func testNoBadgeWhenApiCountIsZero() {
        XCTAssertNil(ActivitiesScreen.mismatchBadgeText(apiCount: 0, parsedCount: 0))
    }

    func testNoBadgeWhenApiCountIsNegative() {
        XCTAssertNil(ActivitiesScreen.mismatchBadgeText(apiCount: -1, parsedCount: 0))
    }

    func testNoBadgeWhenParsedCountIsNegative() {
        // -1 is BuddyActivityService's "no fetch yet" sentinel (lastParsedCount/lastMergedCount).
        XCTAssertNil(ActivitiesScreen.mismatchBadgeText(apiCount: 5, parsedCount: -1))
    }

    func testBadgeShownWhenParsedTrailsApi() {
        XCTAssertEqual(ActivitiesScreen.mismatchBadgeText(apiCount: 5, parsedCount: 3), " (3/5)")
    }

    func testBadgeShownWhenParsedIsZeroButApiIsPositive() {
        XCTAssertEqual(ActivitiesScreen.mismatchBadgeText(apiCount: 5, parsedCount: 0), " (0/5)")
    }

    func testBoundaryParsedOneLessThanApi() {
        XCTAssertEqual(ActivitiesScreen.mismatchBadgeText(apiCount: 2, parsedCount: 1), " (1/2)")
    }

    func testBoundaryParsedEqualToApiMinusOneWithLargerCounts() {
        XCTAssertEqual(ActivitiesScreen.mismatchBadgeText(apiCount: 42, parsedCount: 41), " (41/42)")
    }
}
