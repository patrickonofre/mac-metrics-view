# Specification: Performance Hardening

Status: done
Plan: ../plans/plan-performance-hardening.md

## Problem Statement

Heavy readers share one serial utility queue. Current tests prove correct output but do not prove that repeated open-popover ticks cannot accumulate queued work when a reader is slower than its interval. Two separate maintenance defects are confirmed: an obsolete README claim about an update toggle and a nonexistent SPM `Fixtures` exclusion warning.

## Goals

- [x] Measure queued heavy sampling before changing its scheduling behavior.
- [x] Bound queued work per reader only when measurements show backlog.
- [x] Remove confirmed documentation and SwiftPM warning drift.
- [x] Make local release verification repeatable without adding CI.

## Out of Scope

| Item | Reason |
| --- | --- |
| Filesystem event watcher | Previously measured low ROI; reopen only with new hotspot evidence. |
| New metric cadence or visibility behavior | This plan preserves current product behavior. |
| Remote release, deployment, or push | Requires separate explicit approval. |
| New persistence format | No `UserDefaults` key or shape changes are needed. |

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- |
| Backlog trigger | Implement coalescing only if a controlled slow-reader test or real profile proves more than one queued read for one stream. | Avoid speculative concurrency work. | yes |
| Coalescing policy | Keep at most one read in flight and one pending refresh per stream. | Preserves eventual freshness while bounding queue growth. | yes |
| Token watcher | Keep polling. | Existing local measurement found idle scanning negligible. | yes |
| Release gate | Local executable script, no CI. | Matches project constraint and release workflow. | yes |

**Open questions:** none - all resolved or logged above.

## User Stories

### P1: Bounded Heavy Sampling

**User Story**: As a menu-bar user, I want slow background readers not to pile up work so that an open popover stays responsive and the app remains energy-conscious.

**Why P1**: A queue backlog would make displayed samples stale and can grow unbounded during sustained slow I/O.

**Acceptance Criteria**:

1. WHEN the profiling harness runs a heavy reader that exceeds its sampling interval, the system SHALL record whether that stream has more than one queued read.
2. IF evidence shows more than one queued read for a stream, the system SHALL allow at most one read in flight and one pending refresh for that stream.
3. WHILE a coalesced read is in flight, the system SHALL not enqueue duplicate reads for that stream.
4. WHEN the in-flight read completes with a pending refresh, the system SHALL execute exactly one subsequent refresh.
5. IF a sampler stops before an in-flight read delivers, the system SHALL not publish that stale result.

**Independent Test**: Use an injectable blocked reader and scheduler to prove bounded execution, one follow-up refresh, and no late delivery after stop.

### P1: Correct Local Guidance

**User Story**: As a maintainer, I want repository guidance and test output to be accurate so that release work has no misleading instructions or routine warnings.

**Why P1**: Both defects are confirmed and low-risk to fix.

**Acceptance Criteria**:

1. The README SHALL state that Sparkle automatic checks are governed by `Info.plist` and have no user-facing toggle.
2. WHEN `swift test` runs, the package manifest SHALL not emit an invalid-exclude warning for `MacMetricsViewTests/Fixtures`.

**Independent Test**: Search the update documentation against `AppUpdateService`, then run `swift test` and inspect manifest warnings.

### P2: Repeatable Local Release Gate

**User Story**: As a release maintainer, I want one local command to validate a built app and release metadata so that packaging drift is caught before publication.

**Why P2**: It reduces manual release mistakes without changing production behavior.

**Acceptance Criteria**:

1. WHEN invoked with a built `.app` and appcast path, the release gate SHALL fail non-zero when the bundle is invalid, unsigned, has an unresolved public key, or has a version mismatch with the newest appcast item.
2. WHEN invoked with valid local release inputs, the release gate SHALL complete without network access and print each completed check.
3. IF required input is absent or malformed, the release gate SHALL fail with an actionable message and shall not modify the app, appcast, or release artifacts.

**Independent Test**: Run against the Debug app and controlled invalid copies in a temporary directory.

## Edge Cases

- IF a reader completes after visibility changes, the delivery is discarded.
- IF several timer ticks occur while a reader is blocked, only one subsequent read remains pending.
- IF no backlog appears in controlled and real evidence, no coalescing integration starts.
- IF a release app has no matching appcast item, verification fails before publication.

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| PH-01 | P1: Bounded Heavy Sampling | Evidence | Verified |
| PH-02 | P1: Bounded Heavy Sampling | Implementation | Verified |
| PH-03 | P1: Bounded Heavy Sampling | Implementation | Verified |
| PH-04 | P1: Bounded Heavy Sampling | Implementation | Verified |
| PH-05 | P1: Bounded Heavy Sampling | Implementation | Verified |
| PH-06 | P1: Correct Local Guidance | Hygiene | Verified |
| PH-07 | P1: Correct Local Guidance | Hygiene | Verified |
| PH-08 | P2: Repeatable Local Release Gate | Release | Verified |
| PH-09 | P2: Repeatable Local Release Gate | Release | Verified |
| PH-10 | P2: Repeatable Local Release Gate | Release | Verified |

**Coverage:** 10 total, 10 mapped to tasks, 0 unmapped.

## Success Criteria

- [x] Controlled slow-reader test proves the selected backlog verdict.
- [x] `swift test` passes with no invalid `Fixtures` exclude warning.
- [x] Xcode Debug app passes the local release gate using local inputs only.
- [x] Debug app launch was dispatched; interactive popover-pixel observation remains a human follow-up.

## Handoff: Dev -> QA

- Inputs: requirements PH-01 through PH-10 and the completed implementation.
- Outputs: deterministic deferred-executor coverage for each gated reader and release-gate fixture evidence.
- Decision: go to final validation.
- Evidence: 1,029 XCTest cases pass; Debug Xcode build and local release gate pass.
- Pending: no automated native-popover visual inspection.
