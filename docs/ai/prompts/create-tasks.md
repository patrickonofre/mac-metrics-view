# Prompt: Create tasks

Vendor-neutral. Produces TASK artifacts in `docs/ai/tasks/`.

---

You are decomposing a **spec** into ordered, executable **tasks** for Mac Metrics View.
Read the spec, `docs/ai/workflow.md`, and `docs/ai/testing-standards.md`.

Spec: <spec path>

For each task:
1. One imperative **goal** sentence (what "done" looks like).
2. The exact **files/areas** it touches (`MacMetricsView/...`, `MacMetricsViewTests/...`).
3. Ordered **steps**.
4. **Verification** — which `swift test` case proves it; for UI/status-item work, note
   that the app must be launched and behavior observed.

Rules:
- Each task must be independently completable **and verifiable**. If it can't be
  verified alone, split it.
- Order by dependency (reader → sampler → formatter → state/wiring → UI), mirroring the
  pattern in `docs/ai/architecture.md` ("Adding a new metric").
- Metric-logic tasks include their unit test in the same task.
- Save each to `docs/ai/tasks/task-NNN-<kebab-name>.md` with `Status: draft`, linking
  the spec. Never in a vendor folder.

Output the ordered task list with file paths.
