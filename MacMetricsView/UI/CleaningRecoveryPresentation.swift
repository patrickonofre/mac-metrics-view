import Foundation

/// Pure presentation decisions for the cleaning-permission recovery surfaces
/// (popover header banner + cleaning-section card), kept free of SwiftUI so the
/// state and copy selection are unit-testable without rendering a view. The views
/// themselves are verified by launching the app, per the project's testing standards.
enum CleaningRecoveryPresentation {

    /// Which content the cleaning-lock section shows.
    enum CardState: Equatable {
        /// Feature-level toggle is off (CLNGT-03) — only the toggle itself renders, no
        /// picker/button/guidance, regardless of the underlying (unchecked) grant state.
        case disabled
        /// Granted — the duration picker + Iniciar controls.
        case granted
        /// A valid grant was detected; the transient "applying… reopening" indicator.
        case applying
        /// Ungranted — the recovery guidance + "Open Accessibility" action.
        case awaitingGuidance
    }

    /// - Parameter isEnabled: the feature-level opt-in (`CleaningLockSettings.isEnabled`,
    ///   CLNGT-03). Checked first — a disabled feature short-circuits to `.disabled`
    ///   before any grant/phase check, since those are meaningless while opted out.
    static func cardState(
        isEnabled: Bool,
        isAccessibilityGranted: Bool,
        recoveryPhase: AccessibilityRecoveryPhase
    ) -> CardState {
        guard isEnabled else { return .disabled }
        if isAccessibilityGranted { return .granted }
        if recoveryPhase == .applying { return .applying }
        return .awaitingGuidance
    }

    /// The header recovery banner shows only when the feature is enabled AND the grant
    /// is missing (CLNGT-02) — a disabled feature never shows the banner, regardless of
    /// the underlying (unchecked) grant state.
    static func showsRecoveryBanner(isEnabled: Bool, isAccessibilityGranted: Bool) -> Bool {
        isEnabled && !isAccessibilityGranted
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
