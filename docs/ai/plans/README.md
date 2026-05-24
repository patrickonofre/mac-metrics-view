# Plans

A **plan** defines a macro objective: *what* we're doing and *why*, the phases to get
there, the risks, and the dependencies. It is the document a human approves before any
spec is written. Plans contain **no code**.

See the lifecycle in [`../workflow.md`](../workflow.md).

## When to create one

- Starting a feature or a multi-step refactor.
- Any change with sequencing, risk, or cross-cutting impact worth aligning on first.

Skip a plan only for small, low-risk, single-file changes.

## Naming

kebab-case, prefixed for clarity: `plan-temperature-support.md`,
`plan-launch-at-login.md`.

## Recommended format

```markdown
# Plan: <objective>

Status: draft | ready | in-progress | blocked | done | superseded

## Objective
One paragraph: what success looks like and why it matters now.

## Phases
1. <phase> — outcome
2. <phase> — outcome

## Risks
- <risk> — mitigation

## Dependencies
- <dependency / prerequisite>

## Out of scope
- <explicitly excluded>

## Specs
- Links to docs/ai/specs/* once written.
```

## Rules

- One source of truth: plans live **only** here, never in a vendor folder.
- Keep product rationale linked to `docs/PRD.md` / `docs/TECH_DECISIONS.md` rather than
  restated.
- Update the status as the plan progresses; link the specs it spawns.

## Do not put here

- Code, diffs, or implementation detail (that's the spec/task/code).
- Test logs or evidence (that's `../validation/`).
