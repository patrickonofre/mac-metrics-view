# Validation

A **validation record** is the evidence that an implementation satisfies its spec:
tests run and their results, `swift build` / `swift test` output, lint/review notes,
manual run evidence for UI/status-item behavior, and any residual risks.

See the lifecycle in [`../workflow.md`](../workflow.md).

## When to create one

- Closing out a spec/feature — before marking it `done` and before the PR merges.

## Naming

kebab-case, sharing the spec's stem: `validation-temperature-support.md`.

## Recommended format

```markdown
# Validation: <feature/component>

Status: in-progress | done | blocked
Spec: ../specs/spec-<name>.md

## Acceptance criteria
- [x] Criterion 1 — how it was verified
- [x] Criterion 2 — how it was verified

## Automated checks
- `swift build` — result
- `swift test` — result (which suites/cases)

## Manual verification (UI / status item / popover)
- Launched via <swift run | xcodebuild + open>
- Observed: <what was seen>

## Residual risks
- <known limitation / follow-up>
```

## Rules

- Don't mark a feature `done` without running `swift test`.
- UI / status-item / popover / menu bar behavior is **not** verified by a green build —
  the app must have been launched and the behavior observed
  (see `../testing-standards.md`).
- Record the actual commands run and their outcomes, not intentions.
- One source of truth: validation records live only here, never in a vendor folder.

## Do not put here

- The requirements themselves (that's the spec).
- Plans or task breakdowns.
