# Validation: Honest thermal-state metric + event-driven sampling

Status: done
Plan: ../plans/plan-thermal-state-trend-and-events.md

## Acceptance criteria

- [x] **(10)** Temperature no longer polls on a timer — verified by code
  (`TemperatureSampler` observes `ProcessInfo.thermalStateDidChangeNotification`) and by
  `TemperatureSamplerTests`: emits an initial sample on `start()`, re-samples on a
  posted notification, and stops re-sampling after `stop()`.
- [x] **(9)** The popover trend is no longer a dead Celsius series — `TemperatureHistory`
  keeps every sample and the sparkline plots `TemperatureSample.trendValue`. Verified by
  `testTemperatureHistoryKeepsStateOnlySamples`, `testTrendValueUsesStateLevelWhenCelsiusIsUnavailable`,
  and `testTrendValuePrefersCelsiusWhenAvailable`.
- [x] No SMC/IOKit/privileged temperature source was added (TD-005 honored).

## Automated checks

- `swift build` — success.
- `swift test` — 74 tests, 0 failures (was 69; +3 sampler, +2 trend).

## Manual verification (UI / status item / popover)

- Not performed in this environment (menu bar / popover can't be observed here).
- Recommended before release: `swift run`, enable Temperatura, and confirm the popover
  shows the thermal-state text plus a small trend that escalates under load (e.g. while
  the Mac is busy). The menu bar segment is unchanged.

## Residual risks

- `trendValue` mixes scales conceptually (state level 0–100 vs. Celsius normalized to
  0–100). Today only the state path is active because no numeric reader is wired, so the
  trend is consistent; revisit if/when an SMC reader lands.
- Notification delivery uses `queue: .main` in production; tests inject `deliveryQueue: nil`
  for synchronous delivery. The `MainActor.assumeIsolated` in the observer assumes main
  delivery — correct for `.main`, and tests post on the main actor.
