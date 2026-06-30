import SwiftUI

/// Actions tab body: things the user *does* — start Cleaning Mode (duration presets
/// + Start, with the accessibility-recovery flow) and check for updates. Controls are
/// relocated verbatim from `PopoverView.swift` (task_06); no settings live here.
struct ActionsTab: View {
    @ObservedObject var state: CPUState
    @ObservedObject var lock: CleaningLockModel
    let dismissPopover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CleaningLockSection(
                lock: lock,
                onStart: {
                    lock.start()
                    dismissPopover()
                }
            )

            Divider()

            UpdatesControl(state: state)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Updates

/// Relocated from `PopoverView.swift` (task_06).
struct UpdatesControl: View {
    @ObservedObject var state: CPUState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(Strings.autoUpdateCheck()) {
                state.checkForUpdates()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cleaning lock section

/// Relocated from `PopoverView.swift` (task_06). The card-state/guidance machine is
/// already factored through `CleaningRecoveryPresentation`, so no logic moves.
struct CleaningLockSection: View {
    @ObservedObject var lock: CleaningLockModel
    let onStart: () -> Void

    private static let presetLabels: [(TimeInterval, String)] = [
        (15,  "15s"),
        (30,  "30s"),
        (60,  "1min"),
        (120, "2min"),
        (300, "5min")
    ]

    private var durationBinding: Binding<TimeInterval> {
        Binding<TimeInterval>(
            get: { lock.settings.selectedDuration },
            set: { lock.selectDuration($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Modo limpeza")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            switch CleaningRecoveryPresentation.cardState(
                isAccessibilityGranted: lock.recovery.isGranted,
                recoveryPhase: lock.recovery.phase
            ) {
            case .granted:
                grantedControls
            case .applying:
                applyingIndicator
            case .awaitingGuidance:
                recoveryGuidance
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Preserved unchanged: duration picker + Iniciar.
    private var grantedControls: some View {
        HStack(spacing: 8) {
            Picker("Duração", selection: durationBinding) {
                ForEach(Self.presetLabels, id: \.0) { duration, label in
                    Text(label).tag(duration)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            Button("Iniciar") {
                onStart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(lock.phase == .locked)
        }
    }

    // Transient: the detected grant is being applied via relaunch.
    private var applyingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(Strings.cleaningApplyingPermission())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // Self-healing recovery: open Settings + begin probing; the app detects the
    // re-added grant and relaunches on its own (no manual "reload" button).
    private var recoveryGuidance: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(Strings.cleaningPermissionRequired())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(Strings.cleaningOpenAccessibility()) {
                    lock.recovery.beginRecovery()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            }

            Text(CleaningRecoveryPresentation.guidance(wasResetByUpdate: lock.recovery.resetByUpdate)())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if lock.recovery.phase == .awaitingGrant {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(Strings.cleaningRecoveryChecking())
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
        }
        .font(.caption)
    }
}
