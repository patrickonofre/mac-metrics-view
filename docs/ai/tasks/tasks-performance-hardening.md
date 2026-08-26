# Tasks: Performance Hardening

Status: done
Spec: ../specs/spec-performance-hardening.md
Design: ../specs/design-performance-hardening.md

## Test Coverage Matrix

> Generated from `AGENTS.md`, `docs/ai/testing-standards.md`, existing XCTest sampler suites, and the specification.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| --- | --- | --- | --- | --- |
| Sampling services | XCTest unit | Every PH-01..PH-05 branch, blocked read, stop, and pending transition | `MacMetricsViewTests/*SamplerTests.swift` | `swift test` |
| Package manifest/docs | Build and text check | No warning; prose matches source contract | `Package.swift`, `README.md` | `swift test` |
| Release script | Local integration | Valid app passes; each invalid input fails non-zero without mutation | `scripts/verify-release.sh` | script command plus `xcodebuild` |
| Popover/status item | Manual app smoke | Open, update, hide metric, close/reopen | Xcode Debug app | `xcodebuild ... build` then launch |

## Gate Check Commands

| Gate Level | When to Use | Command |
| --- | --- | --- |
| Quick | Sampler, docs, or manifest task | `swift test` |
| Build | Release script task | `xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Debug -destination platform=macOS -derivedDataPath .build/DerivedData build` |
| Full | Final validation | `swift test` and Xcode Debug build, then manual app smoke |

## Execution Plan

### Phase 1: Evidence and Hygiene

```
T1 -> T2 -> T3
```

### Phase 2: Conditional Sampling Foundation

```
T4 -> T5
T4 -> T6
```

### Phase 3: Conditional Sampling Integration

```
T7
T8
T9
T10
T11
```

### Phase 4: Release Gate

```
T12 -> T13
```

## Task Breakdown

### T1: Profile heavy-sampling backlog

**Status**: done

**What**: Add a controlled slow-reader XCTest and record the baseline queue verdict.
**Where**: `MacMetricsViewTests/TokenUsageSamplerTests.swift`
**Depends on**: None
**Reuses**: `FakeScheduler`, injected `SamplingExecutor`, existing sampler test style.
**Requirement**: PH-01
**Done when**: controlled test records whether repeated ticks produce more than one queued read; result is written to a new validation record; no production scheduler changes occur in this task. Done: three timer ticks queue three reads before the executor runs.
**Tests**: XCTest unit
**Gate**: Quick (`swift test`)
**Commit**: `test(sampling): establish backlog baseline`

### T2: Correct automatic-update documentation

**Status**: done

**What**: Align README update text with the `Info.plist`-only automatic-check contract.
**Where**: `README.md`
**Depends on**: T1
**Reuses**: `AppUpdateService` contract and domain catalog terminology.
**Requirement**: PH-06
**Done when**: README no longer claims a user-facing automatic-update toggle and retains the manual update action. Done: README names `Info.plist` and preserves the manual action.
**Tests**: Build and text check
**Gate**: Quick (`swift test`)
**Commit**: `docs(update): correct automatic-check guidance`

### T3: Remove obsolete SwiftPM exclusion

**Status**: done

**What**: Remove only the nonexistent test-fixture exclusion and its obsolete comment.
**Where**: `Package.swift`
**Depends on**: T2
**Reuses**: existing package target layout.
**Requirement**: PH-07
**Done when**: `swift test` completes without the invalid `MacMetricsViewTests/Fixtures` exclude warning. Done: full test output has no invalid-exclude warning.
**Tests**: Build and manifest check
**Gate**: Quick (`swift test`)
**Commit**: `build(spm): remove obsolete fixture exclusion`

### T4: Add the coalescing gate only after evidence passes

**Status**: done

**What**: Implement the generic per-stream gate and its state-transition tests; skip this task and mark it deferred if T1 proves no backlog.
**Where**: `MacMetricsView/Services/MainRunLoopTimer.swift`
**Depends on**: T1
**Reuses**: `SamplingExecutor` and main-actor lifecycle conventions.
**Requirement**: PH-02, PH-03, PH-04
**Done when**: gate holds one in-flight and one pending request; completion consumes the latest pending request; skipped branch is documented with T1 evidence. Done: T1 proved backlog and gate tests cover both transitions and latest-work replacement.
**Tests**: XCTest unit
**Gate**: Quick (`swift test`)
**Commit**: `perf(sampling): bound queued reader work`

