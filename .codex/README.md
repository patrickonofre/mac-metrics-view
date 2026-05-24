# .codex — adapter

This folder is a **thin adapter** for OpenAI Codex. It contains **no project content of
its own**. The single source of truth is [`../docs/ai/`](../docs/ai/README.md); start at
[`../AGENTS.md`](../AGENTS.md).

The entries below are symlinks into `docs/ai/` so Codex sees the shared context with no
duplication:

| Symlink | Target |
| --- | --- |
| `plans` | `../docs/ai/plans` |
| `specs` | `../docs/ai/specs` |
| `tasks` | `../docs/ai/tasks` |
| `validation` | `../docs/ai/validation` |
| `prompts` | `../docs/ai/prompts` |
| `skills` | `../docs/ai/skills` |

Each shared skill may also carry a thin `agents/openai.yaml` (interface metadata only)
inside its own folder under `docs/ai/skills/<name>/` — that is the Codex-facing display
adapter; the skill's knowledge stays in `SKILL.md`.

## Rules

- Never create plans/specs/tasks/validation here — create them under `docs/ai/`.
- Don't copy content from `docs/ai/` into this folder; link or rely on the symlinks.
- If a symlink is missing, recreate it: `ln -sfn ../docs/ai/<name> .codex/<name>`.
