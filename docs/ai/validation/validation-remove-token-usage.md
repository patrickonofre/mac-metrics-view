# Validation: Remove Token Usage

Status: done
Spec: ../specs/spec-remove-token-usage.md
Tasks: ../tasks/tasks-remove-token-usage.md
Date: 2026-08-27

## Requirement Evidence

| Requirement | Evidence | Result |
| --- | --- | --- |
| TOKRM-01 | `AppDelegate` and `CPUState` no longer construct, schedule, or route token collection. | pass |
| TOKRM-02 | `PopoverTabPresentation.cardOrder` tests assert CPU, GPU, RAM, network, temperature, disk, and battery only. | pass |
| TOKRM-03 | Token card and settings controls are removed; settings models no longer expose token fields. | pass |
| TOKRM-04 | Token production files and all Xcode file/build references are absent. | pass |
| TOKRM-05 | Production-source search found no `TokenUsage`, `TokenProvider`, `TokenPricing`, Claude Code, Codex, or Gemini reference. | pass |
| TOKRM-06 | Production-source search found no token preference read, display, or deletion. Existing values remain inert. | pass |
| TOKRM-07 | Current local README, PRD, project context, and TD-014 describe machine resources and local utilities. | pass |
| TOKRM-08 | TD-012 remains as a superseded historical decision; prior plans/specs/validation were not modified. | pass |

## Automated Checks

- `swift test` on 2026-08-27: **719 tests, 0 failures**.
- `xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Debug -destination platform=macOS -derivedDataPath .build/DerivedData build`: **BUILD SUCCEEDED**.
- Production filename search for `Token`, `Claude`, `Codex`, `Gemini`, and `ActiveFile`: no matches.
- Production implementation search for removed identifiers and legacy token preferences: no matches.
- Xcode project reference search for `Token`, `Claude`, `Codex`, and `ActiveFile`: no matches.
- `git diff --check 0e77603..HEAD`: no whitespace errors.

## Manual Verification

- Opened `.build/DerivedData/Build/Products/Debug/MacMetricsView.app`; the launch request completed successfully.
- Visual inspection of the status item and popover was not available in this environment. `pgrep` could not read the process list because `sysmond` was unavailable. Automated presentation tests cover the machine-only card order.

## Fresh Review

- A fresh requirement-by-requirement pass found no remaining integration, source, test, or Xcode reference to the removed feature.
- Discrimination check: generic programming uses of the word `token` (for example local formatting variables or identity tokens) were excluded from the feature search; no AI usage tracking behavior remains.
- A separately provisioned verifier was not available in this workspace. This review is a fresh pass in the implementation session, not an independent-agent claim.

## Residual Risk

- Existing token `UserDefaults` keys are intentionally left behind and untested at runtime because production code no longer reads or deletes them.
- The UI launch was not visually observed in this environment; build and unit evidence are green.

## Handoff: QA Final -> PM Validate

- Inputs: TOKRM-01 through TOKRM-08 and commits `90f0360`, `7c200ef`, `f478390`, `74bb4cc`.
- Outputs: fresh SwiftPM/Xcode evidence, negative searches, launch attempt, and residual risks.
- Decision: accepted with the documented visual-inspection limitation.
- Evidence: this record.
- Pending: none.