### T5: Integrate bounded work with token sampling

**Status**: done

**What**: Apply the conditional gate to each `TokenUsageSampler` instance without changing its visible interval.
**Where**: `MacMetricsView/Services/TokenUsageSampler.swift`
**Depends on**: T4
**Reuses**: token reader confinement and current empty-batch behavior.
**Requirement**: PH-02, PH-03, PH-04, PH-05
**Done when**: blocked token read yields one pending refresh at most; `stop()` drops late delivery; normal reads keep current delegate behavior. Done: deferred-executor tests cover both paths.
**Tests**: XCTest unit
**Gate**: Quick (`swift test`)
**Commit**: `perf(tokens): coalesce slow reader ticks`

### T6: Integrate bounded work with temperature sampling

**Status**: done

**What**: Apply the conditional gate to temperature reads without changing its 2s/3s cadence.
**Where**: `MacMetricsView/Services/TemperatureSampler.swift`
**Depends on**: T4
**Reuses**: current background executor and stop guard.
**Requirement**: PH-02, PH-03, PH-05
**Done when**: repeated ticks during a blocked read stay bounded and a stopped sampler publishes nothing late. Done: deferred-executor tests cover timer and thermal-notification coalescing plus post-stop suppression.
**Tests**: XCTest unit
**Gate**: Quick (`swift test`)
**Commit**: `perf(temperature): coalesce slow reader ticks`

### T7: Integrate bounded work with disk sampling

**Status**: done

**What**: Apply the conditional gate to disk reads while preserving delta calculations.
**Where**: `MacMetricsView/Services/DiskSampler.swift`
**Depends on**: T4
**Reuses**: existing executor and `isRunning` delivery guard.
**Requirement**: PH-02, PH-03, PH-05
**Done when**: a blocked disk read never duplicates queued work and stop prevents stale sample publication. Done: deferred-executor tests preserve baseline-to-delta sequencing and suppress post-stop work.
**Tests**: XCTest unit
**Gate**: Quick (`swift test`)
**Commit**: `perf(disk): coalesce slow reader ticks`

### T8: Integrate bounded work with GPU sampling

**Status**: done

**What**: Apply the conditional gate to GPU reads.
**Where**: `MacMetricsView/Services/GPUSampler.swift`
**Depends on**: T4
**Reuses**: existing executor and `isRunning` delivery guard.
**Requirement**: PH-02, PH-03, PH-05
**Done when**: GPU polling remains bounded under a blocked reader and stop drops late output. Done: deferred-executor tests cover both paths.
**Tests**: XCTest unit
**Gate**: Quick (`swift test`)
**Commit**: `perf(gpu): coalesce slow reader ticks`

### T9: Integrate bounded work with battery sampling

**Status**: done

**What**: Apply the conditional gate to the 30s safety poll without changing event-driven updates.
**Where**: `MacMetricsView/Services/BatterySampler.swift`
**Depends on**: T4
**Reuses**: IOPS event path and current background executor.
**Requirement**: PH-02, PH-03, PH-05
**Done when**: safety-poll reads stay bounded and IOPS event behavior remains unchanged. Done: deferred-executor tests cover polling bounds and late-delivery suppression; existing immediate/poll tests preserve normal behavior.
**Tests**: XCTest unit
**Gate**: Quick (`swift test`)
**Commit**: `perf(battery): coalesce slow safety polls`

### T10: Integrate bounded work with ambient-light sampling

**Status**: done

**What**: Apply the conditional gate to ambient sensor reads.
**Where**: `MacMetricsView/Services/AmbientLightSampler.swift`
**Depends on**: T4
**Reuses**: current background executor and opt-in lifecycle.
**Requirement**: PH-02, PH-03, PH-05
**Done when**: ambient reads stay bounded under a blocked reader and disabled mode remains inactive. Done: deferred-executor tests cover bounds and post-stop suppression; opt-in lifecycle remains owned by existing coordinator wiring.
**Tests**: XCTest unit
**Gate**: Quick (`swift test`)
**Commit**: `perf(ambient): coalesce slow sensor reads`

