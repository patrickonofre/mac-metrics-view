# .claude — adapter

This folder is a **thin adapter** for Claude Code. It contains **no project content of
its own**. The single source of truth is [`../docs/ai/`](../docs/ai/README.md); start at
[`../AGENTS.md`](../AGENTS.md).

The entries below are symlinks into `docs/ai/` so Claude Code discovers the shared
context with no duplication:

| Symlink | Target |
| --- | --- |
| `plans` | `../docs/ai/plans` |
| `specs` | `../docs/ai/specs` |
| `tasks` | `../docs/ai/tasks` |
| `validation` | `../docs/ai/validation` |
| `prompts` | `../docs/ai/prompts` |
| `skills` | `../docs/ai/skills` |

`settings.json` holds Claude Code project settings (the only file genuinely specific to
this tool).

## Rules

- Never create plans/specs/tasks/validation here — create them under `docs/ai/`.
- Don't copy content from `docs/ai/` into this folder; link or rely on the symlinks.
- If a symlink is missing (e.g. fresh clone on a filesystem without symlink support),
  recreate it: `ln -sfn ../docs/ai/<name> .claude/<name>`.
