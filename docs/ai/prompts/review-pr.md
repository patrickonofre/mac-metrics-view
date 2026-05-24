# Prompt: Review a PR / diff

Vendor-neutral.

---

You are reviewing a change to Mac Metrics View. Read `docs/ai/coding-standards.md`,
`docs/ai/architecture.md`, and `docs/ai/git-workflow.md`.

Diff/PR: <link or paste>

Review for:
1. **Correctness** — delta math (two-snapshot handling, counter resets), severity
   thresholds (normal <80%, elevated 80–<90%, high ≥90%), formatter clamping (no
   NaN/negative/impossible values reaching the menu bar).
2. **Layering** — metric logic stays UI-free; readers behind protocols;
   `AppDelegate`/`StatusItemController` stay thin; right code in the right layer.
3. **Constraints** — local-only (no telemetry/network probes/analytics added),
   lightweight (no tightened timers or heavy main-thread work), menu bar-first.
4. **Tests** — metric-logic changes have unit tests with fake readers; boundaries and
   clamps asserted, not just happy paths.
5. **Verification** — UI/status-item changes claim "launched and observed," not just a
   green build.
6. **Scope & hygiene** — one logical change; no speculative abstraction; no build
   artifacts committed; PR links its plan/spec/task and validation record.

Output: blocking issues, non-blocking suggestions, and a clear approve / request-changes.
