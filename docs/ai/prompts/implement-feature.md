# Prompt: Implement a feature

Vendor-neutral. The output is **code** (no `implementation/` folder).

---

You are implementing a feature in Mac Metrics View from an existing spec/task. Read the
spec/task, `docs/ai/coding-standards.md`, and `docs/ai/architecture.md`.

Spec/Task: <path>

Follow the established pattern ("Adding a new metric" in `architecture.md`):
1. Reader (raw macOS API) behind a protocol so it can be faked in tests.
2. Sample model (value type) and History if a trend is needed.
3. Sampler with a `@MainActor` delegate; rates from snapshot deltas; interval ≥ 1s.
4. Pure Formatter with defensive clamping (no NaN/negative/impossible values).
5. Surface through `CPUState`; register sampler/delegate in `AppDelegate`; gate on
   visibility (hidden metric stops its sampler).
6. Render in `StatusItemController` (menu bar) and/or `PopoverView`.

Rules:
- Keep metric logic UI-free and unit-tested first (`MacMetricsViewTests/`).
- Honor constraints: native-only, local-only (no telemetry/network probes), lightweight,
  menu bar-first.
- Scope strictly to the spec — no speculative abstractions or unrelated refactors.
- Run `swift build && swift test`. For UI/status-item changes, launch the app and
  observe behavior — a green build is not proof.
- Then create/update the VALIDATION record per `validate-implementation.md`.

Output: files changed, test results, and (if UI) what you observed when launching.
