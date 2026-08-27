# Task: RAM Used / Total Only

Status: done

Spec: ../specs/spec-ram-used-total-only.md
Plan: ../plans/plan-ram-used-total-only.md

## Test Coverage Matrix

| Requirement | Test file | Coverage |
| --- | --- | --- |
| RAMONLY-01 | MacMetricsViewTests/CPUFormattingAndHistoryTests.swift, MacMetricsViewTests/RAMUsedTotalFormatterTests.swift | menu-bar value, label/icon variants, placeholders |
| RAMONLY-02 | MacMetricsViewTests/MetricVisibilitySettingsTests.swift, MacMetricsViewTests/MetricDisplaySettingsTests.swift | legacy key does not affect display |
| RAMONLY-03 | MacMetricsViewTests/RAMSampleAndReaderTests.swift | reclaimable cache excluded from used memory |

## Gate Check Commands

- Quick: `swift test --filter RAM`
- Build: `swift test`

## Execution Plan

### Phase 1

```text
T1
```

## Task Breakdown

### T1: Replace selectable RAM menu-bar modes with used/total only

**Depends on**: none
**Where**: MacMetricsView/Services/RAMFormatter.swift, MacMetricsView/Models/MetricDisplaySettings.swift, MacMetricsView/App/SystemMetricsModel.swift, MacMetricsView/App/CPUState.swift, MacMetricsView/App/StatusItemController.swift, MacMetricsView/UI/Popover/SettingsTab.swift, MacMetricsView/UI/Popover/MetricsTab.swift, MacMetricsViewTests
**Tests**: formatter, settings, state title, metric trend, RAM calculation
**Gate**: Build

Done when:

- RAM formatter has no selectable menu-bar metric parameter.
- Settings UI has no RAM metric picker.
- Legacy persisted RAM metric values do not affect menu-bar RAM output.
- RAM used calculation excludes reclaimable file cache.
- `swift test` passes.

## Handoffs

### PM

- Inputs: spec acceptance criteria.
- Outputs: single implementation task.
- Decision: go.
- Evidence: task maps all requirements.
- Pending: none.

### Dev

- Inputs: existing RAM model, formatter, settings, UI.
- Outputs: code and tests.
- Decision: go.
- Evidence: `swift test`.
- Pending: none.

### QA

- Inputs: changed formatter/settings behavior.
- Outputs: regression tests.
- Decision: go.
- Evidence: validation report.
- Pending: none.

### SecOps

- Inputs: no new external behavior.
- Outputs: n/a.
- Decision: go.
- Evidence: no network or telemetry touched.
- Pending: none.

### DBA

- Inputs: old RAM metric preference key.
- Outputs: ignore old key.
- Decision: go.
- Evidence: persistence tests.
- Pending: none.

### DevOps

- Inputs: Swift package.
- Outputs: test gate.
- Decision: go.
- Evidence: `swift test`.
- Pending: none.

