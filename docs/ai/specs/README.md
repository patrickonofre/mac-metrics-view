# Specs

A **spec** turns a plan (or a small direct request) into a precise technical and
functional contract: behavior, inputs/outputs, data shapes, edge cases, acceptance
criteria, and non-goals. The implementation must satisfy the spec.

See the lifecycle in [`../workflow.md`](../workflow.md).

## Relationship to existing design docs

The repo already has authoritative product/spec documents under `docs/`:
`SPEC_DRIVEN_DESIGN_V1.md`, `SPEC_DRIVEN_DEV_POPOVER_UI_POLISH.md`, and the feature
docs in `docs/features/`. Those stay where they are. **New** specs produced by the
PLAN → SPECS → TASKS flow go here, and should link back to the relevant `docs/` design
document instead of duplicating it.

## When to create one

- A plan phase is ready to be made precise.
- A change is small enough to skip a plan but still needs a contract before code.

## Naming

kebab-case, sharing a stem with its plan: `spec-temperature-sampler.md`,
`spec-temperature-menu-bar-row.md`.

## Recommended format

```markdown
# Spec: <feature/component>

Status: draft | ready | in-progress | blocked | done | superseded
Plan: ../plans/plan-<name>.md  (if any)

## Summary
What this delivers, in one paragraph.

## Functional requirements
- <observable behavior>

## Technical requirements
- Types/data shapes, layer placement (Reader/Sampler/Model/Formatter/UI), interfaces.

## Edge cases
- <e.g. no previous snapshot; counter reset; NaN/clamp>

## Acceptance criteria
- [ ] Testable statement 1
- [ ] Testable statement 2

## Non-goals
- <explicitly excluded>
```

## Rules

- Acceptance criteria must be **testable** (so VALIDATION can prove them).
- Place each requirement in the right architecture layer (see `../architecture.md`).
- One source of truth: specs live only here, never in a vendor folder.

## Do not put here

- Step-by-step task breakdowns (that's `../tasks/`).
- Code or test output.
