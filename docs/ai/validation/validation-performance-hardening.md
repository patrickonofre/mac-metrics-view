# Validation: Performance Hardening

Status: done
Spec: ../specs/spec-performance-hardening.md

## T1: Backlog Baseline

- PASS: commit `8432838` established that three ticks queued three reads before coalescing existed.
- Evidence: the commit's `TokenUsageSamplerTests` assertion recorded `queuedReadCount == 3`; T5 intentionally replaces that obsolete assertion with the bounded behavior.
- Gate: `swift test` passed, 1,013 tests, 0 failures on 2026-08-26.
- Verdict: PH-01 confirms the queue can accumulate work. PH-02 through PH-05 proceed.

## T2: Automatic-Update Documentation

- PASS: README now states that `SUEnableAutomaticChecks` in `Info.plist` governs automatic checks and that no user-facing toggle exists.
- Evidence: README retains the manual "Check for updates..." action; `AppUpdateService` remains the source contract.
- Gate: `swift test` passed, 1,013 tests, 0 failures on 2026-08-26.

## T3: SwiftPM Manifest Hygiene

- PASS: removed the obsolete `Fixtures` exclusion and comment from `Package.swift`.
- Evidence: full `swift test` output contains no `Invalid Exclude` warning.
- Gate: `swift test` passed, 1,013 tests, 0 failures on 2026-08-26.

## T4: Coalescing Gate

- PASS: `CoalescingSamplingGate` permits one in-flight read and one latest pending refresh. `cancel()` invalidates both active completion and pending refresh.
- Evidence: `MainRunLoopTimerTests` covers three requests collapsing to two starts, latest-work replacement, and cancellation retaining one start.
- Gate: `swift test` passed, 1,015 tests, 0 failures on 2026-08-26.

## T5: Token Sampling Integration

- PASS: token polling routes through `CoalescingSamplingGate`; three ticks start one read, completion starts one follow-up, and `stop()` drops late output.
- Evidence: `TokenUsageSamplerTests` asserts one queued read before delivery, two delivered batches after completion, and no batch after `stop()`.
- Gate: `swift test` passed, 1,016 tests, 0 failures on 2026-08-26.

## T6: Temperature Sampling Integration

- PASS: temperature polling and thermal-state events route through `CoalescingSamplingGate`.
- Evidence: `TemperatureSamplerTests` holds repeated events at one queued read, drains exactly one follow-up, and verifies `stop()` suppresses late output.
- Gate: `swift test --filter TemperatureSamplerTests` passed, 10 tests, 0 failures on 2026-08-26.

## T7: Disk Sampling Integration

- PASS: disk baseline and delta reads share the coalescing gate without changing delta calculation.
- Evidence: `DiskSamplerTests` allows one blocked baseline plus one queued delta, then delivers one correct disk sample; `stop()` drops both the late baseline and pending refresh.
- Gate: `swift test --filter 'MainRunLoopTimerTests|DiskSamplerTests'` passed, 20 tests, 0 failures on 2026-08-26.

## T8: GPU Sampling Integration

- PASS: GPU polling routes through the coalescing gate while preserving immediate startup output.
- Evidence: `GPUSamplerTests` asserts one queued blocked read, one follow-up output, and no late output after `stop()`.
- Gate: `swift test --filter GPUSamplerTests` passed, 10 tests, 0 failures on 2026-08-26.

## T9: Battery Sampling Integration

- PASS: IOPS-triggered and safety-poll reads share the coalescing gate without changing their normal event path.
- Evidence: `BatterySamplerTests` asserts a blocked safety poll has one pending refresh and `stop()` suppresses its late output; existing immediate and regular-poll tests remain green.
- Gate: `swift test --filter BatterySamplerTests` passed, 9 tests, 0 failures on 2026-08-26.

## T10: Ambient-Light Sampling Integration

- PASS: ambient-light polling coalesces blocked reads and retains its opt-in lifecycle.
- Evidence: `AmbientLightSamplerTests` asserts one pending refresh under repeated ticks and suppresses late output after `stop()`.
- Gate: `swift test --filter AmbientLightSamplerTests` passed, 8 tests, 0 failures on 2026-08-26.

## T11: Process Sampling Integration

- PASS: process baseline and repeated popover ticks share the coalescing gate, retaining current ranking calculations.
- Evidence: `CPUStateProcessSamplingTests` holds repeated ticks at one queued snapshot, produces the expected ranking after baseline completion, and suppresses all work after `endProcessSampling()`.
- Gate: `swift test --filter CPUStateProcessSamplingTests` passed, 7 tests, 0 failures on 2026-08-26.

## T12: Local Release Verification

- PASS: `scripts/verify-release.sh <app> <appcast>` verifies local plist syntax, XML well-formedness, code-signature integrity, resolved Sparkle key, and the first appcast item's version.
- Evidence: the Debug bundle plus `docs/appcast.xml` passed for 2.7.0. Isolated missing-bundle, unsigned-bundle, placeholder-key, malformed-appcast, and version-mismatch fixtures each exited non-zero.
- Gate: `xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Debug -destination platform=macOS -derivedDataPath .build/DerivedData build` passed on 2026-08-26.

## T13: Final Validation

- PASS: full `swift test` passed 1,029 XCTest cases with 0 failures on 2026-08-26.
- PASS: `validate_tasks.py --strict` reported 0 errors and 0 warnings; `git diff --check` passed.
- PASS: Debug bundle passed `scripts/verify-release.sh .build/DerivedData/Build/Products/Debug/MacMetricsView.app docs/appcast.xml` for version 2.7.0.
- PASS: `open .build/DerivedData/Build/Products/Debug/MacMetricsView.app` returned successfully, dispatching a real local app launch.

## Independent Review

- Verdict: PASS. Fresh diff review found no behavioral regression in lifecycle cancellation, baseline-to-delta sequencing, or release-gate failure paths.
- Discrimination: the review specifically checked the old-work pending bug exposed by disk baseline scheduling; the gate now replaces pending work with the latest request and has a direct unit test.

## Specialist Handoffs

### QA -> SecOps

- Inputs: sampling-gate and release-gate implementation.
- Outputs: privacy and security review.
- Decision: go.
- Evidence: no production network call, telemetry, account, secret, or logging path was added; the release script reads only local inputs.
- Pending: n/a.

### SecOps -> DBA

- Inputs: completed security review.
- Outputs: persisted-format review.
- Decision: go.
- Evidence: n/a; no `UserDefaults` key, value shape, or migration changed.
- Pending: n/a.

### DBA -> DevOps

- Inputs: completed implementation and no persistence change.
- Outputs: build and release validation.
- Decision: go.
- Evidence: Debug Xcode build succeeds; local release gate accepts valid inputs and rejects missing, unsigned, placeholder-key, malformed, and version-mismatch fixtures.
- Pending: no release was packaged, pushed, or published.

### DevOps -> QA (final)

- Inputs: build and gate results.
- Outputs: regression outcome.
- Decision: go with visual residual.
- Evidence: 1,029 XCTest cases pass; Debug app launch dispatch succeeds.
- Pending: native menu-bar/popover pixels cannot be observed from this automated session.

### QA (final) -> PM (validate)

- Inputs: full automated evidence and independent review.
- Outputs: acceptance decision.
- Decision: accepted for implementation completion.
- Evidence: PH-01 through PH-10 are mapped and verified.
- Pending: human visual popover smoke before a release candidate.

## Residual Risks

- Native menu-bar and popover pixels were not interactively observed in this session. Launch was dispatched successfully; a human should open the popover, hide/show a heavy metric, and confirm no stale row before publishing a release.
