# AGENTS.md

Vendor-neutral operating guide for any AI agent working in this repository
(Claude Code, OpenAI Codex, OpenCode, Antigravity, or any AGENTS.md-compatible tool).

This file is intentionally short. The single source of truth for shared context,
workflow, standards, prompts, and skills is [`docs/ai/`](docs/ai/README.md).
Read it before doing non-trivial work.

## Project

**Mac Metrics View** — a native macOS menu bar app showing compact CPU, RAM, and
network (and temperature) metrics near the system clock, with a click-through
popover for detail. Local-only, no telemetry, no accounts.

- Language: **Swift 5.9**
- UI: **SwiftUI** with **AppKit** interop (`NSStatusItem`, `NSPopover`, accessory activation policy)
- Minimum target: **macOS 14**
- Build: **Swift Package Manager** (`Package.swift`) and an **Xcode project** (`MacMetricsView.xcodeproj`)
- Tests: **XCTest** (`swift test`)
- Persistence: `UserDefaults`
- No database, no backend, no CI/CD, no Docker. Single repo, single product.

Source lives in `MacMetricsView/` (`App/`, `Models/`, `Services/`, `UI/`).
Tests live in `MacMetricsViewTests/`. Product docs live in `docs/`.

## Mandatory workflow

All non-trivial work follows:

```
PLAN -> SPECS -> TASKS -> IMPLEMENTATION -> VALIDATION
```

- **PLAN** — macro objective, phases, risks, dependencies → `docs/ai/plans/`
- **SPECS** — technical/functional requirements → `docs/ai/specs/`
- **TASKS** — executable, ordered actions → `docs/ai/tasks/`
- **IMPLEMENTATION** — the real code, tests, and updated docs. **There is no `implementation/` folder; the implementation is the code itself.**
- **VALIDATION** — tests, lint, review, checks, evidence, residual risks → `docs/ai/validation/`

Details, transition rules, statuses, and anti-patterns: [`docs/ai/workflow.md`](docs/ai/workflow.md).

## Rules every agent must follow

1. **Single source of truth.** New plans, specs, tasks, and validation records are created **only** under `docs/ai/`. Never create or duplicate them inside a vendor folder (`.claude/`, `.codex/`, `.opencode/`, `.agents/`).
2. **Vendor folders are thin adapters.** They contain only a `README.md` (and tool config such as `.claude/settings.json`) plus symlinks back into `docs/ai/`. Do not put real content there.
3. **Skills use `SKILL.md`.** Each shared skill lives at `docs/ai/skills/<name>/SKILL.md`. Do not invent skills for stacks this project does not use.
4. **Prompts are reusable and vendor-neutral.** They live in `docs/ai/prompts/`. Do not hardcode a specific agent/tool name into a prompt.
5. **Don't duplicate context.** If something is already documented in `docs/ai/` or `docs/`, link to it instead of copying.

## Engineering rules

- **Testing** — System metric logic (sampling, calculation, formatting, history, severity, settings) must be unit-tested in `MacMetricsViewTests/` and isolated from UI. Run `swift test` before claiming done. UI/status-item behavior cannot be claimed verified unless the app was actually launched (`xcodebuild` run target or `swift run`). See [`docs/ai/testing-standards.md`](docs/ai/testing-standards.md).
- **Change policy** — Keep changes scoped to the task. No speculative abstractions, no unrelated refactors bundled into a feature. Planned feature extensions must be specified before production code changes (existing pattern: `docs/features/`).
- **Security & privacy** — Local-only. No telemetry, no external network calls, no accounts. Network metrics read local interface counters only. Don't add analytics, crash reporters, or remote endpoints without an explicit decision recorded in `docs/TECH_DECISIONS.md`.
- **Migrations** — This app has no database. "Migration" means a change to a persisted format (e.g. `UserDefaults` keys/shape). Such changes must be backward-compatible or include a documented upgrade path, plus tests. See `docs/ai/prompts/create-migration.md`.
- **Pull requests** — One logical change per PR. Title under ~70 chars, imperative. Body explains the *why* and links the relevant plan/spec/task and the validation record. See [`docs/ai/git-workflow.md`](docs/ai/git-workflow.md).
- **Coding standards** — Swift API Design Guidelines; samplers/services free of UI; defensive clamping/formatting (no NaN/negative/impossible values in UI). See [`docs/ai/coding-standards.md`](docs/ai/coding-standards.md).

## Where things are

| Need | Go to |
| --- | --- |
| How the workflow works | [`docs/ai/workflow.md`](docs/ai/workflow.md) |
| What this project is | [`docs/ai/project-context.md`](docs/ai/project-context.md) |
| How the code is organized | [`docs/ai/architecture.md`](docs/ai/architecture.md) |
| How to write code here | [`docs/ai/coding-standards.md`](docs/ai/coding-standards.md) |
| How to test | [`docs/ai/testing-standards.md`](docs/ai/testing-standards.md) |
| Git / PR conventions | [`docs/ai/git-workflow.md`](docs/ai/git-workflow.md) |
| Domain terms & metrics | [`docs/ai/domain-catalog.md`](docs/ai/domain-catalog.md) |
| Reusable prompts | [`docs/ai/prompts/`](docs/ai/prompts/) |
| Reusable skills | [`docs/ai/skills/`](docs/ai/skills/) |
| Product PRD / decisions | `docs/PRD.md`, `docs/TECH_DECISIONS.md`, `docs/SPEC_DRIVEN_DESIGN_V1.md` |
