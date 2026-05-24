# Prompt: Fix a bug

Vendor-neutral.

---

You are fixing a bug in Mac Metrics View. Read `docs/ai/architecture.md` and
`docs/ai/testing-standards.md`.

Bug: <symptom, repro steps, expected vs. actual>

Steps:
1. **Reproduce** — confirm the symptom. For metric bugs, identify which layer is wrong
   (Reader / Sampler delta math / Formatter clamp / History / UI). Common culprits:
   missing two-snapshot handling, counter resets producing negative rates, unclamped
   values reaching the menu bar, severity threshold off-by-one.
2. **Write a failing test** in `MacMetricsViewTests/` that captures the bug (use a fake
   reader for deterministic input). If the bug is UI-only, describe the manual repro
   instead.
3. **Fix the root cause** — not the symptom. Keep the change minimal and in the correct
   layer.
4. **Verify** — the new test passes and `swift test` is green; for UI/status-item bugs,
   launch the app and confirm.

Rules:
- No unrelated refactors riding along with the fix.
- Preserve constraints: local-only, lightweight, defensive formatting.

Output: root cause, the test added, files changed, and verification result. Record it in
`docs/ai/validation/` if it closes a spec/feature.
