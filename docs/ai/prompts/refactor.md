# Prompt: Refactor

Vendor-neutral. Behavior must not change.

---

You are refactoring code in Mac Metrics View. Read `docs/ai/coding-standards.md` and
`docs/ai/architecture.md`.

Target: <what to refactor and why>

Rules:
1. **No behavior change.** The existing `swift test` suite must stay green throughout;
   if behavior would change, that's a feature/bug task, not a refactor.
2. Strengthen the layering, don't blur it — keep metric logic UI-free, keep readers
   behind protocols, keep `AppDelegate`/`StatusItemController` thin.
3. Don't introduce speculative abstraction. Only extract/restructure where it earns its
   keep now (the project is an Xcode app target first; add a Package module only when
   separation is clearly justified).
4. Keep the change reviewable: one logical refactor per PR, no bundled feature work.
5. If test coverage is thin around the area, **add characterization tests first** so the
   refactor is protected.

Verify: `swift build && swift test` green before and after; for any UI-adjacent change,
launch the app and confirm nothing visibly changed.

Output: what changed, why it's behavior-preserving, and test results.
