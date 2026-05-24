# Testing standards

Tests use **XCTest** in `MacMetricsViewTests/`, run with `swift test`. The existing
suites cover CPU, RAM, network, temperature calculation/formatting/history and the
settings models — match their style.

## What must be tested

System-metric logic, because it is isolated from UI and therefore fully testable:

- **Calculation** — delta-based rate math, the "no previous snapshot yet" case,
  aggregation (e.g. network across non-loopback interfaces).
- **Formatting** — fixed-width output, units (GB, throughput), and **defensive
  clamping**: never `NaN`, negative, or impossible percentages.
- **History** — bounded capacity, ordering, min/max/trend behavior.
- **Severity** — threshold boundaries (normal <80%, elevated 80–<90%, high ≥90%).
- **Settings** — visibility, display style, launch-at-login persistence round-trips.

Inject fake readers (conforming to the reader protocol, e.g. `CPUReading`) to drive
samplers with deterministic snapshots — never depend on real machine load in a test.

## What we do not unit-test

- Status item rendering and popover presentation (AppKit/SwiftUI surface). These are
  verified by **launching the app**, not by unit tests.

## "Verified" means

- For metric logic: `swift test` passes and the relevant case is covered.
- For UI / status-item / popover / menu bar behavior: the app was actually **launched**
  and the behavior observed. Do **not** claim status-item behavior is verified from
  unit tests or a successful build alone.

Launch for manual verification:

```sh
xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Debug \
  -destination platform=macOS -derivedDataPath .build/DerivedData build
open .build/DerivedData/Build/Products/Debug/MacMetricsView.app
# or, for development:
swift run
```

## Commands

```sh
swift test                         # run the unit suite
swift build                        # compile check
```

## Conventions

- One test file per subject area, named `<Subject>Tests.swift` (the existing pattern,
  e.g. `CPUFormattingAndHistoryTests.swift`).
- Test boundaries and clamps explicitly — the bug we care about is a bad value reaching
  the menu bar, so assert the clamp, not just the happy path.
- A change to metric logic without a corresponding test is incomplete. Record the run
  in the VALIDATION artifact (`docs/ai/validation/`).
