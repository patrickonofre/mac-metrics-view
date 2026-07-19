import SwiftUI

/// Actions tab body: things the user *does* — start Cleaning Mode (duration presets
/// + Start, with the accessibility-recovery flow) and check for updates. Controls are
/// relocated verbatim from `PopoverView.swift` (task_06); no settings live here.
struct ActionsTab: View {
    @ObservedObject var state: CPUState
    @ObservedObject var lock: CleaningLockModel
    @ObservedObject var keepAwake: KeepAwakeModel
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

            KeepAwakeSection(keepAwake: keepAwake)

            Divider()

            UpdatesControl(state: state)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Keep awake

/// Plain on/off keep-awake toggle (feature `keep-awake-toggle`). Observes `keepAwake`
/// directly so the switch reflects the real assertion state — if the OS refuses the
/// assertion, `isActive` stays `false` and the toggle snaps back off.
struct KeepAwakeSection: View {
    @ObservedObject var keepAwake: KeepAwakeModel

    private var isActiveBinding: Binding<Bool> {
        Binding<Bool>(
            get: { keepAwake.isActive },
            set: { keepAwake.setActive($0) }
        )
    }

    /// Lid-close sub-mode binding (feature `lid-close-keep-awake`). The switch shows
    /// on only for `.active` — `.pendingApproval` reads as off plus the guidance card,
    /// so the toggle never claims the flag is set when it isn't (LIDC-05/08). Writes go
    /// through the model's serialized async transition queue; the switch snaps back on
    /// refusal/failure because it renders `lidClose`, not the user's tap.
    private var lidCloseBinding: Binding<Bool> {
        Binding<Bool>(
            get: { keepAwake.lidClose == .active },
            set: { active in
                Task { await keepAwake.setLidCloseActive(active) }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isActiveBinding) {
                Text(Strings.keepAwakeTitle())
                    .font(.caption.weight(.semibold))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Text(Strings.keepAwakeHint())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // LIDC-01: the lid-close sub-option exists only while base keep-awake is on.
            if keepAwake.isActive {
                lidCloseSubOption
                    .padding(.top, 4)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Indented nested control, mirroring the CleaningLockSection conditional-card idiom.
    private var lidCloseSubOption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: lidCloseBinding) {
                Text(Strings.lidCloseTitle())
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Text(Strings.lidCloseHint())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if keepAwake.lidClose == .pendingApproval {
                lidCloseApprovalGuidance
            }
        }
        .padding(.leading, 12)
    }

    // LIDC-08: daemon registered but awaiting user approval — guidance + a deep-link
    // into System Settings → Login Items. The sub-mode stays inactive meanwhile.
    private var lidCloseApprovalGuidance: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
                Text(Strings.lidClosePendingApprovalTitle())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(Strings.lidCloseOpenLoginItems()) {
                    HelperLidCloseSleepService.openApprovalSettings()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            }

            Text(Strings.lidClosePendingApprovalMessage())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
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

    /// Feature-level opt-in toggle (CLNGT-04/05/08). Disabled while a session is
    /// actively locked so the permission/settings chain can't be pulled out from under
    /// an in-flight `CGEventTap` session — mirrors "Iniciar"'s own
    /// `disabled(lock.phase == .locked)` guard below.
    private var isEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { lock.settings.isEnabled },
            set: { lock.setEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Modo limpeza")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Toggle(Strings.cleaningLockEnable(), isOn: isEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(lock.phase == .locked)
            }

            switch CleaningRecoveryPresentation.cardState(
                isEnabled: lock.settings.isEnabled,
                isAccessibilityGranted: lock.recovery.isGranted,
                recoveryPhase: lock.recovery.phase
            ) {
            case .disabled:
                EmptyView()
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
