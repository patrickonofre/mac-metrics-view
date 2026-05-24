# Prompt: Create a migration

Vendor-neutral.

> **Scope note:** Mac Metrics View has **no database**. Here, "migration" means changing
> a **persisted format** — primarily `UserDefaults` keys/shape used by the settings
> models (`MetricVisibilitySettings`, `MetricDisplaySettings`, `LaunchAtLoginSettings`).
> If a future feature introduces real persistence (e.g. a history store on disk), the
> same principles apply.

---

You are changing how Mac Metrics View persists state. Read
`docs/ai/coding-standards.md` and the affected settings model.

Change: <what persisted shape is changing and why>

Rules:
1. **Don't break existing installs.** Users already have values stored under current
   keys. Either keep reading the old key and write the new shape (one-time upgrade), or
   default missing values safely — never silently lose a user's preference.
2. Keep the migration logic **isolated and testable**: read-old → transform → write-new,
   covered by a unit test that feeds old-format input and asserts the new-format result
   (including the "no stored value yet / fresh install" case).
3. Bump/record a stored schema version only if needed to disambiguate formats.
4. No telemetry, no network — persistence stays local.

Verify: add the migration test, run `swift test`, and (since settings drive the menu
bar) launch the app to confirm a pre-existing-preferences scenario loads correctly.

Output: what changed, the upgrade path, the test added, and verification result. Record
in `docs/ai/validation/` if it closes a spec.
