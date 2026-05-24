# .opencode — adapter

This folder is a **thin adapter** for OpenCode. It contains **no project content of its
own**. The single source of truth is [`../docs/ai/`](../docs/ai/README.md); start at
[`../AGENTS.md`](../AGENTS.md).

The entries below are symlinks into `docs/ai/` so OpenCode sees the shared context with
no duplication:

| Symlink | Target |
| --- | --- |
| `plans` | `../docs/ai/plans` |
| `specs` | `../docs/ai/specs` |
| `tasks` | `../docs/ai/tasks` |
| `validation` | `../docs/ai/validation` |
| `prompts` | `../docs/ai/prompts` |
| `skills` | `../docs/ai/skills` |

## Rules

- Never create plans/specs/tasks/validation here — create them under `docs/ai/`.
- Don't copy content from `docs/ai/` into this folder; link or rely on the symlinks.
- If a symlink is missing, recreate it: `ln -sfn ../docs/ai/<name> .opencode/<name>`.
