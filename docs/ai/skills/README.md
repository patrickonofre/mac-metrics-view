# Skills

Reusable, vendor-neutral skills for Mac Metrics View. Each skill lives in its own folder
as `SKILL.md` (with optional `references/` for deep material). They are shared across all
agents via the vendor symlinks (`.claude/skills`, `.codex/skills`, etc.) and the
top-level `skills/` symlink — there is one copy, here.

These skills reflect the **real stack** (Swift / SwiftUI / AppKit, macOS menu bar app).
Do not add skills for stacks this project doesn't use.

## Available skills

| Skill | Use it when |
| --- | --- |
| [`macos-native-app`](macos-native-app/SKILL.md) | Planning/scaffolding/implementing native macOS features — menu bar UI, popovers, app lifecycle, preferences, packaging, status-item behavior. |
| [`system-metrics-cpu`](system-metrics-cpu/SKILL.md) | Working on CPU/RAM (and related metric) sampling, refresh intervals, formatting, severity colors, history, and tests for resource calculations. |
| [`macos-app-design-expert`](macos-app-design-expert/SKILL.md) | UI/UX decisions, visual polish, interaction patterns, macOS HIG alignment for the menu bar and popover. |
| [`menu-bar-product-prd`](menu-bar-product-prd/SKILL.md) | Product scope work — PRDs, acceptance criteria, roadmap slices, feature tradeoffs, non-goals. |

## Structure of a skill

```
<skill-name>/
  SKILL.md            # frontmatter (name, description) + guidance
  references/         # optional deep-dive docs the skill points to
  agents/openai.yaml  # optional thin per-agent interface metadata (adapter)
```

`SKILL.md` content stays vendor-neutral ("when an agent needs to…"). The optional
`agents/<tool>.yaml` file is a thin adapter holding tool-specific display metadata only —
no project knowledge lives there.

## Adding a skill

1. Create `docs/ai/skills/<kebab-name>/SKILL.md` with `name` and `description`
   frontmatter; keep wording agent-neutral.
2. Put long material in `references/` and point to it from `SKILL.md`.
3. Add a row to the table above.
4. No vendor wiring needed — the symlinks already expose it to every agent.
