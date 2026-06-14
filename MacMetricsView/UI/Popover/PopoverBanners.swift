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
