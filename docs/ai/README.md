# docs/ai — Shared AI context

This directory is the **single source of truth** for everything AI agents need to
work on Mac Metrics View, regardless of which tool runs them (Claude Code, OpenAI
Codex, OpenCode, Antigravity, or any AGENTS.md-compatible agent).

Vendor folders (`.claude/`, `.codex/`, `.opencode/`, `.agents/`) are thin adapters
that symlink back here. Nothing of substance lives in them.

## Read order for a new agent

1. [`../../AGENTS.md`](../../AGENTS.md) — the entry point and rules.
2. [`project-context.md`](project-context.md) — what the product is and is not.
3. [`architecture.md`](architecture.md) — how the code is laid out.
4. [`workflow.md`](workflow.md) — the PLAN → SPECS → TASKS → IMPLEMENTATION → VALIDATION flow.
5. [`coding-standards.md`](coding-standards.md) and [`testing-standards.md`](testing-standards.md) — how to write and verify code.
6. [`domain-catalog.md`](domain-catalog.md) — vocabulary and metric definitions.

## Layout

```
docs/ai/
  README.md              # this file
  workflow.md            # the development lifecycle and its rules
  project-context.md     # product scope, users, constraints
  architecture.md        # code structure and key components
  coding-standards.md     # Swift/SwiftUI/AppKit conventions
  testing-standards.md   # what to test, how, and what "verified" means
  git-workflow.md        # branches, commits, PRs
  domain-catalog.md      # metrics, terms, severity thresholds

  plans/        # PLAN artifacts          (one source of truth)
  specs/        # SPEC artifacts
  tasks/        # TASK artifacts
  validation/   # VALIDATION records
  prompts/      # reusable, vendor-neutral prompts
  skills/       # reusable skills (each as <name>/SKILL.md)
```

## Relationship to `docs/`

`docs/` (one level up) holds the existing **product** documents — `PRD.md`,
`TECH_DECISIONS.md`, `SPEC_DRIVEN_DESIGN_V1.md`, and `features/`. Those remain the
authoritative product/architecture-decision record. `docs/ai/` is the **operational**
layer for agents and links to those documents rather than copying them.

When a new technical decision is made, record it in `docs/TECH_DECISIONS.md`.
When a new feature is scoped, follow the existing pattern in `docs/features/` and
create the workflow artifacts under `docs/ai/`.

## Conventions

- File names are **kebab-case** (`popover-temperature-row.md`, not `PopoverTempRow.md`).
- Every plan/spec/task/validation file carries a status (see [`workflow.md`](workflow.md)).
- Link related artifacts to each other; don't restate their content.
