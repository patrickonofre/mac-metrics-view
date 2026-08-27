# RAM Used / Total Only Specification

Status: done

## Problem Statement

The RAM menu-bar display has multiple selectable meanings. That makes the value harder to trust. The app must show one effective value: real memory used over total RAM, matching the screenshot format.

## Goals

- Show RAM as `N.N/NN GB` in the menu bar.
- Use the existing real-used calculation: App Memory + Wired + Compressed.
- Remove the user-facing RAM metric chooser.
- Keep old stored RAM metric values from affecting display.

## Out of Scope

| Feature | Reason |
| --- | --- |
| New memory-pressure visualization | User asked for one display only. |
| New popover redesign | Request targets menu-bar RAM visibility. |
| New persistence migration | Ignoring the old key is enough and safer. |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Meaning of "uso real" | Activity Monitor-style Memory Used: App Memory + Wired + Compressed | Existing project decision TD-007 defines this as the most accurate local approximation and excludes reclaimable cache. | y |
| Menu-bar visual | `used/total GB` with the existing RAM icon when icons are enabled | User screenshot shows that exact shape. | y |
| Legacy `UserDefaults` key | Ignore `MetricDisplaySettings.ramMenuBarMetric` | Keeps upgrades stable without a migration that can create new state bugs. | y |

**Open questions:** none.

---

## User Stories

### P1: Single Honest RAM Value

**User Story**: As a Mac user, I want RAM to show one real used/total value so that I can trust the menu-bar signal without choosing between modes.

**Why P1**: This is the requested behavior.

**Acceptance Criteria**:

1. WHEN RAM has a valid sample THEN the system SHALL show the menu-bar RAM value as `N.N/NN GB`.
2. WHEN the menu bar is in icon mode THEN the system SHALL show the RAM value without a `RAM` label.
3. WHEN the menu bar is in label mode THEN the system SHALL show the RAM value prefixed with `RAM`.
4. IF a legacy RAM metric preference exists THEN the system SHALL still show used/total GB.
5. IF RAM input values are invalid THEN the system SHALL show `--/-- GB` and never show NaN, negative values, or RAM percent in the menu bar.
6. WHEN RAM stats include reclaimable file cache THEN the system SHALL exclude that cache from used memory.

**Independent Test**: Unit tests create deterministic RAM samples and VM stats, then assert the formatted value and persisted legacy behavior.

---

## Edge Cases

- IF `totalGB` is zero or missing THEN the system SHALL show `--/-- GB`.
- IF `usedGB` is negative or NaN THEN the system SHALL show `--/-- GB`.
- IF old `MetricDisplaySettings.ramMenuBarMetric` is `pressure` THEN the system SHALL still show GB, not percent.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| RAMONLY-01 | P1: Single Honest RAM Value | Implementation | Verified |
| RAMONLY-02 | Legacy preference ignored | Implementation | Verified |
| RAMONLY-03 | Reclaimable cache excluded | Implementation | Verified |

**Coverage:** 3 total, 3 mapped to tests, 0 unmapped.

---

## Success Criteria

- [x] RAM menu-bar output has only one semantic mode.
- [x] Settings UI no longer exposes RAM value selection.
- [x] `swift test` passes.

