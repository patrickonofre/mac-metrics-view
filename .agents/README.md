# .agents — adapter

This folder is a **thin adapter** for Antigravity and any other AGENTS.md-compatible
agent. It contains **no project content of its own**. The single source of truth is
[`../docs/ai/`](../docs/ai/README.md); start at [`../AGENTS.md`](../AGENTS.md).

The entries below are symlinks into `docs/ai/` so any compatible agent sees the shared
context with no duplication:

| Symlink | Target |
| --- | --- |
| `plans` | `../docs/ai/plans` |
| `specs` | `../docs/ai/specs` |
| `tasks` | `../docs/ai/tasks` |
| `validation` | `../docs/ai/validation` |
| `prompts` | `../docs/ai/prompts` |
| `skills` | `../docs/ai/skills` |

This is the right place to add a **new** agent that doesn't have its own dedicated
folder: point it at `../AGENTS.md` and reuse these symlinks.

## Rules

- Never create plans/specs/tasks/validation here — create them under `docs/ai/`.
- Don't copy content from `docs/ai/` into this folder; link or rely on the symlinks.
- If a symlink is missing, recreate it: `ln -sfn ../docs/ai/<name> .agents/<name>`.
