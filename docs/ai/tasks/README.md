# Tasks

A **task** turns a spec into an ordered, executable unit of work small enough to do and
verify on its own. Each task names the files/areas it touches and links the spec it
implements.

See the lifecycle in [`../workflow.md`](../workflow.md).

> Note: this folder is for the **planning artifacts** that decompose a spec. For
> tracking live progress within a single working session, agents may also use their
> tool-native task list — but the durable, shared decomposition lives here.

## When to create one

- A spec is `ready` and you're breaking it into concrete steps before coding.

## Naming

kebab-case with an order prefix, sharing the spec's stem:
`task-001-add-temperature-reader.md`, `task-002-add-temperature-sampler.md`.

## Recommended format

```markdown
# Task: <imperative action>

Status: draft | ready | in-progress | blocked | done | superseded
Spec: ../specs/spec-<name>.md

## Goal
One sentence: what done looks like.

## Touches
- MacMetricsView/Services/<file>.swift
- MacMetricsViewTests/<file>.swift

## Steps
1. ...
2. ...

## Verification
- [ ] swift test covers <case>
- [ ] (if UI) app launched and behavior observed
```

## Rules

- A task should be completable and verifiable independently; if it can't be verified,
  split it.
- Reference the spec; don't restate it.
- One source of truth: tasks live only here, never in a vendor folder.
- Metric-logic tasks include their test in the same task (see `../testing-standards.md`).

## Do not put here

- The contract/acceptance criteria (that's the spec).
- Validation evidence (that's `../validation/`).
