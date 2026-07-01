import XCTest
@testable import MacMetricsView

@MainActor
final class CleaningRecoveryPresentationTests: XCTestCase {

    // MARK: - Card state

    func testGrantedSelectsGrantedControlsRegardlessOfPhase() {
        XCTAssertEqual(
            CleaningRecoveryPresentation.cardState(isAccessibilityGranted: true, recoveryPhase: .idle),
            .granted
        )
        XCTAssertEqual(
            CleaningRecoveryPresentation.cardState(isAccessibilityGranted: true, recoveryPhase: .applying),
            .granted
        )
    }

    func testApplyingPhaseSelectsApplyingIndicatorWhenUngranted() {
        XCTAssertEqual(
            CleaningRecoveryPresentation.cardState(isAccessibilityGranted: false, recoveryPhase: .applying),
            .applying
        )
    }

    func testUngrantedIdleSelectsAwaitingGuidance() {
        XCTAssertEqual(
            CleaningRecoveryPresentation.cardState(isAccessibilityGranted: false, recoveryPhase: .idle),
            .awaitingGuidance
        )
    }

    func testUngrantedAwaitingGrantSelectsAwaitingGuidance() {
        XCTAssertEqual(
            CleaningRecoveryPresentation.cardState(isAccessibilityGranted: false, recoveryPhase: .awaitingGrant),
            .awaitingGuidance
        )
    }

    // MARK: - Banner visibility

    func testBannerShownWhenUngranted() {
        XCTAssertTrue(CleaningRecoveryPresentation.showsRecoveryBanner(isAccessibilityGranted: false))
    }

    func testBannerHiddenWhenGranted() {
        XCTAssertFalse(CleaningRecoveryPresentation.showsRecoveryBanner(isAccessibilityGranted: true))
    }

    // MARK: - Copy selection (reset vs first-grant)

    func testGuidanceUsesResetWordingWhenResetByUpdate() {
        XCTAssertEqual(
            CleaningRecoveryPresentation.guidance(wasResetByUpdate: true).en,
            Strings.cleaningRecoveryResetGuidance.en
        )
    }

    func testGuidanceUsesFirstGrantWordingOtherwise() {
        XCTAssertEqual(
            CleaningRecoveryPresentation.guidance(wasResetByUpdate: false).en,
            Strings.cleaningRecoveryFirstGrantGuidance.en
        )
    }

    func testResetAndFirstGrantGuidanceDiffer() {
        XCTAssertNotEqual(
            CleaningRecoveryPresentation.guidance(wasResetByUpdate: true).en,
            CleaningRecoveryPresentation.guidance(wasResetByUpdate: false).en
        )
    }

    func testBannerCopyDiffersByResetState() {
        XCTAssertEqual(
            CleaningRecoveryPresentation.bannerTitle(wasResetByUpdate: true).en,
            Strings.recoveryBannerResetTitle.en
        )
        XCTAssertEqual(
            CleaningRecoveryPresentation.bannerTitle(wasResetByUpdate: false).en,
            Strings.recoveryBannerNeedsGrantTitle.en
        )
        XCTAssertNotEqual(
            CleaningRecoveryPresentation.bannerMessage(wasResetByUpdate: true).en,
            CleaningRecoveryPresentation.bannerMessage(wasResetByUpdate: false).en
        )
    }

    // MARK: - Card primary action begins recovery
    //
    // The SwiftUI button→action binding is verified by launching the app; here the
    // action it invokes is asserted at the CPUState boundary.

    func testCardPrimaryActionBeginsRecovery() {
        let auth = FakeAccessibilityAuthorization(isTrusted: false)
        let state = CPUState(
            userDefaults: UserDefaults(suiteName: "MacMetricsViewTests.Recovery.\(UUID().uuidString)")!,
            accessibilityAuthorization: auth,
            accessibilityProbe: FakeAccessibilityProbe(result: false)
        )

        // What the card's "Open Accessibility" button calls.
        state.beginAccessibilityRecovery()

        XCTAssertEqual(state.lock.recovery.phase, .awaitingGrant)
        XCTAssertEqual(auth.openSettingsCallCount, 1)
    }
}
