# Validation: RAM Used / Total Only

Date: 2026-08-27
Verifier: independent
Target diff: `c042a81` (`fix(ram): show used total only`)
Spec: `docs/ai/specs/spec-ram-used-total-only.md`
Verdict: PASS

## Acceptance Criteria

1. PASS - Valid RAM sample shows `N.N/NN GB`.
   - Evidence: `MacMetricsView/Services/RAMFormatter.swift:17` routes `valueString(for:)` to used/total; `MacMetricsView/Services/RAMFormatter.swift:25-28` formats `%.1f/%.0f GB`; `MacMetricsViewTests/RAMUsedTotalFormatterTests.swift:53-55` asserts `11.2/16 GB`.

2. PASS - Icon mode shows RAM value without `RAM` label.
   - Evidence: `MacMetricsView/Services/RAMFormatter.swift:8-13` omits label when `showLabel == false`; `MacMetricsViewTests/RAMUsedTotalFormatterTests.swift:58-63` asserts `"11.2/16 GB"` with `showLabel: false`.

3. PASS - Label mode prefixes value with `RAM`.
   - Evidence: `MacMetricsView/Services/RAMFormatter.swift:8-13`; `MacMetricsView/App/CPUState.swift:135-149`; `MacMetricsViewTests/RAMUsedTotalFormatterTests.swift:61` asserts `"RAM 11.2/16 GB"`.

4. PASS - Legacy RAM metric preference ignored.
   - Evidence: `MacMetricsView/Models/MetricDisplaySettings.swift:14-19` has no `ramMenuBarMetric` key; `MacMetricsView/Models/MetricDisplaySettings.swift:65-67` only loads current display settings; `MacMetricsViewTests/MetricVisibilitySettingsTests.swift:174-183` persists `"pressure"` and still expects `"RAM 14.0/16 GB"`.

5. PASS - Invalid RAM input shows `--/-- GB`, no NaN/negative/percent in menu bar.
   - Evidence: `MacMetricsView/Services/RAMFormatter.swift:25-28`; `MacMetricsViewTests/RAMUsedTotalFormatterTests.swift:43-48` covers nil, NaN, negative, zero total, missing total; `MacMetricsViewTests/RAMUsedTotalFormatterTests.swift:58-63` asserts no `%`.

6. PASS - Reclaimable file cache excluded from used memory.
   - Evidence: `MacMetricsView/Services/RAMSampler.swift:74-90` computes used as internal minus purgeable plus wired plus compressed, while external/file cache is separate; `MacMetricsViewTests/RAMSampleAndReaderTests.swift:41-49` asserts expected used pages excluding cache.

## Gate

- Command: `swift test`
- Result: PASS, exit 0
- Evidence: `Executed 705 tests, with 0 failures (0 unexpected)`; `Test Suite 'All tests' passed`.
- Warnings: existing Swift warning observed in unrelated `CleaningLockStateTests.swift`; no test failure.

## Discrimination Sensor

- Real worktree status before sensor: clean (`git status --porcelain` produced no output).
- Scratch command: `git worktree add /tmp/ram-used-total-only-sensor c042a81`.
- Mutation in scratch only: changed `RAMFormatter.valueString(for:)` to return `CPUFormatter.percentageString(sample?.pressurePercent)`.
- Test command in scratch: `swift test --filter RAMUsedTotalFormatterTests`.
- Result: expected FAIL, exit 1.
- Evidence: `RAMUsedTotalFormatterTests.swift:61` failed with `"RAM 99%"` vs `"RAM 11.2/16 GB"`; line 62 failed with `"99%"` vs `"11.2/16 GB"`; line 55 failed with `"0%"` vs `"11.2/16 GB"`.
- Cleanup: `git worktree remove --force /tmp/ram-used-total-only-sensor`.
- Real worktree status after sensor, before report: clean (`git status --porcelain` produced no output).

## Risks

- UI/status-item runtime rendering was not manually launched; per `docs/ai/testing-standards.md`, only metric logic is verified by unit tests.
- Existing unrelated Swift 6 warning remains outside this feature.
