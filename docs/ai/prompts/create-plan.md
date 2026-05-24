# Prompt: Create a plan

Vendor-neutral. Produces a PLAN artifact in `docs/ai/plans/`.

---

You are creating a **plan** for Mac Metrics View (native macOS menu bar metrics app —
Swift/SwiftUI/AppKit, macOS 14+, local-only). Read `AGENTS.md`,
`docs/ai/project-context.md`, and `docs/ai/workflow.md` first.

Goal: <describe the objective>

Produce a plan that:
1. States the **objective** and why it matters now (link `docs/PRD.md` /
   `docs/TECH_DECISIONS.md` rather than restating product rationale).
2. Breaks the work into **phases**, each with a concrete outcome.
3. Lists **risks** with mitigations — especially energy/performance, privacy
   (local-only), and macOS API reliability.
4. Lists **dependencies** and prerequisites.
5. Calls out what is **out of scope**.

Constraints:
- No code in the plan.
- Honor hard constraints: native-only, local-only (no telemetry/network probes),
  lightweight (sample interval ≥ 1s), menu bar-first (accessory policy).
- Save to `docs/ai/plans/plan-<kebab-name>.md` with `Status: draft` and the format in
  `docs/ai/plans/README.md`. Do not create it in any vendor folder.

Output the file path and a 3-line summary.
