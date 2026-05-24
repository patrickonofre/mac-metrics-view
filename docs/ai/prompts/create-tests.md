# Prompt: Create tests

Vendor-neutral. Produces XCTest code in `MacMetricsViewTests/`.

---

You are adding tests for Mac Metrics View. Read `docs/ai/testing-standards.md` and the
existing suites (e.g. `CPUFormattingAndHistoryTests.swift`) to match style.

Target: <component / behavior to cover>

Cover the testable metric logic:
1. **Calculation** — delta-based rates, the no-previous-snapshot case, aggregation.
2. **Formatting** — fixed-width output, units, and **clamps**: assert no NaN, negative,
   or impossible percentages — test the boundary, not just the happy path.
3. **History** — bounded capacity, ordering, min/max/trend.
4. **Severity** — threshold edges (79/80/89/90).
5. **Settings** — visibility / display style / launch-at-login round-trips.

Rules:
- Drive samplers with **fake readers** (conforming to the reader protocol) for
  deterministic input — never depend on real machine load.
- Do not attempt to unit-test status-item rendering or popover presentation; note those
  require launching the app.
- One test file per subject, named `<Subject>Tests.swift`.

Verify with `swift test` and report which cases were added and the result.
