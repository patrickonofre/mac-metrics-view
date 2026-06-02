import Foundation

/// Pure presentation decisions for the cleaning-permission recovery surfaces
/// (popover header banner + cleaning-section card), kept free of SwiftUI so the
/// state and copy selection are unit-testable without rendering a view. The views
/// themselves are verified by launching the app, per the project's testing standards.
enum CleaningRecoveryPresentation {

    /// Which content the cleaning-lock section shows.
    enum CardState: Equatable {
        /// Granted — the duration picker + Iniciar controls.
        case granted
        /// A valid grant was detected; the transient "applying… reopening" indicator.
        case applying
        /// Ungranted — the recovery guidance + "Open Accessibility" action.
        case awaitingGuidance
    }

    static func cardState(
        isAccessibilityGranted: Bool,
        recoveryPhase: AccessibilityRecoveryPhase
    ) -> CardState {
        if isAccessibilityGranted { return .granted }
        if recoveryPhase == .applying { return .applying }
        return .awaitingGuidance
    }

    /// The header recovery banner shows whenever the grant is missing.
    static func showsRecoveryBanner(isAccessibilityGranted: Bool) -> Bool {
        !isAccessibilityGranted
    }

    /// Card guidance copy: the update-reset wording stresses remove (−) + re-add;
    /// the first-grant wording covers a normal grant.
    static func guidance(wasResetByUpdate: Bool) -> LocalizedText {
        wasResetByUpdate ? Strings.cleaningRecoveryResetGuidance : Strings.cleaningRecoveryFirstGrantGuidance
    }

    /// Banner title/message: reset wording vs neutral "permission needed" wording
    /// (which also respects a deliberate revoke — never alarming).
    static func bannerTitle(wasResetByUpdate: Bool) -> LocalizedText {
        wasResetByUpdate ? Strings.recoveryBannerResetTitle : Strings.recoveryBannerNeedsGrantTitle
    }

    static func bannerMessage(wasResetByUpdate: Bool) -> LocalizedText {
        wasResetByUpdate ? Strings.recoveryBannerResetMessage : Strings.recoveryBannerNeedsGrantMessage
    }
}