### T11: Integrate bounded work with process sampling

**Status**: done

**What**: Apply the conditional gate to top-process snapshot reads.
**Where**: `MacMetricsView/App/SystemMetricsModel.swift`
**Depends on**: T4
**Reuses**: `previousProcessSnapshot`, `samplingExecutor`, and process ranking tests.
**Requirement**: PH-02, PH-03, PH-05
**Done when**: process enumeration cannot queue repeatedly and ending process sampling drops late rankings. Done: deferred-executor tests cover baseline-to-ranking sequencing and post-end suppression.
**Tests**: XCTest unit
**Gate**: Quick (`swift test`)
**Commit**: `perf(processes): coalesce slow snapshot reads`

### T12: Create local release verification command

**Status**: done

**What**: Add a read-only script that validates bundle signature, plist key, and newest local appcast version.
**Where**: `scripts/verify-release.sh`
**Depends on**: T2, T3
**Reuses**: existing release runbook, `Info.plist`, and `docs/appcast.xml`.
**Requirement**: PH-08, PH-09, PH-10
**Done when**: valid local inputs pass; missing, unsigned, placeholder-key, malformed, and version-mismatch inputs fail non-zero; script makes no network request or mutation. Done: a Debug bundle and repository appcast pass; five isolated invalid fixtures fail.
**Tests**: Local integration
**Gate**: Build (`xcodebuild` Debug build plus valid/invalid script runs)
**Commit**: `build(release): add local verification gate`

### T13: Validate behavior and document evidence

**Status**: done

**What**: Run full gates, inspect the Debug app, and record per-requirement evidence and residual risks.
**Where**: `docs/ai/validation/validation-performance-hardening.md`
**Depends on**: T5, T6, T7, T8, T9, T10, T11, T12
**Reuses**: project validation format and existing performance measurement methodology.
**Requirement**: PH-01, PH-02, PH-03, PH-04, PH-05, PH-06, PH-07, PH-08, PH-09, PH-10
**Done when**: validation includes test/build results, backlog verdict, launch evidence, release-gate evidence, and residual risks. Done: final suite, Debug build, gate, launch dispatch, and independent review are recorded; visual popover observation remains explicit residual risk.
**Tests**: XCTest and manual app smoke
**Gate**: Full (`swift test`, Xcode Debug build, local release gate, manual launch)
**Commit**: `docs(validation): record performance hardening evidence`

## Phase Execution Map

```
T1 -> T2
T2 -> T3
T1 -> T4
T4 -> T5
T4 -> T6
T4 -> T7
T4 -> T8
T4 -> T9
T4 -> T10
T4 -> T11
T2 -> T12
T3 -> T12
T5 -> T13
T6 -> T13
T7 -> T13
T8 -> T13
T9 -> T13
T10 -> T13
T11 -> T13
T12 -> T13
```

## Diagram-Definition Cross-Check

| Task | Depends On | Diagram Shows | Status |
| --- | --- | --- | --- |
| T1 | None | None | OK |
| T2 | T1 | T1 -> T2 | OK |
| T3 | T2 | T2 -> T3 | OK |
| T4 | T1 | Cross-phase | OK |
| T5 | T4 | T4 -> T5 | OK |
| T6 | T4 | T4 -> T6 | OK |
| T7-T11 | T4 | Cross-phase | OK |
| T12 | T2, T3 | Cross-phase | OK |
| T13 | T5-T12 | Cross-phase | OK |

## Test Co-location Validation

| Task | Code Layer | Matrix Requires | Task Says | Status |
| --- | --- | --- | --- |
| T1 | Sampling test | XCTest unit | XCTest unit | OK |
| T2 | Documentation | Build and text check | Build and text check | OK |
| T3 | Package manifest | Build and manifest check | Build and manifest check | OK |
| T4-T11 | Sampling services | XCTest unit | XCTest unit | OK |
| T12 | Release script | Local integration | Local integration | OK |
| T13 | Validation/UI | XCTest and manual smoke | XCTest and manual smoke | OK |
