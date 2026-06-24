import SwiftUI

// MARK: - Recovery header banner

/// Accessibility-permission recovery banner, pinned above the tab bar so it shows on
/// every tab (ADR-001). Copy/gating come from `CleaningRecoveryPresentation`.
/// Relocated from `PopoverView.swift` unchanged (task_03); made internal so the shell
/// can reference it from another file.
struct RecoveryBanner: View {
    let wasResetByUpdate: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 1) {
                Text(CleaningRecoveryPresentation.bannerTitle(wasResetByUpdate: wasResetByUpdate)())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(CleaningRecoveryPresentation.bannerMessage(wasResetByUpdate: wasResetByUpdate)())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ambient theme-suggestion banner

/// Ambient-light theme suggestion banner, pinned above the tab bar (FR-7). Offers an
/// Apply / Dismiss for a suggestion, or denied-Automation guidance + an open-settings
/// link. Copy/state come from `AmbientSuggestionPresentation`; the user always confirms
/// the switch (D-2 — never silent).
struct AmbientSuggestionBanner: View {
    let state: AmbientSuggestionPresentation.BannerState
    let apply: () -> Void
    let dismiss: () -> Void

    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .suggestion(let mode):
            banner(
                icon: mode == .dark ? "moon.fill" : "sun.max.fill",
                tint: .accentColor,
                title: AmbientSuggestionPresentation.title(for: mode),
                message: Strings.ambientSuggestionMessage()
            ) {
                Button(Strings.ambientDismiss(), action: dismiss)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button(Strings.ambientApply(), action: apply)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
            }
        case .notAuthorized:
            banner(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                title: Strings.ambientNotAuthorizedTitle(),
                message: Strings.ambientNotAuthorizedMessage()
            ) {
                Button(Strings.ambientDismiss(), action: dismiss)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                if let url = AmbientSuggestionPresentation.automationSettingsURL() {
                    Link(Strings.ambientOpenAutomationSettings(), destination: url)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private func banner<Actions: View>(
        icon: String,
        tint: Color,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) { actions() }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.35))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Update header banner

/// Update-available banner, pinned above the tab bar (ADR-001). Copy/gating come from
/// `UpdateBannerPresentation`. Relocated from `PopoverView.swift` unchanged (task_03);
/// made internal so the shell can reference it from another file.
struct UpdateBanner: View {
    let availableVersion: String
    let checkForUpdates: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 1) {
                Text(UpdateBannerPresentation.title(for: availableVersion))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                if let url = UpdateBannerPresentation.releaseNotesURL(for: availableVersion) {
                    Link(Strings.whatsNew(), destination: url)
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer(minLength: 8)

            Button(Strings.updateNow()) {
                checkForUpdates()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.35))
        )
        .accessibilityElement(children: .combine)
    }
}
