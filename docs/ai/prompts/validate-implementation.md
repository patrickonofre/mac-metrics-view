# Prompt: Validate an implementation

Vendor-neutral. Produces a VALIDATION record in `docs/ai/validation/`.

---

You are validating that an implementation satisfies its spec for Mac Metrics View. Read
the spec, `docs/ai/testing-standards.md`, and `docs/ai/validation/README.md`.

Spec/feature: <path>

Do, and record the actual results:
1. Walk each **acceptance criterion** and state how it was verified.
2. Run the **automated checks**: `swift build`, then `swift test` — capture results and
   which suites/cases cover the change.
3. For **UI / status item / popover / menu bar** behavior: launch the app
   (`swift run` or the Xcode build + `open`) and observe. A green build is **not** proof
   — explicitly state what you saw.
4. Note **residual risks** and follow-ups.

Rules:
- Don't mark the feature `done` if `swift test` fails or any criterion is unmet.
- Record commands actually run and their real outcomes, not intentions.
- Save to `docs/ai/validation/validation-<kebab-name>.md` using the README format. Never
  in a vendor folder.

Output: the file path and a pass/fail verdict per acceptance criterion.
