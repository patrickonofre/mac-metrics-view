# Plan: Performance Hardening and Release Signal

Status: done

## Objective

Preserve the app's current metric behavior while proving whether the shared heavy-sampling queue needs bounded work, removing two confirmed maintenance defects, and adding a repeatable local release gate. Existing evidence already rejects a filesystem watcher as a default optimization.

## Phases

1. Establish queue evidence and close confirmed documentation/package defects.
2. Add bounded sampling only when the queue evidence meets the specified trigger.
3. Add a local release verification command and validate a real Debug app.

## Risks

- Unmeasured queue work could motivate an unnecessary concurrency refactor. Mitigation: no coalescing code before baseline evidence.
- Coalescing could suppress the final sample after a stop or visibility transition. Mitigation: per-stream pending state, generation guard, and deterministic scheduler tests.
- Release verification could become a second source of release rules. Mitigation: the script reads existing plist/appcast inputs and the runbook links to it.

## Dependencies

- Existing `SamplingExecutor`, sampler fakes, `swift test`, and Xcode Debug build.
- Existing release runbook, `Info.plist`, and `docs/appcast.xml`.

## Out of Scope

- FSEvents/DispatchSource token watchers. `validation-lightweight-performance.md` measured low idle scan cost and rejected this refactor; reopen only with fresh profiling evidence.
- New telemetry, network calls, persistence keys, UI controls, metric intervals, or sampler API replacement.
- CI/CD introduction.

## Specs

- [Spec: performance hardening](../specs/spec-performance-hardening.md)
- [Design: performance hardening](../specs/design-performance-hardening.md)
- [Tasks: performance hardening](../tasks/tasks-performance-hardening.md)

## Handoff: PM -> Dev

- Inputs: responsiveness risk from potentially backlogged heavy readers; release hygiene gaps.
- Outputs: bounded-work scope, explicitly rejected watcher alternative, and local-only release gate.
- Decision: go; preserve metrics, intervals, persistence, and network posture.
- Evidence: controlled backlog test and completed validation record.
- Pending: manual visual popover observation remains a post-automation smoke item.
