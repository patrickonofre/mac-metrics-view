# Tasks: Remove Token Usage

Status: ready
Spec: ../specs/spec-remove-token-usage.md
Design: ../specs/design-remove-token-usage.md

## Gate Check Commands

- Quick: `swift test --filter 'PopoverTabPresentationTests|MetricsTabLayoutTests|MetricVisibilitySettingsTests|CPUStatePopoverTests'`
- Full: `swift test`
- Build: `xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Debug -destination platform=macOS -derivedDataPath .build/DerivedData build`

## Execution Plan

1. T1 Remove runtime ownership and sampler callbacks.
2. T2 Remove menu-bar and popover lifecycle token output.
3. T3 Remove token cards, settings, visibility, and localization.
4. T4 Delete token collection implementation and token-only tests.
5. T5 Remove Xcode references to deleted source.
6. T6 Update current product documentation and technical decision.
7. T7 Run full validation and independent review.

## Task Breakdown

### T1: Remove token runtime ownership

**Status**: pending

**What**: Remove token samplers, callbacks, token model ownership, and token-specific state from the app coordinator.
**Where**: `AppDelegate.swift`, `CPUState.swift`, and focused coordinator tests.
**Depends on**: none.
**Requirement**: TOKRM-01.
**Done when**: app startup creates no token sampler, reader, model, callback, or refresh timer.
**Tests**: XCTest unit.
**Gate**: Quick.
**Commit**: `refactor(tokens): remove runtime ownership`

### T2: Remove token menu-bar and popover lifecycle

**Status**: pending

**What**: Remove token output from the menu-bar title and remove token auto-refresh lifecycle calls from the popover.
**Where**: `StatusItemController.swift`, `PopoverView.swift`, and focused presentation tests.
**Depends on**: T1.
**Requirement**: TOKRM-01.
**Done when**: menu-bar composition and popover open/close handling contain no token reference.
**Tests**: XCTest unit.
**Gate**: Quick.
**Commit**: `refactor(tokens): remove presentation lifecycle`

### T3: Remove token cards and settings

**Status**: pending

**What**: Remove token metric visibility, cards, details, settings controls, presentation enum entry, and localized strings. Update mixed UI tests to assert the exact machine-only order.
**Where**: `MetricsTab.swift`, `SettingsTab.swift`, `PopoverTabPresentation.swift`, `MetricVisibilitySettings.swift`, `Localization.swift`, and focused UI/settings tests.
**Depends on**: T2.
**Requirement**: TOKRM-02, TOKRM-03.
**Done when**: the popover and settings expose no token surface; presentation tests assert CPU, GPU, RAM, network, temperature, disk, and battery only.
**Tests**: XCTest unit.
**Gate**: Quick.
**Commit**: `refactor(tokens): remove popover and settings`

### T4: Delete token collection stack

**Status**: pending

**What**: Delete all token readers, samplers, models, stores, calculations, formatters, and token-only tests. Remove now-orphaned helpers only when they were exclusively token code.
**Where**: token files under `MacMetricsView/App`, `MacMetricsView/Models`, `MacMetricsView/Services`, and token-only `MacMetricsViewTests` files.
**Depends on**: T3.
**Requirement**: TOKRM-04, TOKRM-05, TOKRM-06.
**Done when**: no production source implements AI usage tracking or reads legacy token preferences; token-only tests are deleted as intentional feature removal.
**Tests**: SwiftPM compilation and production-source search.
**Gate**: Full.
**Commit**: `refactor(tokens): delete collection stack`

### T5: Remove Xcode token references

**Status**: pending

**What**: Remove deleted token file references and source build entries from the Xcode project.
**Where**: `MacMetricsView.xcodeproj/project.pbxproj`.
**Depends on**: T4.
**Requirement**: TOKRM-04.
**Done when**: project contains no token source file reference or source build entry and Debug app builds.
**Tests**: Xcode build.
**Gate**: Build.
**Commit**: `build(tokens): remove xcode source entries`

### T6: Update current product documentation

**Status**: pending

**What**: Remove current token/cost capability claims and supersede the dev/AI product-pillar decision with machine-resource focus. Preserve historical records.
**Where**: `README.md`, `docs/PRD.md`, `docs/ai/project-context.md`, and `docs/TECH_DECISIONS.md`.
**Depends on**: T5.
**Requirement**: TOKRM-07, TOKRM-08.
**Done when**: current docs describe machine resources and utilities without token tracking; historical documents remain unchanged.
**Tests**: Targeted text search.
**Gate**: Full.
**Commit**: `docs(tokens): remove current capability claims`

### T7: Validate removal

**Status**: pending

**What**: Run full SwiftPM and Xcode gates, run source/document searches, launch the Debug app, and record independent verification.
**Where**: `docs/ai/validation/validation-remove-token-usage.md`.
**Depends on**: T6.
**Requirement**: TOKRM-01, TOKRM-02, TOKRM-03, TOKRM-04, TOKRM-05, TOKRM-06, TOKRM-07, TOKRM-08.
**Done when**: every requirement has evidence, test counts are explained, and residual inert `UserDefaults` values are recorded.
**Tests**: Full suite, Xcode Debug build, app launch, independent verifier.
**Gate**: Build.
**Commit**: `docs(validation): record token removal evidence`

## Execution Map

```
T1 -> T2 -> T3 -> T4 -> T5 -> T6 -> T7
```

## Test Coverage Matrix

| Requirement | Task | Evidence |
| --- | --- | --- |
| TOKRM-01 | T1 | App wiring has no token sampler/model/refresh references. |
| TOKRM-02 | T1 | `PopoverTabPresentationTests` asserts machine-only order. |
| TOKRM-03 | T1 | Settings and visibility tests assert no token configuration. |
| TOKRM-04 | T2, T3 | Production source search and Xcode build. |
| TOKRM-05 | T2 | Production source search and SwiftPM build. |
| TOKRM-06 | T2 | Search confirms no legacy token key reads or removal. |
| TOKRM-07 | T4 | Current-doc text search. |
| TOKRM-08 | T4 | Historical documentation stays outside touched files. |
