# Workflow

Every non-trivial change moves through five stages:

```
PLAN  ->  SPECS  ->  TASKS  ->  IMPLEMENTATION  ->  VALIDATION
```

Small, obvious changes (a one-line fix, a typo, a test tweak) may skip straight to
IMPLEMENTATION + VALIDATION. Use judgment: if the change has risk, touches multiple
files, or changes product behavior, start at PLAN.

## Stages

### PLAN — `docs/ai/plans/`
Defines the macro objective: *what* we are doing and *why*, the phases to get there,
the risks, and the dependencies. A plan does not contain code. It is the document a
human approves before specs are written.

Create a plan when: starting a feature, a multi-step refactor, or anything with
sequencing or risk worth aligning on first.

### SPECS — `docs/ai/specs/`
Break a plan into concrete technical and functional requirements: behavior,
inputs/outputs, data shapes, edge cases, acceptance criteria, non-goals. A spec is
the contract IMPLEMENTATION must satisfy. One plan can produce several specs.

Create a spec when: a plan phase is ready to be made precise, or when a change is
specced directly (small enough to skip a plan but still needs a contract).

### TASKS — `docs/ai/tasks/`
Turn specs into ordered, executable units of work. Each task is small enough to do
and verify on its own and names the files/areas it touches. Tasks reference the spec
they implement.

### IMPLEMENTATION — the code
The actual Swift code in `MacMetricsView/`, tests in `MacMetricsViewTests/`, and any
updated docs. **There is no `implementation/` folder.** Implementation is committed
code, not a document.

### VALIDATION — `docs/ai/validation/`
Records the evidence that the implementation satisfies the spec: tests run and their
results, `swift build` / `swift test` output, lint/review notes, manual run evidence
for UI/status-item behavior, and any residual risks. One validation record per
spec/feature being closed out.

## Transition rules

- PLAN → SPECS: plan is `ready` and approved.
- SPECS → TASKS: spec is `ready`; acceptance criteria are testable.
- TASKS → IMPLEMENTATION: task is `ready` and unblocked.
- IMPLEMENTATION → VALIDATION: code compiles and tests are written.
- VALIDATION → done: evidence shows acceptance criteria met; risks noted.
- Any stage can produce a `blocked` state — record what unblocks it and where.

## Statuses

Every plan/spec/task/validation file declares one of:

| Status | Meaning |
| --- | --- |
| `draft` | Being written; not ready to act on. |
| `ready` | Reviewed and actionable. |
| `in-progress` | Actively being worked. |
| `blocked` | Cannot proceed; note the blocker. |
| `done` | Completed and verified. |
| `superseded` | Replaced by a newer artifact; link to it. |

Put the status near the top of the file (a `Status:` line or front-matter).

## Naming

- **kebab-case**, descriptive, scoped to the subject: `temperature-menu-bar-row`.
- Optionally prefix for ordering/type within a folder, e.g.
  `plan-temperature-support.md`, `spec-temperature-sampler.md`,
  `task-001-add-temperature-sampler.md`, `validation-temperature-support.md`.
- Keep related artifacts sharing a stem so they're easy to trace.

## Anti-patterns

- Creating an `implementation/` directory — the code is the implementation.
- Writing plans/specs/tasks/validation inside a vendor folder (`.claude/`, etc.).
- Duplicating content that already lives in `docs/ai/` or `docs/` — link instead.
- Marking VALIDATION `done` without running `swift test`, or claiming UI behavior
  verified without launching the app.
- Skipping straight to code on a risky/multi-file change without a plan or spec.
- Hardcoding a vendor/tool name into a shared prompt or skill.
- Bundling unrelated refactors into a feature change.
